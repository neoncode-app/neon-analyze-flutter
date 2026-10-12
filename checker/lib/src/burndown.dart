import 'dart:convert';
import 'dart:io';

import 'package:neon_check/src/baseline.dart';
import 'package:neon_check/src/config.dart';
import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/finding.dart';
import 'package:neon_check/src/runner.dart';
import 'package:neon_check/src/steps/dart_steps.dart';
import 'package:yaml/yaml.dart';

/// The burndown: bringing an app's baseline to zero, rule by rule, driven by
/// the tool. `burndown start` turns it on; from then on the session-start
/// hook tells every session to continue, the Stop hook does not let a turn
/// end while `next` has work (up to `burndown.max_turns_per_session`), and
/// `next` says what to fix and how. A rule that needs a person is skipped
/// with a reason and handed back.

/// The state of a burndown, kept per checkout in `.neon-check/burndown.json`
/// (never committed: it says which branch this machine works on).
final class BurndownState {
  BurndownState({
    this.active = false,
    this.base = '',
    this.branch = '',
    this.ticket = '',
    this.started = '',
    Map<String, String>? skipped,
  }) : skipped = skipped ?? {};

  factory BurndownState.load(String root) {
    final file = File('$root/$path');
    if (!file.existsSync()) return BurndownState();
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    return BurndownState(
      active: json['active'] == true,
      base: '${json['base'] ?? ''}',
      branch: '${json['branch'] ?? ''}',
      ticket: '${json['ticket'] ?? ''}',
      started: '${json['started'] ?? ''}',
      skipped: {
        for (final entry in ((json['skipped'] as Map<String, Object?>?) ?? {}).entries) entry.key: '${entry.value}',
      },
    );
  }

  static const path = '.neon-check/burndown.json';

  bool active;
  String base;
  String branch;
  String ticket;
  String started;

  /// Rules handed back to a person: rule -> why.
  final Map<String, String> skipped;

  void save(String root) {
    final file = File('$root/$path')..parent.createSync(recursive: true);
    file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert({
          'active': active,
          'base': base,
          'branch': branch,
          'ticket': ticket,
          'started': started,
          'skipped': skipped,
        })}\n');
  }
}

/// One phase of `burndown.yaml`.
typedef BurndownPhase = ({String name, String why, List<String> rules});

/// The phases of `burndown.yaml` in [toolRoot].
List<BurndownPhase> loadPhases(String toolRoot) {
  final file = File('$toolRoot/burndown.yaml');
  if (!file.existsSync()) return const [];
  final yaml = loadYaml(file.readAsStringSync());
  final phases = yaml is YamlMap ? yaml['phases'] : null;
  if (phases is! YamlList) return const [];
  return [
    for (final phase in phases.whereType<YamlMap>())
      (
        name: '${phase['name']}',
        why: '${phase['why'] ?? ''}',
        rules: [for (final rule in (phase['rules'] as YamlList? ?? YamlList())) '$rule'],
      ),
  ];
}

/// One rule waiting in the queue.
typedef QueuedRule = ({String rule, int count, int files, String phase, String why});

/// Every rule with findings in [baseline], in burndown order: the phases of
/// [phases], then the rest by count (smallest first). Skipped rules are left
/// out.
List<QueuedRule> burndownQueue(Baseline baseline, List<BurndownPhase> phases, Map<String, String> skipped) {
  int count(String rule) => baseline.filesOf(rule).fold(0, (sum, file) => sum + baseline.allowed(rule, file));
  final placed = <String>{};
  final queue = <QueuedRule>[];
  for (final phase in phases) {
    for (final rule in phase.rules) {
      placed.add(rule);
      final n = count(rule);
      if (n == 0 || skipped.containsKey(rule)) continue;
      queue.add((rule: rule, count: n, files: baseline.filesOf(rule).length, phase: phase.name, why: phase.why));
    }
  }
  final rest = [
    for (final rule in baseline.rules)
      if (!placed.contains(rule) && !skipped.containsKey(rule) && count(rule) > 0) rule,
  ]..sort((a, b) => count(a).compareTo(count(b)));
  for (final rule in rest) {
    queue.add(
        (rule: rule, count: count(rule), files: baseline.filesOf(rule).length, phase: 'rest', why: 'not in any phase'));
  }
  return queue;
}

