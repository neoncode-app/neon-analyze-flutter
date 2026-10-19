import 'dart:io';

import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/finding.dart';
import 'package:neon_check/src/process.dart';
import 'package:neon_check/src/step.dart';
import 'package:neon_check/src/steps/test_impact.dart';

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

/// Whether this run measures coverage (NCR0000022): the tests step then runs
/// `flutter test --coverage` and the coverage step reads the report. On when
/// the app names coverage sources and the run is `--all` or touches one.
bool coverageWanted(CheckContext context) {
  final sources = context.config.coverageSources;
  if (sources.isEmpty) return false;
  if (context.isAll) return true;
  return [
    ...context.changedFiles,
    ...context.deletedFiles,
  ].any((file) => file.endsWith('.dart') && sources.any((glob) => matchesGlob(glob, file)));
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

/// `flutter test`, failures only. `--all` runs every suite; otherwise the
/// suites selected by the changed files, the default suite always. The
/// integration flows are their own step (`IntegrationStep`).
final class TestsStep extends CheckStep {
  const TestsStep();

  @override
  String get name => 'tests';

  @override
  String get description => 'flutter test: the tests the changed files reach (or their suites)';

  @override
  Set<String> get rules => const {'test_failure'};

  @override
  bool appliesTo(CheckContext context) =>
      Directory(context.absolute(context.config.testDir)).existsSync() &&
      (context.isAll || context.dartFiles.isNotEmpty || context.touches(['assets/', 'pubspec.yaml']));

  /// Test paths of [suite]; the default suite owns everything in the test
  /// folder that no other suite claims.
  ///
  /// Only paths that hold a `_test.dart` file are returned: `flutter test`
  /// given a folder without tests (the shared `test/support/` harness, an
  /// empty suite folder) falls back to running the whole test directory.
  List<String> pathsOf(CheckContext context, String suite) {
    final config = context.config;
    if (suite != config.defaultSuite) {
      return [
        for (final dir in config.suites[suite]?.tests ?? const <String>[])
          if (hasTests(context.absolute(dir))) dir,
      ];
    }
    final claimed = [for (final other in config.suites.values) ...other.tests];
    return [
      for (final entity in Directory(context.absolute(config.testDir)).listSync())
        if (!claimed.contains(context.relative(entity.path)) &&
            ((entity is Directory && hasTests(entity.path)) || (entity is File && entity.path.endsWith('_test.dart'))))
          context.relative(entity.path),
    ]..sort();
  }

  /// Whether the folder at [absolutePath] holds at least one `_test.dart` file.
  static bool hasTests(String absolutePath) {
    final directory = Directory(absolutePath);
    if (!directory.existsSync()) return false;
    return directory.listSync(recursive: true).any((entity) => entity is File && entity.path.endsWith('_test.dart'));
  }

  @override
  Future<StepResult> run(CheckContext context) async {
    final config = context.config;
    final paths = context.isAll ? [config.testDir] : selectTestPaths(context);
    final findings = <Finding>[];
    if (paths.isNotEmpty) {
      final result = await runProcess(context.root, 'flutter', [
        'test',
        '--reporter',
        'failures-only',
        if (config.testsConcurrency > 0) ...['--concurrency', '${config.testsConcurrency}'],
        if (coverageWanted(context)) '--coverage',
        ...paths,
      ]);
      if (result.exitCode != 0) findings.addAll(_failures(result.stdout, result.stderr));
    }
    return StepResult(findings: findings);
  }

  /// The test paths a scoped run executes.
  ///
  /// `tests.select: impact` (the default): the test files whose import
  /// closure reaches a changed or deleted file, plus the changed test files.
  /// A change the import graph cannot see falls back to the suites: the
  /// `pubspec.yaml`, anything under `assets/` (the tests load translations and
  /// fonts from there) and a `flutter_test_config.dart`.
  /// `tests.select: suites`: the whole suites the changed files select.
  List<String> selectTestPaths(CheckContext context) {
    final config = context.config;
    final changed = {...context.changedFiles, ...context.deletedFiles};
    final graphBlind = changed.any(
      (file) => file == 'pubspec.yaml' || file.startsWith('assets/') || file.endsWith('flutter_test_config.dart'),
    );
    if (config.testsSelect == 'impact' && !graphBlind) {
      return impactedTests(
        tests: testFilesIn(context.root, config.testDir),
        changed: changed,
        packageName: config.projectName,
        read: (file) {
          final source = File(context.absolute(file));
          return source.existsSync() ? source.readAsStringSync() : null;
        },
      ).toList()
        ..sort();
    }
    final suites = selectSuites(
      changedFiles: changed,
      suites: config.suites,
      shared: config.sharedSources,
      defaultSuite: config.defaultSuite,
    );
    return [for (final suite in suites) ...pathsOf(context, suite)];
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
