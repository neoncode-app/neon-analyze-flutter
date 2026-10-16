import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/model_layout_rules.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/bloc_rule_base.dart';
import 'support/stub_packages.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(EnumInEnumsFolderTest);
    defineReflectiveTests(OneDeclarationPerModelFileTest);
    defineReflectiveTests(ModelsOnlyInModelTest);
    defineReflectiveTests(NoLogicInModelsTest);
  });
}

/// The model rules with the json_annotation stubs.
abstract class _ModelTest extends BlocRuleTest {
  @override
  void setUp() {
    addJsonPackages(this);
    super.setUp();
  }
}

@reflectiveTest
class EnumInEnumsFolderTest extends _ModelTest {
  @override
  AnalysisRule get ruleUnderTest => EnumInEnumsFolder();

  Future<void> test_enum_in_a_cubit_is_flagged() => expectIn(
        'bloc/vernak/cards/cards_state.dart',
        'enum CardsTab { coupons, cards }\n\nenum _Mode { a, b }\n\nclass CardsState {\n  final _Mode mode = _Mode.a;\n}\n',
        ['CardsTab', '_Mode'],
        message: ['not in a scope folder of lib/model/enums/'],
      );

  Future<void> test_enum_in_another_model_folder_is_flagged() =>
      expectIn('model/vernak/notification_kind.dart', 'enum NotificationKind { manual, smart }\n', ['NotificationKind']);

  Future<void> test_enum_directly_in_the_enums_root_is_flagged() => expectIn(
        'model/enums/alert_type.dart',
        'enum AlertType { info, error }\n',
        ['AlertType'],
        message: ['not in a scope folder'],
      );

  Future<void> test_enum_nested_below_a_scope_is_flagged() => expectIn(
        'model/enums/vernak/roles/vernak_role.dart',
        'enum VernakRole { root }\n',
        ['VernakRole'],
        message: ['nested below its scope folder'],
      );

  Future<void> test_message_names_the_file() => expectIn(
        'pages/x_page.dart',
        'enum CardsTab { coupons }\n',
        ['CardsTab'],
        message: ['lib/model/enums/<scope>/cards_tab.dart'],
      );

  Future<void> test_enum_in_a_file_named_otherwise_is_flagged() => expectIn(
        'model/enums/doordrop/doordrop_enums.dart',
        'enum DoorDropTurn { a }\n',
        ['DoorDropTurn'],
        message: ['not named after it'],
      );

  Future<void> test_enum_in_its_scope_file_is_clean() => expectIn(
        'model/enums/doordrop/doordrop_turn.dart',
        'enum DoorDropTurn { a }\n',
        [],
      );

  Future<void> test_snake_case_file_is_clean() =>
      expectIn('model/enums/common/alert_type.dart', 'enum AlertType { info }\n', []);

  Future<void> test_kit_enum_beside_its_widget_goes_to_its_dimens() => expectIn(
        'global_widgets/global/custom_button/custom_button.dart',
        'enum CustomButtonVariant { filled }\n',
        ['CustomButtonVariant'],
        message: ['outside a *_dimens.dart', '<piece>_dimens.dart'],
      );

  Future<void> test_kit_variant_enum_in_dimens_stays() =>
      expectIn('global_widgets/global/app_switch/app_switch_dimens.dart', 'enum AppSwitchVariant { small }\n', []);

  Future<void> test_page_variant_enum_in_dimens_is_flagged() => expectIn(
        'pages/vernak/cards_page/cards_page_dimens.dart',
        'enum CardsPageVariant { small }\n',
        ['CardsPageVariant'],
      );

  Future<void> test_tests_and_generated_files_are_skipped() async {
    await expectIn('model/user.g.dart', 'enum GeneratedThing { a }\n', []);
  }

  Future<void> test_layout_override_lists_the_scopes() async {
    newFile('$testPackageRootPath/neon_check.yaml', 'layout:\n  enums: [lib/model/enums/common/, lib/model/enums/vernak/]\n');
    await expectIn('model/enums/common/alert_type.dart', 'enum AlertType { info }\n', []);
    await expectIn('model/enums/moment/quest_kind.dart', 'enum QuestKind { a }\n', ['QuestKind']);
  }
}

@reflectiveTest
class OneDeclarationPerModelFileTest extends _ModelTest {
  @override
  AnalysisRule get ruleUnderTest => OneDeclarationPerModelFile();

  Future<void> test_further_declarations_are_flagged() => expectIn(
        'model/enums/vernak/vernak_role.dart',
        '''
enum VernakRole { root, admin }

extension VernakRoleX on VernakRole {
  bool get isRoot => this == VernakRole.root;
}

extension on VernakRole {
  bool get isAdmin => this == VernakRole.admin;
}

class _Helper {}

typedef RoleMap = Map<String, VernakRole>;

mixin RoleMixin {}
''',
        ['VernakRoleX', 'extension', '_Helper', 'RoleMap', 'RoleMixin'],
        after: 'enum VernakRole',
        message: ['further top-level declaration'],
      );

