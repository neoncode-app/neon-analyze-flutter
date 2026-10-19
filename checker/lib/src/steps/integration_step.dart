import 'dart:io';

import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/finding.dart';
import 'package:neon_check/src/step.dart';
import 'package:neon_check/src/steps/integration_runner.dart';
import 'package:neon_check/src/steps/tests_step.dart';
import 'package:neon_lints/layout.dart';

/// The integration flows: every `*_test.dart` directly in the integration
/// folder (`integration_test/<suite>_<flow>_test.dart`). Files in its
/// subfolders are shared steps, not flows.
List<String> integrationFlows(CheckContext context) {
  final dir = Directory(context.absolute(context.config.integrationDir));
  if (!dir.existsSync()) return const [];
  return [
    for (final entity in dir.listSync())
      if (entity is File && entity.path.endsWith('_test.dart')) context.relative(entity.path),
  ]..sort();
}

/// The suite a flow belongs to: the longest suite name its file name starts
/// with (`vernak_cards_publish_flow_test.dart` -> `vernak`), else the default
/// suite.
String suiteOfFlow(String flow, String defaultSuite, Iterable<String> suites) {
  final name = flow.split('/').last;
  final candidates = [defaultSuite, ...suites]..sort((a, b) => b.length.compareTo(a.length));
  for (final suite in candidates) {
    if (name.startsWith('${suite}_')) return suite;
  }
  return defaultSuite;
}

/// Files under the integration folder that [flow] imports, directly or
/// through other files there (relative imports only).
Set<String> flowSupportFiles(CheckContext context, String flow) {
  final seen = <String>{};
  final pending = [flow];
  final importPattern = RegExp(r'''^import\s+['"]([^'":]+)['"]''', multiLine: true);
  while (pending.isNotEmpty) {
    final file = pending.removeLast();
    if (!seen.add(file)) continue;
    final source = File(context.absolute(file));
    if (!source.existsSync()) continue;
    final folder = file.contains('/') ? file.substring(0, file.lastIndexOf('/')) : '';
    for (final match in importPattern.allMatches(source.readAsStringSync())) {
      pending.add(_normalize('$folder/${match.group(1)}'));
    }
  }
  return seen..remove(flow);
}

String _normalize(String path) {
  final parts = <String>[];
  for (final part in path.split('/')) {
    if (part == '..' && parts.isNotEmpty) {
      parts.removeLast();
    } else if (part != '.' && part.isNotEmpty) {
      parts.add(part);
    }
  }
  return parts.join('/');
}

/// The flows a run executes: every flow for [IntegrationMode.all]; for
/// [IntegrationMode.affected] and [IntegrationMode.background] the flows the
/// changed files reach.
///
/// * a changed flow runs itself, a changed shared step every flow that
///   imports it;
/// * a changed source under `lib/` selects suites as the unit tests do: a
///   shared source every suite, a suite source its suite, any other source
///   the default suite;
/// * `pubspec.yaml` runs every flow. Tests, translations, assets and docs
///   run none (the static steps and unit tests cover them).
List<String> selectFlows(CheckContext context) {
  final flows = integrationFlows(context);
  if (context.integration == IntegrationMode.all) return flows;
  if (context.integration == IntegrationMode.off) return const [];
  final config = context.config;
  final changed = [...context.changedFiles, ...context.deletedFiles];
  if (changed.contains('pubspec.yaml')) return flows;
  final selected = <String>{};
  final suites = <String>{};
  for (final file in changed) {
    if (!file.startsWith('lib/') || !file.endsWith('.dart')) continue;
    if (config.sharedSources.any((glob) => matchesGlob(glob, file))) return flows;
    final owners = [
      for (final suite in config.suites.entries)
        if (suite.value.sources.any((glob) => matchesGlob(glob, file))) suite.key,
    ];
    suites.addAll(owners.isEmpty ? [config.defaultSuite] : owners);
  }
  for (final flow in flows) {
    if (changed.contains(flow) || suites.contains(suiteOfFlow(flow, config.defaultSuite, config.suites.keys))) {
      selected.add(flow);
      continue;
    }
    final integrationChanges = changed.where((file) => file.startsWith('${config.integrationDir}/'));
    if (integrationChanges.isEmpty) continue;
    final support = flowSupportFiles(context, flow);
    if (integrationChanges.any(support.contains)) selected.add(flow);
  }
  return selected.toList()..sort();
}

