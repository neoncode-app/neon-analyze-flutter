import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';

/// Writes minimal `flutter`, `intl` and `fl_chart` packages into the test's
/// in-memory file system, so rules that match elements by their declaring
/// package can be tested without the real SDKs.
///
/// Call in `setUp` BEFORE `super.setUp()`. Every Flutter class lives in one
/// library under `package:flutter/src/`, re-exported by `material.dart`,
/// `widgets.dart`, `cupertino.dart` and `services.dart`, which is all a
/// package-based match needs.
void addStubPackages(AnalysisRuleTest test) {
  test.newPackage('flutter')
    ..addFile('lib/src/stubs.dart', _flutterStubs)
    ..addFile('lib/material.dart', "export 'src/stubs.dart';")
    ..addFile('lib/widgets.dart', "export 'src/stubs.dart';")
    ..addFile('lib/cupertino.dart', "export 'src/stubs.dart';")
    ..addFile('lib/services.dart', "export 'src/stubs.dart';");
  test.newPackage('intl').addFile('lib/intl.dart', r'''
class DateFormat {
  DateFormat([String? pattern]);
  DateFormat.yMd();
  String format(DateTime date) => '';
}
''');
  test.newPackage('fl_chart').addFile('lib/fl_chart.dart', r'''
import 'package:flutter/widgets.dart';

class LineChart extends Widget {
  const LineChart(Object? data);
}

class LineChartData {
  const LineChartData();
}
''');
}

/// Widgets built with a generic constructor (`child`, `onTap`, `value`, ...).
const _plainWidgets = <String>[
  'DecoratedBox', 'Card', 'ClipRRect', 'GestureDetector', 'InkWell', 'InkResponse', 'Material', //
  'OutlinedButton', 'ElevatedButton', 'FilledButton', 'MaterialButton', 'CupertinoButton',
  'IconButton', 'FloatingActionButton',
  'Switch', 'SwitchListTile', 'CupertinoSwitch', 'Checkbox', 'CheckboxListTile',
  'Radio', 'RadioListTile', 'ChoiceChip', 'FilterChip', 'SegmentedButton', 'ToggleButtons',
  'CupertinoSegmentedControl', 'CupertinoSlidingSegmentedControl',
  'TextField', 'TextFormField', 'CupertinoTextField',
  'DropdownButton', 'DropdownButtonFormField', 'DropdownMenu',
  'Chip', 'InputChip', 'ActionChip', 'RawChip', 'Badge',
  'Divider', 'VerticalDivider', 'ExpansionTile', 'ListTile', 'CircleAvatar',
  'LinearProgressIndicator', 'CircularProgressIndicator', 'CupertinoActivityIndicator',
  'CalendarDatePicker', 'DatePickerDialog', 'DateRangePickerDialog', 'TimePickerDialog',
  'Stepper', 'DataTable', 'PaginatedDataTable', 'Table',
  'SnackBar', 'AlertDialog', 'Dialog', 'SimpleDialog', 'BottomSheet', 'CupertinoAlertDialog',
  'Scaffold', 'AppBar', 'SliverAppBar', 'SafeArea',
  'NavigationRail', 'TabBar', 'TabBarView', 'Drawer', 'NavigationDrawer', 'ReorderableListView',
  'Icon', 'Text', 'SizedBox', 'Column',
];

const _dialogFunctions = <String>[
  'showDialog', 'showModalBottomSheet', 'showGeneralDialog', 'showAdaptiveDialog', //
  'showCupertinoDialog', 'showCupertinoModalPopup', 'showBottomSheet',
  'showDatePicker', 'showTimePicker', 'showDateRangePicker',
];

final _flutterStubs = '''
abstract class BuildContext {}

class Widget {
  const Widget();
}

class IconData {
  const IconData(int codePoint);
}

${_plainWidgets.map((name) => '''
class $name extends Widget {
  const $name({Object? child, Object? onTap, Object? onPressed, Object? value, Object? onChanged, Object? title});
}
''').join()}

class TextButton extends Widget {
  const TextButton({Object? child, Object? onPressed});
  static Object styleFrom() => Object();
}

class Container extends Widget {
  const Container({Object? child, Object? color, Object? decoration, Object? foregroundDecoration, Object? padding});
}

class MouseRegion extends Widget {
  const MouseRegion({Object? child, Object? cursor, Object? onEnter, Object? onExit, Object? onHover});
}

class Image extends Widget {
  const Image.network(String src);
  const Image.asset(String name);
}

class NetworkImage {
  const NetworkImage(String url);
}

abstract final class Icons {
  static const IconData add = IconData(1);
}

abstract final class CupertinoIcons {
  static const IconData add = IconData(2);
}

class Navigator extends Widget {
  const Navigator();
  static NavigatorState of(BuildContext context, {bool rootNavigator = false}) => NavigatorState();
  static void pop<T extends Object?>(BuildContext context, [T? result]) {}
  static Future<T?> push<T extends Object?>(BuildContext context, Object route) async => null;
  static Future<bool> maybePop<T extends Object?>(BuildContext context, [T? result]) async => false;
}

class NavigatorState {
  void pop<T extends Object?>([T? result]) {}
}

abstract final class Clipboard {
  static Future<void> setData(Object data) async {}
}

class ScaffoldMessenger extends Widget {
  const ScaffoldMessenger();
  static ScaffoldMessengerState of(BuildContext context) => ScaffoldMessengerState();
}

class ScaffoldMessengerState {
  void showSnackBar(Object snackBar) {}
}

${_dialogFunctions.map((name) => 'Future<T?> $name<T>({BuildContext? context, Object? builder}) async => null;\n').join()}
''';
