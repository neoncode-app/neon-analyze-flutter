import 'dart:io';

import 'package:args/args.dart';
import 'package:neon_check/src/brief.dart';
import 'package:neon_check/src/burndown.dart' as burndown;
import 'package:neon_check/src/commands.dart' as commands;
import 'package:neon_check/src/config.dart';
import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/runner.dart';

const _usage = '''
Neon Code check runner. Runs the checks of the app's packs in a fixed order
(config, format, fix, analyze + ratchet, translations, assets, catalog,
providers, help, generated code, test gates, tests, coverage, integration),
stops at the first failing step and prints failures only.

Usage: neon-check [command] [options] [files]

Commands:
  (none)               run the checks (a bare run is the `stop` trigger)
  explain              what the tool detected and will check in this app
  init                 a starting neon_check.yaml, git hooks, analyzer section
  install              point git at the shared hooks (core.hooksPath)
  integration [flows]  run integration flows on the app's driver (all without arguments)
  brief <file>         the rules and gates a file must pass, for the AI before it edits it
  next [--peek]        the next batch of the burndown: rule, exact findings, how to fix them
  burndown start|status|skip|unskip|stop
                       bring the baseline to zero, driven by the hooks (start --base <b>
                       [--branch <b> --ticket <key>], skip <rule> --reason "...")

When (default: the `stop` trigger of neon_check.yaml):
  --trigger <name>     edit | stop | commit | push | ci, or any trigger the app defines

Scope (overrides the trigger's):
  --changed            files changed against the branch base
  --all                the whole project
  --staged             files staged for commit
  --files a b          explicit files
''';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('root', help: 'App root (default: current directory).')
    ..addOption('tool', help: 'The neon-analyze-flutter checkout (default: <root>/neon-analyze-flutter).')
    ..addOption('trigger', help: 'Run as this trigger of neon_check.yaml (edit, stop, commit, push, ci).')
    ..addFlag('all', negatable: false)
    ..addFlag('changed', negatable: false)
    ..addFlag('staged', negatable: false)
    ..addMultiOption('files', help: 'Explicit files; the rest of the arguments are files too.')
    ..addOption('base', help: 'Base branch for --changed (default: branch.<name>.neonBase, else default_base).')
    ..addFlag('ci', negatable: false, help: 'Never change files or the baseline; auto-fix steps only check.')
    ..addOption('integration', allowed: ['off', 'affected', 'all'], help: 'Which integration flows run.')
    ..addMultiOption('zero', help: 'Rules that must have no finding at all (implies --all).')
    ..addOption('rule', help: 'List every finding of one rule (whole project) and exit 0.')
    ..addMultiOption('step', help: 'Run only these steps (see --list).')
    ..addFlag('list', negatable: false, help: 'List the steps.')
    ..addFlag('update-baseline', negatable: false, help: 'Rewrite the baseline to the current findings (--all).')
    ..addFlag('prune-translations', negatable: false, help: 'Delete unused translation keys from every file.')
    ..addOption('max-failures', defaultsTo: '0', help: 'Print at most this many failures (0 = all).')
    ..addOption('branch', help: 'burndown start: the branch the burndown works on.')
    ..addOption('ticket', help: 'burndown start: the ticket key.')
    ..addOption('reason', help: 'burndown skip: why a person must decide.')
    ..addFlag('peek', negatable: false, help: 'next: one line for the hooks, no analysis.')
    ..addFlag('help', abbr: 'h', negatable: false);
  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln('${error.message}\n\n$_usage\n${parser.usage}');
    exit(64);
  }
  if (args.flag('help')) {
    stdout.writeln('$_usage\n${parser.usage}');
    return;
  }
  if (args.flag('list')) {
    for (final (index, step) in allSteps().indexed) {
      stdout.writeln('${(index + 1).toString().padLeft(2)}. ${step.name.padRight(22)} ${step.description}');
    }
    return;
  }
  final root = (args.option('root') ?? Directory.current.path).replaceAll(RegExp(r'/+$'), '');
  final tool = args.option('tool') ?? '$root/neon-analyze-flutter';
  final rest = args.rest;
  final command = rest.isNotEmpty &&
          const {'explain', 'init', 'install', 'integration', 'brief', 'next', 'burndown'}.contains(rest.first)
      ? rest.first
      : null;
  try {
    switch (command) {
      case 'explain':
        exit(commands.explain(root, tool, stdout));
      case 'init':
        exit(commands.init(root, tool, stdout));
      case 'install':
        exit(commands.install(root, stdout));
      case 'integration':
        exit(await commands.integration(root, tool, rest.sublist(1)));
      case 'next':
        if (args.flag('peek')) {
          stdout.writeln(burndown.peek(root, tool));
          exit(0);
        }
        exit(await burndown.next(root, tool, stdout));
      case 'burndown':
        exit(burndown.burndown(
          root,
          tool,
          rest.sublist(1),
          base: args.option('base'),
          branch: args.option('branch'),
          ticket: args.option('ticket'),
          reason: args.option('reason'),
          out: stdout,
        ));
      case 'brief':
        for (final file in rest.sublist(1)) {
          final relative = file.startsWith('$root/') ? file.substring(root.length + 1) : file;
          final text = brief(CheckConfig.load(root, toolRoot: tool), tool, relative);
          if (text.isNotEmpty) stdout.writeln(text);
        }
        exit(0);
    }
    final files = [...args.multiOption('files'), ...rest];
    final mode = args.flag('all')
        ? ScopeMode.all
        : args.flag('staged')
            ? ScopeMode.staged
            : files.isNotEmpty
                ? ScopeMode.files
                : ScopeMode.changed;
    final integration = args.option('integration');
    final options = RunOptions(
      mode: mode,
      scopeGiven: args.flag('all') || args.flag('staged') || args.flag('changed') || files.isNotEmpty,
      files: files,
      base: args.option('base'),
      ci: args.flag('ci'),
      zero: {for (final rule in args.multiOption('zero')) ...rule.split(',')},
      rule: args.option('rule'),
      steps: [for (final step in args.multiOption('step')) ...step.split(',')],
      trigger: args.option('trigger'),
      integration: integration == null ? null : IntegrationMode.parse(integration, IntegrationMode.off),
      updateBaseline: args.flag('update-baseline'),
      pruneTranslations: args.flag('prune-translations'),
      maxFailures: int.tryParse(args.option('max-failures') ?? '0') ?? 0,
      toolRoot: tool,
    );
    exit(await runChecks(root, options));
  } on StateError catch (error) {
    stderr.writeln(error.message);
    exit(2);
  }
}