/// Runs the integration flows the run selects ([selectFlows]) on the app's
/// driver. A failing flow is a hard failure; a driver that is missing
/// (no chromedriver, no device) skips with a notice unless
/// `NEON_INTEGRATION_REQUIRED=1`.
///
/// [IntegrationMode.background] (the `stop` trigger, NCC0000075) does not wait
/// for the flows. It first settles the previous background run: still running
/// on the same tree, it is left alone; running on an older tree, it is
/// cancelled and its flows run again in the new one; finished with failures,
/// those flows run again now, in the foreground, and only a flow that still
/// fails is a hard failure (the tree may have changed under the old run).
/// Then it starts the selected flows detached and reports that it did. With
/// less memory available than `integration.background_min_memory_mb` it
/// starts nothing and leaves the flows to `--trigger ci`.
final class IntegrationStep extends CheckStep {
  const IntegrationStep();

  @override
  String get name => 'integration';

  @override
  String get description => 'integration flows the change affects (or all), on the configured driver';

  @override
  Set<String> get rules => const {'integration_failure'};

  @override
  bool appliesTo(CheckContext context) =>
      context.integration != IntegrationMode.off &&
      context.config.integrationDriver != 'none' &&
      (selectFlows(context).isNotEmpty ||
          (context.integration == IntegrationMode.background && BackgroundRun(context.root).exists));

  @override
  Future<StepResult> run(CheckContext context) async {
    if (context.integration == IntegrationMode.background) return _background(context);
    // A foreground run owns the driver and the test accounts.
    BackgroundRun(context.root).cancel(integrationDir: context.config.integrationDir);
    final result = await runFlows(context, selectFlows(context));
    return StepResult(findings: [for (final failure in result.failed) _finding(context, failure)]);
  }

  Future<StepResult> _background(CheckContext context) async {
    final config = context.config;
    final previous = BackgroundRun(context.root);
    final fingerprint = treeFingerprint(context.root);
    final notes = <String>[];
    final carried = <String>{};
    if (previous.running) {
      if (previous.fingerprint == fingerprint) {
        return StepResult(
          notes: [
            'integration: ${previous.flows.length} flow(s) still running in the background on this tree '
                '(log ${previous.logPath})',
          ],
        );
      }
      carried.addAll(previous.flows);
      previous.cancel(integrationDir: config.integrationDir);
    } else if (previous.exists && previous.result == null) {
      // Ended without writing a result (killed, or the tool failed to start):
      // nothing is known, its flows run again.
      notes.add('integration: the background run started ${previous.startedAt} ended without a result '
          '(log ${previous.logPath}); its flows start again');
      carried.addAll(previous.flows);
      previous.clear();
    } else if (previous.exists) {
      final failed = previous.result?.failed ?? const <FlowFailure>[];
      if (failed.isEmpty && previous.fingerprint == fingerprint) {
        return StepResult(notes: ['integration: the background flows passed on this tree']);
      }
      final startedAt = previous.startedAt;
      previous.clear();
      if (failed.isNotEmpty) {
        final again = await runFlows(context, {for (final failure in failed) failure.flow}.toList()..sort());
        if (again.failed.isNotEmpty) {
          return StepResult(
            findings: [
              for (final failure in again.failed)
                _finding(context, failure, prefix: 'failed in the background run started $startedAt and again now: '),
            ],
          );
        }
        notes.add('integration: ${failed.length} flow(s) that failed in the background pass now');
      }
    }
    final flows = {...selectFlows(context), ...carried}.toList()..sort();
    if (flows.isEmpty) return StepResult(notes: notes);
    final memory = availableMemoryMb();
    if (memory != null && memory < config.integrationBackgroundMinMemoryMb) {
      notes.add(
        'integration: ${flows.length} flow(s) NOT started in the background, only $memory MB of memory available '
        '(minimum ${config.integrationBackgroundMinMemoryMb} MB); they run with --trigger ci (/done)',
      );
      return StepResult(notes: notes);
    }
    await BackgroundRun(context.root).start(toolRoot: context.toolRoot, flows: flows, fingerprint: fingerprint);
    notes.add(
      'integration: ${flows.length} flow(s) started in the background (log ${previous.logPath}); '
      'the next check reports the result',
    );
    return StepResult(notes: notes);
  }

