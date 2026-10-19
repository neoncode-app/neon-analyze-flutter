import 'dart:io';

import 'package:neon_check/src/config.dart';
import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/runner.dart';
import 'package:neon_check/src/steps/config_sync_step.dart';
import 'package:neon_check/src/steps/integration_runner.dart';
import 'package:neon_check/src/steps/integration_step.dart';
import 'package:neon_check/src/steps/rule_docs_step.dart';
import 'package:neon_lints/layout.dart';

/// Where the git hooks live, relative to the app root.
const hooksPath = 'neon-analyze-flutter/hooks';

String? _git(String root, List<String> args) {
  final result = Process.runSync('git', args, workingDirectory: root);
  return result.exitCode == 0 ? (result.stdout as String).trim() : null;
}

/// `neon-check explain`: what the tool found out about the app and what it
/// will check, so a wrong guess is visible instead of silent.
int explain(String root, String toolRoot, StringSink out) {
  final config = CheckConfig.load(root, toolRoot: toolRoot);
  final facts = config.facts;
  final enabled = config.enabledPacks.toSet();
  String list(Iterable<String> items) => items.isEmpty ? 'none' : items.join(', ');

  out
    ..writeln('neon-check: ${facts.name.isEmpty ? '(no pubspec name)' : facts.name}  ($root)')
    ..writeln('  preset ${config.presetName ?? '(none)'}, base branch ${config.defaultBase ?? '(not set)'}')
    ..writeln('  detected: flavours ${list(config.flavors)}; languages ${list(config.languages)} '
        '(primary ${config.languages.isEmpty ? '-' : config.primaryLanguage}); platforms ${list(facts.platforms)}')
    ..writeln()
    ..writeln('Packs');
  for (final pack in config.allPacks) {
    final on = enabled.contains(pack.name);
    out.writeln('  ${on ? 'on ' : 'off'}  ${pack.name.padRight(13)} ${pack.rules.length.toString().padLeft(2)} rules, '
        '${pack.steps.length} steps  ${pack.description}');
  }
  final overrides = config.ruleOverrides;
  out.writeln(
      '  rule overrides: ${overrides.isEmpty ? 'none' : overrides.entries.map((e) => '${e.key}=${e.value}').join(', ')}');

  final steps = allSteps();
  out
    ..writeln()
    ..writeln('Steps, in run order')
    ..writeln('  ${steps.where((step) => config.stepEnabled(step.name)).map((step) => step.name).join(', ')}');
  final off = steps.where((step) => !config.stepEnabled(step.name)).map((step) => step.name);
  if (off.isNotEmpty) out.writeln('  off (pack disabled): ${off.join(', ')}');

  out
    ..writeln()
    ..writeln('When (triggers)');
  for (final trigger in config.triggers.values) {
    out.writeln('  ${trigger.name.padRight(7)} scope ${trigger.scope.padRight(8)} '
        'steps ${trigger.steps.isEmpty ? '(none)' : trigger.steps.join(', ')}'
        '${trigger.ci ? '; check only' : '; fixes what it can'}'
        '${trigger.integration == IntegrationMode.off ? '' : '; integration ${trigger.integration.name}'}');
  }

  out
    ..writeln()
    ..writeln('Layout (roles; "*" = set in neon_check.yaml)');
  for (final role in LayoutRole.values) {
    final patterns = config.layout.patterns(role);
    final custom = patterns.join() != role.defaults.join();
    out.writeln('  ${custom ? '*' : ' '} ${role.key.padRight(17)} ${patterns.join(', ')}');
  }
  if (config.hasTree) {
    final unused = config.treeOptional.where((folder) => !config.treeUse.contains(folder));
    out.writeln('  lib/ tree: ${config.treeAllowedFolders.map((folder) => '$folder/').join(', ')}'
        '${unused.isEmpty ? '' : ' (optional, off: ${unused.join(', ')})'}; entrypoints ${config.treeEntrypoints.join(', ')}');
  }

  final context = CheckContext(
    root: root,
    config: config,
    mode: ScopeMode.all,
    changedFiles: const {},
    deletedFiles: const {},
    fix: false,
    ci: true,
    toolRoot: toolRoot,
  );
  final flows = integrationFlows(context);
  final definesFile = config.integrationDefinesFile;
  out
    ..writeln()
    ..writeln('Tests')
    ..writeln('  default suite ${config.defaultSuite}; suites ${list(config.suites.keys)}; '
        'scoped runs select ${config.testsSelect == 'impact' ? 'the tests the change reaches' : 'whole suites'}'
        '${config.testsConcurrency > 0 ? ', concurrency ${config.testsConcurrency}' : ''}')
    ..writeln('  providers files: ${list(config.providersFiles)}')
    ..writeln('  routers: ${list(config.routeRouters)}')
    ..writeln('  page help: ${list(config.pageHelpEntries.map((entry) => entry.enumFile))}')
    ..writeln('  integration: driver ${config.integrationDriver}'
        '${config.integrationDevice.isEmpty ? '' : ' (${config.integrationDevice})'}, ${flows.length} flow(s), '
        'flow required for every page: ${config.requireFlowForPages ? 'yes' : 'no'}, '
        '${config.integrationCombine ? 'one build (reset ${config.integrationReset.isEmpty ? '-' : config.integrationReset}), ' : 'one build per flow, '}'
        'defines ${definesFile.isEmpty ? '-' : '$definesFile${File('$root/$definesFile').existsSync() ? '' : ' (missing)'}'}');
  for (final flow in flows) {
    out.writeln('    ${suiteOfFlow(flow, config.defaultSuite, config.suites.keys).padRight(10)} $flow');
  }

  final docs = loadRuleDocs(context, config.ruleDocsDir);
  final documented = {for (final doc in docs) ...doc.enforcedBy};
  final diagnostics = config.diagnostics;
  final undocumented = [
    for (final pack in config.allPacks)
      for (final rule in pack.rules)
        if (diagnostics[rule] != 'false' && !documented.contains(rule)) rule,
  ];
  out
    ..writeln()
    ..writeln('Written rules (${config.ruleDocsDir})')
    ..writeln(docs.isEmpty
        ? '  none exported here (the ESME session-start hook writes them)'
        : '  ${docs.length} rule(s); ${docs.where((doc) => doc.enforcedBy.isNotEmpty).length} name their checks, '
            '${docs.where((doc) => doc.notEnforced).length} are deliberately not checked')
    ..writeln('  enabled lint rules no written rule explains (their own message is the only guidance): '
        '${undocumented.isEmpty ? 'none' : undocumented.join(', ')}');

  final hooks = _git(root, ['config', 'core.hooksPath']);
  out
    ..writeln()
    ..writeln('Git hooks: core.hooksPath = ${hooks ?? '(not set)'}'
        '${hooks == hooksPath ? '' : '  -> run `$commandName install`'}')
    ..writeln(config.errors.isEmpty ? 'Configuration: OK' : 'Configuration errors:');
  for (final error in config.errors) {
    out.writeln('  $error');
  }
  return config.errors.isEmpty ? 0 : 1;
}

