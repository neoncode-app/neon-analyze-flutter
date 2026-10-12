import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/alert_only_in_cubit.dart';
import 'package:neon_lints/src/cancel_subscriptions_in_close.dart';
import 'package:neon_lints/src/cubit_created_in_provider.dart';
import 'package:neon_lints/src/no_cubit_call_in_lifecycle.dart';
import 'package:neon_lints/src/no_provider_value.dart';
import 'package:neon_lints/src/no_state_enum_branching.dart';
import 'package:neon_lints/src/no_status_enum_state.dart';
import 'package:neon_lints/src/provider_in_router.dart';
import 'package:neon_lints/src/state_is_sealed.dart';
import 'package:neon_lints/src/use_context_getters.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/bloc_rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(UseContextGettersTest);
    defineReflectiveTests(CubitCreatedInProviderTest);
    defineReflectiveTests(ProviderInRouterTest);
    defineReflectiveTests(NoCubitCallInLifecycleTest);
    defineReflectiveTests(NoProviderValueTest);
    defineReflectiveTests(CancelSubscriptionsInCloseTest);
    defineReflectiveTests(AlertOnlyInCubitTest);
    defineReflectiveTests(StateIsSealedTest);
    defineReflectiveTests(NoStatusEnumStateTest);
    defineReflectiveTests(NoStateEnumBranchingTest);
  });
}

const _imports = '''
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:test/bloc/global/base/base_cubit.dart';
''';

const _cubit = '''
class CounterCubit extends BaseCubit<int> {
  CounterCubit() : super(0);
  Future<void> load() async {}
  void save() {}
}
''';

@reflectiveTest
class UseContextGettersTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => UseContextGetters();

  static const _source = '''
$_imports$_cubit
void f(BuildContext context) {
  context.read<CounterCubit>().save();
  context.watch<CounterCubit>();
  context.select<CounterCubit, int>((cubit) => cubit.state);
  BlocProvider.of<CounterCubit>(context);
}
''';

  Future<void> test_direct_reads_are_flagged() => expectIn(
        'pages/counter_page.dart',
        _source,
        [
          'context.read<CounterCubit>()',
          'context.watch<CounterCubit>()',
          'context.select<CounterCubit, int>((cubit) => cubit.state)',
          'BlocProvider.of<CounterCubit>(context)',
        ],
        message: ['lib/flavors/{flavor}/{flavor}_providers.dart'],
      );

  Future<void> test_providers_file_owns_the_reads() => expectIn('flavors/vernak/vernak_providers.dart', _source, []);

  Future<void> test_other_flavor_file_is_not_the_owner() => expectIn(
        'flavors/vernak/neoncode_providers.dart',
        '$_imports$_cubit\nCounterCubit f(BuildContext context) => context.read<CounterCubit>();\n',
        ['context.read<CounterCubit>()'],
      );

  Future<void> test_typed_getter_is_clean() => expectIn(
        'pages/counter_page.dart',
        '$_imports$_cubit\nextension on BuildContext {\n  CounterCubit get counterCubit => throw 0;\n}\n'
            'void f(BuildContext context) => context.counterCubit.save();\n',
        [],
      );
}