String? _currentBranch(String root) {
  final result = Process.runSync('git', ['branch', '--show-current'], workingDirectory: root);
  return result.exitCode == 0 ? (result.stdout as String).trim() : null;
}

int _total(List<QueuedRule> queue) => queue.fold(0, (sum, item) => sum + item.count);

Map<String, Object?> _section(CheckConfig config) {
  final value = config.raw['burndown'];
  return value is Map<String, Object?> ? value : const {};
}

/// Findings per batch (`burndown.batch`, default 40).
int batchSize(CheckConfig config) => (_section(config)['batch'] as int?) ?? 40;

/// Burndown turns the Stop hook drives per session (`burndown.max_turns_per_session`).
int maxTurns(CheckConfig config) => (_section(config)['max_turns_per_session'] as int?) ?? 30;

/// Integration mode of the `stop` trigger while a burndown runs
/// (`burndown.stop_integration`, default off: a burndown touches shared code
/// all the time, so every turn would run every flow).
IntegrationMode stopIntegration(CheckConfig config) =>
    IntegrationMode.parse(_section(config)['stop_integration'], IntegrationMode.off);

/// Whether a burndown runs on the current branch of [root].
bool burndownRunsHere(String root) {
  final state = BurndownState.load(root);
  return state.active && state.branch.isNotEmpty && state.branch == _currentBranch(root);
}

/// `neon-check next --peek`: one line for the hooks, no analysis.
///
/// `off` (no burndown on this branch), `setup` (on, no branch recorded yet),
/// `done`, or `work rule=<r> left=<n> total=<t> max_turns=<m>`.
String peek(String root, String toolRoot) {
  final state = BurndownState.load(root);
  if (!state.active) return 'off';
  if (state.branch.isEmpty) return 'setup';
  if (state.branch != _currentBranch(root)) return 'off';
  final config = CheckConfig.load(root, toolRoot: toolRoot);
  final queue = burndownQueue(Baseline.load('$root/${config.baselinePath}'), loadPhases(toolRoot), state.skipped);
  if (queue.isEmpty) return 'done';
  return 'work rule=${queue.first.rule} left=${queue.first.count} total=${_total(queue)} max_turns=${maxTurns(config)}';
}

/// `neon-check next`: the next batch to fix, with the exact findings and the
/// procedure.
Future<int> next(String root, String toolRoot, StringSink out) async {
  final config = CheckConfig.load(root, toolRoot: toolRoot);
  final state = BurndownState.load(root);
  final baseline = Baseline.load('$root/${config.baselinePath}');
  final phases = loadPhases(toolRoot);
  final queue = burndownQueue(baseline, phases, state.skipped);
  if (queue.isEmpty) {
    out
      ..writeln(
          'neon-check next: the baseline is empty${state.skipped.isEmpty ? '' : ' apart from the skipped rules'}.')
      ..writeln(_finishText(state));
    return 0;
  }
  final item = queue.first;
  final files = baseline.filesOf(item.rule).toList()..sort();
  final batch = <String>[];
  var inBatch = 0;
  for (final file in files) {
    if (inBatch >= batchSize(config) && batch.isNotEmpty) break;
    batch.add(file);
    inBatch += baseline.allowed(item.rule, file);
  }
  final findings = await _findingsOf(root, toolRoot, config, item.rule, batch);
  final catalog = _catalogEntry(toolRoot, item.rule);
  final phaseIndex = phases.indexWhere((phase) => phase.name == item.phase);

  out
    ..writeln('neon-check next: ${_total(queue)} finding(s) left in ${queue.length} rule(s). '
        'Phase ${phaseIndex < 0 ? '-' : '${phaseIndex + 1}/${phases.length}'} `${item.phase}`: ${item.why}.')
    ..writeln()
    ..writeln('Rule `${item.rule}`: ${item.count} left in ${item.files} file(s).'
        '${catalog == null ? '' : ' ${catalog.description} ${catalog.correction}'.trimRight()}')
    ..writeln()
    ..writeln('This batch: ${batch.length} file(s), ${findings.length} finding(s):');
  for (final finding in findings) {
    out.writeln(finding.format());
  }
  if (findings.isEmpty) {
    out.writeln('(no finding reproduced: the baseline is ahead of the code; run `$commandName` to lower it)');
  }
  out
    ..writeln()
    ..writeln('How:')
    ..writeln('1. Fix every finding above. Behaviour and appearance stay exactly the same; follow the rule\'s '
        'correction and the written rules of each path (`$commandName brief <file>`).')
    ..writeln('2. Run `$commandName` (the stop trigger): it must pass and it lowers the baseline for these files.')
    ..writeln('3. Commit: "${state.ticket.isEmpty ? '<ticket>' : state.ticket}: ${item.rule} '
        '(${item.count} -> <left>)", and note the progress in the ticket.')
    ..writeln('4. Run `$commandName next` again.')
    ..writeln('Never `// ignore:`, never raise the baseline, never change a rule to pass. If a finding is not a real '
        'problem or needs a decision of a person, hand the rule back: '
        '`$commandName burndown skip ${item.rule} --reason "<why>"`.');
  return 0;
}

