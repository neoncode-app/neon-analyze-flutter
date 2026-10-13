import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/error/error.dart';
// The diagnostic codes are not exported from a public library.
// ignore: implementation_imports
import 'package:analyzer/src/diagnostic/diagnostic.dart' as diag;
import 'package:neon_lints/src/layering_rules.dart';
import 'package:neon_lints/src/page_template_rules.dart';
import 'package:neon_lints/src/responsive_rules.dart';
import 'package:neon_lints/src/role_rules.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/bloc_rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(PageUsesTemplateTest);
    defineReflectiveTests(PageHasTitleSubtitleTest);
    defineReflectiveTests(GlobalWidgetsLayeringTest);
    defineReflectiveTests(ComponentHasNoStateAccessTest);
    defineReflectiveTests(NoRepositoryInUiTest);
    defineReflectiveTests(NoHttpInUiTest);
    defineReflectiveTests(GlobalWidgetHasCategoryTest);
    defineReflectiveTests(KitSrcInternalTest);
    defineReflectiveTests(NoRoleLiteralTest);
    defineReflectiveTests(NoAccessGuardInPagesTest);
    defineReflectiveTests(NoMediaQuerySizeTest);
    defineReflectiveTests(NoKIsWebInUiTest);
    defineReflectiveTests(NoPlatformInUiTest);
    defineReflectiveTests(NoLayoutBuilderInPagesTest);
    defineReflectiveTests(NoRawBreakpointTest);
  });
}

const _flutter = "import 'package:flutter/widgets.dart';\n";

/// App kit stubs: a template, a layout, RoleGuard, a repository.
abstract class _StructureTest extends BlocRuleTest {
  @override
  void setUp() {
    newFile('$testPackageLibPath/global_widgets/global/app_content_page.dart', '''
${_flutter}
/// The content page.
///
/// {@category Template}
class AppContentPage extends StatelessWidget {
  const AppContentPage({this.title, this.subtitle, this.child});
  final String? title;
  final String? subtitle;
  final Widget? child;
  @override
  Widget build(BuildContext context) => Widget();
}

/// Two panels.
///
/// {@category Layout}
class TwoPanelLayout extends StatelessWidget {
  const TwoPanelLayout();
  @override
  Widget build(BuildContext context) => Widget();
}

/// Role check.
///
/// {@category Behavior}
class RoleGuard extends StatelessWidget {
  const RoleGuard();
  @override
  Widget build(BuildContext context) => Widget();
}
''');
    newFile('$testPackageLibPath/repository/neo_api_repository.dart', 'class NeoApiRepository {}\n');
    newFile('$testPackageLibPath/pages/vernak/vernak_cards_page.dart', 'class CardsPageMarker {}\n');
    newFile('$testPackageLibPath/features/vernak/vernak_shell.dart', 'class ShellMarker {}\n');
    newFile('$testPackageLibPath/global_widgets/global/stats/src/app_chart_axis.dart', 'class AppChartAxis {}\n');
    newFile('$testPackageLibPath/model/enum/app_role.dart',
        "enum AppRole { vernakAdmin('vernak-admin'); const AppRole(this.value); final String value; }\n");
    newPackage('dio').addFile('lib/dio.dart', 'class Dio {}\n');
    super.setUp();
  }
}

const _imports = '''
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:test/bloc/global/base/base_cubit.dart';
import 'package:test/global_widgets/global/app_content_page.dart';

class CounterCubit extends BaseCubit<int> {
  CounterCubit() : super(0);
}
''';

@reflectiveTest
class PageUsesTemplateTest extends _StructureTest {
  @override
  AnalysisRule get ruleUnderTest => PageUsesTemplate();

  Future<void> test_page_without_template_is_flagged() => expectIn(
        'pages/x_page.dart',
        '''
${_imports}class XPage extends StatelessWidget {
  const XPage();
  @override
  Widget build(BuildContext context) => BlocBuilder<CounterCubit, int>(
    builder: (context, state) => state > 0 ? const AppContentPage() : const TwoPanelLayout(),
  );
}

class YPage extends StatelessWidget {
  const YPage();
  @override
  Widget build(BuildContext context) {
    return content();
  }
}

Widget content() => Widget();
''',
        ['TwoPanelLayout', 'content()'],
        message: ['{@category Template}'],
        after: 'class XPage',
      );

