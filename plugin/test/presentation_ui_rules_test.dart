import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/dialog_only_in_listener.dart';
import 'package:neon_lints/src/listener_is_mapping.dart';
import 'package:neon_lints/src/no_dialog_result.dart';
import 'package:neon_lints/src/no_navigation_in_ui.dart';
import 'package:neon_lints/src/page_state_rules.dart';
import 'package:neon_lints/src/ui_callback_calls_cubit.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/bloc_rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(DialogOnlyInListenerTest);
    defineReflectiveTests(NoDialogResultTest);
    defineReflectiveTests(ListenerIsMappingTest);
    defineReflectiveTests(NoNavigationInUiTest);
    defineReflectiveTests(UiCallbackCallsCubitTest);
    defineReflectiveTests(NoSetStateInPagesTest);
    defineReflectiveTests(NoPrivateMethodsInPageStateTest);
    defineReflectiveTests(StatefulPageOnlyForControllersTest);
    defineReflectiveTests(NoEditorControllerInPagesTest);
  });
}

const _imports = '''
import 'dart:async';

import 'package:bloc_presentation/bloc_presentation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:test/bloc/global/alert/alert_cubit.dart';
import 'package:test/bloc/global/base/base_cubit.dart';
import 'package:test/utils/utils.dart';

class CounterCubit extends BaseCubit<int> {
  CounterCubit() : super(0);
  void save() {}
  Future<void> load() async {}
  void select(int item) {}
}

class ShowEditor {}
class CloseDialog {}

Future<void> showEditor(BuildContext context, ShowEditor event) async {}
Future<bool> handleShared(BuildContext context, Object event) async => false;
''';

@reflectiveTest
class DialogOnlyInListenerTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => DialogOnlyInListener();

  Future<void> test_dialog_opened_from_ui_is_flagged() => expectIn(
        'pages/x_page.dart',
        '${_imports}void onTap(BuildContext context) {\n  Utils.showCustomModalBottomSheet<void>(context: context);\n}\n',
        ['showCustomModalBottomSheet'],
        message: ['BlocPresentationListener(listener:)'],
        after: 'void onTap',
      );

  Future<void> test_listener_and_show_functions_may_open_it() => expectIn(
        'pages/x_page.dart',
        '''
${_imports}Widget page() => BlocPresentationListener<CounterCubit, Object>(
  listener: (context, event) {
    Utils.showCustomModalBottomSheet<void>(context: context);
  },
);

Future<void> showConfirm(BuildContext context) => Utils.showCustomModalBottomSheet<void>(context: context);

class EditorDialog {
  static Future<void> show(BuildContext context) => Utils.showCustomModalBottomSheet<void>(context: context);
}
''',
        [],
      );

  Future<void> test_the_helper_itself_is_the_owner() => expectIn(
        'utils/utils.dart',
        '''
import 'package:flutter/widgets.dart';

class Utils {
  static Future<T?> showCustomModalBottomSheet<T>({required BuildContext context, Object? builder}) async => null;
  static Future<void> other(BuildContext context) => showCustomModalBottomSheet<void>(context: context);
}
''',
        [],
      );
}

@reflectiveTest
class NoDialogResultTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => NoDialogResult();

  Future<void> test_used_results_are_flagged() => expectIn(
        'pages/x_page.dart',
        '''
${_imports}Future<bool> showConfirm(BuildContext context) async => true;

Future<void> f(BuildContext context, CounterCubit cubit) async {
  final confirmed = await showConfirm(context);
  if (await showConfirm(context)) cubit.save();
  await Utils.showCustomModalBottomSheet<void>(context: context);
  cubit.save();
  showConfirm(context).then((_) {});
}
''',
        ['showConfirm', 'showConfirm', 'showCustomModalBottomSheet', 'showConfirm'],
        message: ['a dialog returns nothing'],
        after: 'Future<void> f(',
      );

  Future<void> test_unused_results_are_clean() => expectIn(
        'pages/x_page.dart',
        '''
${_imports}Future<bool> showConfirm(BuildContext context) async => true;

Future<void> f(BuildContext context) async {
  showConfirm(context);
  await Utils.showCustomModalBottomSheet<void>(context: context);
  return;
}

Future<bool> g(BuildContext context) => showConfirm(context);
Future<bool> h(BuildContext context) {
  return showConfirm(context);
}
void showLabel() {}
void k() => showLabel();

class Notifications {
  Future<void> show(int id, String title) async {}
}

Future<void> notify(Notifications notifications, CounterCubit cubit) async {
  await notifications.show(1, 'title');
  cubit.save();
}
''',
        [],
      );

  Future<void> test_dialog_helper_is_the_owner() => expectIn(
        'utils/utils.dart',
        '''
import 'package:flutter/widgets.dart';

class Utils {
  static Future<T?> showCustomModalBottomSheet<T>({required BuildContext context}) async => null;
  static Future<bool> confirm(BuildContext context) async {
    final result = await showCustomModalBottomSheet<bool>(context: context);
    return result ?? false;
  }
}
''',
        [],
      );
}

