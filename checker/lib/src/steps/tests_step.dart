import 'dart:io';

import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/finding.dart';
import 'package:neon_check/src/process.dart';
import 'package:neon_check/src/step.dart';

/// Glob for root-relative paths: `**` any folders, `*` any characters within
/// one segment. A pattern without a glob character also matches everything
/// below it (`lib/utils` matches `lib/utils/a.dart`).
bool matchesGlob(String pattern, String path) {
  if (!pattern.contains('*')) return path == pattern || path.startsWith(pattern.endsWith('/') ? pattern : '$pattern/');
  final regex = StringBuffer('^');
  for (var i = 0; i < pattern.length; i++) {
    final char = pattern[i];
    if (char == '*' && i + 1 < pattern.length && pattern[i + 1] == '*') {
      regex.write('.*');
      i++;
    } else if (char == '*') {
      regex.write('[^/]*');
    } else {
      regex.write(RegExp.escape(char));
    }
  }
  regex.write(r'($|/)');
  return RegExp(regex.toString()).hasMatch(path);
}

/// Which suites a set of changed files selects. The default suite always runs;
/// a shared source selects every suite.
Set<String> selectSuites({
  required Iterable<String> changedFiles,
  required Map<String, ({List<String> tests, List<String> sources})> suites,
  required List<String> shared,
  required String defaultSuite,
}) {
  final selected = {defaultSuite};
  for (final file in changedFiles) {
    if (shared.any((glob) => matchesGlob(glob, file))) return {defaultSuite, ...suites.keys};
    for (final suite in suites.entries) {
      final ownsTest = suite.value.tests.any((dir) => matchesGlob(dir, file));
      if (ownsTest || suite.value.sources.any((glob) => matchesGlob(glob, file))) selected.add(suite.key);
    }
  }
  return selected;
}

/// Step 17: `flutter test`, failures only. `--all` runs every suite (and the
/// integration command, if configured); otherwise the suites selected by the
/// changed files, the default suite always.
final class TestsStep extends CheckStep {
  const TestsStep();

  @override
  String get name => 'tests';

  @override
  String get description => 'flutter test, suites selected by the changed files';

  @override
  Set<String> get rules => const {'test_failure', 'integration_failure'};

  @override
  bool appliesTo(CheckContext context) =>
      Directory(context.absolute(context.config.testDir)).existsSync() &&
      (context.isAll || context.dartFiles.isNotEmpty || context.touches(['assets/', 'pubspec.yaml']));

  /// Test paths of [suite]; the default suite owns everything in the test
  /// folder that no other suite claims.
  List<String> _pathsOf(CheckContext context, String suite) {
    final config = context.config;
    if (suite != config.defaultSuite) {
      return [
        for (final dir in config.suites[suite]?.tests ?? const <String>[])
          if (FileSystemEntity.typeSync(context.absolute(dir)) != FileSystemEntityType.notFound) dir,
      ];
    }
    final claimed = [for (final other in config.suites.values) ...other.tests];
    return [
      for (final entity in Directory(context.absolute(config.testDir)).listSync())
        if (!claimed.contains(context.relative(entity.path)) &&
            (entity is Directory || entity.path.endsWith('_test.dart')))
          context.relative(entity.path),
    ]..sort();
  }

  @override
  Future<StepResult> run(CheckContext context) async {
    final config = context.config;
    final suites = context.isAll
        ? {config.defaultSuite, ...config.suites.keys}
        : selectSuites(
            changedFiles: [...context.changedFiles, ...context.deletedFiles],
            suites: config.suites,
            shared: config.sharedSources,
            defaultSuite: config.defaultSuite,
          );
    final paths = context.isAll ? [config.testDir] : [for (final suite in suites) ..._pathsOf(context, suite)];
    final findings = <Finding>[];
    if (paths.isNotEmpty) {
      final result = await runProcess(context.root, 'flutter', ['test', '--reporter', 'failures-only', ...paths]);
      if (result.exitCode != 0) findings.addAll(_failures(result.stdout, result.stderr));
    }
    final integration = config.integrationCommand;
    if (context.isAll && integration.isNotEmpty) {
      final result = await runProcess(context.root, integration.first, integration.sublist(1));
      if (result.exitCode != 0) {
        findings.add(
          Finding(
            rule: 'integration_failure',
            file: 'integration_test',
            message: _tail('${result.stdout}\n${result.stderr}'),
            hard: true,
          ),
        );
      }
    }
    return StepResult(findings: findings);
  }

  /// One finding per failing test: `<file>: <test name>`.
  static List<Finding> _failures(String stdout, String stderr) {
    final failing = RegExp(r'^\d+:\d+ \+\d+(?: ~\d+)? -\d+: (.+?) \[E\]$', multiLine: true);
    final findings = <Finding>[];
    for (final match in failing.allMatches(stdout)) {
      final description = match.group(1) ?? '';
      final file = RegExp(r'^(\S+_test\.dart):? ?').firstMatch(description);
      findings.add(
        Finding(
          rule: 'test_failure',
          file: file?.group(1) ?? 'test',
          message: 'failed: ${file == null ? description : description.substring(file.end)}',
          hard: true,
        ),
      );
    }
    if (findings.isEmpty) {
      findings.add(Finding(rule: 'test_failure', file: 'test', message: _tail('$stdout\n$stderr'), hard: true));
    }
    return findings;
  }

  static String _tail(String output) => output
      .trim()
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .toList()
      .reversed
      .take(8)
      .toList()
      .reversed
      .join(' | ');
}
