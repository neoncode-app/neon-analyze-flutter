import 'dart:io';

import 'package:neon_check/src/baseline.dart';
import 'package:neon_check/src/burndown.dart';
import 'package:neon_check/src/config.dart';
import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/finding.dart';
import 'package:neon_check/src/step.dart';
import 'package:neon_check/src/steps/config_sync_step.dart';
import 'package:neon_check/src/steps/coverage_step.dart';
import 'package:neon_check/src/steps/dart_steps.dart';
import 'package:neon_check/src/steps/integration_step.dart';
import 'package:neon_check/src/steps/feature_used_once_step.dart';
import 'package:neon_check/src/steps/layout_tree_step.dart';
import 'package:neon_check/src/steps/project_steps.dart';
import 'package:neon_check/src/steps/rule_docs_step.dart';
import 'package:neon_check/src/steps/test_existence_step.dart';
import 'package:neon_check/src/steps/tests_step.dart';
import 'package:neon_check/src/steps/translation_steps.dart';

/// How a person runs the tool, for messages.
const commandName = 'neon-analyze-flutter/bin/neon-check';

/// What the command line asked for.
final class RunOptions {
  const RunOptions({
    this.mode = ScopeMode.changed,
    this.scopeGiven = false,
    this.files = const [],
    this.base,
    this.ci = false,
    this.zero = const {},
    this.rule,
    this.steps = const [],
    this.trigger,
    this.integration,
    this.updateBaseline = false,
    this.pruneTranslations = false,
    this.maxFailures = 0,
    this.toolRoot,
  });

  final ScopeMode mode;

  /// Whether `--all`, `--changed`, `--staged` or files were given; without
  /// them the scope comes from the trigger.
  final bool scopeGiven;

  final List<String> files;
  final String? base;
  final bool ci;

  /// Rules that must have no finding at all, baseline or not.
  final Set<String> zero;

  /// `--rule`: list every finding of one rule, never fail.
  final String? rule;

  /// `--step`: run only these steps.
  final List<String> steps;

  /// `--trigger`: the `triggers:` entry that decides scope, steps, check-only
  /// and integration. Without one, a bare run is the `stop` trigger.
  final String? trigger;

  /// `--integration`: overrides the trigger's integration mode.
  final IntegrationMode? integration;

  final bool updateBaseline;
  final bool pruneTranslations;

  /// Prints at most this many failures (0 = all), then the total.
  final int maxFailures;

  /// The neon-analyze-flutter checkout; default `<root>/neon-analyze-flutter`.
  final String? toolRoot;
}

/// Every step, in run order.
List<CheckStep> allSteps({bool pruneTranslations = false}) => [
      const ConfigSyncStep(),
      const FormatStep(),
      const FixStep(),
      const AnalyzeStep(),
      const IgnoreCommentsStep(),
      const RuleDocsStep(),
      const TranslationParityStep(),
      const TranslationDashesStep(),
      const TranslationMissingStep(),
      TranslationUnusedStep(prune: pruneTranslations),
      const TranslationOrderStep(),
      const AssetsStep(),
      const LayoutTreeStep(),
      const FeatureUsedOnceStep(),
      const CatalogIndexStep(),
      const CatalogPreviewsStep(),
      const ProvidersStep(),
      const PageHelpStep(),
      const GeneratedCodeStep(),
      const TestExistenceStep(),
      const IntegrationPagesStep(),
      const TestsStep(),
      const CoverageStep(),
      const IntegrationStep(),
    ];

/// Steps that run code (tests and flows); everything else is `static`.
const dynamicSteps = {'tests', 'coverage', 'integration'};

/// The step names a trigger's `steps:` resolves to; `null` for unknown names.
Set<String>? resolveStepNames(List<String> names, List<CheckStep> steps) {
  final all = {for (final step in steps) step.name};
  if (names.length == 1 && names.first == 'all') return all;
  if (names.length == 1 && names.first == 'static') return all.difference(dynamicSteps);
  final aliases = {'ratchet': 'analyze'};
  final resolved = {for (final name in names) aliases[name] ?? name};
  return resolved.every(all.contains) ? resolved : null;
}

