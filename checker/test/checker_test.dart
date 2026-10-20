import 'dart:io';

import 'package:neon_check/src/baseline.dart';
import 'package:neon_check/src/config.dart';
import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/finding.dart';
import 'package:neon_check/src/steps/project_steps.dart';
import 'package:neon_check/src/steps/dart_steps.dart';
import 'package:neon_check/src/steps/duplicates_step.dart';
import 'package:neon_check/src/steps/translation_steps.dart';
import 'package:neon_check/src/steps/coverage_step.dart';
import 'package:neon_check/src/steps/test_existence_step.dart';
import 'package:neon_check/src/steps/tests_step.dart';
import 'package:test/test.dart';

Finding _f(String rule, String file, [int line = 1]) => Finding(rule: rule, file: file, line: line, message: 'm');

void _write(Directory dir, String path, [String content = '']) => File('${dir.path}/$path')
  ..createSync(recursive: true)
  ..writeAsStringSync(content);

void main() {
  group('ratchet', () {
    RatchetResult check(Baseline baseline, List<Finding> findings, {Set<String> zero = const {}, bool lower = true}) =>
        ratchet(
          findings: findings,
          baseline: baseline,
          owns: (rule) => true,
          inScope: (file) => true,
          zero: zero,
          lower: lower,
        );

    test('a new finding without a baseline fails', () {
      final result = check(Baseline({}), [_f('no_navigator', 'lib/a.dart')]);
      expect(result.failures, hasLength(1));
    });

    test('findings within the baseline pass', () {
      final baseline = Baseline({
        'no_navigator': {'lib/a.dart': 2},
      });
      expect(
          check(baseline, [_f('no_navigator', 'lib/a.dart'), _f('no_navigator', 'lib/a.dart', 2)]).failures, isEmpty);
    });

    test('one finding above the count fails and reports every finding of that file', () {
      final baseline = Baseline({
        'no_navigator': {'lib/a.dart': 1},
      });
      final result = check(baseline, [_f('no_navigator', 'lib/a.dart'), _f('no_navigator', 'lib/a.dart', 2)]);
      expect(result.failures, hasLength(2));
      expect(result.failures.first.message, contains('baseline allows 1'));
    });

    test('a dropped count lowers the baseline, a vanished file removes its entry', () {
      final baseline = Baseline({
        'no_navigator': {'lib/a.dart': 3, 'lib/b.dart': 1},
      });
      final result = check(baseline, [_f('no_navigator', 'lib/a.dart')]);
      expect(result.failures, isEmpty);
      expect(baseline.allowed('no_navigator', 'lib/a.dart'), 1);
      expect(baseline.allowed('no_navigator', 'lib/b.dart'), 0);
      expect(baseline.isDirty, isTrue);
    });

    test('--ci never lowers the baseline', () {
      final baseline = Baseline({
        'no_navigator': {'lib/a.dart': 3},
      });
      check(baseline, const [], lower: false);
      expect(baseline.allowed('no_navigator', 'lib/a.dart'), 3);
    });

    test('--zero ignores the baseline for that rule', () {
      final baseline = Baseline({
        'no_navigator': {'lib/a.dart': 5},
      });
      expect(check(baseline, [_f('no_navigator', 'lib/a.dart')], zero: {'no_navigator'}).failures, hasLength(1));
    });

    test('hard findings are never tolerated', () {
      final baseline = Baseline({
        'undefined_identifier': {'lib/a.dart': 5},
      });
      final hard = const Finding(rule: 'undefined_identifier', file: 'lib/a.dart', message: 'm', hard: true);
      expect(check(baseline, [hard]).failures, [hard]);
    });

    test('entries outside the scope are neither checked nor lowered', () {
      final baseline = Baseline({
        'no_navigator': {'lib/other.dart': 4},
      });
      ratchet(
        findings: const [],
        baseline: baseline,
        owns: (rule) => true,
        inScope: (file) => file == 'lib/a.dart',
      );
      expect(baseline.allowed('no_navigator', 'lib/other.dart'), 4);
    });

    test('baseline round-trips through its file', () {
      final dir = Directory.systemTemp.createTempSync('neon_check');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/baseline.json';
      Baseline({
        'b': {'z.dart': 1, 'a.dart': 2},
      }).save(path);
      expect(Baseline.load(path).allowed('b', 'a.dart'), 2);
    });
  });

  group('suite selection', () {
    final suites = {
      'vernak': (tests: ['test/vernak'], sources: ['lib/pages/vernak', 'lib/bloc/neoncode/admin_*']),
      'doordrop': (tests: ['test/doordrop'], sources: ['lib/pages/neoncode/neoncode_doordrop_*']),
    };
    Set<String> select(List<String> files) =>
        selectSuites(changedFiles: files, suites: suites, shared: ['lib/utils'], defaultSuite: 'neoncode');

    test('the default suite always runs', () {
      expect(select(['lib/pages/neoncode/neoncode_users_page.dart']), {'neoncode'});
    });

    test('an app source selects its suite', () {
      expect(select(['lib/pages/vernak/vernak_cards_page.dart']), {'neoncode', 'vernak'});
      expect(select(['lib/bloc/neoncode/admin_coupons_mgmt/x.dart']), {'neoncode', 'vernak'});
      expect(select(['lib/pages/neoncode/neoncode_doordrop_stats_page.dart']), {'neoncode', 'doordrop'});
    });

    test('a changed test selects its own suite', () {
      expect(select(['test/doordrop/doordrop_helpers_test.dart']), {'neoncode', 'doordrop'});
    });

    test('a shared source selects every suite', () {
      expect(select(['lib/utils/utils.dart']), {'neoncode', 'vernak', 'doordrop'});
    });

    test('globs', () {
      expect(matchesGlob('lib/bloc/neoncode/admin_*', 'lib/bloc/neoncode/admin_x/y.dart'), isTrue);
      expect(matchesGlob('lib/bloc/neoncode/admin_*', 'lib/bloc/neoncode/vernak_x/y.dart'), isFalse);
      expect(matchesGlob('lib/main_*.dart', 'lib/main_vernak.dart'), isTrue);
      expect(matchesGlob('lib/**/x.dart', 'lib/a/b/x.dart'), isTrue);
      expect(matchesGlob('lib/utils', 'lib/utilsx/a.dart'), isFalse);
    });
  });

  test('analyzer machine output is parsed, compile errors are hard', () {
    const output =
        'WARNING|STATIC_WARNING|NO_NAVIGATOR|/app/lib/a.dart|3|5|9|[NEON] Navigator is imperative navigation; use x.\n'
        'ERROR|COMPILE_TIME_ERROR|UNDEFINED_IDENTIFIER|/app/lib/b.dart|7|1|3|Undefined name a\\|b.\n'
        'Analyzing app...\n';
    final findings = AnalyzeStep.parseMachineOutput(output, (path) => path.replaceFirst('/app/', ''));
    expect(findings.map((finding) => finding.format()), [
      'lib/a.dart:3 no_navigator: [NEON] Navigator is imperative navigation; use x.',
      'lib/b.dart:7 undefined_identifier: Undefined name a|b.',
    ]);
    expect(findings.map((finding) => finding.hard), [false, true]);
  });

  group('analyze batches of an --all run (NCC0000078)', () {
    test('without nested packages one bare dart analyze covers the app', () {
      expect(AnalyzeStep.allBatches(['lib/a.dart'], const {}), [<String>[]]);
    });

    test('a nested package never shares a process with the app', () {
      final batches = AnalyzeStep.allBatches(
        ['lib/a.dart', 'test/a_test.dart'],
        {
          'packages/p': ['packages/p/lib/p.dart']
        },
      );
      expect(batches, [
        ['lib/a.dart', 'test/a_test.dart'],
        ['packages/p/lib/p.dart'],
      ]);
    });

    test('nested packages are the tracked pubspecs below the root', () {
      final dir = Directory.systemTemp.createTempSync('neon_nested_');
      addTearDown(() => dir.deleteSync(recursive: true));
      _write(dir, 'pubspec.yaml');
      _write(dir, 'lib/a.dart');
      _write(dir, 'packages/p/pubspec.yaml');
      _write(dir, 'packages/p/lib/p.dart');
      _write(dir, 'packages/p/lib/p.g.dart');
      _write(dir, 'packages/p/.dart_tool/x.dart');
      _write(dir, 'packages/untracked/pubspec.yaml');
      _write(dir, 'packages/untracked/lib/u.dart');
      for (final args in [
        ['init', '-q'],
        ['add', 'pubspec.yaml', 'lib', 'packages/p/pubspec.yaml', 'packages/p/lib/p.dart'],
      ]) {
        Process.runSync('git', args, workingDirectory: dir.path);
      }
      final context = CheckContext(
        root: dir.path,
        config: CheckConfig.parse(''),
        mode: ScopeMode.all,
        changedFiles: const {},
        deletedFiles: const {},
        fix: false,
        ci: true,
      );
      expect(AnalyzeStep.nestedPackageFiles(context), {
        'packages/p': ['packages/p/lib/p.dart'],
      });
    });
  });

  group('translations', () {
    late Directory dir;
    late CheckContext context;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('neon_check');
      File('${dir.path}/assets/translations/cs.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
            '{\n  "a_one": "Jedna",\n  "api_error": {\n    "X": "Chyba — x"\n  },\n  "b_two": "Dva"\n}\n');
      File('${dir.path}/assets/translations/en.json').writeAsStringSync('{\n  "b_two": "Two",\n  "a_one": "One"\n}\n');
      File('${dir.path}/lib/page.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          "/// Example: tr('doc_only')\n"
          "final a = tr('a_one');\n"
          "final m = tr('missing_key');\n"
          r"final d = tr('api_error.$code');"
          '\n',
        );
      context = CheckContext(
        root: dir.path,
        config: CheckConfig.parse('translations: {languages: [cs, en], primary: cs}\nsource_dirs: [lib]'),
        mode: ScopeMode.all,
        changedFiles: const {},
        deletedFiles: const {},
        fix: false,
        ci: true,
      );
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('keys are flattened with their lines', () {
      final cs = TranslationFile.load(context, 'cs');
      expect(cs.values.keys, ['a_one', 'api_error.X', 'b_two']);
      expect(cs.lineOf('api_error.X'), 4);
      expect(cs.lineOf('b_two'), 6);
    });

    test('parity reports keys missing in a language', () async {
      final result = await const TranslationParityStep().run(context);
      expect(result.findings.map((finding) => '${finding.file} ${finding.message}'), [
        contains('en.json key `api_error.X` is missing'),
      ]);
    });

    test('a plural group needs only the categories its language uses (NCC0000078)', () async {
      File('${dir.path}/assets/translations/cs.json').writeAsStringSync(
        '{\n  "n": {\n    "one": "{} bod",\n    "few": "{} body",\n    "other": "{} bodů"\n  },\n'
        '  "v": {\n    "one": "a",\n    "other": "b"\n  }\n}\n',
      );
      File('${dir.path}/assets/translations/en.json').writeAsStringSync(
        '{\n  "n": {\n    "one": "{} point",\n    "many": "{} points",\n    "other": "{} points"\n  },\n'
        '  "v": {\n    "one": "a"\n  }\n}\n',
      );
      final result = await const TranslationParityStep().run(context);
      expect(result.findings.map((finding) => '${finding.file} ${finding.message}'), [
        contains('en.json key `v.other` is missing'),
      ]);
    });

    test('dashes are reported with their line', () async {
      final result = await const TranslationDashesStep().run(context);
      expect(result.findings.single.format(), startsWith('assets/translations/cs.json:4 translation_dash'));
    });

    test('a missing literal key is reported, comments and dynamic keys are not', () async {
      final result = await const TranslationMissingStep().run(context);
      expect(result.findings.single.format(), startsWith('lib/page.dart:3 translation_missing'));
    });

    test('unused keys exclude literal and dynamic uses', () async {
      final result = await const TranslationUnusedStep().run(context);
      expect(result.findings.single.message, startsWith('`b_two`'));
    });

    test('order is checked against the primary file and fixed', () async {
      expect((await const TranslationOrderStep().run(context)).findings, hasLength(1));
      final fixing = CheckContext(
        root: context.root,
        config: context.config,
        mode: context.mode,
        changedFiles: const {},
        deletedFiles: const {},
        fix: true,
        ci: false,
      );
      expect((await const TranslationOrderStep().run(fixing)).fixed, ['assets/translations/en.json']);
      expect(TranslationFile.load(context, 'en').values.keys, ['a_one', 'b_two']);
    });
  });

  test('suite paths skip folders without a _test.dart file (the shared harness, an empty suite)', () {
    final dir = Directory.systemTemp.createTempSync('neon_check');
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final path in [
      'test/global/a_test.dart',
      'test/neoncode/b_test.dart',
      'test/support/harness.dart',
      'test/vernak/c_test.dart'
    ]) {
      File('${dir.path}/$path').createSync(recursive: true);
    }
    Directory('${dir.path}/test/quest').createSync(recursive: true);
    File('${dir.path}/test/flutter_test_config.dart').createSync();
    final context = CheckContext(
      root: dir.path,
      config: CheckConfig.parse(
        'tests:\n  default_suite: neoncode\n  suites:\n    vernak: {tests: [test/vernak]}\n    quest: {tests: [test/quest]}',
      ),
      mode: ScopeMode.changed,
      changedFiles: const {},
      deletedFiles: const {},
      fix: false,
      ci: true,
    );
    const step = TestsStep();
    expect(step.pathsOf(context, 'neoncode'), ['test/global', 'test/neoncode']);
    expect(step.pathsOf(context, 'vernak'), ['test/vernak']);
    expect(step.pathsOf(context, 'quest'), isEmpty);
    expect(TestsStep.hasTests('${dir.path}/test/support'), isFalse);
  });

  test('a registry path of a named package resolves in that package, other missing paths are reported', () async {
    final dir = Directory.systemTemp.createTempSync('neon_check');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/pkg/assets/icons/stamp.svg').createSync(recursive: true);
    File('${dir.path}/assets/icons/own.svg').createSync(recursive: true);
    File('${dir.path}/.dart_tool/package_config.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
          '{"configVersion": 2, "packages": [{"name": "cards", "rootUri": "../pkg/", "packageUri": "lib/"}]}');
    File('${dir.path}/lib/app_assets.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "const own = 'assets/icons/own.svg';\n"
        "const stamp = 'assets/icons/stamp.svg';\n"
        "const stampPackage = 'cards';\n"
        "const gone = 'assets/icons/gone.svg';\n",
      );
    final context = CheckContext(
      root: dir.path,
      config: CheckConfig.parse('source_dirs: [lib]\nassets: {registries: [lib/app_assets.dart]}'),
      mode: ScopeMode.files,
      changedFiles: const {'lib/app_assets.dart'},
      deletedFiles: const {},
      fix: false,
      ci: true,
    );
    final result = await const AssetsStep().run(context);
    expect(result.findings.map((finding) => finding.format()),
        ['lib/app_assets.dart:4 asset_missing: `assets/icons/gone.svg` does not exist']);
  });

  test('pubspec tool sections use assets, the flutter: bundle list does not (NCC0000078)', () {
    expect(
      AssetsStep.pubspecReferences('''
name: app
flutter:
  assets:
    - assets/images/
    - assets/images/bundled.png
flutter_launcher_icons:
  image_path: "assets/images/icon.png"
  adaptive_icon_foreground: assets/images/fg.png
flutter_native_splash:
  image: assets/images/splash.png
  android_12:
    image: assets/images/splash12.png
'''),
      {'assets/images/icon.png', 'assets/images/fg.png', 'assets/images/splash.png', 'assets/images/splash12.png'},
    );
    expect(AssetsStep.pubspecReferences('name: [broken'), isEmpty);
  });

  group('test existence (NCR0000022)', () {
    test('identifiers become snake case file names', () {
      expect(toSnakeCase('adminPosts'), 'admin_posts');
      expect(toSnakeCase('appVernak'), 'app_vernak');
      expect(toSnakeCase('users'), 'users');
      expect(toSnakeCase('doordropStats'), 'doordrop_stats');
    });

    test('a cubit without a test and a route without a test are reported, the others are not', () async {
      final dir = Directory.systemTemp.createTempSync('neon_check');
      addTearDown(() => dir.deleteSync(recursive: true));
      _write(dir, 'lib/bloc/a/a_cubit.dart');
      _write(dir, 'lib/bloc/b/b_cubit.dart');
      _write(dir, 'lib/bloc/base/base_cubit.dart');
      _write(dir, 'lib/bloc/a/a_state.dart');
      _write(
        dir,
        'lib/flavors/f/f_router.dart',
        'GoRoute(\n  path: Routes.users.absolutePath,\n),\nGoRoute(\n  path: Routes.adminPosts.absolutePath,\n),\n'
            'GoRoute(path: Routes.adminPosts.absolutePath),\n',
      );
      _write(dir, 'test/app/bloc/a_cubit_test.dart');
      _write(dir, 'test/app/routes/users_route_test.dart');
      _write(dir, 'test/support/harness.dart');
      final context = CheckContext(
        root: dir.path,
        config: CheckConfig.parse(
          'tests:\n  existence:\n    cubits: {dir: lib/bloc, exempt: [lib/bloc/base/base_cubit.dart]}\n'
          '    routes: {routers: [lib/flavors/f/f_router.dart]}',
        ),
        mode: ScopeMode.all,
        changedFiles: const {},
        deletedFiles: const {},
        fix: false,
        ci: true,
      );
      const step = TestExistenceStep();
      expect(step.appliesTo(context), isTrue);
      final result = await step.run(context);
      expect(result.findings.map((finding) => finding.format()), [
        startsWith('lib/bloc/b/b_cubit.dart:1 test_missing: no cubit test: add test/<suite>/bloc/b_cubit_test.dart'),
        startsWith(
          'lib/flavors/f/f_router.dart:5 test_missing: route Routes.adminPosts has no test: '
          'add test/<suite>/routes/admin_posts_route_test.dart',
        ),
      ]);
      final scope = result.findingsScope;
      expect(scope, isNotNull);
      expect(scope?.call('lib/bloc/a/a_cubit.dart'), isTrue);
      expect(scope?.call('lib/flavors/f/f_router.dart'), isTrue);
      expect(scope?.call('lib/pages/x.dart'), isFalse);
    });

    test('does not apply without an existence section', () {
      final context = CheckContext(
        root: '/nowhere',
        config: CheckConfig.parse('tests: {dir: test}'),
        mode: ScopeMode.all,
        changedFiles: const {},
        deletedFiles: const {},
        fix: false,
        ci: true,
      );
      expect(const TestExistenceStep().appliesTo(context), isFalse);
    });
  });

  group('coverage (NCR0000022)', () {
    test('lcov is parsed per file and line', () {
      final report = parseLcov(
          'SF:lib/bloc/a/a_cubit.dart\nDA:1,1\nDA:2,0\nDA:3,4\nend_of_record\nSF:lib/b.dart\nDA:7,0\nend_of_record\n');
      expect(report['lib/bloc/a/a_cubit.dart'], {1: 1, 2: 0, 3: 4});
      expect(report['lib/b.dart'], {7: 0});
    });

    test('the + side of every hunk gives the changed lines', () {
      const diff = '--- a\n+++ b\n@@ -1 +1 @@\n-x\n+y\n@@ -5,2 +6,3 @@\n+a\n+b\n+c\n@@ -9,1 +12,0 @@\n-gone\n';
      expect(changedLines(diff), {1, 6, 7, 8});
    });

    test('coverage counts only executable changed lines and names the first uncovered one', () {
      final coverage = coverageOf({1, 2, 3, 4, 10}, {1: 1, 2: 0, 3: 2, 4: 0});
      expect(coverage.executable, 4);
      expect(coverage.covered, 2);
      expect(coverage.firstUncovered, 2);
      expect(coverageOf({5}, {1: 1}).executable, 0);
    });

    test('coverage is wanted for --all and for a change under a coverage source', () {
      CheckContext context(ScopeMode mode, Set<String> changed) => CheckContext(
            root: '/nowhere',
            config: CheckConfig.parse('tests:\n  coverage: {sources: [lib/bloc]}'),
            mode: mode,
            changedFiles: changed,
            deletedFiles: const {},
            fix: false,
            ci: true,
          );
      expect(coverageWanted(context(ScopeMode.all, const {})), isTrue);
      expect(coverageWanted(context(ScopeMode.changed, {'lib/bloc/a/a_cubit.dart'})), isTrue);
      expect(coverageWanted(context(ScopeMode.changed, {'lib/pages/a.dart'})), isFalse);
      expect(coverageWanted(context(ScopeMode.changed, {'lib/bloc/a/a_cubit.g.dart'})), isTrue);
      final none = CheckContext(
        root: '/nowhere',
        config: CheckConfig.parse('tests: {dir: test}'),
        mode: ScopeMode.all,
        changedFiles: const {},
        deletedFiles: const {},
        fix: false,
        ci: true,
      );
      expect(coverageWanted(none), isFalse);
    });
  });

  test('NEON ignore comments are reported', () async {
    final dir = Directory.systemTemp.createTempSync('neon_check');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/plugin/lib/src/rule.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync("class R { R() : super(name: 'no_navigator'); }");
    File('${dir.path}/lib/a.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '// ignore: no_navigator\n// ignore: neon_lints/use_kit_widgets\n// ignore: unused_import\n',
      );
    final context = CheckContext(
      root: dir.path,
      config: CheckConfig.parse('plugin: plugin\nsource_dirs: [lib]'),
      mode: ScopeMode.all,
      changedFiles: const {},
      deletedFiles: const {},
      fix: false,
      ci: true,
    );
    final result = await const IgnoreCommentsStep().run(context);
    expect(result.findings.map((finding) => finding.line), [1, 2]);
  });

  group('duplicates', () {
    String body(String name) => [
          for (var i = 0; i < 14; i++) '  final $name$i = compute($i, "x$i");',
        ].join('\n');

    test('normalising drops comments, directives, blank and punctuation lines', () {
      final lines = DuplicatesStep.normalise('''
import 'a.dart';
// a comment
/* a
   block */
void f() {
  final   a = 1; // kept with its comment
});
''');
      expect([for (final line in lines) line.text], ['void f() {', 'final a = 1; // kept with its comment']);
      expect(lines.first.line, 5);
    });

    test('a copy across two files is one region in each, naming the other', () {
      final clones = DuplicatesStep.findClones({
        'lib/a.dart': 'void a() {\n${body('v')}\n}\n',
        'lib/b.dart': 'void b() {\n${body('v')}\n}\n',
        'lib/c.dart': 'void c() {\n${body('w')}\n}\n',
      });
      expect(clones.keys, ['lib/a.dart', 'lib/b.dart']);
      expect(clones['lib/a.dart']?.single.other, 'lib/b.dart');
      expect(clones['lib/a.dart']?.single.line, 2);
      expect(clones['lib/b.dart']?.single.otherLine, 2);
    });

    test('a copy shorter than the window is no finding', () {
      final short = [for (var i = 0; i < 5; i++) '  final v$i = compute($i);'].join('\n');
      expect(DuplicatesStep.findClones({'lib/a.dart': short, 'lib/b.dart': short}), isEmpty);
    });

    test('two copies inside one file are found, overlapping windows are not', () {
      final clones = DuplicatesStep.findClones({'lib/a.dart': '${body('v')}\nvoid gap() {}\n${body('v')}\n'});
      expect(clones['lib/a.dart'], hasLength(2));
      final repeated = List.filled(30, '  tick();').join('\n');
      expect(DuplicatesStep.findClones({'lib/b.dart': repeated})['lib/b.dart'], hasLength(1));
    });
  });
}