@reflectiveTest
class ListenerIsMappingTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => ListenerIsMapping();

  Future<void> test_logic_in_the_listener_is_flagged() => expectIn(
        'pages/x_page.dart',
        '''
${_imports}Widget page() => BlocPresentationListener<CounterCubit, Object>(
  listener: (context, event) async {
    if (event is ShowEditor) {
      final cubit = context.read<CounterCubit>();
      await showEditor(context, event);
      return;
    }
    if (context.canPop()) return;
    if (!context.mounted) handleShared(context, event);
    if (event is CloseDialog) {
      showEditor(context, ShowEditor());
      handleShared(context, event);
    }
    context.read<AlertCubit>().showSuccess('x');
  },
);
''',
        [
          "final cubit = context.read<CounterCubit>();",
          'await showEditor(context, event)',
          'context.canPop()',
          'handleShared(context, event);',
          'handleShared(context, event);',
          "context.read<AlertCubit>()",
        ],
        message: ['may only map `event is X` to one show call'],
        after: 'listener: (context, event)',
      );

  Future<void> test_pure_mapping_is_clean() => expectIn(
        'pages/x_page.dart',
        '''
${_imports}Widget page() => BlocPresentationListener<CounterCubit, Object>(
  listener: (context, event) async {
    if (event is ShowEditor) {
      showEditor(context, event);
      return;
    }
    if (event is CloseDialog) return context.pop();
    if (await handleShared(context, event)) return;
    if (!context.mounted) return;
    switch (event) {
      case ShowEditor():
        showEditor(context, event);
      default:
        break;
    }
    if (context.mounted) handleShared(context, event);
  },
);

Widget other() => BlocPresentationListener<CounterCubit, Object>(listener: (context, event) => handleShared(context, event));

void notAListener(BuildContext context) {
  final cubit = context.read<CounterCubit>();
}
''',
        [],
      );
}

@reflectiveTest
class NoNavigationInUiTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => NoNavigationInUi();

  static const _source = '''
${_imports}void f(BuildContext context) {
  context.go('/a');
  context.push('/b');
  context.pop(true);
}
''';

  Future<void> test_navigation_in_ui_folders_is_flagged() async {
    for (final folder in ['pages', 'features', 'global_widgets']) {
      await expectIn(
        '$folder/x.dart',
        _source,
        ["context.go('/a')", "context.push('/b')", 'context.pop(true)'],
        message: ['emits NavigateTo'],
        after: 'void f(',
      );
    }
  }

  Future<void> test_a_kit_dialog_closes_itself_before_its_callback() async {
    const source = '''
${_imports}void confirm(BuildContext context, void Function(int) onPicked) {
  context.pop();
  onPicked(1);
}
''';
    await expectIn('global_widgets/global/x_picker.dart', source, []);
    await expectIn('pages/x_dialog.dart', source, ['context.pop()'],
        message: ['emits NavigateTo'], after: 'void confirm(');
  }

  Future<void> test_pure_cancel_and_close_dialog_are_allowed() => expectIn(
        'pages/x_dialog.dart',
        '''
${_imports}class Button {
  const Button({this.onCancel});
  final void Function()? onCancel;
}

Object cancel(BuildContext context) => Button(onCancel: () => context.pop());
Object cancelBlock(BuildContext context) => Button(onCancel: () {
  context.pop();
});

Widget page() => BlocPresentationListener<CounterCubit, Object>(
  listener: (context, event) {
    if (event is CloseDialog) context.pop();
  },
);
''',
        [],
      );

  Future<void> test_presentation_handler_and_router_own_navigation() async {
    await expectIn('utils/ui/presentation_event_handler.dart', _source, []);
    await expectIn('flavors/vernak/vernak_router.dart', _source, []);
  }
}

@reflectiveTest
class UiCallbackCallsCubitTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => UiCallbackCallsCubit();

  static const _button = '''
class Button {
  const Button({this.onTap, this.onSelect, this.onSave});
  final void Function()? onTap;
  final void Function(int item)? onSelect;
  final Future<void> Function()? onSave;
}

class Row {
  const Row({required this.onPick, this.onClear});
  final void Function(int item) onPick;
  final void Function()? onClear;
  Object build(CounterCubit cubit, BuildContext context) => [
    Button(onTap: cubit.save),
    Button(onTap: () => cubit.select(1)),
    Button(onSelect: onPick),
    Button(onTap: () => onPick(2)),
    Button(onTap: () => onClear?.call()),
    Button(onTap: () { cubit.save(); }),
    Button(onTap: () => context.pop()),
    Button(onTap: () => unawaited(cubit.load())),
    Button(onTap: null),
    Mark(onAccent: 0xFFFFFFFF),
  ];
}

class Mark {
  const Mark({required this.onAccent});
  final int onAccent;
}
''';

  Future<void> test_allowed_callbacks_are_clean() => expectIn('pages/x_page.dart', '$_imports$_button', []);

  Future<void> test_logic_in_callbacks_is_flagged() => expectIn(
        'pages/x_page.dart',
        '''
$_imports$_button
Object bad(CounterCubit cubit, bool flag) => [
  Button(onTap: () { if (flag) cubit.save(); }),
  Button(onTap: () { cubit.save(); cubit.save(); }),
  Button(onSave: () async => cubit.save()),
  Button(onTap: () => print('x')),
  Button(onTap: flag ? cubit.save : null),
];
''',
        [
          'onTap: () { if (flag) cubit.save(); }',
          'onTap: () { cubit.save(); cubit.save(); }',
          'onSave: () async => cubit.save()',
          "onTap: () => print('x')",
          'onTap: flag ? cubit.save : null',
        ],
        message: ['Move the logic into the cubit'],
        after: 'Object bad(',
      );

  Future<void> test_global_widgets_are_not_pages() => expectIn(
        'global_widgets/global/x.dart',
        '$_imports$_button\nObject ok(bool flag, CounterCubit cubit) => Button(onTap: () { if (flag) cubit.save(); });\n',
        [],
      );
}

