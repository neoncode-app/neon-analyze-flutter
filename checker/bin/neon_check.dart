import 'dart:io';

import 'package:args/args.dart';
import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/runner.dart';

const _usage = '''
Neon Code check runner. Runs format, fix, analyze + ratchet, translation,
asset, catalog, provider, help, generated-code and test checks in a fixed
order, stops at the first failing step and prints failures only.

Scope (default --changed):
  --changed            files changed against the branch base (branch.<name>.neonBase)
  --all                the whole project (CI)
  --staged             files staged for commit (pre-commit hook)
  --files a b          explicit files (editor hooks)
''';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('root', help: 'App root (default: current directory).')
    ..addFlag('all', negatable: false)
    ..addFlag('changed', negatable: false)
    ..addFlag('staged', negatable: false)
    ..addMultiOption('files', help: 'Explicit files; the rest of the arguments are files too.')
    ..addOption('base', help: 'Base branch for --changed when the branch records none.')
    ..addFlag('ci', negatable: false, help: 'Never change files or the baseline; auto-fix steps only check.')
    ..addMultiOption('zero', help: 'Rules that must have no finding at all (implies --all).')
    ..addOption('rule', help: 'List every finding of one rule (whole project) and exit 0.')
    ..addMultiOption('step', help: 'Run only these steps (see --list).')
    ..addFlag('list', negatable: false, help: 'List the steps.')
    ..addFlag('update-baseline', negatable: false, help: 'Rewrite the baseline to the current findings (--all).')
    ..addFlag('prune-translations', negatable: false, help: 'Delete unused translation keys from every file.')
    ..addOption('max-failures', defaultsTo: '0', help: 'Print at most this many failures (0 = all).')
    ..addFlag('help', abbr: 'h', negatable: false);
  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln('${error.message}\n\n$_usage${parser.usage}');
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
  final files = [...args.multiOption('files'), ...args.rest];
  final mode = args.flag('all')
      ? ScopeMode.all
      : args.flag('staged')
          ? ScopeMode.staged
          : files.isNotEmpty
              ? ScopeMode.files
              : ScopeMode.changed;
  final options = RunOptions(
    mode: mode,
    files: files,
    base: args.option('base'),
    ci: args.flag('ci'),
    zero: {for (final rule in args.multiOption('zero')) ...rule.split(',')},
    rule: args.option('rule'),
    steps: [for (final step in args.multiOption('step')) ...step.split(',')],
    updateBaseline: args.flag('update-baseline'),
    pruneTranslations: args.flag('prune-translations'),
    maxFailures: int.tryParse(args.option('max-failures') ?? '0') ?? 0,
  );
  try {
    exit(await runChecks(root, options));
  } on StateError catch (error) {
    stderr.writeln(error.message);
    exit(2);
  }
}