  Future<void> test_template_through_wrappers_is_clean() => expectIn(
        'pages/x_page.dart',
        '''
${_imports}class XPage extends StatelessWidget {
  const XPage();
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => CounterCubit(),
    child: BlocBuilder<CounterCubit, int>(
      builder: (context, state) {
        if (state > 0) return const AppContentPage(title: 'a');
        return const AppContentPage(title: 'b');
      },
    ),
  );
}

class XPanel extends StatelessWidget {
  const XPanel();
  @override
  Widget build(BuildContext context) => const TwoPanelLayout();
}
''',
        [],
      );

  Future<void> test_widgets_outside_pages_are_not_pages() => expectIn(
        'global_widgets/global/x_page.dart',
        '${_imports}class XPage extends StatelessWidget {\n  const XPage();\n  @override\n'
            '  Widget build(BuildContext context) => const TwoPanelLayout();\n}\n',
        [],
      );
}

@reflectiveTest
class PageHasTitleSubtitleTest extends _StructureTest {
  @override
  AnalysisRule get ruleUnderTest => PageHasTitleSubtitle();

  Future<void> test_missing_title_or_subtitle_is_flagged() => expectIn(
        'pages/x_page.dart',
        "${_imports}Object a() => const AppContentPage(title: 'x');\nObject b() => const AppContentPage(subtitle: null);\n",
        ['AppContentPage', 'AppContentPage'],
        message: ['passes title: and subtitle:'],
        after: 'Object a()',
      );

  Future<void> test_both_given_is_clean() =>
      expectIn('pages/x_page.dart', "${_imports}Object a() => const AppContentPage(title: 'x', subtitle: 'y');\n", []);

  Future<void> test_pages_outside_subtitled_pages_and_catalog_previews_are_not_checked() async {
    newFile('$testPackageRootPath/neon_check.yaml', 'layout:\n  subtitled_pages: lib/pages/neoncode/\n');
    const source = "${_imports}Object a() => const AppContentPage(title: 'x');\n";
    await expectIn('pages/vernak/x_page.dart', source, []);
    await expectIn('pages/neoncode/widgets/widget_catalog/previews/previews_x.dart', source, []);
    await expectIn('pages/neoncode/x_page.dart', source, ['AppContentPage'], after: 'Object a()');
  }
}

@reflectiveTest
class GlobalWidgetsLayeringTest extends _StructureTest {
  @override
  AnalysisRule get ruleUnderTest => GlobalWidgetsLayering();

  static const _source =
      "import 'package:test/pages/vernak/vernak_cards_page.dart';\nimport '../../features/vernak/vernak_shell.dart';\n";

  Future<void> test_global_widget_importing_pages_is_flagged() => expectIn(
        'global_widgets/global/x.dart',
        _source,
        ["'package:test/pages/vernak/vernak_cards_page.dart'", "'../../features/vernak/vernak_shell.dart'"],
        message: ['must not depend on pages/'],
      );

  Future<void> test_pages_may_import_pages() => expectIn('pages/neoncode/x.dart', _source.split('\n').first, []);
}

@reflectiveTest
class ComponentHasNoStateAccessTest extends _StructureTest {
  @override
  AnalysisRule get ruleUnderTest => ComponentHasNoStateAccess();

  static String _widget(String category) => '''
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:test/bloc/global/base/base_cubit.dart';

/// A widget.
///
/// {@category $category}
class XWidget extends StatelessWidget {
  const XWidget();
  @override
  Widget build(BuildContext context) {
    context.read<BaseCubit<int>>();
    return Widget();
  }
}
''';

  Future<void> test_component_reading_state_is_flagged() => expectIn(
        'global_widgets/global/x.dart',
        _widget('Component'),
        [
          "'package:flutter_bloc/flutter_bloc.dart'",
          "'package:test/bloc/global/base/base_cubit.dart'",
          'context.read<BaseCubit<int>>()'
        ],
        message: ['draw from parameters and the theme only'],
      );

  Future<void> test_feature_and_behavior_may_read_state() async {
    await expectIn('features/vernak/x.dart', _widget('Feature'), []);
    await expectIn('global_widgets/global/role_guard.dart', _widget('Behavior'), []);
  }
}

@reflectiveTest
class NoRepositoryInUiTest extends _StructureTest {
  @override
  AnalysisRule get ruleUnderTest => NoRepositoryInUi();

  static const _source =
      "import 'package:test/repository/neo_api_repository.dart';\nvoid f(NeoApiRepository repo) {}\n";