@reflectiveTest
class NoSetStateInPagesTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => NoSetStateInPages();

  static const _source = '''
${_imports}class Page extends StatefulWidget {
  const Page();
}

class _PageState extends State<Page> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    setState(() => _selected = 1);
    return Widget();
  }
}
''';

  Future<void> test_setstate_in_pages_and_features_is_flagged() async {
    await expectIn('pages/x_page.dart', _source, ['setState'], message: ['keep selection'], after: 'build(');
    await expectIn('features/vernak/x.dart', _source, ['setState'], after: 'build(');
  }

  Future<void> test_global_widgets_keep_local_ui_state() => expectIn('global_widgets/global/x.dart', _source, []);
}

@reflectiveTest
class NoPrivateMethodsInPageStateTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => NoPrivateMethodsInPageState();

  static const _source = '''
${_imports}class Page extends StatefulWidget {
  const Page();
}

class _PageState extends State<Page> {
  @override
  void initState() {}

  @override
  void dispose() {}

  void didChangeAppLifecycleState(Object state) {}

  @override
  Widget build(BuildContext context) => Widget();

  void _save() {}

  int get _count => 0;

  static int helper() => 0;
}
''';

  Future<void> test_non_lifecycle_methods_are_flagged() => expectIn('pages/x_page.dart', _source, ['_save', '_count'],
      message: ['only lifecycle methods'], after: 'Widget();');

  Future<void> test_states_outside_pages_are_not_checked() => expectIn('global_widgets/global/x.dart', _source, []);

  Future<void> test_feature_states_are_checked_too() => expectIn(
      'features/vernak/flow/flow.dart', _source, ['_save', '_count'],
      message: ['page or feature State'], after: 'Widget();');
}

@reflectiveTest
class StatefulPageOnlyForControllersTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => StatefulPageOnlyForControllers();

  Future<void> test_state_holding_data_or_nothing_is_flagged() => expectIn(
        'pages/x_page.dart',
        '''
${_imports}class TextEditingController {}

class Page extends StatefulWidget {
  const Page();
}

class _PageState extends State<Page> {
  final _search = TextEditingController();
  int _selected = 0;

  @override
  Widget build(BuildContext context) => Widget();
}

class Empty extends StatefulWidget {
  const Empty();
}

class _EmptyState extends State<Empty> {
  @override
  Widget build(BuildContext context) => Widget();
}
''',
        ['_PageState', '_EmptyState'],
        message: ['only owns controllers'],
        after: 'const Page();',
      );

  Future<void> test_feature_state_holding_data_is_flagged() => expectIn(
        'features/vernak/flow/flow.dart',
        '''
${_imports}class Flow extends StatefulWidget {
  const Flow();
}

class _FlowState extends State<Flow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => Widget();
}
''',
        ['_FlowState'],
        message: ['holds _expanded'],
        after: 'const Flow();',
      );

  Future<void> test_states_in_the_kit_are_not_checked() => expectIn(
        'global_widgets/global/components/flow/flow.dart',
        '''
${_imports}class Flow extends StatefulWidget {
  const Flow();
}

class _FlowState extends State<Flow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => Widget();
}
''',
        [],
      );

  Future<void> test_state_owning_only_controllers_is_clean() => expectIn(
        'pages/x_page.dart',
        '''
${_imports}class TextEditingController {}
class FocusNode {}
class TapGestureRecognizer {}

class Page extends StatefulWidget {
  const Page();
}

class _PageState extends State<Page> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  final _link = TapGestureRecognizer();

  @override
  Widget build(BuildContext context) => Widget();
}
''',
        [],
      );
}

@reflectiveTest
class NoEditorControllerInPagesTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => NoEditorControllerInPages();

  static const _source = '''
${_imports}class LoyaltyEditorController {
  bool validate() => true;
}

class Dialog {
  final controller = LoyaltyEditorController();
  bool save() => controller.validate();
}
''';

  Future<void> test_editor_controller_in_pages_is_flagged() => expectIn(
        'pages/x_dialog.dart',
        _source,
        ['LoyaltyEditorController', 'controller.validate()'],
        message: ['onSubmit(data)'],
        after: 'class Dialog',
      );

  Future<void> test_editors_own_their_controller() =>
      expectIn('global_widgets/vernak/loyalty_card_editor.dart', _source, []);
}