/// `neon-check install`: points git at the shared hooks of the tool.
int install(String root, StringSink out) {
  if (!Directory('$root/$hooksPath').existsSync()) {
    out.writeln('$hooksPath does not exist; is neon-analyze-flutter checked out?');
    return 1;
  }
  if (_git(root, ['config', 'core.hooksPath', hooksPath]) == null) {
    out.writeln('git config core.hooksPath failed');
    return 1;
  }
  out.writeln('git hooks: core.hooksPath = $hooksPath (pre-commit, pre-push; an app hook in .githooks/ or '
      'tool/git-hooks/ still runs first)');
  return 0;
}

/// `neon-check init`: a starting `neon_check.yaml` for an app that has none,
/// the git hooks and the analyzer section. The baseline is the next step.
int init(String root, String toolRoot, StringSink out) {
  final file = File('$root/${CheckConfig.fileName}');
  if (file.existsSync()) {
    out.writeln('${CheckConfig.fileName} exists already; `$commandName explain` shows what it resolves to.');
    return 0;
  }
  final facts = ProjectFacts.detect(root);
  final preset = Directory('$root/lib/flavors').existsSync() ? 'admin' : 'app';
  final remoteHead = _git(root, ['symbolic-ref', '--short', 'refs/remotes/origin/HEAD']);
  final base = remoteHead == null ? 'main' : remoteHead.replaceFirst('origin/', '');
  file.writeAsStringSync('''
# neon-check configuration of ${facts.name.isEmpty ? 'this app' : facts.name}. Everything not set here
# comes from neon-analyze-flutter/presets/base.yaml and the preset below, or is
# detected (flavours, languages, platforms). `$commandName explain`
# shows the result. See neon-analyze-flutter/README.md.

preset: $preset

# Branch the changed files are compared against.
default_base: $base

# Packs on top of the preset: `packs:` replaces its list, `skip_packs:` drops some.
# skip_packs: []

# One rule on or off: true, false, error, warning, info.
# rules: {}

# Where this app keeps each kind of code, when it differs from the default
# (roles: `$commandName explain`).
# layout:
#   providers: lib/app/app_providers.dart

# Test suites: which sources select which test folder.
# tests:
#   suites:
#     orders: [lib/pages/orders, lib/bloc/orders]
''');
  out.writeln('wrote ${CheckConfig.fileName} (preset $preset, base $base)');
  install(root, out);
  final config = CheckConfig.load(root, toolRoot: toolRoot);
  final options = File('$root/${ConfigSyncStep.optionsFile}');
  final before =
      options.existsSync() ? options.readAsStringSync() : 'include: package:neon_analysis/analysis_options.yaml\n';
  options.writeAsStringSync(ConfigSyncStep.withPluginBlock(before, ConfigSyncStep.pluginBlock(config)));
  out
    ..writeln('wrote the neon_lints section of ${ConfigSyncStep.optionsFile}')
    ..writeln()
    ..writeln('Next:')
    ..writeln('  $commandName explain                  check what was detected')
    ..writeln('  $commandName --all --update-baseline  today\'s findings become the baseline')
    ..writeln('  $commandName --zero <rule>            then bring one rule to zero at a time');
  return 0;
}

