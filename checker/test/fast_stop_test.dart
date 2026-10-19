import 'dart:convert';
import 'dart:io';

import 'package:neon_check/src/config.dart';
import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/steps/integration_runner.dart';
import 'package:neon_check/src/steps/integration_step.dart';
import 'package:neon_check/src/steps/test_impact.dart';
import 'package:neon_check/src/steps/tests_step.dart';
import 'package:test/test.dart';

/// NCC0000075: the stop trigger tests what a change reaches, runs the flows
/// from one build and leaves them running in the background.
void _write(Directory dir, String path, [String content = '']) => File('${dir.path}/$path')
  ..createSync(recursive: true)
  ..writeAsStringSync(content);

Directory _temp() {
  final dir = Directory.systemTemp.createTempSync('neon_check_fast');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

CheckContext _context(Directory dir, String yaml, {Set<String> changed = const {}, IntegrationMode? integration}) =>
    CheckContext(
      root: dir.path,
      config: CheckConfig.parse(yaml),
      mode: ScopeMode.changed,
      changedFiles: changed,
      deletedFiles: const {},
      fix: false,
      ci: true,
      integration: integration ?? IntegrationMode.off,
    );

void main() {
  group('import graph', () {
    test('package URIs of the app resolve under lib/, relative ones against the file, parts count, part of not', () {
      const source = '''
library;
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:app/pages/a.dart';
import '../support/harness.dart' if (dart.library.html) '../support/web.dart';
export 'package:app/model/m.dart' show M;
part 'x.g.dart';
part of 'other.dart';
''';
      expect(directDependencies('test/pages/a_test.dart', source, 'app'), {
        'lib/pages/a.dart',
        'test/support/harness.dart',
        'test/support/web.dart',
        'lib/model/m.dart',
        'test/pages/x.g.dart',
      });
    });

    test('a test is selected when its closure reaches a changed or deleted file, through cycles', () {
      final sources = {
        'test/a_test.dart': "import 'package:app/a.dart';",
        'test/b_test.dart': "import 'package:app/b.dart';",
        'test/gone_test.dart': "import 'package:app/gone.dart';",
        'lib/a.dart': "import 'c.dart';",
        'lib/c.dart': "import 'a.dart';\nimport 'deep.dart';",
        'lib/deep.dart': '',
        'lib/b.dart': "import 'a.dart';",
      };
      Set<String> impacted(Set<String> changed) => impactedTests(
            tests: ['test/a_test.dart', 'test/b_test.dart', 'test/gone_test.dart'],
            changed: changed,
            packageName: 'app',
            read: (file) => sources[file],
          );
      expect(impacted({'lib/deep.dart'}), {'test/a_test.dart', 'test/b_test.dart'});
      expect(impacted({'lib/b.dart'}), {'test/b_test.dart'});
      expect(impacted({'lib/gone.dart'}), {'test/gone_test.dart'});
      expect(impacted({'test/b_test.dart'}), {'test/b_test.dart'});
      expect(impacted({'lib/unrelated.dart'}), isEmpty);
    });

    test('the tests step runs only the reached tests, and falls back to the suites for what imports cannot see', () {
      final dir = _temp();
      _write(dir, 'pubspec.yaml', 'name: app');
      _write(dir, 'test/a_test.dart', "import 'package:app/a.dart';");
      _write(dir, 'test/other/b_test.dart', "import 'package:app/b.dart';");
      _write(dir, 'lib/a.dart');
      _write(dir, 'lib/b.dart');
      const yaml = 'tests:\n  default_suite: app\n  suites:\n    other: {tests: [test/other], sources: [lib/b.dart]}';
      const step = TestsStep();
      CheckContext context(Set<String> changed, [String extra = '']) => CheckContext(
            root: dir.path,
            config: CheckConfig.parse('$yaml$extra', facts: const ProjectFacts(name: 'app')),
            mode: ScopeMode.changed,
            changedFiles: changed,
            deletedFiles: const {},
            fix: false,
            ci: true,
          );
      expect(step.selectTestPaths(context({'lib/a.dart'})), ['test/a_test.dart']);
      expect(step.selectTestPaths(context({'lib/b.dart'})), ['test/other/b_test.dart']);
      expect(step.selectTestPaths(context({'assets/translations/cs.json'})), ['test/a_test.dart']);
      expect(step.selectTestPaths(context({'lib/b.dart'}, '\n  select: suites')), ['test/a_test.dart', 'test/other']);
    });
  });

  group('combined integration run', () {
    test('test descriptions join adjacent literals and unescape quotes', () {
      const source = '''
  testWidgets('the owner\\'s list '
      "narrows", (tester) async {});
  testWidgets(
    'a second one',
    (tester) async {},
  );
''';
      expect(testDescriptions(source), ["the owner's list narrows", 'a second one']);
    });

    test('a failure is attributed to its flow; an unknown failure names no flow', () {
      final dir = _temp();
      _write(dir, 'integration_test/x_a_test.dart', "testWidgets('opens a', (t) async {});");
      _write(dir, 'integration_test/x_b_test.dart', "testWidgets('opens b', (t) async {});");
      final context = _context(dir, '');
      const flows = ['integration_test/x_a_test.dart', 'integration_test/x_b_test.dart'];
      expect(attributeFailures(context, flows, 'x\nFailure in method: opens b\ny'), ['integration_test/x_b_test.dart']);
      expect(attributeFailures(context, flows, 'Failure in method: something else'), isEmpty);
      expect(attributeFailures(context, flows, 'Failed to compile application.'), isEmpty);
    });

    test('the target initialises the binding before the groups, resets after each flow and is git-excluded', () {
      final dir = _temp();
      Process.runSync('git', ['init', '-q'], workingDirectory: dir.path);
      final context = _context(dir, 'integration:\n  reset: integration_test/shared/reset.dart');
      Directory('${dir.path}/integration_test').createSync();
      final target = writeCombinedTarget(context, ['integration_test/x_a_test.dart', 'integration_test/x_b_test.dart']);
      final source = File('${dir.path}/$target').readAsStringSync();
      expect(target, 'integration_test/$combinedTargetName');
      expect(source, contains("import 'shared/reset.dart' as reset;"));
      expect(source, contains("import 'x_b_test.dart' as flow1;"));
      expect(
        source.indexOf('IntegrationTestWidgetsFlutterBinding.ensureInitialized();'),
        lessThan(source.indexOf("group('integration_test/x_a_test.dart'")),
      );
      expect('tearDown(reset.resetBetweenFlows);'.allMatches(source), hasLength(2));
      final status =
          Process.runSync('git', ['status', '--porcelain', '--untracked-files=all'], workingDirectory: dir.path);
      expect(status.stdout as String, isNot(contains(combinedTargetName)));
    });
  });

  group('background integration run', () {
    Directory app() {
      final dir = _temp();
      Process.runSync('git', ['init', '-q'], workingDirectory: dir.path);
      // As in every Flutter app: the state under build/ is not part of the tree.
      _write(dir, '.gitignore', 'build/\n');
      _write(dir, 'integration_test/app_x_test.dart', "testWidgets('x', (t) async {});");
      _write(dir, 'lib/a.dart');
      return dir;
    }

    const yaml = 'tests:\n  default_suite: app\nintegration:\n  driver: web-server\n';

    test('a run that passed on the same tree is reported and nothing starts', () async {
      final dir = app();
      final state = Directory('${dir.path}/$backgroundDir')..createSync(recursive: true);
      final fingerprint = treeFingerprint(dir.path);
      File('${state.path}/state.json').writeAsStringSync(jsonEncode({
        'pid': 0,
        'fingerprint': fingerprint,
        'flows': ['integration_test/app_x_test.dart'],
        'started': 'earlier',
      }));
      File('${state.path}/result.json').writeAsStringSync(jsonEncode({'failed': <Object>[]}));
      final context = _context(dir, yaml, changed: {'lib/a.dart'}, integration: IntegrationMode.background);
      const step = IntegrationStep();
      expect(step.appliesTo(context), isTrue);
      final result = await step.run(context);
      expect(result.findings, isEmpty);
      expect(result.notes.single, contains('passed on this tree'));
      expect(BackgroundRun(dir.path).fingerprint, fingerprint);
    });

    test('with too little memory nothing starts and the flows are left to ci', () async {
      final dir = app();
      final context = _context(
        dir,
        '${yaml}  background_min_memory_mb: 100000000',
        changed: {'lib/a.dart'},
        integration: IntegrationMode.background,
      );
      final result = await const IntegrationStep().run(context);
      expect(result.findings, isEmpty);
      expect(result.notes.single, contains('NOT started'));
      expect(BackgroundRun(dir.path).exists, isFalse);
    }, skip: availableMemoryMb() == null ? 'no /proc/meminfo here' : false);

    test('a run that ended without a result counts as unknown: it is reported and its flows run again', () async {
      final dir = app();
      final state = Directory('${dir.path}/$backgroundDir')..createSync(recursive: true);
      File('${state.path}/state.json').writeAsStringSync(jsonEncode({
        'pid': 0,
        'fingerprint': treeFingerprint(dir.path),
        'flows': ['integration_test/app_x_test.dart'],
        'started': 'earlier',
      }));
      final context = _context(
        dir,
        '${yaml}  background_min_memory_mb: 100000000',
        integration: IntegrationMode.background,
      );
      final result = await const IntegrationStep().run(context);
      expect(result.findings, isEmpty);
      expect(result.notes, [contains('ended without a result'), contains('1 flow(s) NOT started')]);
    }, skip: availableMemoryMb() == null ? 'no /proc/meminfo here' : false);

    test('a result written by the run is read back; a run without a live process is not running', () {
      final dir = _temp();
      Directory('${dir.path}/$backgroundDir').createSync(recursive: true);
      File('${dir.path}/$backgroundDir/state.json').writeAsStringSync(jsonEncode({'pid': 0, 'flows': <String>[]}));
      final run = BackgroundRun(dir.path)..writeResult([(flow: 'integration_test/a_test.dart', log: 'a.log')]);
      expect(run.running, isFalse);
      expect(run.result?.failed.single.flow, 'integration_test/a_test.dart');
      run.cancel(integrationDir: 'integration_test');
      expect(run.exists, isFalse);
    });
  });

  test('configuration errors name a wrong test selection and a wrong integration mode', () {
    final dir = _temp();
    _write(dir, 'pubspec.yaml', 'name: app');
    _write(dir, 'neon_check.yaml', 'tests:\n  select: some\ntriggers:\n  stop: {integration: sometimes}\n');
    final config = CheckConfig.load(dir.path, toolRoot: Directory.current.parent.path);
    expect(config.errors.join('\n'), allOf(contains('tests.select'), contains('triggers.stop.integration')));
  });
}