  static Finding _finding(CheckContext context, FlowFailure failure, {String prefix = ''}) => Finding(
        rule: 'integration_failure',
        file: failure.flow,
        message: '${prefix}the flow failed: '
            '${failure.log.isEmpty ? 'see the output above' : failureSummary(context.absolute(failure.log))} '
            '(full log ${failure.log.isEmpty ? '-' : failure.log}; rerun with `neon-check integration ${failure.flow}`)',
        hard: true,
      );
}

/// Every page has an integration flow that reaches it (rule
/// `integration_missing`, `integration.require_flow_for_pages`).
///
/// A page is a `*_page.dart` in the layout role `pages`, outside a `widgets/`
/// folder. A flow reaches it when some file of the integration folder
/// imports the page or names one of its `*Page` classes. Ratcheted: today's
/// gaps are in the baseline, a new page without a flow fails.
final class IntegrationPagesStep extends CheckStep {
  const IntegrationPagesStep();

  @override
  String get name => 'integration_pages';

  @override
  String get description => 'every page has an integration flow that opens it';

  @override
  Set<String> get rules => const {'integration_missing'};

  bool _isPage(CheckContext context, String file) =>
      file.endsWith('_page.dart') &&
      !file.contains('/widgets/') &&
      context.config.layout.matches(LayoutRole.pages, file) &&
      !context.config.integrationExemptPages.any((exempt) => file == exempt || file.endsWith('/$exempt'));

  @override
  bool appliesTo(CheckContext context) {
    if (!context.config.requireFlowForPages) return false;
    return context.isAll ||
        [...context.changedFiles, ...context.deletedFiles].any(
          (file) => _isPage(context, file) || file.startsWith('${context.config.integrationDir}/'),
        );
  }

  @override
  Future<StepResult> run(CheckContext context) async {
    final config = context.config;
    final dir = Directory(context.absolute(config.integrationDir));
    final flowsText = StringBuffer();
    if (dir.existsSync()) {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) flowsText.writeln(entity.readAsStringSync());
      }
    }
    final text = flowsText.toString();
    final classPattern = RegExp(r'^class\s+(\w+Page)\b', multiLine: true);
    final findings = <Finding>[];
    for (final page in context.allLibDartFiles.where((file) => _isPage(context, file))) {
      final source = File(context.absolute(page)).readAsStringSync();
      final importUri = 'package:${config.projectName}/${page.substring('lib/'.length)}';
      final classes = [for (final match in classPattern.allMatches(source)) match.group(1) ?? ''];
      final reached =
          text.contains(importUri) || classes.any((name) => RegExp('\\b${RegExp.escape(name)}\\b').hasMatch(text));
      if (reached) continue;
      final line = source.split('\n').indexWhere((line) => classPattern.hasMatch(line)) + 1;
      findings.add(
        Finding(
          rule: 'integration_missing',
          file: page,
          line: line < 1 ? 1 : line,
          message: '${classes.isEmpty ? 'this page' : '`${classes.first}`'} has no integration flow; add '
              '${config.integrationDir}/<suite>_<flow>_test.dart that opens it (import the page or find it by type)',
        ),
      );
    }
    return StepResult(findings: findings, findingsScope: (file) => _isPage(context, file));
  }
}

/// What went wrong in a flow's log: the lines that name the failure
/// (exceptions, expectations, errors), else its last lines.
String failureSummary(String logPath) {
  final file = File(logPath);
  if (logPath.isEmpty || !file.existsSync()) return 'no log';
  final lines = file.readAsLinesSync();
  final telling = RegExp(
      r'Expected|Actual|Which|EXCEPTION|Exception|Error:|failed|Some tests failed|TimeoutException|timed out|was thrown');
  final picked = [
    for (final line in lines)
      if (telling.hasMatch(line) && !line.contains('handleRequest')) line.trim(),
  ];
  return picked.isEmpty ? tail(lines.join('\n')) : picked.take(8).join(' | ');
}

/// The last lines of a tool's output, joined, for a one-line finding.
String tail(String output, [int lines = 8]) => output
    .trim()
    .split('\n')
    .where((line) => line.trim().isNotEmpty)
    .toList()
    .reversed
    .take(lines)
    .toList()
    .reversed
    .join(' | ');