ScopeMode _scopeOf(String scope) => switch (scope) {
      'all' => ScopeMode.all,
      'staged' => ScopeMode.staged,
      'files' => ScopeMode.files,
      _ => ScopeMode.changed,
    };

/// Runs the checks for the app at [root]; returns the exit code.
Future<int> runChecks(String root, RunOptions options, {StringSink? out}) async {
  final sink = out ?? stdout;
  final config = CheckConfig.load(root, toolRoot: options.toolRoot);
  final steps = allSteps(pruneTranslations: options.pruneTranslations);

  final triggerName = options.trigger ?? (options.scopeGiven ? null : 'stop');
  final trigger = triggerName == null ? null : config.triggers[triggerName];
  if (triggerName != null && trigger == null && options.trigger != null) {
    sink.writeln('Unknown trigger: $triggerName. Triggers: ${config.triggers.keys.join(', ')}');
    return 64;
  }

  // Listing a rule, demanding zero and rewriting the baseline need the whole project.
  final reportOnly = options.rule != null || options.updateBaseline;
  var mode = options.scopeGiven || trigger == null ? options.mode : _scopeOf(trigger.scope);
  if (mode == ScopeMode.files && options.files.isEmpty) mode = ScopeMode.changed;
  if (reportOnly || options.zero.isNotEmpty) mode = ScopeMode.all;
  final ci = options.ci || (trigger?.ci ?? false);

  final wanted = options.steps.isNotEmpty ? options.steps : (trigger?.steps ?? const ['all']);
  final names = resolveStepNames(wanted, steps);
  if (names == null) {
    sink.writeln('Unknown step in ${wanted.join(', ')}. Steps: ${steps.map((step) => step.name).join(', ')}');
    return 64;
  }

  final base = options.base ?? recordedBase(root) ?? config.defaultBase;
  final scope = switch (mode) {
    ScopeMode.all => (existing: <String>{}, deleted: <String>{}),
    ScopeMode.files => (
        existing: {for (final file in options.files) _relative(root, file)},
        deleted: <String>{},
      ),
    _ => gitScope(root, mode, base: base),
  };
  // A burndown touches shared code all the time; its turns skip the flows.
  final burndownIntegration = triggerName == 'stop' && burndownRunsHere(root) ? stopIntegration(config) : null;
  final integration = options.integration ??
      burndownIntegration ??
      trigger?.integration ??
      (mode == ScopeMode.all ? IntegrationMode.all : IntegrationMode.off);
  final context = CheckContext(
    root: root,
    config: config,
    mode: mode,
    changedFiles: scope.existing,
    deletedFiles: scope.deleted,
    fix: !ci && !reportOnly,
    ci: ci,
    base: base,
    integration: reportOnly ? IntegrationMode.off : integration,
    toolRoot: options.toolRoot,
  );
  final baselinePath = context.absolute(config.baselinePath);
  final baseline = Baseline.load(baselinePath);

  final checkRules = {for (final step in steps) ...?step.rules};
  final selected = [
    for (final step in steps)
      if (names.contains(step.name) && config.stepEnabled(step.name)) step,
  ];

  final fixed = <String>[];
  final lowered = <(String, String, int, int)>[];
  final collected = <Finding>[];
  var ran = 0;
  for (final step in selected) {
    if (reportOnly && (step.autoFix || dynamicSteps.contains(step.name))) continue;
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
      lower: !ci,
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
        sink.writeln('... ${verdict.failures.length - shown.length} more; list them with $commandName --rule <rule>');
      }
      if (baseline.isDirty && !ci) baseline.save(baselinePath);
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

  if (baseline.isDirty && !ci) baseline.save(baselinePath);
  _printFixed(sink, fixed);
  for (final (rule, file, from, to) in lowered) {
    sink.writeln('baseline lowered: $rule $file $from -> $to');
  }
  final scopeLabel = mode == ScopeMode.all ? 'all' : '${mode.name}, ${scope.existing.length} file(s)';
  final label = [
    if (triggerName != null && trigger != null) 'trigger $triggerName',
    scopeLabel,
    if (context.integration != IntegrationMode.off) 'integration ${context.integration.name}',
  ].join(', ');
  sink.writeln('check OK: $ran step(s) ran ($label)');
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