  Future<void> test_repository_in_ui_is_flagged() => expectIn('pages/x_page.dart', _source, ['NeoApiRepository'],
      message: ['Inject the repository'], after: 'void f(');

  Future<void> test_cubits_own_repositories() => expectIn('bloc/x/x_cubit.dart', _source, []);

  Future<void> test_repository_through_a_getter_is_flagged() => expectIn(
        'pages/x_page.dart',
        "import 'package:test/repository/neo_api_repository.dart';\n"
            'class Holder {\n  Object get api => throw 0;\n  NeoApiRepository get neoApi => throw 0;\n}\n'
            'void f(Holder holder) {\n  g(holder.neoApi);\n  g(holder.api);\n}\nvoid g(Object value) {}\n',
        ['NeoApiRepository', 'holder.neoApi'],
      );
}

@reflectiveTest
class NoHttpInUiTest extends _StructureTest {
  @override
  AnalysisRule get ruleUnderTest => NoHttpInUi();

  static const _source = "import 'package:dio/dio.dart';\nDio? client;\n";

  Future<void> test_http_in_ui_is_flagged() =>
      expectIn('global_widgets/global/x.dart', _source, ["'package:dio/dio.dart'"], message: ['API layer']);

  Future<void> test_api_layer_owns_http() => expectIn('model/request_models/x_request.dart', _source, []);
}

@reflectiveTest
class GlobalWidgetHasCategoryTest extends _StructureTest {
  @override
  AnalysisRule get ruleUnderTest => GlobalWidgetHasCategory();

  static const _source = '''
${_flutter}
/// No tier.
class AppNoTier extends StatelessWidget {
  const AppNoTier();
  @override
  Widget build(BuildContext context) => Widget();
}

/// Wrong tier.
///
/// {@category Page}
class AppWrongTier extends StatelessWidget {
  const AppWrongTier();
  @override
  Widget build(BuildContext context) => Widget();
}

/// Good.
///
/// {@category Component}
class AppGood extends StatelessWidget {
  const AppGood();
  @override
  Widget build(BuildContext context) => Widget();
}

class _Private extends StatelessWidget {
  const _Private();
  @override
  Widget build(BuildContext context) => Widget();
}
''';

  Future<void> test_untiered_kit_widgets_are_flagged() =>
      expectIn('global_widgets/global/x.dart', _source, ['AppNoTier', 'AppWrongTier'],
          message: ['{@category X}'], after: '/// No tier.');

  Future<void> test_pages_and_src_parts_are_exempt() async {
    await expectIn('pages/x_page.dart', _source, []);
    await expectIn('global_widgets/global/stats/src/x.dart', _source, []);
  }
}

@reflectiveTest
class KitSrcInternalTest extends _StructureTest {
  @override
  AnalysisRule get ruleUnderTest => KitSrcInternal();

  static const _source = "import 'package:test/global_widgets/global/stats/src/app_chart_axis.dart';\n";

  Future<void> test_src_import_from_outside_the_kit_is_flagged() async {
    await expectIn(
        'pages/x_page.dart', _source, ["'package:test/global_widgets/global/stats/src/app_chart_axis.dart'"]);
    await expectIn('global_widgets/global/x.dart', _source,
        ["'package:test/global_widgets/global/stats/src/app_chart_axis.dart'"]);
  }

  Future<void> test_the_kit_imports_its_own_src() =>
      expectIn('global_widgets/global/stats/app_area_chart.dart', "import 'src/app_chart_axis.dart';\n", []);
}

@reflectiveTest
class NoRoleLiteralTest extends _StructureTest {
  @override
  AnalysisRule get ruleUnderTest => NoRoleLiteral();

  static const _source = "const roles = ['vernak-admin', 'root', 'admin'];\nconst other = ['user', 'editor'];\n";

  Future<void> test_role_strings_are_flagged() =>
      expectIn('pages/x_page.dart', _source, ["'vernak-admin'", "'root'", "'admin'"], message: ['use the role enums']);

  Future<void> test_role_enums_own_the_strings() => expectIn('model/enum/vernak_role.dart', _source, []);
}

@reflectiveTest
class NoAccessGuardInPagesTest extends _StructureTest {
  @override
  AnalysisRule get ruleUnderTest => NoAccessGuardInPages();

