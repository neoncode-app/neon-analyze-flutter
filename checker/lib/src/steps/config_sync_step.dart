import 'dart:io';

import 'package:neon_check/src/config.dart';
import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/finding.dart';
import 'package:neon_check/src/step.dart';

/// The configuration is valid, and the analyzer sees the packs it names.
///
/// The analyzer reads only `analysis_options.yaml`, so the rules of the
/// enabled packs (and the `rules:` overrides) are written there, between two
/// marker lines, as the `plugins: neon_lints: diagnostics:` section. An
/// existing hand-written `plugins:` section is replaced the first time.
/// Auto-fix; with `--ci` a stale section fails.
final class ConfigSyncStep extends CheckStep {
  const ConfigSyncStep();

  static const optionsFile = 'analysis_options.yaml';
  static const startMarker =
      '# >>> neon-check: generated from neon_check.yaml (packs, rules); edit that file, not this block';
  static const endMarker = '# <<< neon-check';

  @override
  bool get autoFix => true;

  @override
  String get name => 'config_sync';

  @override
  String get description => 'neon_check.yaml is valid; analysis_options.yaml enables the rules of its packs (auto-fix)';

  @override
  Set<String> get rules => const {'config_invalid', 'config_sync'};

  @override
  Future<StepResult> run(CheckContext context) async {
    final config = context.config;
    final findings = <Finding>[
      for (final error in config.errors)
        Finding(rule: 'config_invalid', file: CheckConfig.fileName, message: error, hard: true),
    ];
    if (config.allPacks.isEmpty) return StepResult(findings: findings);
    final file = File(context.absolute(optionsFile));
    final before = file.existsSync() ? file.readAsStringSync() : '';
    final after = withPluginBlock(before, pluginBlock(config));
    if (after == before) return StepResult(findings: findings);
    if (context.fix) {
      file.writeAsStringSync(after);
      return StepResult(findings: findings, fixed: const [optionsFile]);
    }
    findings.add(
      const Finding(
        rule: 'config_sync',
        file: optionsFile,
        message: 'the plugins section does not match neon_check.yaml; run neon-check locally',
      ),
    );
    return StepResult(findings: findings);
  }

  /// The generated section for [config].
  static String pluginBlock(CheckConfig config) {
    final enabled = config.enabledPacks.toSet();
    final diagnostics = config.diagnostics;
    final buffer = StringBuffer()
      ..writeln(startMarker)
      ..writeln('plugins:')
      ..writeln('  neon_lints:')
      ..writeln('    path: ${config.pluginPath}')
      ..writeln('    diagnostics:');
    for (final pack in config.allPacks) {
      if (pack.rules.isEmpty) continue;
      buffer.writeln('      # ${pack.name} (${enabled.contains(pack.name) ? 'on' : 'off'})');
      for (final rule in pack.rules) {
        buffer.writeln('      $rule: ${diagnostics[rule]}');
      }
    }
    buffer.write(endMarker);
    return buffer.toString();
  }

  /// [source] with its plugin section replaced by [block]: between the
  /// markers if they exist, else in place of a top-level `plugins:` section
  /// (and the comment right above it), else appended.
  static String withPluginBlock(String source, String block) {
    final lines = source.isEmpty ? <String>[] : source.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    final start = lines.indexWhere((line) => line.startsWith('# >>> neon-check'));
    final end = lines.indexWhere((line) => line.startsWith(endMarker));
    if (start >= 0 && end > start) {
      return [...lines.sublist(0, start), block, ...lines.sublist(end + 1)].join('\n') + '\n';
    }
    final plugins = lines.indexWhere((line) => line.trimRight() == 'plugins:');
    if (plugins < 0) {
      return [...lines, if (lines.isNotEmpty && lines.last.trim().isNotEmpty) '', block].join('\n') + '\n';
    }
    bool topLevelKey(String line) => line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('#');
    var after = plugins + 1;
    while (after < lines.length && !topLevelKey(lines[after])) {
      after++;
    }
    // Comments and blank lines right before the next key belong to it.
    while (after > plugins + 1 && (lines[after - 1].trim().isEmpty || lines[after - 1].startsWith('#'))) {
      after--;
    }
    var before = plugins;
    while (before > 0 && lines[before - 1].startsWith('#')) {
      before--;
    }
    return [...lines.sublist(0, before), block, ...lines.sublist(after)].join('\n') + '\n';
  }
}