@reflectiveTest
class CubitCreatedInProviderTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => CubitCreatedInProvider();

  Future<void> test_construction_outside_a_provider_is_flagged() => expectIn(
        'pages/counter_page.dart',
        '$_imports$_cubit\nfinal cubit = CounterCubit();\nvoid f() {\n  final local = CounterCubit()..load();\n}\n',
        ['CounterCubit', 'CounterCubit'],
        message: ['BlocProvider(create:'],
        after: 'final cubit =',
      );

  Future<void> test_create_callback_owns_construction() => expectIn(
        'flavors/neoncode/neoncode_router.dart',
        '$_imports$_cubit\n'
            'Widget a() => BlocProvider(create: (_) => CounterCubit()..load());\n'
            'Widget b() => BlocProvider(create: (_) {\n  final cubit = CounterCubit();\n  return cubit..load();\n});\n',
        [],
      );

  Future<void> test_app_startup_builds_the_app_wide_cubits() => expectIn(
        'app/bootstrap.dart',
        '$_imports$_cubit\nWidget a() {\n  final cubit = CounterCubit();\n  return BlocProvider<CounterCubit>.value(value: cubit);\n}\n',
        [],
      );

  Future<void> test_own_async_factory_is_not_a_construction_site() => expectIn(
        'bloc/session/session_cubit.dart',
        '$_imports\nclass SessionCubit extends BaseCubit<int> {\n  SessionCubit._() : super(0);\n'
            '  static Future<SessionCubit> create() async => SessionCubit._();\n}\n'
            'class Other extends BaseCubit<int> {\n  Other() : super(0);\n  SessionCubit make() => SessionCubit._();\n}\n',
        ['SessionCubit._'],
        after: 'SessionCubit make',
      );

  Future<void> test_closure_inside_create_that_is_not_create_is_flagged() => expectIn(
        'pages/counter_page.dart',
        '$_imports$_cubit\nWidget a(void Function(Object) run) => BlocProvider(create: (_) {\n'
            '  run(() => CounterCubit());\n  return CounterCubit();\n});\n',
        ['CounterCubit'],
        after: 'run(() =>',
      );
}

@reflectiveTest
class ProviderInRouterTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => ProviderInRouter();

  static const _source = '''
$_imports$_cubit
CounterCubit c() => throw 0;
Widget a() => BlocProvider(create: (_) => c());
Widget b() => MultiBlocProvider(providers: []);
Widget d() => BlocProvider.value(value: c());
''';

  Future<void> test_provider_in_a_page_is_flagged() => expectIn(
        'pages/counter_page.dart',
        _source,
        ['BlocProvider', 'MultiBlocProvider', 'BlocProvider.value'],
        message: ['route builder'],
      );

  Future<void> test_router_and_shell_own_providers() => expectIn('flavors/vernak/vernak_router.dart', _source, []);

  Future<void> test_dialog_helper_owns_providers() => expectIn('utils/utils.dart', _source, []);

  Future<void> test_app_startup_owns_providers() => expectIn('app/bootstrap.dart', _source, []);
}

@reflectiveTest
class NoCubitCallInLifecycleTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => NoCubitCallInLifecycle();

  Future<void> test_calls_in_lifecycle_methods_are_flagged() => expectIn(
        'pages/counter_page.dart',
        '''
$_imports$_cubit
CounterCubit cubitOf(BuildContext context) => throw 0;

class CounterPage extends StatefulWidget {
  const CounterPage();
}

class _CounterPageState extends State<CounterPage> {
  final CounterCubit _cubit = cubitOf(BuildContextStub());

  @override
  void initState() {
    super.initState();
    _cubit.load();
  }

  @override
  void didChangeDependencies() {
    cubitOf(context).save();
  }

  @override
  Widget build(BuildContext context) {
    cubitOf(context).load();
    return Widget();
  }
}

class Label extends StatelessWidget {
  const Label();

  @override
  Widget build(BuildContext context) {
    cubitOf(context).save();
    return Widget();
  }
}

class BuildContextStub implements BuildContext {}
''',
        ['load', 'save', 'load', 'save'],
        message: ['BlocProvider(create:'],
        after: 'super.initState();',
      );

  Future<void> test_callbacks_and_other_methods_are_clean() => expectIn(
        'pages/counter_page.dart',
        '''
$_imports$_cubit
CounterCubit cubitOf(BuildContext context) => throw 0;

class Button extends StatelessWidget {
  const Button({this.onTap});
  final void Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final count = cubitOf(context).state;
    return Button(onTap: () => cubitOf(context).save());
  }

  void tapped(BuildContext context) => cubitOf(context).save();
}
''',
        [],
      );

  Future<void> test_cubit_own_methods_are_not_widget_lifecycle() => expectIn(
        'bloc/counter/counter_cubit.dart',
        '$_imports$_cubit\nclass Other extends BaseCubit<int> {\n  Other(this.counter) : super(0);\n'
            '  final CounterCubit counter;\n  void build() => counter.load();\n}\n',
        [],
      );
}