/// `neon-check integration [flows]`: runs flows on the app's driver (all
/// without arguments), from one build when `integration.combine` is on. A
/// background run is cancelled first: both would share the driver and the
/// test accounts. [record] (`--record`) is the background run itself
/// (started by the `stop` trigger): it writes its result for the next check.
Future<int> integration(String root, String toolRoot, List<String> files, {bool record = false}) async {
  final config = CheckConfig.load(root, toolRoot: toolRoot);
  final context = CheckContext(
    root: root,
    config: config,
    mode: ScopeMode.all,
    changedFiles: const {},
    deletedFiles: const {},
    fix: false,
    ci: true,
    toolRoot: toolRoot,
  );
  final background = BackgroundRun(root);
  if (!record) background.cancel(integrationDir: config.integrationDir);
  final flows = files.isEmpty ? integrationFlows(context) : files;
  stdout.writeln(
      'integration: ${flows.length} flow(s)${config.integrationCombine && flows.length > 1 ? ', one build' : ''}');
  final result = await runFlows(context, flows);
  stdout.writeln(result.output);
  if (record) background.writeResult(result.failed);
  for (final failure in result.failed) {
    stdout.writeln('integration: FAILED ${failure.flow} ${failure.log}');
  }
  stdout.writeln(result.failed.isEmpty
      ? 'integration: all ${flows.length} flow(s) passed'
      : 'integration: ${result.failed.length} flow(s) failed');
  return result.failed.isEmpty ? 0 : 1;
}
