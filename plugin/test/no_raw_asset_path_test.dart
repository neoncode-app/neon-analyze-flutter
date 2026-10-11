import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/no_raw_asset_path.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/expect.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(NoRawAssetPathTest);
  });
}

@reflectiveTest
class NoRawAssetPathTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = NoRawAssetPath();
    super.setUp();
  }

  Future<void> test_asset_path_in_app_code_is_flagged() async {
    const source = "const icon = 'assets/icons/global/ic_add.svg';";
    await assertDiagnostics(source, lintsAt(this, source, ["'assets/icons/global/ic_add.svg'"]));
  }

  Future<void> test_registry_owns_asset_paths() async {
    final path = '$testPackageLibPath/utils/ui/app_assets.dart';
    newFile(path, "const icon = 'assets/icons/global/ic_add.svg';");
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_translations_root_is_allowed() async {
    await assertNoDiagnostics("const dir = 'assets/translations';");
  }

  Future<void> test_files_outside_lib_are_skipped() async {
    // A test reading a translation file through dart:io references no asset.
    final path = '$testPackageRootPath/test/flutter_test_config.dart';
    newFile(path, "const file = 'assets/translations/cs.json';");
    await assertNoDiagnosticsInFile(path);
  }
}
