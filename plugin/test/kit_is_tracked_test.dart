import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/kit_is_tracked.dart';
import 'package:neon_lints/src/support/rule_layout.dart';
import 'package:neon_lints/src/use_kit_widgets.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/bloc_rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(KitIsTrackedTest);
    defineReflectiveTests(KitIsTrackedWithoutConfigTest);
  });
  test('the tracked rows are real rows of use_kit_widgets', () {
    // A renamed row would silently stop being checked.
    expect({for (final row in UseKitWidgets.rows) row.id}, containsAll(KitIsTracked.rows));
  });
}

const _tapArea = 'lib/global_widgets/behaviors/app_tap_area/app_tap_area.dart';
const _folder = 'lib/global_widgets/components/app_pill_button/';
const _theme = 'lib/utils/ui/app_style.dart';

const _config = '''
preset: app
kit:
  gesture_detector: {use: AppTapArea, owners: [$_tapArea]}
  ink_well: {use: RoundedContainer, owners: [lib/global_widgets/components/rounded_container/rounded_container.dart]}
  buttons: {use: CustomButton, owners: [lib/global_widgets/components/custom_button/custom_button.dart, $_folder, $_theme]}
  switches: {use: AppSwitch, owners: [lib/global_widgets/components/app_switch/app_switch.dart]}
  checkboxes: {use: AppCheckbox, owners: [lib/global_widgets/components/app_checkbox/app_checkbox.dart]}
  text_fields: {use: AppTextField, owners: [lib/global_widgets/components/app_text_field/app_text_field.dart]}
  dividers: {use: AppDivider, owners: [lib/global_widgets/components/app_divider/app_divider.dart]}
''';

const _untracked = 'class AppPiece {}\n';

const _import = "import 'package:neon_flutter_analytics/neon_flutter_analytics.dart';\n";

const _tracked = '''
${_import}class AppPiece {
  const AppPiece();
  Object? wrap(Object? onTap) => NeonAnalytics.onTap(onTap, id: 'a', component: 'AppPiece');
}
''';

void _addAnalytics(KitRuleTestBase test) {
  test.newPackage('neon_flutter_analytics').addFile('lib/neon_flutter_analytics.dart', r'''
class NeonAnalytics {
  static Object? onTap(Object? callback, {String? id, String? component}) => callback;
}
''');
}

abstract class KitRuleTestBase extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => KitIsTracked();

  /// Writes [source] at the root-relative [relative] and expects one finding
  /// at its first class.
  Future<void> expectReported(String relative, String source, {String name = 'AppPiece'}) =>
      expectIn(relative.substring('lib/'.length), source, [name]);

  Future<void> expectClean(String relative, String source) async {
    final path = '$testPackageRootPath/$relative';
    newFile(path, source);
    await assertNoDiagnosticsInFile(path);
  }
}

@reflectiveTest
class KitIsTrackedTest extends KitRuleTestBase {
  @override
  void setUp() {
    RuleLayout.clearCache();
    _addAnalytics(this);
    super.setUp();
    newFile('$testPackageRootPath/neon_check.yaml', _config);
  }

  Future<void> test_every_tracked_row_is_reported() async {
    for (final file in const [
      _tapArea,
      'lib/global_widgets/components/rounded_container/rounded_container.dart',
      'lib/global_widgets/components/custom_button/custom_button.dart',
      'lib/global_widgets/components/app_switch/app_switch.dart',
      'lib/global_widgets/components/app_checkbox/app_checkbox.dart',
      'lib/global_widgets/components/app_text_field/app_text_field.dart',
    ]) {
      await expectReported(file, _untracked);
    }
  }

  Future<void> test_the_message_names_the_row() => expectIn(
        _tapArea.substring('lib/'.length),
        _untracked,
        ['AppPiece'],
        message: ['gesture_detector', 'NeonAnalytics'],
      );

  Future<void> test_an_owner_that_references_it_is_clean() => expectClean(_tapArea, _tracked);

  Future<void> test_a_theme_owner_is_clean() => expectClean(_theme, _untracked);

  Future<void> test_a_reference_behind_an_import_prefix_is_clean() => expectClean(_tapArea, '''
import 'package:neon_flutter_analytics/neon_flutter_analytics.dart' as analytics;

Object? wrap(Object? onTap) => analytics.NeonAnalytics.onTap(onTap);
''');

  Future<void> test_a_reference_in_a_part_of_the_library_is_clean() async {
    newFile(
      '$testPackageRootPath/lib/global_widgets/behaviors/app_tap_area/app_tap_area_part.dart',
      '''
part of 'app_tap_area.dart';

Object? wrap(Object? onTap) => NeonAnalytics.onTap(onTap);
''',
    );
    await expectClean(_tapArea, '''
${_import}part 'app_tap_area_part.dart';

class AppPiece {}
''');
  }

  Future<void> test_a_comment_or_a_string_is_not_a_reference() => expectReported(_tapArea, '''
/// Reports to NeonAnalytics.
class AppPiece {
  // NeonAnalytics.onTap
  final String name = 'NeonAnalytics';
}
''');

  Future<void> test_a_file_without_a_class_is_reported_at_its_start() =>
      expectReported(_tapArea, 'void wrap() {}\n', name: 'void');

  Future<void> test_a_folder_owner_stands_for_its_entry_file() =>
      expectReported('${_folder}app_pill_button.dart', _untracked);

  Future<void> test_another_file_of_a_folder_owner_is_clean() =>
      expectClean('${_folder}app_pill_button_dimens.dart', _untracked);

  Future<void> test_an_owner_of_another_row_is_clean() =>
      expectClean('lib/global_widgets/components/app_divider/app_divider.dart', _untracked);

  Future<void> test_a_file_that_owns_nothing_is_clean() =>
      expectClean('lib/global_widgets/components/app_pill/app_pill.dart', _untracked);
}

@reflectiveTest
class KitIsTrackedWithoutConfigTest extends KitRuleTestBase {
  @override
  void setUp() {
    RuleLayout.clearCache();
    _addAnalytics(this);
    super.setUp();
  }

  Future<void> test_no_config_is_not_checked() => expectClean(_tapArea, _untracked);

  Future<void> test_a_config_without_the_rows_is_not_checked() async {
    newFile(
      '$testPackageRootPath/neon_check.yaml',
      'preset: app\nkit:\n  dividers: {use: AppDivider, owners: [$_tapArea]}\n',
    );
    await expectClean(_tapArea, _untracked);
  }
}
