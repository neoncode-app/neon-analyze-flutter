import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/layout.dart';
import 'package:neon_lints/src/use_context_getters.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/bloc_rule_base.dart';

void main() {
  group('layout patterns', () {
    test('a folder matches everything below it, a file only itself', () {
      expect(matchesLayoutPattern('lib/pages/', 'lib/pages/a/b_page.dart'), isTrue);
      expect(matchesLayoutPattern('lib/pages/', 'lib/pages_old/a.dart'), isFalse);
      expect(matchesLayoutPattern('lib/utils/utils.dart', 'lib/utils/utils.dart'), isTrue);
      expect(matchesLayoutPattern('lib/utils/utils.dart', 'lib/utils/utils.dart.bak'), isFalse);
    });

    test('* stays in one segment, **/ crosses folders', () {
      expect(matchesLayoutPattern('lib/bloc/*/app_wide/', 'lib/bloc/vernak/app_wide/rules_cubit.dart'), isTrue);
      expect(matchesLayoutPattern('lib/bloc/*/app_wide/', 'lib/bloc/a/b/app_wide/x.dart'), isFalse);
      expect(matchesLayoutPattern('lib/**/*_dimens.dart', 'lib/global_widgets/global/button_dimens.dart'), isTrue);
      expect(matchesLayoutPattern('lib/**/*_dimens.dart', 'lib/button_dimens.dart'), isTrue);
      expect(matchesLayoutPattern('**/theme/', 'lib/utils/ui/theme/app_colors.dart'), isTrue);
      expect(matchesLayoutPattern('**/color_editor*/', 'lib/x/color_editor_widgets/a.dart'), isTrue);
    });

    test('a named segment must repeat the same text', () {
      const pattern = 'lib/flavors/{flavor}/{flavor}_providers.dart';
      expect(matchesLayoutPattern(pattern, 'lib/flavors/vernak/vernak_providers.dart'), isTrue);
      expect(matchesLayoutPattern(pattern, 'lib/flavors/vernak/neoncode_providers.dart'), isFalse);
    });
  });

  group('layout config', () {
    test('roles keep their defaults unless the layout section names them', () {
      final layout = Layout.fromConfigSource('''
preset: app
layout:
  providers: lib/app/app_providers.dart
  routing: [lib/app/, lib/router/]
''');
      expect(layout.patterns(LayoutRole.providers), ['lib/app/app_providers.dart']);
      expect(layout.patterns(LayoutRole.routing), ['lib/app/', 'lib/router/']);
      expect(layout.patterns(LayoutRole.pages), LayoutRole.pages.defaults);
      expect(layout.unknownKeys, isEmpty);
    });

    test('an unknown key is reported, a broken file falls back to the defaults', () {
      expect(Layout.fromConfigSource('layout:\n  pagez: lib/screens/\n').unknownKeys, ['pagez']);
      expect(Layout.fromConfigSource('layout: [').patterns(LayoutRole.pages), LayoutRole.pages.defaults);
      expect(Layout.fromConfigSource(null).patterns(LayoutRole.bloc), LayoutRole.bloc.defaults);
    });

    test('an app without flavours keeps its router and providers under lib/app/ (NCC0000078)', () {
      final single = Layout.fromConfigSource('preset: app\n', flavorsFolder: false);
      expect(single.patterns(LayoutRole.providers), ['lib/app/app_providers.dart']);
      expect(single.patterns(LayoutRole.routing), ['lib/app/']);
      expect(single.patterns(LayoutRole.routers), ['lib/app/app_router.dart']);
      expect(single.patterns(LayoutRole.pages), LayoutRole.pages.defaults);

      final flavoured = Layout.fromConfigSource('preset: admin\ntree:\n  use: [flavors]\n', flavorsFolder: false);
      expect(flavoured.patterns(LayoutRole.providers), LayoutRole.providers.defaults);
      expect(flavoured.patterns(LayoutRole.routers), LayoutRole.routers.defaults);

      expect(Layout.fromConfigSource('preset: admin\n').patterns(LayoutRole.routers), LayoutRole.routers.defaults);

      final overridden = Layout.fromConfigSource('layout:\n  routers: lib/router.dart\n', flavorsFolder: false);
      expect(overridden.patterns(LayoutRole.routers), ['lib/router.dart']);
    });

    test('UI code is pages, features and the widget kit', () {
      final layout = Layout.defaults();
      expect(layout.isUi('lib/pages/a_page.dart'), isTrue);
      expect(layout.isUi('lib/features/vernak/x.dart'), isTrue);
      expect(layout.isUi('lib/global_widgets/global/a.dart'), isTrue);
      expect(layout.isUi('lib/bloc/a_cubit.dart'), isFalse);
      expect(Layout.isAppSource('lib/a.g.dart'), isFalse);
      expect(Layout.isAppSource('test/a_test.dart'), isFalse);
    });
  });

  defineReflectiveSuite(() {
    defineReflectiveTests(LayoutOverrideTest);
  });
}

/// A rule follows the app's `layout:` section: an app without flavours
/// declares its providers file and the rule accepts reads there.
@reflectiveTest
class LayoutOverrideTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => UseContextGetters();

  static const _source = '''
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:test/bloc/global/base/base_cubit.dart';

class CounterCubit extends BaseCubit<int> {
  CounterCubit() : super(0);
}

CounterCubit f(BuildContext context) => context.read<CounterCubit>();
''';

  Future<void> test_the_configured_providers_file_owns_the_reads() {
    newFile('$testPackageRootPath/neon_check.yaml', 'layout:\n  providers: lib/app/app_providers.dart\n');
    return expectIn('app/app_providers.dart', _source, []);
  }

  Future<void> test_the_default_location_no_longer_owns_them() {
    newFile('$testPackageRootPath/neon_check.yaml', 'layout:\n  providers: lib/app/app_providers.dart\n');
    return expectIn(
      'flavors/vernak/vernak_providers.dart',
      _source,
      ['context.read<CounterCubit>()'],
      message: ['lib/app/app_providers.dart'],
    );
  }
}
