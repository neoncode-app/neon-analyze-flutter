import 'dart:io';

import 'package:neon_check/src/baseline.dart';
import 'package:neon_check/src/config.dart';
import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/finding.dart';
import 'package:neon_check/src/step.dart';
import 'package:neon_check/src/steps/dart_steps.dart';
import 'package:neon_check/src/steps/project_steps.dart';
import 'package:neon_check/src/steps/coverage_step.dart';
import 'package:neon_check/src/steps/test_existence_step.dart';
import 'package:neon_check/src/steps/tests_step.dart';
import 'package:neon_check/src/steps/translation_steps.dart';

/// What the command line asked for.
final class RunOptions {
  const RunOptions({
    this.mode = ScopeMode.changed,
    this.files = const [],
    this.base,
    this.ci = false,
    this.zero = const {},
    this.rule,
    this.steps = const [],
    this.updateBaseline = false,
    this.pruneTranslations = false,
    this.maxFailures = 0,
  });

  final ScopeMode mode;
  final List<String> files;
  final String? base;
  final bool ci;

  /// Rules that must have no finding at all, baseline or not.
  final Set<String> zero;

  /// `--rule`: list every finding of one rule, never fail.
  final String? rule;

  /// `--step`: run only these steps.
  final List<String> steps;

  final bool updateBaseline;
  final bool pruneTranslations;

  /// Prints at most this many failures (0 = all), then the total.
  final int maxFailures;
}

/// Every step, in run order.
List<CheckStep> allSteps({bool pruneTranslations = false}) => [
      const FormatStep(),
      const FixStep(),
      const AnalyzeStep(),
      const IgnoreCommentsStep(),
      const TranslationParityStep(),
      const TranslationDashesStep(),
      const TranslationMissingStep(),
      TranslationUnusedStep(prune: pruneTranslations),
      const TranslationOrderStep(),
      const AssetsStep(),
      const CatalogIndexStep(),
      const CatalogPreviewsStep(),
      const ProvidersStep(),
      const PageHelpStep(),
      const GeneratedCodeStep(),
      const TestExistenceStep(),
      const TestsStep(),
      const CoverageStep(),
    ];

/// Runs the checks for the app at [root]; returns the exit code.
Future<int> runChecks(String root, RunOptions options, {StringSink? out}) async {
  final sink = out ?? stdout;
  final config = CheckConfig.load(root);
  // Listing a rule, demanding zero and rewriting the baseline need the whole project.
  final reportOnly = options.rule != null || options.updateBaseline;
  final mode = reportOnly || options.zero.isNotEmpty ? ScopeMode.all : options.mode;
  final scope = switch (mode) {
    ScopeMode.all => (existing: <String>{}, deleted: <String>{}),
    ScopeMode.files => (
        existing: {for (final file in options.files) _relative(root, file)},
        deleted: <String>{},
      ),
    _ => gitScope(root, mode, base: options.base),
  };
  final context = CheckContext(
    root: root,
    config: config,
    mode: mode,
    changedFiles: scope.existing,
    deletedFiles: scope.deleted,
    fix: !options.ci && !reportOnly,
    ci: options.ci,
    base: options.base ?? recordedBase(root) ?? config.defaultBase,
  );
  final baselinePath = context.absolute(config.baselinePath);
  final baseline = Baseline.load(baselinePath);

  final steps = allSteps(pruneTranslations: options.pruneTranslations);
  final checkRules = {for (final step in steps) ...?step.rules};
  final aliases = {'ratchet': 'analyze'};
  final selected = options.steps.isEmpty
      ? steps
      : [
          for (final step in steps)
            if (options.steps.map((name) => aliases[name] ?? name).contains(step.name)) step,
        ];
  if (options.steps.isNotEmpty && selected.isEmpty) {
    sink.writeln('Unknown step: ${options.steps.join(', ')}. Steps: ${steps.map((step) => step.name).join(', ')}');
    return 64;
  }

  final fixed = <String>[];
  final lowered = <(String, String, int, int)>[];
  final collected = <Finding>[];
  var ran = 0;
  for (final step in selected) {
    if (reportOnly && (step.autoFix || step is TestsStep || step is CoverageStep)) continue;
    if (!step.appliesTo(context)) continue;
    ran++;
    final result = await step.run(context);
    fixed.addAll(result.fixed.map((file) => '${step.name}: $file'));
    if (reportOnly) {
      collected.addAll(result.findings);
      continue;
    }
    final stepRules = step.rules;
    final verdict = ratchet(
      findings: result.findings,
      baseline: baseline,
      owns: stepRules == null ? (rule) => !checkRules.contains(rule) : stepRules.contains,
      inScope: result.findingsScope ?? context.inScope,
      zero: options.zero,
      lower: !options.ci,
    );
    lowered.addAll(verdict.lowered);
    if (verdict.failures.isNotEmpty) {
      _printFixed(sink, fixed);
      sink.writeln('FAIL ${step.name}: ${verdict.failures.length} failure(s)');
      final shown = options.maxFailures > 0 ? verdict.failures.take(options.maxFailures) : verdict.failures;
      for (final failure in shown) {
        sink.writeln(failure.format());
      }
      if (shown.length < verdict.failures.length) {
        sink.writeln('... ${verdict.failures.length - shown.length} more; list them with tool/check.sh --rule <rule>');
      }
      if (baseline.isDirty && !options.ci) baseline.save(baselinePath);
      return 1;
    }
  }

  if (options.rule != null) {
    final matching = collected.where((finding) => finding.rule == options.rule).toList();
    for (final finding in matching) {
      sink.writeln(finding.format());
    }
    sink.writeln(
        '${options.rule}: ${matching.length} finding(s) in ${{for (final f in matching) f.file}.length} file(s)');
    return 0;
  }
  if (options.updateBaseline) {
    final hard = collected.where((finding) => finding.hard).toList();
    for (final finding in hard) {
      sink.writeln(finding.format());
    }
    baseline
      ..resetTo(collected)
      ..save(baselinePath);
    final byRule = <String, int>{};
    for (final finding in collected.where((finding) => !finding.hard)) {
      byRule[finding.rule] = (byRule[finding.rule] ?? 0) + 1;
    }
    for (final entry in byRule.entries.toList()..sort((a, b) => b.value.compareTo(a.value))) {
      sink.writeln('  ${entry.key}: ${entry.value}');
    }
    sink.writeln('baseline written: ${config.baselinePath} (${collected.length - hard.length} findings)');
    return hard.isEmpty ? 0 : 1;
  }

  if (baseline.isDirty && !options.ci) baseline.save(baselinePath);
  _printFixed(sink, fixed);
  for (final (rule, file, from, to) in lowered) {
    sink.writeln('baseline lowered: $rule $file $from -> $to');
  }
  final scopeLabel = mode == ScopeMode.all ? '--all' : '--${mode.name}, ${scope.existing.length} file(s)';
  sink.writeln('check OK: $ran step(s) ran ($scopeLabel)');
  return 0;
}

void _printFixed(StringSink sink, List<String> fixed) {
  for (final entry in fixed) {
    sink.writeln('fixed $entry');
  }
}

String _relative(String root, String path) {
  final absolute = path.startsWith('/') ? path : '${Directory.current.path}/$path';
  return absolute.startsWith('$root/') ? absolute.substring(root.length + 1) : path;
}
