import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/router_rules.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/bloc_rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(RouterOnlyRoutesTest);
    defineReflectiveTests(RouteUsesPageFactoryTest);
  });
}

/// The router rules with the app's page factory and a page (go_router is
/// stubbed by [BlocRuleTest]).
abstract class _RouterTest extends BlocRuleTest {
  @override
  void setUp() {
    super.setUp();
    newFile('$testPackageLibPath/flavors/vernak/vernak_page_factory/vernak_page_factory.dart', '''
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

Page<void> vernakPage(GoRouterState state, {required Widget page}) => NoTransitionPage(child: page);
''');
    newFile('$testPackageLibPath/pages/home_page.dart', '''
import 'package:flutter/widgets.dart';

class HomePage extends Widget {
  const HomePage();
}

void showHomeHelp(BuildContext context) {}
''');
  }
}

const _imports = "import 'package:flutter/widgets.dart';\n"
    "import 'package:go_router/go_router.dart';\n"
    "import 'package:test/flavors/vernak/vernak_page_factory/vernak_page_factory.dart';\n"
    "import 'package:test/pages/home_page.dart';\n\n";

const _router = 'flavors/vernak/vernak_router.dart';

@reflectiveTest
class RouterOnlyRoutesTest extends _RouterTest {
  @override
  AnalysisRule get ruleUnderTest => RouterOnlyRoutes();

  Future<void> test_routes_only_is_clean() => expectIn(
        _router,
        '''
${_imports}final routes = <RouteBase>[];

GoRouter buildVernakRouter() => GoRouter(
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => vernakPage(state, page: const HomePage()),
        ),
      ],
    );

final help = showHomeHelp;
''',
        [],
      );

  Future<void> test_classes_helpers_dialogs_and_tr_are_flagged() => expectIn(
        _router,
        '''
${_imports}Object tr(Object key) => key;

class _Shell extends Widget {
  const _Shell();
}

enum Tab { a }

GoRouter buildVernakRouter() => GoRouter(routes: []);

GoRouter buildOtherRouter() => GoRouter(routes: []);

void open(BuildContext context) {
  showHomeHelp(context);
  tr('title');
}
''',
        ['tr', '_Shell', 'Tab', 'buildOtherRouter', 'open', 'showHomeHelp', 'tr'],
      );

  Future<void> test_outside_a_router_is_clean() => expectIn(
        'flavors/vernak/vernak_shell/vernak_shell.dart',
        '''
${_imports}class VernakShell extends Widget {
  const VernakShell();
}

void open(BuildContext context) => showHomeHelp(context);
''',
        [],
      );
}

@reflectiveTest
class RouteUsesPageFactoryTest extends _RouterTest {
  @override
  AnalysisRule get ruleUnderTest => RouteUsesPageFactory();

  Future<void> test_factory_routes_and_shell_builder_are_clean() => expectIn(
        _router,
        '''
${_imports}GoRouter buildVernakRouter() => GoRouter(
      routes: [
        ShellRoute(
          builder: (context, state, child) => child,
          routes: [
            GoRoute(
              path: '/',
              pageBuilder: (context, state) => vernakPage(state, page: const HomePage()),
            ),
            GoRoute(
              path: '/b',
              pageBuilder: (context, state) {
                return vernakPage(state, page: const HomePage());
              },
            ),
          ],
        ),
      ],
    );
''',
        [],
      );

  Future<void> test_builder_and_hand_built_pages_are_flagged() => expectIn(
        _router,
        '''
${_imports}GoRouter buildVernakRouter() => GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomePage()),
        GoRoute(path: '/b', pageBuilder: (context, state) => const NoTransitionPage(child: HomePage())),
        GoRoute(
          path: '/c',
          pageBuilder: (context, state) => CustomTransitionPage(child: const HomePage()),
        ),
      ],
    );
''',
        ['builder', 'pageBuilder', 'NoTransitionPage', 'pageBuilder', 'CustomTransitionPage'],
      );
}
