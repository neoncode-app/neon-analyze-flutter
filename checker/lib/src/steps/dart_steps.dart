import 'dart:io';

import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/finding.dart';
import 'package:neon_check/src/process.dart';
import 'package:neon_check/src/step.dart';

/// `dart format --line-length <n>`. Fixes in place; with `--ci` it
/// only checks and fails on files that need formatting.
final class FormatStep extends CheckStep {
  const FormatStep();

  @override
  bool get autoFix => true;

  @override
  String get name => 'format';

  @override
  String get description => 'dart format --line-length 120 (auto-fix)';

  @override
  Set<String> get rules => const {'format'};

  @override
  bool appliesTo(CheckContext context) => context.dartFiles.isNotEmpty;

  @override
  Future<StepResult> run(CheckContext context) async {
    final files = context.dartFiles;
    final findings = <Finding>[];
    final fixed = <String>[];
    for (final chunk in chunks(files)) {
      final result = await runProcess(context.root, 'dart', [
        'format',
        '--line-length',
        '${context.config.lineLength}',
        if (!context.fix) ...['--output=none', '--set-exit-if-changed'],
        ...chunk,
      ]);
      for (final line in result.stdout.split('\n')) {
        if (!line.startsWith('Changed ')) continue;
        final file = context.relative(line.substring('Changed '.length).trim());
        if (context.fix) {
          fixed.add(file);
        } else {
          findings.add(Finding(
              rule: 'format', file: file, message: 'not formatted; run neon-analyze-flutter/bin/neon-check locally'));
        }
      }
      if (result.exitCode != 0 && result.exitCode != 1) {
        findings.add(Finding(rule: 'format', file: '.', message: result.stderr.trim(), hard: true));
      }
    }
    return StepResult(findings: findings, fixed: fixed);
  }
}

/// `dart fix --apply` (core analyzer fixes; plugin fixes cannot be
/// applied from the command line). With `--ci` it only checks.
final class FixStep extends CheckStep {
  const FixStep();

  @override
  bool get autoFix => true;

  @override
  String get name => 'fix';

  @override
  String get description => 'dart fix --apply (auto-fix)';

  @override
  Set<String> get rules => const {'dart_fix'};

  @override
  bool appliesTo(CheckContext context) => context.dartFiles.isNotEmpty;

  @override
  Future<StepResult> run(CheckContext context) async {
    // One dry run over the project (seconds, the analysis is shared), then
    // only the files in scope that actually have fixes.
    final dryRun = await runProcess(context.root, 'dart', ['fix', '--dry-run', '.']);
    final inScope = context.dartFiles.toSet();
    final withFixes = [
      for (final line in dryRun.stdout.split('\n'))
        if (line.isNotEmpty && !line.startsWith(' ') && line.endsWith('.dart') && inScope.contains(line.trim()))
          line.trim(),
    ];
    if (!context.fix) {
      return StepResult(
        findings: [
          for (final file in withFixes)
            Finding(
                rule: 'dart_fix',
                file: file,
                message: 'dart fix has fixes; run neon-analyze-flutter/bin/neon-check locally'),
        ],
      );
    }
    for (final file in withFixes) {
      await runProcess(context.root, 'dart', ['fix', '--apply', file]);
    }
    return StepResult(fixed: withFixes);
  }
}

/// `dart analyze` (never `flutter analyze`, which skips the plugin).
///
/// Runs on the package root in `--all` and on explicit file paths otherwise
/// (`dart analyze lib` would silently skip the plugin). Compile errors are
/// hard failures; every other diagnostic goes through the ratchet (step 4).
final class AnalyzeStep extends CheckStep {
  const AnalyzeStep();

  @override
  String get name => 'analyze';

  @override
  String get description => 'dart analyze (plugin rules included), then the ratchet baseline';

  @override
  Set<String>? get rules => null;

  @override
  bool appliesTo(CheckContext context) => context.isAll || context.dartFiles.isNotEmpty;

  static const _hardTypes = {'COMPILE_TIME_ERROR', 'SYNTACTIC_ERROR'};

  @override
  Future<StepResult> run(CheckContext context) async {
    final findings = <Finding>[];
    final batches =
        context.isAll ? allBatches(context.dartFiles, nestedPackageFiles(context)) : chunks(context.dartFiles).toList();
    for (final batch in batches) {
      var output = await _analyze(context, batch);
      if (_crashed(output)) output = await _analyze(context, batch);
      if (_crashed(output)) {
        findings.add(
          const Finding(
            rule: 'analyzer_crash',
            file: '.',
            message: 'the analysis server crashed twice; run `dart analyze` by hand',
            hard: true,
          ),
        );
        continue;
      }
      findings.addAll(parseMachineOutput(output, context.relative));
    }
    return StepResult(findings: findings);
  }

