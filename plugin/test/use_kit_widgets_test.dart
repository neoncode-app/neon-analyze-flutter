import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/banned_api/banned_api.dart';
import 'package:neon_lints/src/use_kit_widgets.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/expect.dart';
import 'support/stub_packages.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(UseKitWidgetsTest);
  });
}

const _material = "import 'package:flutter/material.dart';\n";

/// One violating source per table row; `flagged` lists the reported texts in
/// source order. Every row of [UseKitWidgets.rows] must appear here.
const _violations = <({String row, String source, List<String> flagged})>[
  (
    row: 'Container(decoration:)',
    source: '${_material}Object f() => [Container(decoration: 1), Container(foregroundDecoration: 1)];',
    flagged: ['Container', 'Container'],
  ),
  (
    row: 'DecoratedBox / Card / ClipRRect',
    source: '${_material}Object f() => [DecoratedBox(), Card(), ClipRRect()];',
    flagged: ['DecoratedBox', 'Card', 'ClipRRect'],
  ),
  (
    row: 'GestureDetector / InkWell / InkResponse / Material',
    source: '${_material}Object f() => [GestureDetector(), InkWell(), InkResponse(), Material()];',
    flagged: ['GestureDetector', 'InkWell', 'InkResponse', 'Material'],
  ),
  (
    row: 'MouseRegion for hover',
    source: '${_material}Object f() => [MouseRegion(onEnter: 1), MouseRegion(onExit: 1), MouseRegion(onHover: 1)];',
    flagged: ['MouseRegion', 'MouseRegion', 'MouseRegion'],
  ),
  (
    row: 'TextButton / OutlinedButton / ElevatedButton / FilledButton',
    source: '${_material}Object f() => [TextButton(), OutlinedButton(), ElevatedButton(), FilledButton(), '
        'TextButton.styleFrom(), TextButton.new];',
    flagged: [
      'TextButton',
      'OutlinedButton',
      'ElevatedButton',
      'FilledButton',
      'TextButton.styleFrom()',
      'TextButton.new',
    ],
  ),
  (
    row: 'IconButton / FloatingActionButton',
    source: '${_material}Object f() => [IconButton(), FloatingActionButton()];',
    flagged: ['IconButton', 'FloatingActionButton'],
  ),
  (
    row: 'Switch / SwitchListTile',
    source: '${_material}Object f() => [Switch(), SwitchListTile(), CupertinoSwitch()];',
    flagged: ['Switch', 'SwitchListTile', 'CupertinoSwitch'],
  ),
  (
    row: 'Checkbox / CheckboxListTile',
    source: '${_material}Object f() => [Checkbox(), CheckboxListTile()];',
    flagged: ['Checkbox', 'CheckboxListTile'],
  ),
  (
    row: 'Radio / ChoiceChip / FilterChip / SegmentedButton / ToggleButtons',
    source: '${_material}Object f() => [Radio(), ChoiceChip(), FilterChip(), SegmentedButton(), ToggleButtons()];',
    flagged: ['Radio', 'ChoiceChip', 'FilterChip', 'SegmentedButton', 'ToggleButtons'],
  ),
  (
    row: 'TextField / TextFormField',
    source: '${_material}Object f() => [TextField(), TextFormField()];',
    flagged: ['TextField', 'TextFormField'],
  ),
  (
    row: 'DropdownButton / DropdownMenu',
    source: '${_material}Object f() => [DropdownButton(), DropdownMenu()];',
    flagged: ['DropdownButton', 'DropdownMenu'],
  ),
  (
    row: 'Chip / Badge',
    source: '${_material}Object f() => [Chip(), Badge()];',
    flagged: ['Chip', 'Badge'],
  ),
  (
    row: 'Divider / VerticalDivider',
    source: '${_material}Object f() => [Divider(), VerticalDivider()];',
    flagged: ['Divider', 'VerticalDivider'],
  ),
  (row: 'ExpansionTile', source: '${_material}Object f() => ExpansionTile();', flagged: ['ExpansionTile']),
  (row: 'ListTile', source: '${_material}Object f() => ListTile();', flagged: ['ListTile']),
  (row: 'CircleAvatar', source: '${_material}Object f() => CircleAvatar();', flagged: ['CircleAvatar']),
  (row: 'Image.network', source: "${_material}Object f() => Image.network('u');", flagged: ['Image.network']),
  (row: 'NetworkImage', source: "${_material}Object f() => NetworkImage('u');", flagged: ['NetworkImage']),
  (
    row: 'Icons.x (Material / Cupertino icons)',
    source: '${_material}Object f() => [Icon(), Icons.add, CupertinoIcons.add];',
    flagged: ['Icons.add', 'CupertinoIcons.add'],
  ),
  (
    row: 'LinearProgressIndicator',
    source: '${_material}Object f() => LinearProgressIndicator();',
    flagged: ['LinearProgressIndicator'],
  ),
  (
    row: 'CircularProgressIndicator',
    source: '${_material}Object f() => [CircularProgressIndicator(), CupertinoActivityIndicator()];',
    flagged: ['CircularProgressIndicator', 'CupertinoActivityIndicator'],
  ),
  (
    row: 'showDatePicker / showTimePicker / showDateRangePicker',
    source: '${_material}void f() {\n  showDatePicker();\n  showTimePicker();\n  showDateRangePicker();\n}',
    flagged: ['showDatePicker', 'showTimePicker', 'showDateRangePicker'],
  ),
  (
    row: 'CalendarDatePicker',
    source: '${_material}Object f() => CalendarDatePicker();',
    flagged: ['CalendarDatePicker'],
  ),
  (row: 'Stepper', source: '${_material}Object f() => Stepper();', flagged: ['Stepper']),
  (
    row: 'DataTable / Table',
    source: '${_material}Object f() => [DataTable(), Table()];',
    flagged: ['DataTable', 'Table'],
  ),
  (
    row: 'package:fl_chart outside the stats kit',
    source: "import 'package:fl_chart/fl_chart.dart';\nObject f() => LineChart(1);",
    flagged: ["import 'package:fl_chart/fl_chart.dart';", 'LineChart'],
  ),
  (
    row: 'Clipboard',
    source: "import 'package:flutter/services.dart';\nvoid f() {\n  Clipboard.setData(1);\n}",
    flagged: ['Clipboard.setData(1)'],
  ),
  (
    row: 'SnackBar / ScaffoldMessenger',
    source:
        '${_material}void f(BuildContext c) {\n  final bar = SnackBar();\n  ScaffoldMessenger.of(c).showSnackBar(bar);\n}',
    flagged: ['SnackBar', 'ScaffoldMessenger.of(c)'],
  ),
  (
    row: 'DateFormat',
    source: "import 'package:intl/intl.dart';\nObject f() => [DateFormat('d'), DateFormat.yMd()];",
    flagged: ['DateFormat', 'DateFormat.yMd'],
  ),
  (
    row: 'showDialog / showModalBottomSheet / showGeneralDialog',
    source: '${_material}void f() {\n  showDialog();\n  showModalBottomSheet();\n  showGeneralDialog();\n'
        '  showCupertinoModalPopup();\n}',
    flagged: ['showDialog', 'showModalBottomSheet', 'showGeneralDialog', 'showCupertinoModalPopup'],
  ),
  (
    row: 'AlertDialog / Dialog / SimpleDialog / BottomSheet',
    source: '${_material}Object f() => [AlertDialog(), Dialog(), SimpleDialog(), BottomSheet()];',
    flagged: ['AlertDialog', 'Dialog', 'SimpleDialog', 'BottomSheet'],
  ),
  (
    row: 'Scaffold / AppBar outside a template',
    source: '${_material}Object f() => Scaffold(child: AppBar());',
    flagged: ['Scaffold', 'AppBar'],
  ),
  (row: 'SafeArea', source: '${_material}Object f() => SafeArea();', flagged: ['SafeArea']),
  (
    row: 'NavigationRail / TabBar / Drawer',
    source: '${_material}Object f() => [NavigationRail(), TabBar(), Drawer()];',
    flagged: ['NavigationRail', 'TabBar', 'Drawer'],
  ),
  (
    row: 'ReorderableListView',
    source: '${_material}Object f() => ReorderableListView();',
    flagged: ['ReorderableListView'],
  ),
];

