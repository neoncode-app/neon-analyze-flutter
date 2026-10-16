import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/result_handles_unauthorized.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/bloc_rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ResultHandlesUnauthorizedTest);
  });
}

@reflectiveTest
class ResultHandlesUnauthorizedTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => ResultHandlesUnauthorized();

  @override
  void setUp() {
    newPackage('neonapi').addFile('lib/neonapi.dart', r'''
sealed class Result<T, E> {
  const Result();
  R? when<R>({required R Function(T data) success, R Function(E error)? unauthorized, required R Function(E error) error});
  R handleError<R>({required R Function(E error) error, required R Function(T data) success});
}
''');
    super.setUp();
  }

  static const _imports = "import 'package:neonapi/neonapi.dart';\n";

  Future<void> test_when_without_unauthorized_is_flagged() => expectIn(
        'bloc/x/x_cubit.dart',
        '${_imports}void f(Result<int, String> result) {\n  result.when(success: (_) {}, error: (_) {});\n}\n',
        ['when'],
        message: ['handleError'],
      );

  Future<void> test_when_with_unauthorized_is_clean() => expectIn(
        'bloc/x/x_cubit.dart',
        '${_imports}void f(Result<int, String> result) {\n'
            '  result.when(success: (_) {}, unauthorized: (_) {}, error: (_) {});\n}\n',
        [],
      );

  Future<void> test_handle_error_is_clean() => expectIn(
        'bloc/x/x_cubit.dart',
        '${_imports}void f(Result<int, String> result) {\n  result.handleError(error: (_) {}, success: (_) {});\n}\n',
        [],
      );

  Future<void> test_utils_are_checked_too() => expectIn(
        'utils/helpers/loader.dart',
        '${_imports}int? f(Result<int, String> result) => result.when(success: (v) => v, error: (_) => 0);\n',
        ['when'],
      );

  Future<void> test_other_when_methods_are_ignored() => expectIn(
        'bloc/x/x_cubit.dart',
        'class Other { void when({Object? success, Object? error}) {} }\n'
            'void f(Other o) {\n  o.when(success: 1, error: 2);\n}\n',
        [],
      );
}
