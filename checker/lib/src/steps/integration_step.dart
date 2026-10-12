import 'dart:io';

import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/finding.dart';
import 'package:neon_check/src/process.dart';
import 'package:neon_check/src/step.dart';
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
/// [IntegrationMode.affected] the flows the changed files reach.
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

/// Runs [flows] with the app's driver (`integration.driver`) through
/// `integration/run.sh`; returns the exit code and the output.
Future<({int exitCode, String output})> runFlows(CheckContext context, List<String> flows) async {
  final config = context.config;
  final defines = config.integrationDefinesFile;
  final result = await runProcess(context.root, '${context.toolRoot}/integration/run.sh', [
    '--driver',
    config.integrationDriver,
    if (config.integrationDevice.isNotEmpty) ...['--device', config.integrationDevice],
    if (defines.isNotEmpty && File(context.absolute(defines)).existsSync()) ...['--defines', defines],
    '--',
    ...flows,
  ]);
  return (exitCode: result.exitCode, output: '${result.stdout}\n${result.stderr}');
}

/// Runs the integration flows the run selects ([selectFlows]) on the app's
/// driver. A failing flow is a hard failure; a driver that is missing
/// (no chromedriver, no device) skips with a notice unless
/// `NEON_INTEGRATION_REQUIRED=1`.
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
      selectFlows(context).isNotEmpty;

  @override
  Future<StepResult> run(CheckContext context) async {
    final flows = selectFlows(context);
    final result = await runFlows(context, flows);
    if (result.exitCode == 0) return const StepResult();
    final failed =
        RegExp(r'^integration: FAILED (\S+)(?: (\S+))?$', multiLine: true).allMatches(result.output).toList();
    return StepResult(
      findings: [
        if (failed.isEmpty)
          Finding(
              rule: 'integration_failure',
              file: context.config.integrationDir,
              message: tail(result.output),
              hard: true)
        else
          for (final match in failed)
            Finding(
              rule: 'integration_failure',
              file: match.group(1) ?? context.config.integrationDir,
              message: 'the flow failed: ${failureSummary(context.absolute(match.group(2) ?? ''))} '
                  '(full log ${match.group(2) ?? '-'}; rerun with `neon-check integration ${match.group(1)}`)',
              hard: true,
            ),
      ],
    );
  }
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