String _finishText(BurndownState state) => [
      if (state.skipped.isNotEmpty) ...[
        'Skipped rules, for a person to decide:',
        for (final entry in state.skipped.entries) '  ${entry.key}: ${entry.value}',
      ],
      'Finish: `$commandName --trigger ci` green (all tests and flows), `$commandName burndown stop`, then /done '
          '(PR into ${state.base.isEmpty ? 'the base branch' : state.base}).',
    ].join('\n');

typedef _CatalogEntry = ({String description, String correction});

_CatalogEntry? _catalogEntry(String toolRoot, String rule) {
  final file = File('$toolRoot/plugin/rule_catalog.json');
  if (!file.existsSync()) return null;
  final rules = (jsonDecode(file.readAsStringSync()) as Map<String, Object?>)['rules'];
  final entry = rules is Map<String, Object?> ? rules[rule] : null;
  if (entry is! Map<String, Object?>) return null;
  final correction = '${entry['correction'] ?? ''}';
  return (description: '${entry['description'] ?? ''}', correction: correction.contains('{') ? '' : correction);
}

/// The exact findings of [rule] in [files]: the analyzer on just those files
/// for an analyzer rule, else the step that reports the rule.
Future<List<Finding>> _findingsOf(
    String root, String toolRoot, CheckConfig config, String rule, List<String> files) async {
  final steps = allSteps();
  final owner = steps.where((step) => step.rules?.contains(rule) ?? false).firstOrNull;
  final context = CheckContext(
    root: root,
    config: config,
    mode: owner == null ? ScopeMode.files : ScopeMode.all,
    changedFiles: owner == null ? files.toSet() : const {},
    deletedFiles: const {},
    fix: false,
    ci: true,
    toolRoot: toolRoot,
  );
  final result = await (owner ?? const AnalyzeStep()).run(context);
  final wanted = files.toSet();
  return [
    for (final finding in result.findings)
      if (finding.rule == rule && wanted.contains(finding.file)) finding,
  ]..sort((a, b) => a.file == b.file ? a.line.compareTo(b.line) : a.file.compareTo(b.file));
}