@reflectiveTest
class NoProviderValueTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => NoProviderValue();

  static const _page = '''
$_imports$_cubit
class CounterPage extends StatefulWidget {
  const CounterPage();
}

class _CounterPageState extends State<CounterPage> {
  final CounterCubit _cubit = CounterCubit();

  @override
  Widget build(BuildContext context) => BlocProvider.value(value: _cubit);

  Widget other() => BlocProvider.value(value: this._cubit);
}
''';

  Future<void> test_field_held_cubit_is_flagged() => expectIn(
        'pages/counter_page.dart',
        _page,
        ['_cubit', 'this._cubit'],
        message: ['BlocProvider(create: ...)'],
        after: 'BlocProvider.value(value: ',
      );

  Future<void> test_value_not_held_in_state_is_clean() => expectIn(
        'pages/counter_page.dart',
        '$_imports$_cubit\nclass CounterPage extends StatefulWidget {\n  const CounterPage();\n}\n\n'
            'class _CounterPageState extends State<CounterPage> {\n'
            '  @override\n  Widget build(BuildContext context) => BlocProvider.value(value: CounterCubit());\n}\n'
            'Widget dialog(CounterCubit cubit) => BlocProvider.value(value: cubit);\n',
        [],
      );
}

@reflectiveTest
class CancelSubscriptionsInCloseTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => CancelSubscriptionsInClose();

  Future<void> test_unstored_or_uncancelled_subscriptions_are_flagged() => expectIn(
        'bloc/rules/rules_cubit.dart',
        '''
import 'dart:async';
$_imports$_cubit
class RulesCubit extends BaseCubit<int> {
  RulesCubit(this.session) : super(0) {
    session.stream.listen((_) {});
    _kept = session.stream.listen((_) {});
  }

  final CounterCubit session;
  StreamSubscription<int>? _kept;
}
''',
        ['session.stream.listen((_) {})', 'session.stream.listen((_) {})'],
        message: ['cancel it in close()'],
        after: 'super(0) {',
      );

  Future<void> test_field_cancelled_in_close_is_clean() => expectIn(
        'bloc/rules/rules_cubit.dart',
        '''
import 'dart:async';
$_imports$_cubit
class RulesCubit extends BaseCubit<int> {
  RulesCubit(this.session) : super(0) {
    _sub = session.stream.listen((_) {});
    _other ??= session.stream.listen((_) {});
  }

  final CounterCubit session;
  StreamSubscription<int>? _sub;
  StreamSubscription<int>? _other;

  @override
  Future<void> close() async {
    await _sub?.cancel();
    await _other?.cancel();
    return super.close();
  }
}

class NotACubit {
  NotACubit(Stream<int> stream) {
    stream.listen((_) {});
  }
}
''',
        [],
      );
}

@reflectiveTest
class AlertOnlyInCubitTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => AlertOnlyInCubit();

  static const _source = '''
$_imports
import 'package:test/bloc/global/alert/alert_cubit.dart';

extension on BuildContext {
  AlertCubit get alertCubit => throw 0;
}

void f(BuildContext context) {
  context.read<AlertCubit>().showSuccess('ok');
  context.alertCubit.showSuccess('ok');
  g(context.alertCubit);
}

void g(Object alert) {}
''';

  Future<void> test_alert_in_ui_folders_is_flagged() async {
    for (final folder in ['pages', 'features', 'global_widgets']) {
      await expectIn(
        '$folder/x.dart',
        _source,
        ['AlertCubit', 'AlertCubit', 'context.alertCubit', 'context.alertCubit'],
        message: ['inject AlertCubit into the cubit'],
        after: 'extension on BuildContext',
      );
    }
  }

  Future<void> test_cubits_and_the_toast_renderer_may_use_it() async {
    await expectIn('bloc/counter/counter_cubit.dart', _source, []);
    await expectIn('app/bootstrap.dart', _source, []);
  }
}

