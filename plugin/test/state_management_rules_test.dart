import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/cubit_only_state.dart';
import 'package:neon_lints/src/no_value_notifier_state.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/bloc_rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(CubitOnlyStateTest);
    defineReflectiveTests(NoValueNotifierStateTest);
  });
}

const _imports = '''
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:test/bloc/global/base/base_cubit.dart';
''';

@reflectiveTest
class CubitOnlyStateTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => CubitOnlyState();

  @override
  void setUp() {
    newPackage('state_notifier').addFile('lib/state_notifier.dart', r'''
abstract class StateNotifier<T> {
  StateNotifier(T state);
}
''');
    for (final name in ['riverpod', 'flutter_riverpod', 'hooks_riverpod', 'get']) {
      newPackage(name).addFile('lib/$name.dart', 'class Marker$name {}\n');
    }
    super.setUp();
  }

  Future<void> test_bloc_change_notifier_and_state_notifier_are_flagged() => expectIn(
        'bloc/counter/counter_bloc.dart',
        '''
${_imports}import 'package:state_notifier/state_notifier.dart';

class CounterBloc extends Bloc<Object, int> {
  CounterBloc() : super(0);
}

mixin CounterMixin on Bloc<Object, int> {}

class CounterModel extends ChangeNotifier {}

class Mixed with ChangeNotifier {}

class CounterNotifier extends StateNotifier<int> {
  CounterNotifier() : super(0);
}

Object f() => ChangeNotifier();
''',
        [
          'Bloc<Object, int>',
          'Bloc<Object, int>',
          'ChangeNotifier',
          'ChangeNotifier',
          'StateNotifier<int>',
          'ChangeNotifier'
        ],
        message: ['not how this app manages state', 'BaseCubit'],
        after: 'class CounterBloc',
      );

  Future<void> test_provider_widgets_are_flagged() => expectIn(
        'flavors/vernak/vernak_router.dart',
        '''
${_imports}import 'package:provider/provider.dart';

class Model extends BaseCubit<int> {
  Model() : super(0);
}

Widget f(BuildContext context) => MultiProvider(providers: [
      Provider<int>(create: (_) => 1),
      ChangeNotifierProvider<ChangeNotifier>(create: (_) => throw 0),
    ], child: Consumer<int>(builder: (context, value, child) => const Widget()));

int g(BuildContext context) => Provider.of<int>(context);
''',
        [
          'MultiProvider',
          'Provider<int>',
          'ChangeNotifierProvider<ChangeNotifier>',
          'Consumer<int>',
          'Provider.of<int>(context)'
        ],
        message: ['package:provider'],
        after: 'Widget f(',
      );

  Future<void> test_riverpod_and_getx_imports_are_flagged() => expectIn(
        'pages/x_page/x_page.dart',
        '''
import 'package:riverpod/riverpod.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:get/get.dart';
''',
        [
          "import 'package:riverpod/riverpod.dart';",
          "import 'package:flutter_riverpod/flutter_riverpod.dart';",
          "import 'package:hooks_riverpod/hooks_riverpod.dart';",
          "import 'package:get/get.dart';",
        ],
      );

  Future<void> test_cubits_bloc_providers_and_controllers_are_clean() => expectIn(
        'bloc/counter/counter_cubit.dart',
        '''
$_imports
class CounterCubit extends BaseCubit<int> {
  CounterCubit() : super(0);
  void increment() => emit(state + 1);
}

class Plain extends Cubit<int> {
  Plain() : super(0);
}

Widget f(BuildContext context, ChangeNotifier listenable) {
  final controller = TextEditingController();
  context.read<CounterCubit>();
  return BlocProvider<CounterCubit>(create: (_) => CounterCubit(), child: BlocBuilder<CounterCubit, int>(
    builder: (context, state) => const Widget(),
  ));
}
''',
        [],
      );

  Future<void> test_the_kit_owns_controllers_extending_change_notifier() => expectIn(
        'global_widgets/global/app_hint/app_hint.dart',
        '''
${_imports}class HintController extends ChangeNotifier {}

Object f() => ChangeNotifier();
''',
        ['ChangeNotifier'],
        after: 'Object f()',
      );

  Future<void> test_a_layout_override_moves_the_kit() async {
    newFile('$testPackageRootPath/neon_check.yaml', 'layout:\n  global_widgets: [lib/kit/]\n');
    await expectIn('kit/app_hint/app_hint.dart', '${_imports}class HintController extends ChangeNotifier {}\n', []);
    await expectIn(
      'global_widgets/app_hint/app_hint.dart',
      '${_imports}class HintController extends ChangeNotifier {}\n',
      ['ChangeNotifier'],
      after: 'class HintController',
    );
  }
}

@reflectiveTest
class NoValueNotifierStateTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => NoValueNotifierState();

  Future<void> test_value_notifiers_outside_the_kit_are_flagged() => expectIn(
        'features/vernak/layout/layout.dart',
        '''
${_imports}class LayoutState {
  final ValueNotifier<bool> expanded = ValueNotifier<bool>(false);
  final open = ValueNotifier(0);
}

class Flag extends ValueNotifier<bool> {
  Flag() : super(false);
}
''',
        ['ValueNotifier<bool>', 'ValueNotifier', 'ValueNotifier<bool>'],
        message: ['cubit state'],
        after: '= ValueNotifier',
      );

  Future<void> test_in_cubits_too() => expectIn(
        'bloc/x/x_cubit.dart',
        '${_imports}final flag = ValueNotifier<int>(0);\n',
        ['ValueNotifier<int>'],
        after: 'final flag',
      );

  Future<void> test_reading_and_flutter_controllers_are_clean() => expectIn(
        'pages/x_page/x_page.dart',
        '''
${_imports}class XPageState {
  final controller = TextEditingController();
  ValueNotifier<int>? held;
}

Widget f(ValueListenable<int> box) => ValueListenableBuilder<int>(valueListenable: box);
''',
        [],
      );

  Future<void> test_the_kit_keeps_local_ui_state() => expectIn(
        'global_widgets/global/app_crop/app_crop.dart',
        '''
${_imports}class CropState {
  final ValueNotifier<double> scale = ValueNotifier<double>(1);
}

class Hover extends ValueNotifier<bool> {
  Hover() : super(false);
}
''',
        [],
      );
}