/// `neon-check burndown <start|status|skip|unskip|stop>`.
int burndown(String root, String toolRoot, List<String> args,
    {String? base, String? branch, String? ticket, String? reason, required StringSink out}) {
  final command = args.isEmpty ? 'status' : args.first;
  final state = BurndownState.load(root);
  final config = CheckConfig.load(root, toolRoot: toolRoot);
  switch (command) {
    case 'start':
      state
        ..active = true
        ..base = base ?? (state.base.isEmpty ? (config.defaultBase ?? '') : state.base)
        ..branch = branch ?? state.branch
        ..ticket = ticket ?? state.ticket
        ..started = state.started.isEmpty ? DateTime.now().toIso8601String() : state.started;
      if (state.base.isEmpty) {
        out.writeln('Pass --base <branch> (the branch the burndown PRs go into).');
        return 64;
      }
      state.save(root);
      _ignoreStateFolder(root);
      out.writeln('burndown on: base ${state.base}${state.branch.isEmpty ? '' : ', branch ${state.branch}'}'
          '${state.ticket.isEmpty ? '' : ', ticket ${state.ticket}'}');
      if (state.branch.isEmpty) {
        out.writeln('Next session: a ticket and a branch from ${state.base} are created and recorded with '
            '`$commandName burndown start --branch <branch> --ticket <key>`; then `$commandName next` drives the work.');
      }
      return 0;
    case 'skip':
      if (args.length < 2 || reason == null || reason.trim().isEmpty) {
        out.writeln('Usage: $commandName burndown skip <rule> --reason "<why a person must decide>"');
        return 64;
      }
      state.skipped[args[1]] = reason.trim();
      state.save(root);
      out.writeln(
          'skipped ${args[1]}: $reason (a person decides; `$commandName burndown unskip ${args[1]}` brings it back)');
      return 0;
    case 'unskip':
      if (args.length < 2) return 64;
      state.skipped.remove(args[1]);
      state.save(root);
      out.writeln('${args[1]} is back in the queue');
      return 0;
    case 'stop':
      state.active = false;
      state.save(root);
      out.writeln('burndown off (the state stays in ${BurndownState.path}; `burndown start` resumes)');
      return 0;
    case 'status':
      final queue = burndownQueue(Baseline.load('$root/${config.baselinePath}'), loadPhases(toolRoot), state.skipped);
      out
        ..writeln('burndown ${state.active ? 'on' : 'off'}: base ${state.base.isEmpty ? '-' : state.base}, '
            'branch ${state.branch.isEmpty ? '-' : state.branch}, ticket ${state.ticket.isEmpty ? '-' : state.ticket}')
        ..writeln('${_total(queue)} finding(s) left in ${queue.length} rule(s)');
      final byPhase = <String, int>{};
      for (final item in queue) {
        byPhase[item.phase] = (byPhase[item.phase] ?? 0) + item.count;
      }
      for (final entry in byPhase.entries) {
        out.writeln('  ${entry.key.padRight(10)} ${entry.value}');
      }
      if (queue.isNotEmpty) out.writeln('next: ${queue.first.rule} (${queue.first.count})');
      for (final entry in state.skipped.entries) {
        out.writeln('skipped ${entry.key}: ${entry.value}');
      }
      return 0;
    case 'session':
      // For the session-start hook: what this session has to do, or nothing.
      if (!state.active) return 0;
      if (state.branch.isEmpty) {
        out.writeln('[neon-check burndown] A burndown of the lint baseline is on (base ${state.base}) and has no '
            'branch yet. Before anything else: create ONE ticket (type change) for it in ESME, ask the user to '
            'confirm its transitions, create the branch change/<KEY>-lint-burndown from ${state.base}, set '
            '`git config branch.<branch>.neonBase ${state.base}`, record it with '
            '`$commandName burndown start --branch <branch> --ticket <KEY>`, then run `$commandName next` and work '
            'through it. Commit after every batch, note progress in the ticket.');
      } else if (state.branch != _currentBranch(root)) {
        out.writeln('[neon-check burndown] A burndown runs on branch ${state.branch} (ticket ${state.ticket}). This '
            'session is on another branch, so it is not driven here; check out ${state.branch} to continue it.');
      } else {
        out.writeln('[neon-check burndown] Continue the burndown of ticket ${state.ticket} on ${state.branch}: run '
            '`$commandName next`, fix the batch, run `$commandName`, commit, note progress in the ticket, repeat. '
            'Skip a rule that needs a person with `$commandName burndown skip <rule> --reason "..."`.');
      }
      return 0;
  }
  out.writeln('Usage: $commandName burndown start|status|skip|unskip|stop');
  return 64;
}

void _ignoreStateFolder(String root) {
  final gitignore = File('$root/.gitignore');
  final current = gitignore.existsSync() ? gitignore.readAsStringSync() : '';
  if (current.split('\n').any((line) => line.trim() == '.neon-check/')) return;
  gitignore.writeAsStringSync(
    '${current.isEmpty || current.endsWith('\n') ? current : '$current\n'}'
    '\n# neon-check burndown state of this checkout\n.neon-check/\n',
  );
}
