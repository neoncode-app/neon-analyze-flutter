import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/no_raw_color.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/expect.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(NoRawColorTest);
  });
}

@reflectiveTest
class NoRawColorTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = NoRawColor();
    super.setUp();
  }

  Future<void> test_literal_color_in_app_code_is_flagged() async {
    const source = '''
class Color { const Color(int value); }
const c = Color(0xFF123456);
''';
    await assertDiagnostics(source, lintsAt(this, source, ['Color(0xFF123456)']));
  }

  Future<void> test_generated_part_of_a_library_is_skipped() async {
    // hive_ce writes the adapters into `hive_adapters.g.dart`, a part of the
    // hand-written `hive_adapters.dart`: the defining unit is not generated.
    final library = '$testPackageLibPath/hive/hive_adapters.dart';
    final part = '$testPackageLibPath/hive/hive_adapters.g.dart';
    newFile(library, '''
part 'hive_adapters.g.dart';
class Color { const Color(int value); }
''');
    newFile(part, '''
part of 'hive_adapters.dart';
const c = Color(0xFF123456);
''');
    await assertNoDiagnosticsInFile(part);
  }
}