  Future<void> test_one_class_with_constants_is_clean() => expectIn(
        'model/user.dart',
        "const userBase = '/api/users';\n\nclass User {\n  const User(this.name);\n  final String name;\n}\n",
        [],
      );

  Future<void> test_outside_the_model_role_is_clean() =>
      expectIn('bloc/cards/cards_state.dart', 'sealed class CardsState {}\n\nclass CardsLoading extends CardsState {}\n', []);
}

@reflectiveTest
class ModelsOnlyInModelTest extends _ModelTest {
  @override
  AnalysisRule get ruleUnderTest => ModelsOnlyInModel();

  Future<void> test_serializing_class_outside_model_is_flagged() => expectIn(
        'bloc/vernak/cards/vernak_cards_parsing.dart',
        '''
import 'package:json_annotation/json_annotation.dart';

class CardRow {
  const CardRow(this.id);
  factory CardRow.fromJson(Map<String, dynamic> json) => CardRow(json['id'] as String);
  final String id;
}

class TierRow {
  Map<String, dynamic> toJson() => {};
}

@JsonSerializable()
class Annotated {}

class PlainState {}
''',
        ['CardRow', 'TierRow', 'Annotated'],
        after: 'json_annotation.dart',
        message: ['serializes outside the model role'],
      );

  Future<void> test_models_file_outside_model_is_flagged() => expectIn(
        'global_widgets/vernak/pricing/pricing_tier_models.dart',
        '''
import 'package:flutter/widgets.dart';

class PricingTierItem {
  const PricingTierItem(this.name);
  final String name;
}

class PricingTierActionLabels {
  const PricingTierActionLabels(this.buy);
  final String buy;
}

class PricingTierBadge extends StatelessWidget {
  const PricingTierBadge();
  @override
  Widget build(BuildContext context) => Widget();
}
''',
        ['PricingTierItem'],
        message: ['the model PricingTierItem is declared outside the model role'],
      );

  Future<void> test_plain_classes_outside_model_are_clean() =>
      expectIn('bloc/vernak/cards/vernak_cards_view.dart', 'class CardRowView {\n  const CardRowView();\n}\n', []);

  Future<void> test_serializing_class_in_model_is_clean() => expectIn(
        'model/vernak/vernak_coupon.dart',
        'class VernakCoupon {\n  const VernakCoupon(this.color);\n'
            '  factory VernakCoupon.fromJson(Map<String, dynamic> json) => const VernakCoupon(0);\n'
            '  final int color;\n}\n',
        [],
      );

  Future<void> test_ui_in_model_is_flagged() => expectIn(
        'model/widget_catalog/widget_catalog_entry.dart',
        '''
import 'package:flutter/material.dart';
import 'package:test/pages/x_page.dart';

class CatalogPreview extends StatelessWidget {
  const CatalogPreview();
  @override
  Widget build(BuildContext context) => const XPage();
}

abstract final class VernakSampleCardsDimens {
  static const double fontSize28 = 28;
}
''',
        ["'package:flutter/material.dart'", "'package:test/pages/x_page.dart'", 'CatalogPreview', 'VernakSampleCardsDimens'],
      );

  Future<void> test_foundation_is_clean() => expectIn(
        'model/vernak/vernak_banner.dart',
        "import 'package:flutter/foundation.dart';\n\nclass VernakBanner {}\n",
        [],
      );

  Future<void> test_layout_override_of_the_model_role() async {
    newFile('$testPackageRootPath/neon_check.yaml', 'layout:\n  model: [lib/data/]\n');
    await expectIn('data/user.dart', 'class User {\n  Map<String, dynamic> toJson() => {};\n}\n', []);
    await expectIn('model/user.dart', 'class User {\n  Map<String, dynamic> toJson() => {};\n}\n', ['User']);
  }

  @override
  void setUp() {
    super.setUp();
    newFile('$testPackageLibPath/pages/x_page.dart', '''
import 'package:flutter/widgets.dart';

class XPage extends StatelessWidget {
  const XPage();
  @override
  Widget build(BuildContext context) => Widget();
}
''');
  }
}

@reflectiveTest
class NoLogicInModelsTest extends _ModelTest {
  @override
  AnalysisRule get ruleUnderTest => NoLogicInModels();

  Future<void> test_top_level_functions_are_flagged() => expectIn(
        'model/vernak/vernak_loyalty_card.dart',
        '''
String colorToHex(int color) => '\$color';

int _parse(Object? raw) => raw is int ? raw : 0;

int get defaultColor => 0;

class VernakLoyaltyCard {
  const VernakLoyaltyCard(this.color);
  final int color;
  String get hex => colorToHex(color) + '\${_parse(color)}\$defaultColor';
}
''',
        ['colorToHex', '_parse', 'defaultColor'],
      );

  Future<void> test_methods_of_the_model_are_clean() => expectIn(
        'model/user.dart',
        "class User {\n  const User(this.name);\n  final String name;\n  String get initials => name.substring(0, 1);\n}\n",
        [],
      );

  Future<void> test_helpers_outside_the_model_role_are_clean() =>
      expectIn('utils/helpers/color_helpers.dart', 'String colorToHex(int color) => "\$color";\n', []);
}