  static const _source = '''
${_flutter}import 'package:test/global_widgets/global/app_content_page.dart';

class AccessDeniedView extends StatelessWidget {
  const AccessDeniedView();
  @override
  Widget build(BuildContext context) => Widget();
}

Object a() => const RoleGuard();
Object b() => const AccessDeniedView();
''';

  Future<void> test_guards_in_pages_are_flagged() => expectIn(
        'pages/x_page.dart',
        _source,
        ['RoleGuard', 'AccessDeniedView'],
        message: ['declare the permission on the route'],
        after: 'Object a()',
      );

  Future<void> test_router_owns_guards() => expectIn('flavors/vernak/vernak_router.dart', _source, []);
}

@reflectiveTest
class NoMediaQuerySizeTest extends _StructureTest {
  @override
  AnalysisRule get ruleUnderTest => NoMediaQuerySize();

  static const _source = '''
${_flutter}void f(BuildContext context) {
  MediaQuery.sizeOf(context);
  MediaQuery.widthOf(context);
  MediaQuery.of(context).size;
  final data = MediaQuery.of(context);
  data.size;
}
''';

  Future<void> test_screen_size_reads_are_flagged() => expectIn(
        'pages/x_page.dart',
        _source,
        ['MediaQuery.sizeOf(context)', 'MediaQuery.widthOf(context)', 'MediaQuery.of(context).size', 'data.size'],
        message: ['app_responsive.dart'],
        after: 'void f(',
      );

  Future<void> test_app_responsive_owns_them() => expectIn('utils/ui/app_responsive.dart', _source, []);
}

@reflectiveTest
class NoKIsWebInUiTest extends _StructureTest {
  @override
  AnalysisRule get ruleUnderTest => NoKIsWebInUi();

  static const _source = '${_flutter}bool f() => kIsWeb;\n';

  Future<void> test_kisweb_in_ui_is_flagged() =>
      expectIn('global_widgets/global/x.dart', _source, ['kIsWeb'], message: ['by screen size'], after: 'bool f()');

  Future<void> test_services_may_use_it() => expectIn('utils/helpers/x_service.dart', _source, []);
}

@reflectiveTest
class NoPlatformInUiTest extends _StructureTest {
  @override
  AnalysisRule get ruleUnderTest => NoPlatformInUi();

  // The mock SDK marks Platform.isAndroid deprecated.
  @override
  List<DiagnosticCode> get ignoredDiagnosticCodes => [...super.ignoredDiagnosticCodes, diag.deprecatedMemberUse];

  static const _source = '''
import 'dart:io';
${_flutter}bool f() => Platform.isAndroid || defaultTargetPlatform == TargetPlatform.iOS;
''';

  Future<void> test_platform_in_ui_is_flagged() => expectIn(
        'pages/x_page.dart',
        _source,
        ['Platform.isAndroid', 'defaultTargetPlatform'],
        message: ['follows the screen size'],
        after: 'bool f()',
      );

  Future<void> test_services_may_use_it() => expectIn('utils/helpers/x_service.dart', _source, []);
}

@reflectiveTest
class NoLayoutBuilderInPagesTest extends _StructureTest {
  @override
  AnalysisRule get ruleUnderTest => NoLayoutBuilderInPages();

  static const _source = '${_flutter}Object f() => LayoutBuilder(builder: (context, constraints) => Widget());\n';

  Future<void> test_layout_builder_in_pages_is_flagged() =>
      expectIn('pages/x_page.dart', _source, ['LayoutBuilder'], message: ['ResponsiveBuilder'], after: 'Object f()');

  Future<void> test_global_widgets_own_layout_builder() => expectIn('global_widgets/global/x.dart', _source, []);
}

@reflectiveTest
class NoRawBreakpointTest extends _StructureTest {
  @override
  AnalysisRule get ruleUnderTest => NoRawBreakpoint();

  static const _source = '''
${_flutter}bool f(BoxConstraints constraints, Size size, double maxWidth, int count) =>
    constraints.maxWidth > 600 || size.width <= 900.0 || 1240 < maxWidth || count > 3 || maxWidth > 0;
''';

  Future<void> test_width_compared_with_a_number_is_flagged() => expectIn(
        'global_widgets/global/x.dart',
        _source,
        ['constraints.maxWidth > 600', 'size.width <= 900.0', '1240 < maxWidth'],
        message: ['AppScreenSize'],
        after: '=>',
      );

  Future<void> test_app_responsive_owns_breakpoints() => expectIn('utils/ui/app_responsive.dart', _source, []);
}
