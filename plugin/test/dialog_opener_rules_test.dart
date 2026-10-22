import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/dialog_only_in_listener.dart';
import 'package:neon_lints/src/dialog_opener_returns_void.dart';
import 'package:neon_lints/src/no_unawaited_dialog_opener.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/bloc_rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(DialogOpenerReturnsVoidTest);
    defineReflectiveTests(NoUnawaitedDialogOpenerTest);
    defineReflectiveTests(VoidHelperInListenerTest);
  });
}

const _imports = '''
import 'dart:async';

import 'package:bloc_presentation/bloc_presentation.dart';
import 'package:flutter/widgets.dart';
import 'package:test/bloc/global/base/base_cubit.dart';
import 'package:test/utils/utils.dart';

class CounterCubit extends BaseCubit<int> {
  CounterCubit() : super(0);
  Future<void> load() async {}
}

class ShowEditor {}
''';

@reflectiveTest
class DialogOpenerReturnsVoidTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => DialogOpenerReturnsVoid();

  Future<void> test_future_openers_are_flagged() => expectIn(
        'pages/x_page.dart',
        '''
${_imports}class EditorSheet {
  static Future<bool?> show(BuildContext context) => Utils.showCustomModalBottomSheet<bool>(context: context);
}

Future<void> showEditor(BuildContext context, ShowEditor event) {
  return Utils.showCustomModalBottomSheet<void>(context: context);
}

Future<void> _showStep(BuildContext context) async {
  await Utils.showCustomModalBottomSheet<void>(context: context);
}

Future<void> showStepFor(BuildContext context) => _showStep(context);
''',
        ['show', 'showEditor', '_showStep', 'showStepFor'],
        message: ['returns void'],
        after: 'class ShowEditor {}',
      );

  Future<void> test_void_openers_and_non_openers_are_clean() => expectIn(
        'features/x/x.dart',
        '''
${_imports}void showEditor(BuildContext context, ShowEditor event) {
  Utils.openModalBottomSheet(context: context);
}

void showOther(BuildContext context) => unawaited(Utils.showCustomModalBottomSheet<void>(context: context));

Future<void> showLater(CounterCubit cubit) => cubit.load();

Future<void> openEditor(BuildContext context) => Utils.showCustomModalBottomSheet<void>(context: context);

class EditorSheet {
  static void show(BuildContext context) => Utils.openModalBottomSheet(context: context);
  Future<void> showInstance(BuildContext context) => Utils.showCustomModalBottomSheet<void>(context: context);
}

Future<void> _showNotification(String message) async {}

Future<void> showBackgroundNotification(String message) => _showNotification(message);
''',
        [],
      );

  Future<void> test_the_dialog_helper_is_the_owner() => expectIn(
        'utils/utils.dart',
        '''
import 'package:flutter/widgets.dart';

class Utils {
  static Future<T?> showCustomModalBottomSheet<T>({required BuildContext context}) async => null;
  static Future<void> showWrapped(BuildContext context) => showCustomModalBottomSheet<void>(context: context);
}
''',
        [],
      );
}

@reflectiveTest
class NoUnawaitedDialogOpenerTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => NoUnawaitedDialogOpener();

  static const _openers = '''
Future<void> showEditor(BuildContext context, ShowEditor event) =>
    Utils.showCustomModalBottomSheet<void>(context: context);

class EditorSheet {
  static Future<void> show(BuildContext context) => Utils.showCustomModalBottomSheet<void>(context: context);
}
''';

  Future<void> test_wrapped_openers_are_flagged() => expectIn(
        'pages/x_page.dart',
        '''
$_imports${_openers}Widget page() => BlocPresentationListener<CounterCubit, Object>(
  listener: (context, event) {
    if (event is ShowEditor) return unawaited(showEditor(context, event));
    unawaited((EditorSheet.show(context)));
    unawaited(Utils.showCustomModalBottomSheet<void>(context: context));
  },
);
''',
        ['showEditor', 'show', 'showCustomModalBottomSheet'],
        message: ['wraps a dialog opener'],
        after: 'Widget page()',
      );

  Future<void> test_in_the_routing_files_too() => expectIn(
        'flavors/vernak/vernak_router.dart',
        '$_imports${_openers}void f(BuildContext context) => unawaited(EditorSheet.show(context));\n',
        ['show'],
        after: 'void f(',
      );

  Future<void> test_background_work_and_direct_calls_are_clean() => expectIn(
        'features/x/x.dart',
        '''
$_imports${_openers}void showVoid(BuildContext context) => unawaited(Utils.showCustomModalBottomSheet<void>(context: context));

void f(BuildContext context, CounterCubit cubit) {
  unawaited(cubit.load());
  showVoid(context);
  showEditor(context, ShowEditor());
}
''',
        [],
      );

  Future<void> test_cubits_and_the_helper_are_out_of_scope() async {
    await expectIn(
      'bloc/x/x_cubit.dart',
      '$_imports${_openers}void f(BuildContext context) => unawaited(showEditor(context, ShowEditor()));\n',
      [],
    );
    await expectIn(
      'utils/utils.dart',
      '''
import 'dart:async';

import 'package:flutter/widgets.dart';

class Utils {
  static Future<T?> showCustomModalBottomSheet<T>({required BuildContext context}) async => null;
  static void openModalBottomSheet({required BuildContext context}) =>
      unawaited(showCustomModalBottomSheet<void>(context: context));
}
''',
      [],
    );
  }
}

/// `dialog_only_in_listener` treats the void entry point as the dialog helper.
@reflectiveTest
class VoidHelperInListenerTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => DialogOnlyInListener();

  Future<void> test_void_helper_outside_an_opener_is_flagged() => expectIn(
        'pages/x_page.dart',
        '''
${_imports}void onTap(BuildContext context) {
  Utils.openModalBottomSheet(context: context);
}

void showEditor(BuildContext context) => Utils.openModalBottomSheet(context: context);
''',
        ['openModalBottomSheet'],
        after: 'void onTap',
      );
}
