import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/feature_reads_state.dart';
import 'package:neon_lints/src/no_data_logic_in_ui.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/bloc_rule_base.dart';
import 'support/stub_packages.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(FeatureReadsStateTest);
    defineReflectiveTests(NoDataLogicInUiTest);
  });
}

/// The app files the rules look at: a cubit with its state, a providers
/// file with a typed getter, a repository and a model.
abstract class _PlacementTest extends BlocRuleTest {
  @override
  void setUp() {
    newPackage('neon_flutter_hive').addFile('lib/neon_flutter_hive.dart', '''
import 'package:flutter/widgets.dart';

class EntityBox<T> {}

class HiveEntityBuilder<T> extends StatelessWidget {
  const HiveEntityBuilder({required this.box, required this.id, required this.builder});
  final EntityBox<T> box;
  final String id;
  final Widget Function(BuildContext context, T entity) builder;
  @override
  Widget build(BuildContext context) => Widget();
}
''');
    super.setUp();
    patchMockSdk(this);
    newFile('$testPackageLibPath/bloc/vernak/cards/cards_cubit.dart', '''
import 'package:test/bloc/global/base/base_cubit.dart';

sealed class CardsState {}

class CardsCubit extends BaseCubit<CardsState> {
  CardsCubit(super.initialState);
  void open() {}
}
''');
    newFile('$testPackageLibPath/flavors/vernak/vernak_providers.dart', '''
import 'package:flutter/widgets.dart';
import 'package:test/bloc/vernak/cards/cards_cubit.dart';

extension VernakProviders on BuildContext {
  CardsCubit get cardsCubit => throw 0;
  bool get canEdit => true;
}
''');
    newFile('$testPackageLibPath/repository/api_repository.dart', '''
class ApiRepository {
  Future<void> load() async {}
}
''');
    newFile('$testPackageLibPath/hive/boxes.dart', '''
import 'package:neon_flutter_hive/neon_flutter_hive.dart';
import 'package:test/model/coupon.dart';

abstract final class Boxes {
  static final coupons = EntityBox<Coupon>();
}
''');
    newFile('$testPackageLibPath/utils/ui/theme_extensions.dart', '''
import 'package:flutter/widgets.dart';

extension ThemeContext on BuildContext {
  int get appColors => 0;
}
''');
    newFile('$testPackageLibPath/model/coupon.dart', '''
class Coupon {
  const Coupon(this.price, this.name, this.active);
  final int price;
  final String name;
  final bool active;
  static const int limit = 3;
}

enum CouponKind { stamp, discount }
''');
  }
}

const _imports = '''
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bloc_presentation/bloc_presentation.dart';
import 'package:test/bloc/vernak/cards/cards_cubit.dart';
import 'package:test/flavors/vernak/vernak_providers.dart';
import 'package:test/repository/api_repository.dart';
import 'package:test/utils/ui/theme_extensions.dart';
import 'package:test/model/coupon.dart';
''';

@reflectiveTest
class FeatureReadsStateTest extends _PlacementTest {
  @override
  AnalysisRule get ruleUnderTest => FeatureReadsState();

  Future<void> test_feature_drawing_from_parameters_and_theme_is_flagged() => expectIn(
        'features/vernak/banner/banner.dart',
        '''
${_imports}
/// A banner.
///
/// {@category Feature}
class Banner extends StatelessWidget {
  const Banner({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => _Body(color: context.appColors);
}

class _Body extends StatelessWidget {
  const _Body({required this.color});
  final int color;
  @override
  Widget build(BuildContext context) => Widget();
}
''',
        ['Banner'],
        message: ['the Feature `Banner` reads no state', 'belongs to the kit'],
        after: 'class Banner',
      );

  Future<void> test_an_entity_read_from_hive_through_a_builder_is_a_read() => expectIn(
        'features/vernak/coupon_tile/coupon_tile.dart',
        '''
${_imports}import 'package:neon_flutter_hive/neon_flutter_hive.dart';
import 'package:test/hive/boxes.dart';

/// A coupon by its id.
///
/// {@category Feature}
class CouponTile extends StatelessWidget {
  const CouponTile({required this.id});
  final String id;
  @override
  Widget build(BuildContext context) =>
      HiveEntityBuilder<Coupon>(box: Boxes.coupons, id: id, builder: (context, coupon) => Widget());
}
''',
        [],
      );

