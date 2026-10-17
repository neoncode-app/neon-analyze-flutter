import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/storage_rules.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/bloc_rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(HiveOnlyInRepositoriesTest);
    defineReflectiveTests(StorageHiveOnlyTest);
  });
}

/// Stubs of hive_ce, neon_flutter_hive and shared_preferences.
abstract class _StorageTest extends BlocRuleTest {
  @override
  void setUp() {
    newPackage('hive_ce').addFile('lib/hive_ce.dart', '''
class Listenable {}

class Box<T> {
  Listenable listenable() => Listenable();
}

class _Hive {
  Box<T> box<T>(String name) => Box<T>();
  Future<Box<T>> openBox<T>(String name) async => Box<T>();
}

final Hive = _Hive();
''');
    newPackage('neon_flutter_hive').addFile('lib/neon_flutter_hive.dart', '''
class KeyValueBox {
  KeyValueBox(String name);
  Object listenable(String key) => Object();
}

class EntityBox<T> {
  EntityBox(String name, {required String Function(T) idOf});
}
''');
    newPackage('shared_preferences').addFile('lib/shared_preferences.dart', 'class SharedPreferences {}\n');
    super.setUp();
  }
}

const _imports = "import 'package:hive_ce/hive_ce.dart';\n"
    "import 'package:neon_flutter_hive/neon_flutter_hive.dart';\n\n";

const _boxes = '''
${_imports}final settings = KeyValueBox('settings');

Object read() => Hive.box<String>('cache');

Object watch() => settings.listenable('locale');

Future<Object> open() => Hive.openBox<String>('cache');
''';

@reflectiveTest
class HiveOnlyInRepositoriesTest extends _StorageTest {
  @override
  AnalysisRule get ruleUnderTest => HiveOnlyInRepositories();

  Future<void> test_repositories_and_lib_hive_own_boxes() async {
    await expectIn('repository/settings_repository.dart', _boxes, []);
    await expectIn('hive/app_boxes.dart', _boxes, []);
  }

  Future<void> test_boxes_elsewhere_are_flagged() => expectIn(
        'bloc/cookie_consent/cookie_consent_cubit.dart',
        _boxes,
        ['KeyValueBox', 'box', 'listenable', 'openBox'],
        after: 'final settings',
      );
}

@reflectiveTest
class StorageHiveOnlyTest extends _StorageTest {
  @override
  AnalysisRule get ruleUnderTest => StorageHiveOnly();

  Future<void> test_other_stores_are_flagged() => expectIn(
        'repository/prefs_repository.dart',
        '''
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neon_flutter_hive/neon_flutter_hive.dart';

class Window {
  Object? localStorage;
}

final window = Window();

Object? stored() => window.localStorage;

Object? kept(SharedPreferences prefs, KeyValueBox box) => box;
''',
        ["'package:shared_preferences/shared_preferences.dart'", 'window.localStorage'],
      );
}
