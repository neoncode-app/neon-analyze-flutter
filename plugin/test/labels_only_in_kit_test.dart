import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/labels_only_in_kit.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/bloc_rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(LabelsOnlyInKitTest);
  });
}

const _kitLabels = '''
import 'package:flutter/widgets.dart';

class EditorLabels {
  const EditorLabels({required this.title});
  final String title;
}

/// An editor.
///
/// {@category Component}
class Editor extends StatelessWidget {
  const Editor({required this.labels});
  final EditorLabels labels;
  @override
  Widget build(BuildContext context) => Widget();
}
''';

@reflectiveTest
class LabelsOnlyInKitTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => LabelsOnlyInKit();

  @override
  void setUp() {
    super.setUp();
    newFile('$testPackageLibPath/global_widgets/global/components/editor/editor.dart', _kitLabels);
  }

  Future<void> test_labels_class_in_a_feature_or_page_is_flagged() async {
    const source = '''
class UpgradeFlowLabels {
  const UpgradeFlowLabels({required this.title});
  final String title;
}

class _PrivateLabels {}
''';
    await expectIn('features/vernak/upgrade_flow/upgrade_flow.dart', source, ['UpgradeFlowLabels', '_PrivateLabels'],
        message: ['a *Labels class outside the widget kit', 'FlavorConfig']);
    await expectIn('pages/vernak/shared_labels.dart', source, ['UpgradeFlowLabels', '_PrivateLabels']);
  }

  Future<void> test_feature_taking_labels_is_flagged() => expectIn(
        'features/vernak/banner/banner.dart',
        '''
import 'package:flutter/widgets.dart';
import 'package:test/global_widgets/global/components/editor/editor.dart';

/// A banner.
///
/// {@category Feature}
class Banner extends StatelessWidget {
  const Banner({required this.labels, EditorLabels? extra, this.title = ''});
  final EditorLabels labels;
  final String title;
  @override
  Widget build(BuildContext context) => Editor(labels: labels);
}
''',
        ['EditorLabels?', 'EditorLabels'],
        message: ['the Feature `Banner` takes a `EditorLabels`'],
        after: 'class Banner',
      );

  Future<void> test_page_widget_taking_labels_is_flagged() => expectIn(
        'pages/vernak/x_page/widgets/patterns/block.dart',
        '''
import 'package:flutter/widgets.dart';
import 'package:test/global_widgets/global/components/editor/editor.dart';

/// A block.
///
/// {@category Pattern}
class Block extends StatelessWidget {
  const Block({required this.labels});
  final EditorLabels labels;
  @override
  Widget build(BuildContext context) => Editor(labels: labels);
}
''',
        ['EditorLabels'],
        message: ['the page widget `Block`'],
        after: 'class Block',
      );

  Future<void> test_page_building_kit_labels_where_it_draws_is_clean() => expectIn(
        'pages/vernak/x_page/x_page.dart',
        '''
import 'package:flutter/widgets.dart';
import 'package:test/global_widgets/global/components/editor/editor.dart';

String tr(String key) => key;

class XPage extends StatelessWidget {
  const XPage();
  @override
  Widget build(BuildContext context) => Editor(labels: EditorLabels(title: tr('x_title')));
}

/// A plain class of the page may hold labels for a kit call; it is no widget.
class XConfig {
  const XConfig(this.labels);
  final EditorLabels labels;
}
''',
        [],
      );

  Future<void> test_the_kit_owns_labels() => expectIn(
        'global_widgets/global/components/other/other.dart',
        _kitLabels.replaceAll('Editor', 'Other'),
        [],
      );

  Future<void> test_a_layout_override_moves_the_roles() async {
    newFile('$testPackageRootPath/neon_check.yaml', 'layout:\n  features: [lib/modules/]\n');
    await expectIn('modules/upgrade/upgrade.dart', 'class UpgradeLabels {}\n', ['UpgradeLabels']);
    await expectIn('features/upgrade/upgrade.dart', 'class UpgradeLabels {}\n', []);
  }
}