  Future<void> test_a_typed_context_getter_is_a_read() => expectIn(
        'features/vernak/banner/banner.dart',
        '''
${_imports}
/// A banner.
///
/// {@category Feature}
class Banner extends StatelessWidget {
  const Banner();
  @override
  Widget build(BuildContext context) => context.canEdit ? Widget() : Widget();
}
''',
        [],
      );

  Future<void> test_a_bloc_builder_in_a_private_class_of_the_file_is_a_read() => expectIn(
        'features/vernak/banner/banner.dart',
        '''
${_imports}
/// A banner.
///
/// {@category Feature}
class Banner extends StatelessWidget {
  const Banner();
  @override
  Widget build(BuildContext context) => const _Body();
}

class _Body extends StatelessWidget {
  const _Body();
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<CardsCubit, CardsState>(builder: (context, state) => Widget());
}
''',
        [],
      );

  Future<void> test_the_state_class_a_cubit_field_a_repository_and_a_feature_are_reads() async {
    await expectIn(
      'features/vernak/a/a.dart',
      '''
${_imports}
/// A.
///
/// {@category Feature}
class A extends StatefulWidget {
  const A();
}

class _AState extends State<A> {
  @override
  Widget build(BuildContext context) => BlocPresentationListener<CardsCubit, Object>(listener: (_, __) {});
}
''',
      [],
    );
    await expectIn(
      'features/vernak/b/b.dart',
      '''
${_imports}
/// B.
///
/// {@category Feature}
class B extends StatelessWidget {
  const B(this.repository);
  final ApiRepository repository;
  @override
  Widget build(BuildContext context) => Widget();
}
''',
      [],
    );
    await expectIn(
      'features/vernak/c/c.dart',
      '''
${_imports}import 'package:test/features/vernak/b/b.dart';

/// A shell built from features.
///
/// {@category Feature}
class C extends StatelessWidget {
  const C(this.repository);
  final ApiRepository repository;
  @override
  Widget build(BuildContext context) => B(repository);
}
''',
      [],
    );
  }

  Future<void> test_a_private_function_in_another_part_of_the_library_is_its_implementation() async {
    const part = '''
part of '../scope.dart';

/// A strip.
///
/// {@category Feature}
class Strip extends StatelessWidget {
  const Strip();
  @override
  Widget build(BuildContext context) => _items(context) ? Widget() : Widget();
}
''';
    newFile('$testPackageLibPath/features/vernak/scope/scope.dart', '''
${_imports}
part 'widgets/strip.dart';

bool _items(BuildContext context) => context.canEdit;
''');
    await expectIn('features/vernak/scope/widgets/strip.dart', part, []);
  }

  Future<void> test_a_library_whose_private_functions_read_nothing_is_flagged() async {
    newFile('$testPackageLibPath/features/vernak/ticker/ticker.dart', '''
${_imports}
part 'widgets/strip.dart';

bool _items(BuildContext context) => context.appColors == 0;
''');
    await expectIn(
      'features/vernak/ticker/widgets/strip.dart',
      '''
part of '../ticker.dart';

/// A strip.
///
/// {@category Feature}
class Strip extends StatelessWidget {
  const Strip();
  @override
  Widget build(BuildContext context) => _items(context) ? Widget() : Widget();
}
''',
      ['Strip'],
      after: 'class ',
    );
  }

  Future<void> test_other_categories_are_not_checked() => expectIn(
        'global_widgets/global/components/pill/pill.dart',
        '''
import 'package:flutter/widgets.dart';

/// A pill.
///
/// {@category Component}
class Pill extends StatelessWidget {
  const Pill();
  @override
  Widget build(BuildContext context) => Widget();
}
''',
        [],
      );

  Future<void> test_a_layout_override_moves_the_providers() async {
    newFile('$testPackageRootPath/neon_check.yaml', 'layout:\n  providers: lib/utils/ui/theme_extensions.dart\n');
    await expectIn(
      'features/vernak/banner/banner.dart',
      '''
${_imports}
/// A banner.
///
/// {@category Feature}
class Banner extends StatelessWidget {
  const Banner();
  @override
  Widget build(BuildContext context) => context.appColors == 0 ? Widget() : Widget();
}
''',
      [],
    );
  }
}

