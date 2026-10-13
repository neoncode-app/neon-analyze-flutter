import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/dimens_rules.dart';
import 'package:neon_lints/src/text_rules.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/bloc_rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(NoRawDimensionTest);
    defineReflectiveTests(DimensPrivateToWidgetTest);
    defineReflectiveTests(PageDimensSpacingOnlyTest);
    defineReflectiveTests(NoAppDimensTest);
    defineReflectiveTests(ComponentTakesVariantTest);
    defineReflectiveTests(NoRawTextStyleTest);
    defineReflectiveTests(NoDebugPrintTest);
    defineReflectiveTests(NoHardcodedUiStringTest);
    defineReflectiveTests(NoDashInStringsTest);
  });
}

const _flutter = "import 'package:flutter/widgets.dart';\n";

/// The scale, a widget dimens file and the old AppDimens.
abstract class _DimensTest extends BlocRuleTest {
  @override
  void setUp() {
    newFile('$testPackageLibPath/utils/ui/tokens/app_spacing.dart',
        'abstract final class AppSpacing {\n  static const s16 = 16.0;\n}\n');
    newFile('$testPackageLibPath/utils/ui/tokens/app_radius.dart',
        'abstract final class AppRadius {\n  static const card = 12.0;\n}\n');
    newFile(
      '$testPackageLibPath/global_widgets/global/app_text_field/app_text_field_dimens.dart',
      'final class AppTextFieldDimens {\n  const AppTextFieldDimens._(this.height);\n  final double height;\n'
          '  static const standard = AppTextFieldDimens._(48);\n}\n',
    );
    newFile('$testPackageLibPath/utils/ui/theme/app_dimens.dart',
        'abstract final class AppDimens {\n  static const spacing16 = 16.0;\n}\n');
    super.setUp();
  }
}

@reflectiveTest
class NoRawDimensionTest extends _DimensTest {
  @override
  AnalysisRule get ruleUnderTest => NoRawDimension();

  static const _source = '''
${_flutter}Object f() => [
  SizedBox(height: 8),
  EdgeInsets.all(16),
  EdgeInsets.symmetric(horizontal: 12.5),
  BorderRadius.circular(-4),
  SizedBox(width: 0),
  EdgeInsets.zero,
];
''';

  Future<void> test_literal_dimensions_are_flagged() => expectIn(
        'pages/x_page.dart',
        _source,
        ['8', '16', '12.5', '-4'],
        message: ['lib/utils/ui/tokens/'],
        after: 'Object f()',
      );

  Future<void> test_scale_and_dimens_files_own_literals() async {
    await expectIn('utils/ui/tokens/app_gap.dart', _source, []);
    await expectIn('global_widgets/global/app_pill/app_pill_dimens.dart', _source, []);
  }

  Future<void> test_non_dimension_numbers_are_clean() =>
      expectIn('pages/x_page.dart', '${_flutter}int f(List<int> items) => items.length + 1;\n', []);

  Future<void> test_a_dimension_name_on_an_int_parameter_is_clean() => expectIn(
        'pages/x_page.dart',
        '${_flutter}class File {\n  const File({required this.size});\n  final int size;\n}\n'
            'const file = File(size: 1200000);\n',
        [],
      );
}

@reflectiveTest
class DimensPrivateToWidgetTest extends _DimensTest {
  @override
  AnalysisRule get ruleUnderTest => DimensPrivateToWidget();

  static const _source = "import 'package:test/global_widgets/global/app_text_field/app_text_field_dimens.dart';\n"
      'double f() => AppTextFieldDimens.standard.height;\n';

  Future<void> test_other_widget_borrowing_dimens_is_flagged() => expectIn(
        'global_widgets/global/app_pill/app_pill.dart',
        _source,
        ['AppTextFieldDimens'],
        message: ['belongs to another widget'],
        after: 'double f()',
      );

  Future<void> test_own_folder_may_use_it() =>
      expectIn('global_widgets/global/app_text_field/app_text_field.dart', _source, []);
}

@reflectiveTest
class PageDimensSpacingOnlyTest extends _DimensTest {
  @override
  AnalysisRule get ruleUnderTest => PageDimensSpacingOnly();

  static const _source = '''
import 'package:test/utils/ui/tokens/app_spacing.dart';
import 'package:test/utils/ui/tokens/app_radius.dart';
import 'package:test/global_widgets/global/app_text_field/app_text_field_dimens.dart';

final gap = AppSpacing.s16;
final radius = AppRadius.card;
final height = AppTextFieldDimens.standard;
''';

  Future<void> test_pages_using_more_than_spacing_are_flagged() => expectIn(
        'pages/x_page.dart',
        _source,
        ['AppRadius.card', 'AppTextFieldDimens.standard'],
        message: ['pages use only AppSpacing'],
        after: 'final gap',
      );

  Future<void> test_components_may_use_the_scale() => expectIn('global_widgets/global/x.dart', _source, []);
}

@reflectiveTest
class NoAppDimensTest extends _DimensTest {
  @override
  AnalysisRule get ruleUnderTest => NoAppDimens();

  static const _source = "import 'package:test/utils/ui/theme/app_dimens.dart';\nfinal gap = AppDimens.spacing16;\n";

