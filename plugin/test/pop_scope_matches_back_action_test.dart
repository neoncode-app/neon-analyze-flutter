import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/pop_scope_matches_back_action.dart';
import 'package:neon_lints/src/support/rule_layout.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/bloc_rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(PopScopeMatchesBackActionTest);
    defineReflectiveTests(PopScopeWithoutConfigTest);
  });
}

const _imports = '''
import 'package:flutter/widgets.dart';

class SubmitBar extends Widget {
  const SubmitBar({Object? onTap});
}

class ProfileCubit {
  Future<void> save() async {}
}

ProfileCubit cubit = ProfileCubit();
''';

@reflectiveTest
class PopScopeMatchesBackActionTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => PopScopeMatchesBackAction();

  @override
  void setUp() {
    RuleLayout.clearCache();
    super.setUp();
    newFile('$testPackageRootPath/neon_check.yaml', 'preset: app\nback_actions: {SubmitBar: onTap}\n');
  }

  Future<void> test_a_bar_without_pop_scope_is_reported() => expectIn(
        'pages/profile/profile_page.dart',
        '${_imports}Widget f() => SubmitBar(onTap: cubit.save);',
        ['SubmitBar'],
        message: ['`SubmitBar.onTap` runs `cubit.save`'],
        after: 'Widget f()',
      );

  Future<void> test_a_pop_scope_running_another_action_is_reported() => expectIn(
        'pages/profile/profile_page.dart',
        '${_imports}Widget f() => PopScope(canPop: false, onPopInvokedWithResult: (didPop, _) { if (!didPop) other(); }, '
            'child: SubmitBar(onTap: () => cubit.save()));\nvoid other() {}',
        ['SubmitBar'],
        after: 'child:',
      );

  Future<void> test_a_pop_scope_running_the_same_action_is_clean() async {
    final path = '$testPackageLibPath/pages/profile/profile_page.dart';
    newFile(
      path,
      '${_imports}Widget f() => PopScope(canPop: false, onPopInvokedWithResult: (didPop, _) { '
      'if (didPop) return; cubit.save(); }, child: SubmitBar(onTap: cubit.save));',
    );
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_a_forwarded_callback_belongs_to_the_composing_page() async {
    final path = '$testPackageLibPath/pages/report/widgets/report_action_block.dart';
    newFile(path, '''
$_imports
class ReportActionBlock extends StatelessWidget {
  const ReportActionBlock({required this.onBack});
  final Object onBack;
  @override
  Widget build(BuildContext context) => SubmitBar(onTap: onBack);
}
''');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_the_kit_is_not_checked() async {
    final path = '$testPackageLibPath/global_widgets/submit_bar_row.dart';
    newFile(path, '${_imports}Widget f() => SubmitBar(onTap: cubit.save);');
    await assertNoDiagnosticsInFile(path);
  }
}

@reflectiveTest
class PopScopeWithoutConfigTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => PopScopeMatchesBackAction();

  @override
  void setUp() {
    RuleLayout.clearCache();
    super.setUp();
  }

  Future<void> test_without_back_actions_nothing_is_checked() async {
    final path = '$testPackageLibPath/pages/profile/profile_page.dart';
    newFile(path, '${_imports}Widget f() => SubmitBar(onTap: cubit.save);');
    await assertNoDiagnosticsInFile(path);
  }
}
