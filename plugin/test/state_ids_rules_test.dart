import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/state_ids_rules.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/bloc_rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(StateCarriesIdsTest);
    defineReflectiveTests(UiReadsEntitiesThroughBuilderTest);
  });
}

/// A neon_flutter_hive stub, the models and the app's boxes: `Coupon` has an
/// EntityBox, `Branding` only an adapter (a value stored inside an entity).
abstract class _StateIdsTest extends BlocRuleTest {
  @override
  void setUp() {
    newPackage('neon_flutter_hive').addFile('lib/neon_flutter_hive.dart', '''
class EntityBox<T> {
  EntityBox(String name, {required String Function(T) idOf});
  T? get(String id) => null;
  List<T> get values => const [];
}
''');
    super.setUp();
    newFile('$testPackageLibPath/hive/hive_adapters.dart', '''
// @GenerateAdapters([AdapterSpec<Coupon>(), AdapterSpec<Branding>()])
''');
    newFile('$testPackageLibPath/model/coupon.dart', '''
class Coupon {
  const Coupon(this.id);
  final String id;
}

class CouponDraft {
  const CouponDraft(this.text);
  final String text;
}

class Branding {
  const Branding(this.name);
  final String name;
}
''');
    newFile('$testPackageLibPath/hive/boxes.dart', '''
import 'package:neon_flutter_hive/neon_flutter_hive.dart';
import 'package:test/model/coupon.dart';

abstract final class Boxes {
  static final coupons = EntityBox<Coupon>('coupons', idOf: (coupon) => coupon.id);
}
''');
  }
}

const _models = "import 'package:test/model/coupon.dart';\n\n";

@reflectiveTest
class StateCarriesIdsTest extends _StateIdsTest {
  @override
  AnalysisRule get ruleUnderTest => StateCarriesIds();

  Future<void> test_ids_flags_and_drafts_are_clean() => expectIn(
        'bloc/cards/cards_state.dart',
        '''
${_models}sealed class CardsState {
  const CardsState();
}

class CardsLoaded extends CardsState {
  const CardsLoaded(this.couponIds, this.draft, this.branding, {this.saving = false});
  final List<String> couponIds;
  final CouponDraft draft;
  final Branding? branding;
  final bool saving;
}
''',
        [],
      );

  Future<void> test_entities_in_a_state_are_flagged() => expectIn(
        'bloc/cards/cards_state.dart',
        '''
${_models}sealed class CardsState {
  const CardsState();
}

class CardsLoaded extends CardsState {
  const CardsLoaded(this.coupons, this.selected, this.byId);
  final List<Coupon> coupons;
  final Coupon? selected;
  final Map<String, Coupon> byId;
}
''',
        ['coupons', 'selected', 'byId'],
        after: 'this.byId);',
      );

  Future<void> test_outside_the_bloc_role_is_clean() => expectIn(
        'pages/cards/cards_view_state.dart',
        '${_models}class CardsViewState {\n  const CardsViewState(this.coupons);\n  final List<Coupon> coupons;\n}\n',
        [],
      );
}

@reflectiveTest
class UiReadsEntitiesThroughBuilderTest extends _StateIdsTest {
  @override
  AnalysisRule get ruleUnderTest => UiReadsEntitiesThroughBuilder();

  static const _source = '''
import 'package:test/hive/boxes.dart';
import 'package:test/model/coupon.dart';

Object passed() => Boxes.coupons;

Coupon? read(String id) => Boxes.coupons.get(id);

List<Coupon> all() {
  final box = Boxes.coupons;
  return box.values;
}
''';

  Future<void> test_reading_a_box_in_a_page_is_flagged() =>
      expectIn('pages/cards/cards_page.dart', _source, ['Boxes.coupons.get(id)', 'box.values'], after: 'read(');

  Future<void> test_repositories_read_boxes() => expectIn('repository/cards_repository.dart', _source, []);
}
