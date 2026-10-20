import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/api_environment_rules.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/bloc_rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ApiEnvironmentValuesOnEnumTest);
    defineReflectiveTests(ApiEnvironmentFixedByBuildTest);
  });
}

const _enum = '''
import 'package:test/utils/modes.dart';

enum ApiEnvironment {
  test(baseUrl: 'https://test-api.example.cz'),
  prod(baseUrl: 'https://api.example.cz');

  const ApiEnvironment({required this.baseUrl});

  final String baseUrl;

  static ApiEnvironment get current => resolve(const String.fromEnvironment('API_ENV'), isRelease: kReleaseMode);

  static ApiEnvironment resolve(String define, {required bool isRelease}) {
    if (define.isEmpty) return isRelease ? prod : test;
    return define == 'prod' ? prod : test;
  }

  String get label => switch (this) {
        ApiEnvironment.test => 'TEST',
        ApiEnvironment.prod => 'PROD',
      };
}
''';

const _enumPath = 'model/enums/common/api_environment.dart';

const _imports = "import 'package:test/model/enums/common/api_environment.dart';\n"
    "import 'package:test/utils/modes.dart';\n\n";

const _modes = '''
const bool kReleaseMode = false;
const bool kDebugMode = true;
''';

@reflectiveTest
class ApiEnvironmentValuesOnEnumTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => ApiEnvironmentValuesOnEnum();

  @override
  void setUp() {
    super.setUp();
    newFile('$testPackageLibPath/utils/modes.dart', _modes);
  }

  Future<void> test_the_enum_and_its_resolver_are_clean() => expectIn(_enumPath, _enum, []);

  Future<void> test_a_config_reading_the_environment_is_clean() async {
    newFile('$testPackageLibPath/$_enumPath', _enum);
    await expectIn(
      'utils/settings/api_options.dart',
      '''
${_imports}abstract final class ApiConfig {
  static ApiEnvironment get environment => ApiEnvironment.current;

  static String get baseUrl => environment.baseUrl;
}

void select(ApiEnvironment target, ApiEnvironment current) {
  if (target == current) return;
}
''',
      [],
    );
  }

  Future<void> test_branches_on_the_mode_or_the_environment_are_flagged() async {
    newFile('$testPackageLibPath/$_enumPath', _enum);
    await expectIn(
      'utils/settings/api_options.dart',
      '''
${_imports}final ApiEnvironment environment = ApiEnvironment.current;

String get apiKey => environment == ApiEnvironment.prod ? 'prod-key' : 'test-key';

bool get debugPayments => !kReleaseMode;

void log(String message) {
  if (kDebugMode) print(message);
}

String get label => switch (environment) {
      ApiEnvironment.test => 'TEST',
      ApiEnvironment.prod => 'PROD',
    };

abstract class FlavorConfig {
  ApiEnvironment get defaultApiEnvironment => kReleaseMode ? ApiEnvironment.prod : ApiEnvironment.test;
}
''',
      ['environment == ApiEnvironment.prod', 'kReleaseMode', 'kDebugMode', 'environment', 'kReleaseMode'],
    );
  }

  Future<void> test_a_resolver_field_is_clean_too() => expectIn(
        _enumPath,
        '''
import 'package:test/utils/modes.dart';

enum ApiEnvironment {
  test,
  prod;

  static final ApiEnvironment current = kReleaseMode ? prod : test;
}
''',
        [],
      );

  Future<void> test_the_build_mode_outside_the_resolver_is_flagged() => expectIn(
        _enumPath,
        '''
import 'package:test/utils/modes.dart';

enum ApiEnvironment {
  test,
  prod;

  static final ApiEnvironment current = kReleaseMode ? prod : test;

  static final ApiEnvironment fallback = kReleaseMode ? prod : test;
}
''',
        ['kReleaseMode'],
        after: 'fallback',
      );
}

@reflectiveTest
class ApiEnvironmentFixedByBuildTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => ApiEnvironmentFixedByBuild();

  @override
  void setUp() {
    super.setUp();
    newFile('$testPackageLibPath/utils/modes.dart', _modes);
    newFile('$testPackageLibPath/utils/store.dart', '''
class Store {
  String? getString(String key) => null;
  Future<void> setString(String key, String value) async {}
  Future<void> remove(String key) async {}
  Future<void> delete({required String key}) async {}
  Future<String?> read({required String key}) async => null;
}

class Client {
  void setBaseUrl(String url) {}
}
''');
  }

  Future<void> test_readers_are_clean_a_reassignment_is_flagged() async {
    newFile('$testPackageLibPath/$_enumPath', _enum);
    await expectIn(
      'utils/settings/api_options.dart',
      '''
${_imports}abstract final class ApiConfig {
  static ApiEnvironment get environment => ApiEnvironment.current;

  static final ApiEnvironment pinned = ApiEnvironment.current;
}

void scope() {
  var local = ApiEnvironment.current;
  local = ApiEnvironment.test;
  print(local);
}
''',
      ['local = ApiEnvironment.test'],
    );
  }

  Future<void> test_a_switch_a_setter_and_an_override_are_flagged() async {
    newFile('$testPackageLibPath/$_enumPath', _enum);
    await expectIn(
      'utils/settings/api_options.dart',
      '''
${_imports}import 'package:test/utils/store.dart';

abstract final class ApiConfig {
  static late ApiEnvironment environment;

  static ApiEnvironment? environmentOverride;

  static const String define = String.fromEnvironment('API_ENV');
}

ApiEnvironment chosen = ApiEnvironment.test;

void switchTo(ApiEnvironment target, Client client) {
  ApiConfig.environment = target;
  client.setBaseUrl(target.baseUrl);
}
''',
      [
        'environment',
        'environmentOverride',
        "String.fromEnvironment('API_ENV')",
        'chosen',
        'ApiConfig.environment = target',
        'setBaseUrl',
      ],
      after: 'late ApiEnvironment ',
    );
  }

  Future<void> test_a_persisted_choice_is_flagged_its_deletion_is_clean() => expectIn(
        'repository/settings_repository.dart',
        '''
import 'package:test/utils/store.dart';

class SettingsRepository {
  SettingsRepository(this._store);

  final Store _store;

  static const _keyApiEnvironment = 'api_environment';

  String? get environment => _store.getString(_keyApiEnvironment);

  Future<void> save(String name) => _store.setString('key_api_environment', name);

  Future<void> cleanUp() async {
    await _store.remove('api_environment');
    await _store.delete(key: 'key_api_environment');
  }
}
''',
        ["'api_environment'", "'key_api_environment'"],
      );
}
