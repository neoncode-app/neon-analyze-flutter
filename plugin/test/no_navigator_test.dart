import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/no_navigator.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/expect.dart';
import 'support/stub_packages.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(NoNavigatorTest);
  });
}

const _material = "import 'package:flutter/material.dart';\n";

@reflectiveTest
class NoNavigatorTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = NoNavigator();
    addStubPackages(this);
    super.setUp();
  }

  Future<void> test_static_calls_are_flagged_and_name_go_router() async {
    const source = '''
${_material}void f(BuildContext c) {
  Navigator.of(c).pop();
  Navigator.pop(c);
  Navigator.push(c, 1);
  Navigator.maybePop(c);
  Navigator.of(c, rootNavigator: true);
}
''';
    await assertDiagnostics(
      source,
      lintsAt(
        this,
        source,
        [
          'Navigator.of(c)',
          'Navigator.pop(c)',
          'Navigator.push(c, 1)',
          'Navigator.maybePop(c)',
          'Navigator.of(c, rootNavigator: true)',
        ],
        messageContainsAll: ['context.pop / context.go / context.push'],
      ),
    );
  }

  Future<void> test_tear_off_and_construction_are_flagged() async {
    const source = '${_material}Object f() => [Navigator.pop, Navigator()];';
    await assertDiagnostics(source, lintsAt(this, source, ['Navigator.pop', 'Navigator']));
  }

  Future<void> test_import_prefix_does_not_hide_it() async {
    const source = "import 'package:flutter/widgets.dart' as w;\nvoid f(w.BuildContext c) => w.Navigator.pop(c);";
    await assertDiagnostics(source, lintsAt(this, source, ['w.Navigator.pop(c)']));
  }

  Future<void> test_clean_go_router_style_code() async {
    await assertNoDiagnostics('''
$_material
extension on BuildContext {
  void pop() {}
}

void f(BuildContext c, NavigatorState state) {
  c.pop();
  state.pop();
}

void g({bool useRootNavigator = true}) {}
''');
  }

  Future<void> test_app_class_named_navigator_is_not_flagged() async {
    await assertNoDiagnostics('''
class Navigator {
  static void pop() {}
}

void f() => Navigator.pop();
''');
  }

  void test_no_file_owns_navigator() {
    // NCR0000014 decision 11: Navigator is forbidden everywhere, including
    // the kit and the dialog helper.
    expect(NoNavigator.rows.single.owners, isEmpty);
    expect(NoNavigator.rows.single.ownerCategory, isNull);
  }

  Future<void> test_kit_and_dialog_helper_files_are_not_exempt() async {
    const source = '${_material}void f(BuildContext c) => Navigator.pop(c);';
    for (final file in ['global_widgets/global/app_dialog/app_dialog.dart', 'utils/utils.dart', 'flavors/neoncode/router.dart']) {
      final path = '$testPackageLibPath/$file';
      newFile(path, source);
      await assertDiagnosticsInFile(path, lintsAt(this, source, ['Navigator.pop(c)']));
    }
  }

  Future<void> test_files_outside_lib_are_skipped() async {
    final path = '$testPackageRootPath/test/page_test.dart';
    newFile(path, '${_material}void f(BuildContext c) => Navigator.pop(c);');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_generated_file_is_skipped() async {
    final path = '$testPackageLibPath/model/catalog.g.dart';
    newFile(path, '${_material}void f(BuildContext c) => Navigator.pop(c);');
    await assertNoDiagnosticsInFile(path);
  }
}
