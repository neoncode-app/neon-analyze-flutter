import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/api_environment_rules.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/bloc_rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ApiEnvironmentValuesOnEnumTest);
  });
}

const _enum = '''
enum ApiEnvironment {
  test(baseUrl: 'https://test-api.example.cz'),
  prod(baseUrl: 'https://api.example.cz');

  const ApiEnvironment({required this.baseUrl});

  final String baseUrl;

  String get label => switch (this) {
        ApiEnvironment.test => 'TEST',
        ApiEnvironment.prod => 'PROD',
      };
}
''';

const _imports = "import 'package:test/model/enums/common/api_environment.dart';\n"
    "import 'package:test/utils/modes.dart';\n\n";

@reflectiveTest
class ApiEnvironmentValuesOnEnumTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => ApiEnvironmentValuesOnEnum();

  @override
  void setUp() {
    super.setUp();
    newFile('$testPackageLibPath/utils/modes.dart', '''
const bool kReleaseMode = false;
const bool kDebugMode = true;
''');
  }

  Future<void> test_the_enum_and_the_default_are_clean() async {
    newFile('$testPackageLibPath/model/enums/common/api_environment.dart', _enum);
    await expectIn(
      'flavors/flavor_config.dart',
      '''
${_imports}abstract class FlavorConfig {
  ApiEnvironment get defaultApiEnvironment => kReleaseMode ? ApiEnvironment.prod : ApiEnvironment.test;

  static ApiEnvironment defaultFor({required bool isRelease}) =>
      isRelease ? ApiEnvironment.prod : ApiEnvironment.test;
}

void select(ApiEnvironment target, ApiEnvironment current) {
  if (target == current) return;
}
''',
      [],
    );
  }

  Future<void> test_branches_on_the_mode_or_the_environment_are_flagged() async {
    newFile('$testPackageLibPath/model/enums/common/api_environment.dart', _enum);
    await expectIn(
      'utils/settings/api_options.dart',
      '''
${_imports}ApiEnvironment environment = ApiEnvironment.test;

String get apiKey => environment == ApiEnvironment.prod ? 'prod-key' : 'test-key';

bool get debugPayments => !kReleaseMode;

void log(String message) {
  if (kDebugMode) print(message);
}

String get label => switch (environment) {
      ApiEnvironment.test => 'TEST',
      ApiEnvironment.prod => 'PROD',
    };

abstract class OtherConfig {
  ApiEnvironment get defaultApiEnvironment => kReleaseMode ? ApiEnvironment.test : ApiEnvironment.prod;
}
''',
      ['environment == ApiEnvironment.prod', 'kReleaseMode', 'kDebugMode', 'environment', 'kReleaseMode'],
    );
  }
}