@reflectiveTest
class UseKitWidgetsTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = UseKitWidgets();
    addStubPackages(this);
    super.setUp();
  }

  BannedApi _row(String label) => UseKitWidgets.rows.singleWhere((row) => row.label == label);

  void test_every_row_has_a_violation_case() {
    expect(
      _violations.map((violation) => violation.row).toSet(),
      UseKitWidgets.rows.map((row) => row.label).toSet(),
    );
  }

  Future<void> test_violation_per_row_names_the_replacement() async {
    for (final (index, violation) in _violations.indexed) {
      final path = '$testPackageLibPath/pages/violation_$index.dart';
      newFile(path, violation.source);
      await assertDiagnosticsInFile(
        path,
        lintsAt(
          this,
          violation.source,
          violation.flagged,
          messageContainsAll: [_row(violation.row).replacement],
        ),
      );
    }
  }

  Future<void> test_owner_file_may_use_its_row() async {
    for (final (index, violation) in _violations.indexed) {
      final row = _row(violation.row);
      for (final owner in row.owners) {
        final path = '$testPackageLibPath/${owner.endsWith('/') ? '${owner}owner_$index.dart' : owner}';
        newFile(path, violation.source);
        await assertNoDiagnosticsInFile(path);
      }
    }
  }

  Future<void> test_owner_of_one_row_is_not_owner_of_another() async {
    // custom_button.dart owns raw buttons and taps, not dialogs.
    const source = '${_material}Object f() => [TextButton(), AlertDialog()];';
    final path = '$testPackageLibPath/global_widgets/global/custom_button.dart';
    newFile(path, source);
    await assertDiagnosticsInFile(path, lintsAt(this, source, ['AlertDialog']));
  }

  Future<void> test_template_category_owns_scaffold() async {
    const source = '''
$_material
/// The frame of a page.
///
/// {@category Template}
class AppPageFrame {
  Object build() => Scaffold(child: AppBar());
}
''';
    final path = '$testPackageLibPath/global_widgets/global/app_page_frame.dart';
    newFile(path, source);
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_other_category_does_not_own_scaffold() async {
    const source = '''
$_material
/// A row.
///
/// {@category Component}
class AppRow {
  Object build() => Scaffold();
}
''';
    await assertDiagnostics(source, lintsAt(this, source, ['Scaffold']));
  }

  Future<void> test_generated_file_is_skipped() async {
    final path = '$testPackageLibPath/model/catalog.g.dart';
    newFile(path, '${_material}Object f() => [TextButton(), Icons.add];');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_files_outside_lib_are_skipped() async {
    // Widget tests pump raw MaterialApp / Scaffold.
    final path = '$testPackageRootPath/test/page_test.dart';
    newFile(path, '${_material}Object f() => Scaffold(child: TextButton());');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_import_prefix_does_not_hide_a_banned_api() async {
    const source = "import 'package:flutter/material.dart' as m;\nObject f() => [m.TextButton(), m.Icons.add];";
    await assertDiagnostics(source, lintsAt(this, source, ['m.TextButton', 'm.Icons.add']));
  }

  Future<void> test_clean_kit_usage() async {
    await assertNoDiagnostics('''
$_material
Object f() => [
  Container(color: 1, padding: 2),
  MouseRegion(cursor: 1),
  Image.asset('a.png'),
  Icon(),
  Text('a'),
  SizedBox(),
  Column(),
];
''');
  }

  Future<void> test_type_annotations_are_not_flagged() async {
    await assertNoDiagnostics('''
$_material
void f(TextButton button, ScaffoldMessengerState messenger, List<Switch> switches) {}
''');
  }

  Future<void> test_app_class_with_a_banned_name_is_not_flagged() async {
    await assertNoDiagnostics('''
class Switch {
  const Switch();
  static const on = Switch();
}

class Icons {
  static const add = 1;
}

Object f() => [Switch(), Switch.on, Icons.add];
''');
  }
}
