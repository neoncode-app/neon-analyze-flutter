import 'dart:io';

import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/finding.dart';
import 'package:neon_check/src/step.dart';
import 'package:neon_check/src/steps/tests_step.dart';

/// `file -> (line -> hits)` of an lcov report (`flutter test --coverage`).
Map<String, Map<int, int>> parseLcov(String report) {
  final result = <String, Map<int, int>>{};
  Map<int, int>? current;
  for (final line in report.split('\n')) {
    if (line.startsWith('SF:')) {
      current = result[line.substring(3).trim()] ??= {};
    } else if (line.startsWith('DA:') && current != null) {
      final parts = line.substring(3).split(',');
      final number = parts.isNotEmpty ? int.tryParse(parts[0].trim()) : null;
      final hits = parts.length > 1 ? int.tryParse(parts[1].trim()) : null;
      if (number != null && hits != null) current[number] = (current[number] ?? 0) + hits;
    } else if (line.trim() == 'end_of_record') {
      current = null;
    }
  }
  return result;
}

/// The line numbers on the `+` side of every hunk of a `git diff -U0` output:
/// the lines added or changed.
Set<int> changedLines(String unifiedDiff) {
  final lines = <int>{};
  final hunk = RegExp(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@', multiLine: true);
  for (final match in hunk.allMatches(unifiedDiff)) {
    final start = int.tryParse(match.group(1) ?? '') ?? 0;
    final count = int.tryParse(match.group(2) ?? '') ?? 1;
    for (var i = 0; i < count; i++) {
      lines.add(start + i);
    }
  }
  return lines;
}

/// How many of the [changed] lines are executable (have a DA entry in [hits])
/// and how many of those ran; [firstUncovered] is 0 when all ran.
({int executable, int covered, int firstUncovered}) coverageOf(Set<int> changed, Map<int, int> hits) {
  var executable = 0;
  var covered = 0;
  var firstUncovered = 0;
  for (final line in changed.toList()..sort()) {
    final count = hits[line];
    if (count == null) continue;
    executable++;
    if (count > 0) {
      covered++;
    } else if (firstUncovered == 0) {
      firstUncovered = line;
    }
  }
  return (executable: executable, covered: covered, firstUncovered: firstUncovered);
}

/// Step: the lines changed under the coverage sources (`lib/bloc` in neoncode)
/// are covered by the tests that just ran (NCR0000022).
///
/// Reads the lcov report the tests step wrote with `--coverage`, diffs every
/// changed source file against the merge base with the branch base and
/// requires `min_percent` of the changed executable lines to have run. A
/// changed file no test touched is 0 %. Hard failures: a cubit change ships
/// with its test or not at all. Without a resolvable base (a fresh clone
/// that lacks the base branch) the step has nothing to compare and skips.
final class CoverageStep extends CheckStep {
  const CoverageStep();

  @override
  String get name => 'coverage';

  @override
  String get description => 'changed lines under the coverage sources are covered by the tests that ran';

  @override
  Set<String> get rules => const {'coverage_low'};

  @override
  bool appliesTo(CheckContext context) => coverageWanted(context);

  @override
  Future<StepResult> run(CheckContext context) async {
    final config = context.config;
    final base = context.base;
    final mergeBaseSha = base == null ? null : mergeBase(context.root, base);
    if (mergeBaseSha == null) return const StepResult();
    final lcov = File(context.absolute(config.coverageLcov));
    if (!lcov.existsSync()) {
      return StepResult(
        findings: [
          Finding(
            rule: 'coverage_low',
            file: config.coverageLcov,
            message: 'coverage report missing: the tests step writes it (flutter test --coverage); run the whole check',
            hard: true,
          ),
        ],
      );
    }
    final report = parseLcov(lcov.readAsStringSync());
    final files = context.isAll ? gitScope(context.root, ScopeMode.changed, base: base).existing : context.changedFiles;
    final sources = [
      for (final file in files)
        if (file.endsWith('.dart') &&
            !file.endsWith('.g.dart') &&
            config.coverageSources.any((glob) => matchesGlob(glob, file)))
          file,
    ]..sort();
    final findings = <Finding>[];
    for (final file in sources) {
      final changed = _changedLinesOf(context, mergeBaseSha, file);
      if (changed.isEmpty) continue;
      final hits = report[file];
      if (hits == null) {
        findings.add(
          Finding(
            rule: 'coverage_low',
            file: file,
            message: 'no test ran against this file: ${changed.length} changed line(s), 0 covered, '
                'minimum ${config.coverageMinPercent} % (add or extend its cubit test, NCR0000022)',
            hard: true,
          ),
        );
        continue;
      }
      final coverage = coverageOf(changed, hits);
      if (coverage.executable == 0) continue;
      final percent = coverage.covered * 100 ~/ coverage.executable;
      if (percent >= config.coverageMinPercent) continue;
      findings.add(
        Finding(
          rule: 'coverage_low',
          file: file,
          line: coverage.firstUncovered,
          message: '${coverage.covered} of ${coverage.executable} changed line(s) covered ($percent %), '
              'minimum ${config.coverageMinPercent} % (add or extend its cubit test, NCR0000022)',
          hard: true,
        ),
      );
    }
    return StepResult(findings: findings);
  }

  /// Lines of [file] (working tree) that differ from its version at
  /// [mergeBaseSha]; every line of a file git does not know yet.
  ///
  /// The base version is formatted (`dart format`, the app's line length)
  /// before the diff, so a reformat of old code is not a change that needs
  /// coverage: only lines whose code differs count. The copy is formatted
  /// inside the app root (`.dart_tool/`), so the formatter uses the app's
  /// language version and `formatter:` options, exactly as the tree was.
  static Set<int> _changedLinesOf(CheckContext context, String mergeBaseSha, String file) {
    final tracked = Process.runSync('git', ['ls-files', '--error-unmatch', file], workingDirectory: context.root);
    if (tracked.exitCode != 0) {
      final length = File(context.absolute(file)).readAsLinesSync().length;
      return {for (var i = 1; i <= length; i++) i};
    }
    final baseContent = Process.runSync('git', ['show', '$mergeBaseSha:$file'], workingDirectory: context.root);
    if (baseContent.exitCode != 0) {
      // Added on this branch: every line is new.
      final length = File(context.absolute(file)).readAsLinesSync().length;
      return {for (var i = 1; i <= length; i++) i};
    }
    final temp = Directory('${context.root}/.dart_tool').createTempSync('neon_check_base_');
    try {
      final baseFile = File('${temp.path}/${file.split('/').last}')..writeAsStringSync(baseContent.stdout as String);
      Process.runSync('dart', ['format', '--line-length', '${context.config.lineLength}', baseFile.path]);
      final diff = Process.runSync(
        'git',
        ['diff', '--no-index', '-U0', '--', baseFile.path, context.absolute(file)],
        workingDirectory: context.root,
      );
      return changedLines(diff.stdout as String);
    } finally {
      temp.deleteSync(recursive: true);
    }
  }
}
