import 'dart:io';

import 'package:neon_check/src/baseline.dart';
import 'package:neon_check/src/brief.dart';
import 'package:neon_check/src/burndown.dart';
import 'package:neon_check/src/config.dart';
import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/runner.dart';
import 'package:neon_check/src/steps/config_sync_step.dart';
import 'package:neon_check/src/steps/dart_steps.dart';
import 'package:neon_check/src/steps/integration_step.dart';
import 'package:neon_check/src/steps/rule_docs_step.dart';
import 'package:test/test.dart';

/// The neon-analyze-flutter checkout these tests run in (`checker/` is the
/// working directory of `dart test`).
final _tool = Directory.current.parent.path;

void _write(Directory dir, String path, [String content = '']) => File('${dir.path}/$path')
  ..createSync(recursive: true)
  ..writeAsStringSync(content);

CheckContext _context(String root, CheckConfig config,
        {Set<String> changed = const {}, IntegrationMode? integration}) =>
    CheckContext(
      root: root,
      config: config,
      mode: ScopeMode.changed,
      changedFiles: changed,
      deletedFiles: const {},
      fix: false,
      ci: true,
      integration: integration ?? IntegrationMode.affected,
      toolRoot: _tool,
    );

void main() {
  group('packs', () {
    final packs = CheckConfig.loadPacks('$_tool/packs.yaml');

    test('every plugin rule is in exactly one pack', () {
      final pluginRules = IgnoreCommentsStep.pluginRuleNames('$_tool/plugin');
      expect(pluginRules, isNotEmpty);
      final inPacks = [for (final pack in packs) ...pack.rules];
      expect(inPacks.toSet(), pluginRules, reason: 'a rule without a pack is never enabled');
      expect(inPacks.length, inPacks.toSet().length, reason: 'a rule in two packs has two switches');
    });

    test('every step is in a pack and every pack names real steps', () {
      final steps = {for (final step in allSteps()) step.name};
      final inPacks = {for (final pack in packs) ...pack.steps};
      expect(inPacks, steps);
    });

    test('presets name existing packs and never set a layout', () {
      final names = {for (final pack in packs) pack.name};
      for (final preset in Directory('$_tool/presets').listSync().whereType<File>()) {
        final source = preset.readAsStringSync();
        expect(RegExp(r'^layout:', multiLine: true).hasMatch(source), isFalse, reason: preset.path);
        final config = CheckConfig.parse(source, packs: packs);
        expect(config.enabledPacks.where((pack) => !names.contains(pack)), isEmpty, reason: preset.path);
      }
    });
  });

  group('loading an app', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('neon_config');
      _write(dir, 'pubspec.yaml', 'name: shop\n');
      _write(dir, 'lib/flavors/shop/shop_router.dart');
      _write(dir, 'lib/main_shop.dart');
      _write(dir, 'assets/translations/cs.json', '{}');
      _write(dir, 'assets/translations/en.json', '{}');
      Directory('${dir.path}/web').createSync();
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('base, preset and app merge in that order; facts are detected', () {
      _write(dir, 'neon_check.yaml', 'preset: admin\nskip_packs: [catalog]\nline_length: 100\n');
      final config = CheckConfig.load(dir.path, toolRoot: _tool);
      expect(config.errors, isEmpty);
      expect(config.lineLength, 100);
      expect(config.baselinePath, 'tool/lint_baseline.json');
      expect(config.enabledPacks, contains('kit'));
      expect(config.packEnabled('catalog'), isFalse);
      expect(config.stepEnabled('catalog_index'), isFalse);
      expect(config.stepEnabled('page_help'), isTrue);
      expect(config.flavors, ['shop']);
      expect(config.languages, ['cs', 'en']);
      expect(config.primaryLanguage, 'cs');
      expect(config.facts.platforms, ['web']);
      expect(config.defaultSuite, 'shop');
      expect(config.integrationDriver, 'web-server');
      expect(config.routeRouters, ['lib/flavors/shop/shop_router.dart']);
      expect(config.diagnostics['use_kit_widgets'], 'true');
    });

    test('the app preset leaves the admin packs off and their rules false', () {
      _write(dir, 'neon_check.yaml', 'preset: app\nrules: {no_raw_color: error}\n');
      final config = CheckConfig.load(dir.path, toolRoot: _tool);
      expect(config.packEnabled('admin'), isFalse);
      expect(config.diagnostics['page_uses_template'], 'false');
      expect(config.diagnostics['no_raw_color'], 'error');
      expect(config.stepEnabled('providers'), isFalse);
      expect(config.integrationDriver, 'device');
    });

    test('mistakes in the configuration are reported, not ignored', () {
      _write(dir, 'neon_check.yaml', '''
preset: admn
packs: [core, blok]
rules: {no_such_rule: true, avoid_bang: maybe}
layout: {pagez: lib/screens/}
''');
      final errors = CheckConfig.load(dir.path, toolRoot: _tool).errors.join('\n');
      expect(errors, contains('preset `admn` does not exist'));
      expect(errors, contains('pack `blok` does not exist'));
      expect(errors, contains('`no_such_rule` is not a neon_lints rule'));
      expect(errors, contains('`maybe` is not one of'));
      expect(errors, contains('`pagez` is not a role'));
    });

    test('page help expands per flavour and keeps only flavours with a help enum', () {
      _write(dir, 'neon_check.yaml', 'preset: admin\nflavors: [shop, admin]\n');
      _write(dir, 'lib/pages/shop/help/shop_page_help.dart');
      final entries = CheckConfig.load(dir.path, toolRoot: _tool).pageHelpEntries;
      expect(entries.map((entry) => entry.enumFile), ['lib/pages/shop/help/shop_page_help.dart']);
      expect(entries.single.pagePrefix, 'shop_');
      expect(entries.single.keyPrefix, 'shop_help_');
    });

    test('suites accept the short form', () {
      _write(dir, 'neon_check.yaml', 'tests:\n  suites:\n    orders: [lib/pages/orders]\n');
      final suites = CheckConfig.load(dir.path, toolRoot: _tool).suites;
      expect(suites['orders']?.tests, ['test/orders']);
      expect(suites['orders']?.sources, ['lib/pages/orders']);
    });
  });

  group('triggers', () {
    test('step groups resolve, unknown names do not', () {
      final steps = allSteps();
      expect(resolveStepNames(['static'], steps), isNot(contains('tests')));
      expect(resolveStepNames(['static'], steps), contains('analyze'));
      expect(resolveStepNames(['all'], steps), contains('integration'));
      expect(resolveStepNames(['ratchet', 'format'], steps), {'analyze', 'format'});
      expect(resolveStepNames(['nope'], steps), isNull);
    });

    test('the base preset defines the five triggers', () {
      final config = CheckConfig.parse(File('$_tool/presets/base.yaml').readAsStringSync());
      final triggers = config.triggers;
      expect(triggers.keys, containsAll(['edit', 'stop', 'commit', 'push', 'ci']));
      expect(triggers['edit']?.ci, isTrue);
      expect(triggers['stop']?.integration, IntegrationMode.affected);
      expect(triggers['ci']?.integration, IntegrationMode.all);
      for (final trigger in triggers.values) {
        expect(resolveStepNames(trigger.steps.isEmpty ? ['static'] : trigger.steps, allSteps()), isNotNull);
      }
    });
  });

  group('config sync', () {
    const block = '${ConfigSyncStep.startMarker}\nplugins:\n  neon_lints:\n    diagnostics:\n      a: true\n'
        '${ConfigSyncStep.endMarker}';

    test('a hand-written plugins section and its comment are replaced, other keys stay', () {
      const source = '''
include: package:x/y.yaml

# Our plugin.
plugins:
  neon_lints:
    path: p
    diagnostics:
      a: true

# The analyzer.
analyzer:
  plugins:
    - extra_pedantic
''';
      final result = ConfigSyncStep.withPluginBlock(source, block);
      expect(result, startsWith('include: package:x/y.yaml\n\n${ConfigSyncStep.startMarker}'));
      expect(result,
          contains('${ConfigSyncStep.endMarker}\n\n# The analyzer.\nanalyzer:\n  plugins:\n    - extra_pedantic\n'));
      expect(result, isNot(contains('# Our plugin.')));
      expect(ConfigSyncStep.withPluginBlock(result, block), result, reason: 'idempotent');
    });

    test('without a plugins section the block is appended', () {
      expect(ConfigSyncStep.withPluginBlock('include: a\n', block), 'include: a\n\n$block\n');
    });

    test('the block lists every rule of every pack, on or off', () {
      final config = CheckConfig.parse('packs: [core]', packs: CheckConfig.loadPacks('$_tool/packs.yaml'));
      final generated = ConfigSyncStep.pluginBlock(config);
      expect(generated, contains('      # core (on)\n      avoid_bang: true'));
      expect(generated, contains('      # kit (off)\n      use_kit_widgets: false'));
    });
  });

  group('integration flows', () {
    late Directory dir;
    late CheckConfig config;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('neon_flows');
      for (final flow in ['shop_login_flow_test.dart', 'orders_pay_flow_test.dart', 'orders_refund_flow_test.dart']) {
        _write(dir, 'integration_test/$flow', flow.startsWith('orders_pay') ? "import 'orders/support.dart';\n" : '');
      }
      _write(dir, 'integration_test/orders/support.dart');
      config = CheckConfig.parse('''
tests:
  default_suite: shop
  shared: [lib/utils]
  suites:
    orders: [lib/pages/orders]
''');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    List<String> select(Set<String> changed) => selectFlows(_context(dir.path, config, changed: changed));

    test('a flow belongs to the suite its name starts with', () {
      expect(suiteOfFlow('integration_test/orders_pay_flow_test.dart', 'shop', ['orders']), 'orders');
      expect(suiteOfFlow('integration_test/other_flow_test.dart', 'shop', ['orders']), 'shop');
    });

    test('a suite source selects its flows, any other source the default suite', () {
      expect(select({'lib/pages/orders/orders_page.dart'}),
          ['integration_test/orders_pay_flow_test.dart', 'integration_test/orders_refund_flow_test.dart']);
      expect(select({'lib/pages/home_page.dart'}), ['integration_test/shop_login_flow_test.dart']);
    });

    test('a shared source or pubspec.yaml runs every flow', () {
      expect(select({'lib/utils/a.dart'}), hasLength(3));
      expect(select({'pubspec.yaml'}), hasLength(3));
    });

    test('a changed shared step runs the flows that import it; tests and assets run none', () {
      expect(select({'integration_test/orders/support.dart'}), ['integration_test/orders_pay_flow_test.dart']);
      expect(select({'test/a_test.dart', 'assets/translations/cs.json'}), isEmpty);
    });

    test('off runs nothing, all runs everything', () {
      expect(
          selectFlows(_context(dir.path, config, changed: {'lib/a.dart'}, integration: IntegrationMode.off)), isEmpty);
      expect(selectFlows(_context(dir.path, config, integration: IntegrationMode.all)), hasLength(3));
    });
  });

  test('a failing flow is summarised from its log', () {
    final dir = Directory.systemTemp.createTempSync('neon_log');
    addTearDown(() => dir.deleteSync(recursive: true));
    _write(
        dir,
        'flow.log',
        'Launching\nGET /assets/x.ttf\nhandleRequest Error: noise\nThe following assertion was thrown:\n'
            'pumpAndSettle timed out\nSome tests failed.\n');
    expect(
      failureSummary('${dir.path}/flow.log'),
      'The following assertion was thrown: | pumpAndSettle timed out | Some tests failed.',
    );
    expect(failureSummary('${dir.path}/missing.log'), 'no log');
  });

  group('pages without a flow', () {
    test('a page is reached by an import or by its class name', () async {
      final dir = Directory.systemTemp.createTempSync('neon_pages');
      addTearDown(() => dir.deleteSync(recursive: true));
      _write(dir, 'lib/pages/a_page.dart', 'class APage {}\n');
      _write(dir, 'lib/pages/b_page.dart', 'class BPage {}\n');
      _write(dir, 'lib/pages/c_page.dart', '\nclass CPage {}\n');
      _write(dir, 'lib/pages/widgets/d_page.dart', 'class DPage {}\n');
      _write(dir, 'integration_test/x_test.dart', "import 'package:app/pages/a_page.dart';\nfind.byType(BPage);\n");
      final config = CheckConfig.parse('integration: {require_flow_for_pages: true}');
      final context = CheckContext(
        root: dir.path,
        config: config,
        mode: ScopeMode.all,
        changedFiles: const {},
        deletedFiles: const {},
        fix: false,
        ci: true,
      );
      // CheckConfig.parse detects nothing, so the import of the page names no
      // package: only the class name reaches B; A and C have no flow.
      final result = await const IntegrationPagesStep().run(context);
      expect(result.findings.map((finding) => '${finding.file}:${finding.line}'),
          ['lib/pages/a_page.dart:1', 'lib/pages/c_page.dart:2']);
    });
  });

  group('written rules and the brief', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('neon_docs');
      _write(dir, 'pubspec.yaml', 'name: shop\n');
      _write(dir, 'neon_check.yaml', 'preset: admin\n');
      _write(dir, '.claude/rules/shared/README.md', '# company overview, never a rule\n');
      _write(dir, '.claude/rules/shared/tokens.md',
          '---\npaths:\n  - "lib/**/*.dart"\n---\n# Tokens\n\nEnforced by: `no_raw_color`, `no_such_check`\n');
      _write(dir, '.claude/rules/shared/reuse.md',
          '---\npaths:\n  - "lib/**"\n---\n# Reuse\n\nNot enforced: judgement.\n');
      _write(dir, '.claude/rules/shared/silent.md', '---\npaths:\n  - "lib/pages/**"\n---\n# Silent\n\nNo marker.\n');
      _write(dir, '.claude/rules/shared/web.md', '---\npaths:\n  - "web/**"\n---\n# Web\n');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('a rule names existing checks or says it is not checked', () async {
      final config = CheckConfig.load(dir.path, toolRoot: _tool);
      final result = await const RuleDocsStep().run(_context(dir.path, config));
      expect(
          result.findings.map((finding) => '${finding.rule} ${finding.file}:${finding.line}'),
          unorderedEquals([
            'rule_doc_unlinked .claude/rules/shared/silent.md:1',
            'rule_doc_unknown_check .claude/rules/shared/tokens.md:7',
          ]));
    });

    test('the brief of a page lists its kind, its rules, its gates and its written rules', () {
      final config = CheckConfig.load(dir.path, toolRoot: _tool);
      final text = brief(config, _tool, 'lib/pages/shop/shop_orders_page.dart');
      expect(text, contains('it is `pages`, `subtitled_pages` (UI code)'));
      expect(text, contains('- page_uses_template: '));
      expect(text, contains('- no_setstate_in_pages: '));
      expect(text, isNot(contains('- state_is_sealed:')), reason: 'a bloc rule is not about a page');
      expect(text, contains('an integration flow in integration_test/ that opens this page'));
      expect(text, contains('Written rules for this path (.claude/rules/shared, the why): reuse, silent, tokens.'));
    });

    test('the brief of a cubit asks for its test; files outside lib get none', () {
      final config = CheckConfig.load(dir.path, toolRoot: _tool);
      final text = brief(config, _tool, 'lib/bloc/orders/orders_cubit.dart');
      expect(text, contains('- state_is_sealed: '));
      expect(text, contains('a cubit test `orders_cubit_test.dart`'));
      expect(brief(config, _tool, 'test/a_test.dart'), isEmpty);
    });
  });

  group('burndown', () {
    test('the queue follows the phases, then the rest by count; skipped rules wait for a person', () {
      final baseline = Baseline({
        'no_app_dimens': {'lib/a.dart': 5},
        'no_debug_print': {'lib/b.dart': 2},
        'unknown_big': {'lib/c.dart': 9},
        'unknown_small': {'lib/d.dart': 1},
        'test_missing': {'lib/bloc/x_cubit.dart': 1},
      });
      final phases = loadPhases(_tool);
      expect(phases.map((phase) => phase.name), containsAllInOrder(['local', 'tokens', 'cubits', 'tests']));
      final queue = burndownQueue(baseline, phases, const {});
      expect(queue.map((item) => item.rule),
          ['no_debug_print', 'no_app_dimens', 'test_missing', 'unknown_small', 'unknown_big']);
      expect(burndownQueue(baseline, phases, {'no_debug_print': 'needs a person'}).first.rule, 'no_app_dimens');
    });

    test('every rule of burndown.yaml is a real rule, in one phase only', () {
      final known = {
        ...IgnoreCommentsStep.pluginRuleNames('$_tool/plugin'),
        for (final step in allSteps()) ...?step.rules,
      };
      final listed = [for (final phase in loadPhases(_tool)) ...phase.rules];
      expect(listed.where((rule) => !known.contains(rule)), isEmpty);
      expect(listed.length, listed.toSet().length);
    });

    test('peek says off, setup, work or done, and only drives the recorded branch', () {
      final dir = Directory.systemTemp.createTempSync('neon_burndown');
      addTearDown(() => dir.deleteSync(recursive: true));
      Process.runSync('git', ['init', '-q', '-b', 'work'], workingDirectory: dir.path);
      _write(dir, 'pubspec.yaml', 'name: shop\n');
      _write(dir, 'neon_check.yaml', 'preset: app\n');
      expect(peek(dir.path, _tool), 'off');
      BurndownState(active: true, base: 'main').save(dir.path);
      expect(peek(dir.path, _tool), 'setup');
      BurndownState(active: true, base: 'main', branch: 'other').save(dir.path);
      expect(peek(dir.path, _tool), 'off');
      BurndownState(active: true, base: 'main', branch: 'work').save(dir.path);
      expect(peek(dir.path, _tool), 'done');
      Baseline({
        'no_debug_print': {'lib/a.dart': 3},
      }).save('${dir.path}/tool/lint_baseline.json');
      expect(peek(dir.path, _tool), 'work rule=no_debug_print left=3 total=3 max_turns=30');
      expect(burndownRunsHere(dir.path), isTrue);
    });

    test('skip needs a reason and survives a reload', () {
      final dir = Directory.systemTemp.createTempSync('neon_burndown');
      addTearDown(() => dir.deleteSync(recursive: true));
      _write(dir, 'pubspec.yaml', 'name: shop\n');
      _write(dir, 'neon_check.yaml', 'preset: app\n');
      final out = StringBuffer();
      expect(burndown(dir.path, _tool, ['skip', 'no_debug_print'], out: out), 64);
      expect(burndown(dir.path, _tool, ['skip', 'no_debug_print'], reason: 'logs of the payment SDK', out: out), 0);
      expect(BurndownState.load(dir.path).skipped, {'no_debug_print': 'logs of the payment SDK'});
      expect(burndown(dir.path, _tool, ['start'], base: 'main', out: out), 0);
      expect(File('${dir.path}/.gitignore').readAsStringSync(), contains('.neon-check/'));
    });
  });

  group('base branch', () {
    test('without a recorded neonBase the changed scope uses default_base', () {
      final dir = Directory.systemTemp.createTempSync('neon_git');
      addTearDown(() => dir.deleteSync(recursive: true));
      void git(List<String> args) {
        final result = Process.runSync('git', args, workingDirectory: dir.path);
        expect(result.exitCode, 0, reason: '${result.stderr}');
      }

      git(['init', '-q', '-b', 'main']);
      git(['config', 'user.email', 't@t']);
      git(['config', 'user.name', 't']);
      _write(dir, 'a.dart');
      git(['add', '.']);
      git(['commit', '-q', '-m', 'a']);
      git(['checkout', '-q', '-b', 'work']);
      _write(dir, 'b.dart');
      git(['add', '.']);
      git(['commit', '-q', '-m', 'b']);
      _write(dir, 'c.dart');
      expect(recordedBase(dir.path), isNull);
      expect(gitScope(dir.path, ScopeMode.changed, base: 'main').existing, {'b.dart', 'c.dart'});
      expect(() => gitScope(dir.path, ScopeMode.changed), throwsStateError);
    });
  });
}