@reflectiveTest
class NoDataLogicInUiTest extends _PlacementTest {
  @override
  AnalysisRule get ruleUnderTest => NoDataLogicInUi();

  Future<void> test_computations_over_model_data_are_flagged() => expectIn(
        'pages/vernak/x_page/x_page.dart',
        '''
${_imports}
class XPage extends StatelessWidget {
  const XPage(this.coupons, this.coupon);
  final List<Coupon> coupons;
  final Coupon coupon;

  @override
  Widget build(BuildContext context) {
    final active = coupons.where((c) => c.active);
    final first = coupons.firstWhere((c) => c.active);
    final total = coupons.fold<int>(0, (sum, c) => sum + c.price);
    final some = coupons.any((c) => c.active) || coupons.every((c) => c.active);
    final today = DateTime.now();
    final doubled = coupon.price * 2;
    final half = (coupon.price - first.price) / 2 + 1;
    return Widget();
  }
}
''',
        ['where', 'firstWhere', 'fold', 'sum + c.price', 'any', 'every', 'DateTime.now()', 'coupon.price * 2', '(coupon.price - first.price) / 2 + 1'],
        message: ['UI only draws'],
        after: 'Widget build',
      );

  Future<void> test_sorting_in_a_state_and_in_the_kit_is_flagged() async {
    await expectIn(
      'features/vernak/list/list.dart',
      '''
${_imports}
class CouponList extends StatefulWidget {
  const CouponList(this.coupons);
  final List<Coupon> coupons;
}

class _CouponListState extends State<CouponList> {
  final coupons = <Coupon>[];

  @override
  Widget build(BuildContext context) {
    coupons.sort((a, b) => a.price.compareTo(b.price));
    return Widget();
  }
}
''',
      ['sort'],
    );
    await expectIn(
      'global_widgets/global/components/coupon_row/coupon_row.dart',
      '''
${_imports}
class CouponRow extends StatelessWidget {
  const CouponRow(this.coupons);
  final Iterable<Coupon> coupons;
  @override
  Widget build(BuildContext context) => coupons.expand((c) => [c]).isEmpty ? Widget() : Widget();
}
''',
      ['expand'],
    );
  }

  Future<void> test_drawing_comparing_and_layout_maths_are_clean() => expectIn(
        'global_widgets/global/components/coupon_grid/coupon_grid.dart',
        '''
${_imports}
class CouponGrid extends StatelessWidget {
  const CouponGrid(this.coupons, this.coupon, this.columns, this.kinds, this.names);
  final List<Coupon> coupons;
  final Coupon coupon;
  final int columns;
  final List<CouponKind> kinds;
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final width = columns * 120.0 + 8;
    final rows = (coupons.length / columns).ceil() - 1;
    final cheap = coupon.price > 10;
    final label = coupon.name + '!';
    final limit = Coupon.limit * 2;
    final shown = kinds.where((k) => k != CouponKind.stamp);
    final filtered = names.where((n) => n.isNotEmpty);
    return Column(child: [for (final c in coupons) Widget(), ...coupons.map((c) => Widget())]);
  }
}

double total(List<Coupon> coupons) => coupons.fold(0, (sum, c) => sum + c.price);
''',
        [],
      );

  Future<void> test_the_cubit_computes_freely() => expectIn(
        'bloc/vernak/cards/cards_logic.dart',
        '''
${_imports}
class CardsLogic {
  List<Coupon> active(List<Coupon> coupons) => coupons.where((c) => c.active).toList();
  DateTime now() => DateTime.now();
}
''',
        [],
      );

  Future<void> test_a_layout_override_moves_the_models() async {
    newFile('$testPackageRootPath/neon_check.yaml', 'layout:\n  model: [lib/domain/]\n');
    await expectIn(
      'pages/vernak/x_page/x_page.dart',
      '''
${_imports}
class XPage extends StatelessWidget {
  const XPage(this.coupons);
  final List<Coupon> coupons;
  @override
  Widget build(BuildContext context) => coupons.any((c) => c.active) ? Widget() : Widget();
}
''',
      [],
    );
  }
}
