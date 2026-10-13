import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/piece_rules.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/bloc_rule_base.dart';

void main() {
  group('snakeCase', () {
    test('splits words and acronyms', () {
      expect(snakeCase('AppSwitch'), 'app_switch');
      expect(snakeCase('AppHTMLView'), 'app_html_view');
      expect(snakeCase('Neoncode2FaPage'), 'neoncode2_fa_page');
    });
  });
  defineReflectiveSuite(() {
    defineReflectiveTests(PieceInOwnFolderTest);
    defineReflectiveTests(PieceHasSkeletonTest);
  });
}

String _widget(String name, [String? category]) => '''
import 'package:flutter/widgets.dart';

/// A widget.${category == null ? '' : '\n///\n/// {@category $category}'}
class $name extends StatelessWidget {
  const $name();
  @override
  Widget build(BuildContext context) => Widget();
}
''';

@reflectiveTest
class PieceInOwnFolderTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => PieceInOwnFolder();

  Future<void> test_a_component_beside_others_is_flagged() => expectIn(
        'global_widgets/global/app_switch.dart',
        _widget('AppSwitch', 'Component'),
        ['AppSwitch'],
        message: ['lib/global_widgets/global/app_switch/app_switch.dart'],
        after: 'class',
      );

  Future<void> test_a_component_in_its_folder_is_clean() =>
      expectIn('global_widgets/global/app_switch/app_switch.dart', _widget('AppSwitch', 'Component'), []);

  Future<void> test_a_second_piece_in_the_entry_file_is_flagged() => expectIn(
        'global_widgets/global/app_switch/app_switch.dart',
        '${_widget('AppSwitch', 'Component')}\n${_widget('AppSwitchRow', 'Component').split('\n').skip(1).join('\n')}',
        ['AppSwitchRow'],
        message: ['app_switch/app_switch_row/app_switch_row.dart'],
      );

  Future<void> test_a_page_and_a_layout_need_a_folder_too() async {
    await expectIn('pages/vernak/vernak_company_page.dart', _widget('VernakCompanyPage'), ['VernakCompanyPage'],
        after: 'class');
    await expectIn('global_widgets/global/two_panel_layout.dart', _widget('TwoPanelLayout', 'Layout'),
        ['TwoPanelLayout'],
        after: 'class');
  }

  Future<void> test_a_part_in_a_subfolder_is_clean() async {
    newFile('$testPackageLibPath/pages/vernak/vernak_company_page/vernak_company_page.dart',
        _widget('VernakCompanyPage'));
    await expectIn('pages/vernak/vernak_company_page/widgets/company_users_block.dart',
        _widget('CompanyUsersBlock'), []);
  }

  Future<void> test_the_skeleton_file_is_part_of_its_piece() => expectIn(
        'global_widgets/global/app_switch/app_switch_skeleton.dart',
        _widget('AppSwitchSkeleton', 'Skeleton'),
        [],
      );

  Future<void> test_private_and_non_widget_classes_are_clean() => expectIn(
        'global_widgets/global/x.dart',
        "import 'package:flutter/widgets.dart';\nclass AppLabels {}\n"
            'class _Row extends StatelessWidget {\n  @override\n  Widget build(BuildContext context) => Widget();\n}\n',
        [],
      );

  Future<void> test_outside_the_ui_is_clean() => expectIn('utils/x.dart', _widget('AppThing', 'Component'), []);
}

@reflectiveTest
class PieceHasSkeletonTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => PieceHasSkeleton();

  Future<void> test_a_component_without_skeleton_is_flagged() => expectIn(
        'global_widgets/global/app_switch/app_switch.dart',
        _widget('AppSwitch', 'Component'),
        ['AppSwitch'],
        message: ['lib/global_widgets/global/app_switch/app_switch_skeleton.dart', 'AppSwitchSkeleton'],
        after: 'class',
      );

  Future<void> test_a_component_with_skeleton_is_clean() async {
    newFile('$testPackageLibPath/global_widgets/global/app_switch/app_switch_skeleton.dart',
        _widget('AppSwitchSkeleton', 'Skeleton'));
    await expectIn('global_widgets/global/app_switch/app_switch.dart', _widget('AppSwitch', 'Component'), []);
  }

  Future<void> test_a_skeleton_file_without_the_class_is_flagged() async {
    newFile('$testPackageLibPath/global_widgets/global/app_switch/app_switch_skeleton.dart', '// empty\n');
    await expectIn('global_widgets/global/app_switch/app_switch.dart', _widget('AppSwitch', 'Component'),
        ['AppSwitch'],
        after: 'class');
  }

  Future<void> test_a_page_needs_one() => expectIn(
        'pages/vernak/vernak_company_page/vernak_company_page.dart',
        _widget('VernakCompanyPage'),
        ['VernakCompanyPage'],
        message: ['vernak_company_page/vernak_company_page_skeleton.dart'],
        after: 'class',
      );

  Future<void> test_layouts_behaviors_and_skeletons_need_none() async {
    await expectIn('global_widgets/global/two_panel_layout/two_panel_layout.dart', _widget('TwoPanelLayout', 'Layout'),
        []);
    await expectIn('global_widgets/global/app_safe_area/app_safe_area.dart', _widget('AppSafeArea', 'Behavior'), []);
    await expectIn('global_widgets/global/skeleton_card/skeleton_card.dart', _widget('SkeletonCard', 'Skeleton'), []);
    await expectIn(
        'global_widgets/global/app_content_page/app_content_page.dart', _widget('AppContentPage', 'Template'), []);
  }

  Future<void> test_dialogs_and_sheets_need_none() async {
    await expectIn('global_widgets/global/app_dialog/app_dialog.dart', _widget('AppDialog', 'Pattern'), []);
    await expectIn('pages/vernak/vernak_company_page/widgets/edit_roles_sheet.dart', _widget('EditRolesSheet'), []);
    await expectIn('pages/vernak/invite_members_sheet/invite_members_sheet.dart', _widget('InviteMembersSheet'), []);
  }

  Future<void> test_a_piece_not_yet_in_its_folder_is_told_where_the_skeleton_goes() => expectIn(
        'global_widgets/global/app_switch.dart',
        _widget('AppSwitch', 'Component'),
        ['AppSwitch'],
        message: ['lib/global_widgets/global/app_switch/app_switch_skeleton.dart'],
        after: 'class',
      );
}