@reflectiveTest
class StateIsSealedTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => StateIsSealed();

  Future<void> test_non_sealed_state_is_flagged() => expectIn(
        'bloc/counter/counter_cubit.dart',
        '''
$_imports
abstract class CounterState {}

class CounterCubit extends BaseCubit<CounterState> {
  CounterCubit() : super(throw 0);
}

class FlagCubit extends BaseCubit<bool> {
  FlagCubit() : super(false);
}
''',
        ['BaseCubit<CounterState>', 'BaseCubit<bool>'],
        message: ['sealed class'],
      );

  Future<void> test_sealed_state_is_clean() => expectIn(
        'bloc/counter/counter_cubit.dart',
        '''
$_imports
sealed class CounterState {}

final class CounterLoaded extends CounterState {}

class CounterCubit extends BaseCubit<CounterState> {
  CounterCubit() : super(CounterLoaded());
}
''',
        [],
      );

  Future<void> test_app_wide_folder_is_exempt() => expectIn(
        'bloc/vernak/app_wide/rules_cubit.dart',
        '$_imports\nclass RulesCubit extends BaseCubit<int> {\n  RulesCubit() : super(0);\n}\n',
        [],
      );
}

@reflectiveTest
class NoStatusEnumStateTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => NoStatusEnumState();

  Future<void> test_status_enum_field_is_flagged() => expectIn(
        'bloc/invoices/invoices_state.dart',
        '''
enum InvoicesStatus { initial, loading, loaded }

class InvoicesState {
  const InvoicesState({this.status = InvoicesStatus.initial});
  final InvoicesStatus status;
}

class InvoicesLoaded extends InvoicesState {
  final InvoicesStatus previous;
  const InvoicesLoaded(this.previous);
}
''',
        ['status', 'previous'],
        message: ['sealed state'],
        after: 'final InvoicesStatus',
      );

  Future<void> test_other_enums_and_non_state_classes_are_clean() => expectIn(
        'bloc/invoices/invoices_state.dart',
        '''
enum InvoicesStatus { initial }
enum Period { month, year }

class InvoicesState {
  const InvoicesState(this.period);
  final Period period;
}

class InvoicesFilter {
  const InvoicesFilter(this.status);
  final InvoicesStatus status;
}
''',
        [],
      );

  Future<void> test_states_outside_bloc_folder_are_not_checked() => expectIn(
        'pages/x_page.dart',
        'enum XStatus { a }\nclass XState {\n  const XState(this.status);\n  final XStatus status;\n}\n',
        [],
      );
}

@reflectiveTest
class NoStateEnumBranchingTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => NoStateEnumBranching();

  @override
  void setUp() {
    super.setUp();
    newFile('$testPackageLibPath/bloc/promo/promo_state.dart', '''
enum PromoTab { pending, done }
enum Shade { light, dark }
class PromoState {
  final PromoTab tab;
  final int count;
  const PromoState(this.tab, this.count);
}
''');
  }

  static const _source = '''
import 'package:test/bloc/promo/promo_state.dart';
class Style {
  final Shade shade;
  const Style(this.shade);
}
String f(PromoState state, Style style) {
  if (state.tab == PromoTab.done) return 'done';
  if (style.shade == Shade.dark) return 'dark';
  if (state.count == 1) return 'one';
  return switch (state.tab) {
    PromoTab.pending => 'pending',
    PromoTab.done => 'done',
  };
}
bool changed(PromoState a, PromoState b) => a.tab != b.tab;
bool selected(PromoTab tab, PromoState state) => tab == state.tab;
''';

  Future<void> test_branching_on_a_state_enum_in_ui_is_flagged() => expectIn(
        'pages/promo_page.dart',
        _source,
        ['state.tab', 'state.tab'],
        message: ['PromoState.tab', 'sealed state'],
      );

  Future<void> test_cubits_may_read_their_own_enums() => expectIn('bloc/promo/promo_cubit.dart', _source, []);
}