  /// The batches of an `--all` run. Without nested packages one bare
  /// `dart analyze` covers the app. A nested package (its own pubspec, like
  /// vernakapp's `packages/conversation_shortcuts`) is a second analysis
  /// context, and with two contexts in one run the CLI reports the plugin's
  /// findings of the nested one only: the app's own [NEON] findings vanish
  /// while the IDE still shows them (NCC0000078). So then every package runs
  /// on its own, by file paths, never two packages in one process.
  static List<List<String>> allBatches(List<String> appFiles, Map<String, List<String>> nested) {
    if (nested.isEmpty) return [<String>[]];
    return [
      ...chunks(appFiles),
      for (final files in nested.values) ...chunks(files),
    ];
  }

  /// Root-relative Dart files of every nested package tracked in the app's
  /// git checkout, by package folder. Submodules (neon-analyze-flutter) are
  /// not listed by `git ls-files`, and generated files are left out.
  static Map<String, List<String>> nestedPackageFiles(CheckContext context) {
    final result = Process.runSync('git', ['ls-files', '--', '*pubspec.yaml'], workingDirectory: context.root);
    if (result.exitCode != 0) return const {};
    final packages = [
      for (final line in (result.stdout as String).split('\n'))
        if (line.trim().endsWith('/pubspec.yaml'))
          line.trim().substring(0, line.trim().length - '/pubspec.yaml'.length),
    ];
    return {
      for (final package in packages)
        if (Directory(context.absolute(package)).existsSync())
          package: [
            for (final entity in Directory(context.absolute(package)).listSync(recursive: true))
              if (entity is File &&
                  entity.path.endsWith('.dart') &&
                  !entity.path.endsWith('.g.dart') &&
                  !entity.path.endsWith('.freezed.dart') &&
                  !entity.path.contains('/.dart_tool/') &&
                  !entity.path.contains('/build/'))
                context.relative(entity.path),
          ]..sort(),
    }..removeWhere((_, files) => files.isEmpty);
  }

  Future<String> _analyze(CheckContext context, List<String> files) async {
    final result = await runProcess(context.root, 'dart', ['analyze', '--format=machine', ...files]);
    return '${result.stdout}\n${result.stderr}';
  }

  static bool _crashed(String output) =>
      output.contains('===== CRASH =====') || output.contains('analysis server shut down unexpectedly');

  /// Parses `SEVERITY|TYPE|CODE|FILE|LINE|COLUMN|LENGTH|MESSAGE` lines.
  static List<Finding> parseMachineOutput(String output, String Function(String) relative) {
    final findings = <Finding>[];
    for (final line in output.split('\n')) {
      final fields = line.replaceAll(r'\|', '\u0000').split('|');
      if (fields.length < 8 || !const {'INFO', 'WARNING', 'ERROR'}.contains(fields[0])) continue;
      final message = fields.sublist(7).join('|').replaceAll('\u0000', '|').replaceAll(r'\\', r'\');
      findings.add(
        Finding(
          rule: fields[2].toLowerCase(),
          file: relative(fields[3]),
          line: int.tryParse(fields[4]) ?? 1,
          message: message,
          hard: _hardTypes.contains(fields[1]),
        ),
      );
    }
    return findings;
  }
}

/// No `// ignore:` / `// ignore_for_file:` for a neon_lints rule. A
/// rule that reports a false positive is fixed in the plugin, never silenced.
final class IgnoreCommentsStep extends CheckStep {
  const IgnoreCommentsStep();

  @override
  String get name => 'ignores';

  @override
  String get description => 'no ignore comments for [NEON] rules';

  @override
  Set<String> get rules => const {'neon_ignore'};

  @override
  bool appliesTo(CheckContext context) => context.dartFiles.isNotEmpty;

  /// Rule names registered by the plugin at [pluginPath].
  static Set<String> pluginRuleNames(String pluginPath) {
    final dir = Directory('$pluginPath/lib');
    if (!dir.existsSync()) return const {};
    final pattern = RegExp(r"super\(\s*name:\s*'(\w+)'");
    return {
      for (final entity in dir.listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          for (final match in pattern.allMatches(entity.readAsStringSync())) match.group(1) ?? '',
    }..remove('');
  }

  @override
  Future<StepResult> run(CheckContext context) async {
    final names = pluginRuleNames(context.absolute(context.config.pluginPath));
    final comment = RegExp(r'//\s*ignore(?:_for_file)?\s*:(.*)$');
    final findings = <Finding>[];
    for (final file in context.dartFiles) {
      final lines = File(context.absolute(file)).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final match = comment.firstMatch(lines[i]);
        if (match == null) continue;
        final codes = (match.group(1) ?? '').split(RegExp(r'[,\s]+')).map((code) => code.trim());
        for (final code in codes) {
          final bare = code.startsWith('neon_lints/') ? code.substring('neon_lints/'.length) : code;
          if (code.startsWith('neon_lints/') || names.contains(bare)) {
            findings.add(
              Finding(
                rule: 'neon_ignore',
                file: file,
                line: i + 1,
                message:
                    '`$code` silences a [NEON] rule; fix the code, or fix a false positive in neon-analyze-flutter',
              ),
            );
          }
        }
      }
    }
    return StepResult(findings: findings);
  }
}
