import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/category_matches_folder.dart';
import 'package:neon_lints/src/support/layer_folders.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/bloc_rule_base.dart';

void main() {
  group('expectedLayerFolder', () {
    test('maps every tier and the overlay suffixes', () {
      expect(expectedLayerFolder('AppSwitch', 'Component'), 'components');
      expect(expectedLayerFolder('TwoPanelLayout', 'Layout'), 'layouts');
      expect(expectedLayerFolder('AppSafeArea', 'Behavior'), 'behaviors');
      expect(expectedLayerFolder('AppPageSection', 'Pattern'), 'patterns');
      expect(expectedLayerFolder('AppContentPage', 'Template'), 'templates');
      expect(expectedLayerFolder('SkeletonCard', 'Skeleton'), 'skeletons');
      expect(expectedLayerFolder('CouponEditor', 'Feature'), 'features');
      expect(expectedLayerFolder('ConfirmActionSheet', 'Pattern'), 'dialogs');
      expect(expectedLayerFolder('VernakCheckoutDialog', 'Feature'), 'dialogs');
      expect(expectedLayerFolder('CardListSkeleton', null), 'skeletons');
      expect(expectedLayerFolder('AppThing', null), isNull);
      expect(expectedLayerFolder('AppThing', 'Page'), isNull);
    });
  });
  defineReflectiveSuite(() {
    defineReflectiveTests(CategoryMatchesFolderTest);
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

const _page = 'pages/vernak/vernak_company_page';

@reflectiveTest
class CategoryMatchesFolderTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => CategoryMatchesFolder();

  void _pageEntry() => newFile('$testPackageLibPath/$_page/vernak_company_page.dart', _widget('VernakCompanyPage'));

  // ------------------------------------------------------------- the kit

  Future<void> test_a_kit_piece_in_its_layer_folder_is_clean() async {
    await expectIn(
        'global_widgets/global/components/app_switch/app_switch.dart', _widget('AppSwitch', 'Component'), []);
    await expectIn('global_widgets/global/layouts/two_panel_layout/two_panel_layout.dart',
        _widget('TwoPanelLayout', 'Layout'), []);
    await expectIn(
        'global_widgets/vernak/features/coupon_editor/coupon_editor.dart', _widget('CouponEditor', 'Feature'), []);
    await expectIn(
        'global_widgets/global/skeletons/skeleton_card/skeleton_card.dart', _widget('SkeletonCard', 'Skeleton'), []);
  }

  Future<void> test_a_kit_piece_at_its_old_location_is_told_its_layer_folder() => expectIn(
        'global_widgets/global/app_switch/app_switch.dart',
        _widget('AppSwitch', 'Component'),
        ['AppSwitch'],
        message: ['a Component', 'no layer folder', 'lib/global_widgets/global/components/app_switch/app_switch.dart'],
        after: 'class',
      );

  Future<void> test_a_kit_piece_in_the_wrong_layer_folder_is_flagged() => expectIn(
        'global_widgets/global/components/app_page_section/app_page_section.dart',
        _widget('AppPageSection', 'Pattern'),
        ['AppPageSection'],
        message: ['a Pattern', 'sits in `components/`', 'global/patterns/app_page_section/app_page_section.dart'],
        after: 'class',
      );

  // A kit without an owner level (NCC0000078, vernakapp): the layer folders
  // sit right under lib/global_widgets/.
  Future<void> test_an_ownerless_kit_piece_in_its_layer_folder_is_clean() async {
    await expectIn('global_widgets/layouts/centered_scroll_column/centered_scroll_column.dart',
        _widget('CenteredScrollColumn', 'Layout'), []);
    await expectIn(
        'global_widgets/components/custom_button/custom_button.dart', _widget('CustomButton', 'Component'), []);
  }

  Future<void> test_an_ownerless_kit_piece_in_the_wrong_layer_folder_is_told_the_right_one() async {
    newFile('$testPackageLibPath/global_widgets/layouts/centered_scroll_column/centered_scroll_column.dart',
        _widget('CenteredScrollColumn', 'Layout'));
    await expectIn(
      'global_widgets/components/share_sheet_tile/share_sheet_tile.dart',
      _widget('ShareSheetTile', 'Pattern'),
      ['ShareSheetTile'],
      message: [
        'a Pattern',
        'sits in `components/`',
        'lib/global_widgets/patterns/share_sheet_tile/share_sheet_tile.dart'
      ],
      after: 'class',
    );
  }

  Future<void> test_an_ownerless_kit_piece_at_its_old_location_is_told_its_layer_folder() async {
    newFile('$testPackageLibPath/global_widgets/layouts/centered_scroll_column/centered_scroll_column.dart',
        _widget('CenteredScrollColumn', 'Layout'));
    await expectIn(
      'global_widgets/app_switch/app_switch.dart',
      _widget('AppSwitch', 'Component'),
      ['AppSwitch'],
      message: ['a Component', 'no layer folder', 'lib/global_widgets/components/app_switch/app_switch.dart'],
      after: 'class',
    );
  }

  Future<void> test_dialogs_and_sheets_go_to_dialogs_whatever_their_category() async {
    await expectIn('global_widgets/global/dialogs/confirm_action_sheet/confirm_action_sheet.dart',
        _widget('ConfirmActionSheet', 'Pattern'), []);
    await expectIn(
      'global_widgets/global/patterns/app_help_dialog/app_help_dialog.dart',
      _widget('AppHelpDialog', 'Pattern'),
      ['AppHelpDialog'],
      message: ['a dialog', 'global/dialogs/app_help_dialog/app_help_dialog.dart'],
      after: 'class',
    );
  }

  Future<void> test_a_grouping_folder_may_stand_on_either_side_of_the_layer_folder() async {
    await expectIn('global_widgets/global/stats/components/app_stat_tile/app_stat_tile.dart',
        _widget('AppStatTile', 'Component'), []);
    await expectIn('global_widgets/global/components/stats/app_bar_chart/app_bar_chart.dart',
        _widget('AppBarChart', 'Component'), []);
    await expectIn(
      'global_widgets/global/stats/app_funnel/app_funnel.dart',
      _widget('AppFunnel', 'Component'),
      ['AppFunnel'],
      message: ['global/components/stats/app_funnel/app_funnel.dart'],
      after: 'class',
    );
  }

  Future<void> test_kit_internals_get_their_layer_below_src() async {
    await expectIn('global_widgets/global/src/templates/app_page_scaffold/app_page_scaffold.dart',
        _widget('AppPageScaffold', 'Template'), []);
    await expectIn(
      'global_widgets/global/src/app_top_panel/app_top_panel.dart',
      _widget('AppTopPanel', 'Pattern'),
      ['AppTopPanel'],
      message: ['global/src/patterns/app_top_panel/app_top_panel.dart'],
      after: 'class',
    );
  }

  Future<void> test_a_skeleton_beside_its_widget_moves_with_it() async {
    await expectIn(
        'global_widgets/global/app_switch/app_switch_skeleton.dart', _widget('AppSwitchSkeleton', 'Skeleton'), []);
    newFile('$testPackageLibPath/global_widgets/global/components/app_pill/app_pill.dart', _widget('AppPill'));
    await expectIn(
        'global_widgets/global/components/app_pill/app_pill.dart',
        '${_widget('AppPill', 'Component')}\n${_widget('AppPillSkeleton', 'Skeleton').split('\n').skip(1).join('\n')}',
        []);
  }

  Future<void> test_a_skeleton_of_its_own_goes_to_skeletons() => expectIn(
        'global_widgets/global/card_list_skeleton/card_list_skeleton.dart',
        _widget('CardListSkeleton', 'Skeleton'),
        ['CardListSkeleton'],
        message: ['a skeleton of its own', 'global/skeletons/card_list_skeleton/card_list_skeleton.dart'],
        after: 'class',
      );

  Future<void> test_parts_of_a_kit_piece_go_to_its_widgets_layer_folder() async {
    newFile('$testPackageLibPath/global_widgets/global/templates/admin_layout/admin_layout.dart',
        _widget('AdminLayout', 'Template'));
    await expectIn('global_widgets/global/templates/admin_layout/widgets/components/admin_sidebar_profile.dart',
        _widget('AdminSidebarProfile', 'Component'), []);
    await expectIn(
      'global_widgets/global/templates/admin_layout/widgets/admin_nav_row.dart',
      _widget('AdminNavRow', 'Component'),
      ['AdminNavRow'],
      message: ['global/templates/admin_layout/widgets/components/admin_nav_row.dart'],
      after: 'class',
    );
  }

  Future<void> test_the_kit_without_a_category_is_left_to_global_widget_has_category() =>
      expectIn('global_widgets/global/app_thing/app_thing.dart', _widget('AppThing'), []);

  // ------------------------------------------------------------- pages and features

  Future<void> test_a_page_part_in_its_layer_folder_is_clean() async {
    _pageEntry();
    await expectIn('$_page/widgets/patterns/company_users_block.dart', _widget('CompanyUsersBlock', 'Pattern'), []);
    await expectIn('$_page/widgets/dialogs/edit_roles_sheet.dart', _widget('EditRolesSheet'), []);
    await expectIn('$_page/widgets/features/smart/smart_trigger_card.dart', _widget('SmartTriggerCard', 'Feature'), []);
  }

  Future<void> test_a_page_part_at_its_old_location_is_flagged() async {
    _pageEntry();
    await expectIn(
      '$_page/widgets/company_users_block.dart',
      _widget('CompanyUsersBlock', 'Pattern'),
      ['CompanyUsersBlock'],
      message: ['lib/$_page/widgets/patterns/company_users_block.dart'],
      after: 'class',
    );
  }

  Future<void> test_a_page_part_without_a_category_is_flagged() async {
    _pageEntry();
    await expectIn(
      '$_page/widgets/company_header.dart',
      _widget('CompanyHeader'),
      ['CompanyHeader'],
      message: ['names no layer', '{@category X}'],
      after: 'class',
    );
  }

  Future<void> test_a_part_outside_widgets_is_told_to_go_there() async {
    _pageEntry();
    await expectIn(
      '$_page/sections/company_users_block.dart',
      _widget('CompanyUsersBlock', 'Pattern'),
      ['CompanyUsersBlock'],
      message: ['lib/$_page/widgets/patterns/sections/company_users_block.dart'],
      after: 'class',
    );
  }

  Future<void> test_a_feature_part_and_a_shared_page_piece() async {
    newFile('$testPackageLibPath/features/vernak/vernak_company_editor/vernak_company_editor.dart',
        _widget('VernakCompanyEditor', 'Feature'));
    await expectIn('features/vernak/vernak_company_editor/widgets/patterns/company_address_section.dart',
        _widget('CompanyAddressSection', 'Pattern'), []);
    await expectIn(
      'features/vernak/vernak_company_editor/widgets/company_logo_field.dart',
      _widget('CompanyLogoField', 'Component'),
      ['CompanyLogoField'],
      message: ['vernak_company_editor/widgets/components/company_logo_field.dart'],
      after: 'class',
    );
    await expectIn('pages/neoncode/widgets/doordrop/components/doordrop_status_badge/doordrop_status_badge.dart',
        _widget('DoorDropStatusBadge', 'Component'), []);
    await expectIn(
      'pages/vernak/widgets/vernak_feature_gate/vernak_feature_gate.dart',
      _widget('VernakFeatureGate', 'Behavior'),
      ['VernakFeatureGate'],
      message: ['lib/pages/vernak/widgets/behaviors/vernak_feature_gate/vernak_feature_gate.dart'],
      after: 'class',
    );
  }

  Future<void> test_pages_feature_pieces_and_page_skeletons_are_not_placed_by_layer() async {
    await expectIn('$_page/vernak_company_page.dart', _widget('VernakCompanyPage'), []);
    await expectIn('$_page/vernak_company_page_skeleton.dart', _widget('VernakCompanyPageSkeleton'), []);
    await expectIn('features/vernak/banners/vernak_banner_stack/vernak_banner_stack.dart',
        _widget('VernakBannerStack', 'Feature'), []);
    await expectIn('pages/vernak/help/vernak_help_row.dart', _widget('VernakHelpRow'), []);
  }

  Future<void> test_private_classes_non_widgets_and_previews_are_clean() async {
    await expectIn(
      'global_widgets/global/x.dart',
      "import 'package:flutter/widgets.dart';\nclass AppLabels {}\n"
          'class _Row extends StatelessWidget {\n  @override\n  Widget build(BuildContext context) => Widget();\n}\n',
      [],
    );
    await expectIn('pages/neoncode/widgets/widget_catalog/previews/previews_a.dart', _widget('PreviewThing'), []);
    await expectIn('utils/x.dart', _widget('AppThing', 'Component'), []);
  }
}
