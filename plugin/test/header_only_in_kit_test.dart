import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/header_only_in_kit.dart';
import 'package:neon_lints/src/support/rule_layout.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/bloc_rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(HeaderOnlyInKitTest);
    defineReflectiveTests(HeaderWithoutConfigTest);
  });
  group('RuleLayout.headerOf', () {
    test('reads the section', () {
      final header = RuleLayout.headerOf(_config);
      expect(header?.use, 'AppHeader');
      expect(header?.buttons, {'AppIconButton'});
      expect(header?.icons, {(type: 'AppIcons', member: 'arrowLeft'), (type: 'AppIcons', member: 'x')});
      expect(header?.isOwner('lib/global_widgets/components/app_header/app_header.dart'), isTrue);
      expect(header?.isOwner('lib/pages/home_page/home_page.dart'), isFalse);
    });

    test('a folder owner covers its files', () {
      final header = RuleLayout.headerOf(
        'header: {use: AppHeader, owners: [lib/global_widgets/components/app_header/], buttons: [B], icons: [I.x]}',
      );
      expect(header?.isOwner('lib/global_widgets/components/app_header/app_header_row.dart'), isTrue);
    });

    test('no section, no buttons or no icons is no header', () {
      expect(RuleLayout.headerOf('preset: app\n'), isNull);
      expect(RuleLayout.headerOf('header: {use: AppHeader, icons: [AppIcons.x]}'), isNull);
      expect(RuleLayout.headerOf('header: {use: AppHeader, buttons: [AppIconButton]}'), isNull);
    });
  });
}

const _config = '''
preset: app
header:
  use: AppHeader
  owners: [lib/global_widgets/components/app_header/app_header.dart]
  buttons: [AppIconButton]
  icons: [AppIcons.arrowLeft, AppIcons.x]
''';

const _icons = '''
enum AppIcons { arrowLeft, x, share, search }
''';

const _button = '''
import 'package:flutter/widgets.dart';
import 'package:test/model/enums/common/app_icons.dart';

class AppIconButton extends StatelessWidget {
  const AppIconButton({required this.icon, this.onTap});
  const AppIconButton.positional(this.icon) : onTap = null;
  final AppIcons icon;
  final Object? onTap;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class AppButton extends StatelessWidget {
  const AppButton({required this.icon});
  final AppIcons icon;
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

const _imports = '''
import 'package:flutter/widgets.dart';
import 'package:test/global_widgets/components/app_icon_button/app_icon_button.dart';
import 'package:test/model/enums/common/app_icons.dart';
''';

void _addKit(HeaderRuleTestBase test) {
  test
    ..newFile('${test.testPackageLibPath}/model/enums/common/app_icons.dart', _icons)
    ..newFile('${test.testPackageLibPath}/global_widgets/components/app_icon_button/app_icon_button.dart', _button);
}

abstract class HeaderRuleTestBase extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => HeaderOnlyInKit();
}

@reflectiveTest
class HeaderOnlyInKitTest extends HeaderRuleTestBase {
  @override
  void setUp() {
    RuleLayout.clearCache();
    super.setUp();
    newFile('$testPackageRootPath/neon_check.yaml', _config);
    _addKit(this);
  }

  Future<void> test_a_back_button_in_a_page_is_reported() => expectIn(
        'pages/profile_page/profile_page.dart',
        '${_imports}Widget f() => AppIconButton(icon: AppIcons.arrowLeft, onTap: () {});',
        ['AppIconButton'],
        message: ['(AppIconButton(AppIcons.arrowLeft))', 'every header is AppHeader'],
        after: 'Widget f()',
      );

  Future<void> test_a_const_close_button_with_a_positional_icon_is_reported() => expectIn(
        'pages/home_page/widgets/dialogs/filter_sheet/filter_sheet.dart',
        '${_imports}Widget f() => const AppIconButton.positional(AppIcons.x);',
        ['AppIconButton.positional'],
        after: 'Widget f()',
      );

  Future<void> test_a_conditional_branch_is_reported() => expectIn(
        'pages/home_page/widgets/patterns/empty/empty.dart',
        '${_imports}Widget f(bool done) => AppIconButton(icon: done ? AppIcons.share : (AppIcons.arrowLeft));',
        ['AppIconButton'],
        message: ['AppIcons.arrowLeft'],
        after: 'Widget f(',
      );

  Future<void> test_an_import_prefix_does_not_hide_the_icon() => expectIn(
        'pages/map_page/map_page.dart',
        "import 'package:flutter/widgets.dart';\n"
            "import 'package:test/global_widgets/components/app_icon_button/app_icon_button.dart' as kit;\n"
            "import 'package:test/model/enums/common/app_icons.dart' as icons;\n"
            'Widget f() => kit.AppIconButton(icon: icons.AppIcons.x);',
        ['kit.AppIconButton'],
        after: 'Widget f()',
      );

  Future<void> test_another_icon_is_clean() async {
    final path = '$testPackageLibPath/pages/home_page/home_header.dart';
    newFile(path, '${_imports}Widget f() => AppIconButton(icon: AppIcons.search, onTap: () {});');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_another_widget_with_the_icon_is_clean() async {
    final path = '$testPackageLibPath/pages/home_page/home_empty.dart';
    newFile(path, '${_imports}Widget f() => AppButton(icon: AppIcons.arrowLeft);');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_the_header_owner_is_not_reported() async {
    final path = '$testPackageLibPath/global_widgets/components/app_header/app_header.dart';
    newFile(path, '${_imports}Widget f() => AppIconButton(icon: AppIcons.arrowLeft);');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_a_generated_file_is_not_reported() async {
    final path = '$testPackageLibPath/pages/profile_page/profile_page.g.dart';
    newFile(path, '${_imports}Widget f() => AppIconButton(icon: AppIcons.x);');
    await assertNoDiagnosticsInFile(path);
  }
}

@reflectiveTest
class HeaderWithoutConfigTest extends HeaderRuleTestBase {
  @override
  void setUp() {
    RuleLayout.clearCache();
    super.setUp();
    newFile('$testPackageRootPath/neon_check.yaml', 'preset: app\n');
    _addKit(this);
  }

  Future<void> test_without_header_nothing_is_checked() async {
    final path = '$testPackageLibPath/pages/profile_page/profile_page.dart';
    newFile(path, '${_imports}Widget f() => AppIconButton(icon: AppIcons.arrowLeft);');
    await assertNoDiagnosticsInFile(path);
  }
}