  Future<void> test_app_dimens_use_is_flagged() =>
      expectIn('global_widgets/global/x.dart', _source, ['AppDimens.spacing16'], message: ['old AppDimens']);

  Future<void> test_app_dimens_itself_is_the_owner() => expectIn(
        'utils/ui/theme/app_dimens.dart',
        'abstract final class AppDimens {\n  static const spacing16 = 16.0;\n  static const spacing32 = AppDimens.spacing16 * 2;\n}\n',
        [],
      );
}

@reflectiveTest
class ComponentTakesVariantTest extends _DimensTest {
  @override
  AnalysisRule get ruleUnderTest => ComponentTakesVariant();

  static String _widget(String name, String category) => '''
${_flutter}
/// A widget.
///
/// {@category $category}
class $name extends StatelessWidget {
  const $name({this.padding, this.height, this.label = ''});
  const $name.compact({this.label = ''}) : padding = null, height = null;
  final double? padding;
  final double? height;
  final String label;
  @override
  Widget build(BuildContext context) => Widget();
}
''';

  Future<void> test_component_with_raw_dimensions_is_flagged() => expectIn(
        'global_widgets/global/app_pill.dart',
        _widget('AppPill', 'Component'),
        ['this.padding', 'this.height'],
        message: ['take `variant:`'],
        after: 'const AppPill({',
      );

  Future<void> test_primitives_and_other_tiers_are_clean() async {
    await expectIn('global_widgets/global/rounded_container.dart', _widget('RoundedContainer', 'Component'), []);
    await expectIn('global_widgets/global/two_panel.dart', _widget('TwoPanel', 'Layout'), []);
  }
}

@reflectiveTest
class NoRawTextStyleTest extends _DimensTest {
  @override
  AnalysisRule get ruleUnderTest => NoRawTextStyle();

  static const _source = '''
${_flutter}const base = TextStyle(fontSize: 14);
final bold = base.copyWith(fontWeight: FontWeight.bold);
final tinted = base.copyWith(color: 1);
''';

  Future<void> test_hand_built_styles_are_flagged() => expectIn(
        'pages/x_page.dart',
        _source,
        ['TextStyle', 'copyWith'],
        message: ['named style in AppTextStyles'],
        after: 'const base',
      );

  Future<void> test_text_style_files_own_styles() async {
    await expectIn('utils/ui/theme/app_text_styles.dart', _source, []);
    await expectIn('utils/ui/app_style.dart', _source, []);
  }
}

@reflectiveTest
class NoDebugPrintTest extends _DimensTest {
  @override
  AnalysisRule get ruleUnderTest => NoDebugPrint();

  static const _source = "${_flutter}void f() => debugPrint('x');\n";

  Future<void> test_debug_print_is_flagged() =>
      expectIn('bloc/x/x_cubit.dart', _source, ['debugPrint'], message: ['app logger'], after: 'void f()');

  Future<void> test_logger_owns_it() => expectIn('utils/helpers/log_utils.dart', _source, []);
}

@reflectiveTest
class NoHardcodedUiStringTest extends _DimensTest {
  @override
  AnalysisRule get ruleUnderTest => NoHardcodedUiString();

  static const _source = '''
${_flutter}class Card {
  const Card({this.title, this.label, this.value});
  final String? title;
  final String? label;
  final String? value;
}

Object f(String name) => [
  Text('Uložit změny'),
  Card(title: 'Statistiky', label: 'Hotovo'),
  Text(name),
  Text('•'),
  Card(value: 'raw-value'),
];
''';

  Future<void> test_hardcoded_texts_in_ui_are_flagged() async {
    for (final folder in ['pages', 'global_widgets/global']) {
      await expectIn(
        '$folder/x.dart',
        _source,
        ["'Uložit změny'", "'Statistiky'", "'Hotovo'"],
        message: ["tr('key')"],
        after: 'Object f(',
      );
    }
  }

  Future<void> test_catalog_previews_and_non_ui_code_are_exempt() async {
    await expectIn('pages/neoncode/widgets/widget_catalog/previews/previews_core.dart', _source, []);
    await expectIn('model/x.dart', _source, []);
  }
}

@reflectiveTest
class NoDashInStringsTest extends _DimensTest {
  @override
  AnalysisRule get ruleUnderTest => NoDashInStrings();

  static const _source = '''
${_flutter}Object f(int count) => [
  Text('od 9:00 – 11:00'),
  Text('Celkem — \$count'),
  Text('20 % sleva'),
];

void g() {
  debugPrint('upload — retry');
  throw ArgumentError('bad state — x');
}
''';

  Future<void> test_dashes_in_texts_are_flagged() => expectIn(
        'pages/x_page.dart',
        _source,
        ["'od 9:00 – 11:00'", r"'Celkem — $count'"],
        message: ['use a comma'],
        after: 'Object f(',
      );

  Future<void> test_logs_and_errors_are_allow_listed() => expectIn(
        'pages/x_page.dart',
        "${_flutter}void g() {\n  debugPrint('upload — retry');\n  throw ArgumentError('bad state — x');\n}\n",
        [],
      );
}
