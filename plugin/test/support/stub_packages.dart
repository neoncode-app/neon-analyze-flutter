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
    ..addFile('lib/services.dart', "export 'src/stubs.dart';")
    ..addFile('lib/foundation.dart', "export 'src/stubs.dart';");
  test.newPackage('intl').addFile('lib/intl.dart', r'''
class DateFormat {
  DateFormat([String? pattern]);
  DateFormat.yMd();
  String format(DateTime date) => '';
}

class NumberFormat {
  NumberFormat([String? pattern]);
  NumberFormat.currency({String? symbol});
  String format(num value) => '';
}
''');
  // The real package declares launchUrl in src/ and re-exports it.
  test.newPackage('url_launcher')
    ..addFile('lib/src/url_launcher_uri.dart', r'''
Future<bool> launchUrl(Uri url) async => true;
Future<bool> canLaunchUrl(Uri url) async => true;
''')
    ..addFile('lib/url_launcher.dart', "export 'src/url_launcher_uri.dart';")
    ..addFile('lib/url_launcher_string.dart', r'''
Future<bool> launchUrlString(String url) async => true;
Future<bool> canLaunchUrlString(String url) async => true;
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

/// Adds to the analyzer's mock SDK what it lacks and the rules match:
/// `num.toStringAsFixed`, `jsonDecode`, `Timer.periodic` / `cancel` and a
/// non-deprecated `Platform.isIOS`.
///
/// Call in `setUp` AFTER `super.setUp()` (which writes the mock SDK).
void patchMockSdk(AnalysisRuleTest test) {
  void patch(String unit, String anchor, String addition) {
    final path = test.convertPath('/sdk/lib/$unit');
    final file = test.resourceProvider.getFile(path);
    final source = file.readAsStringSync();
    if (!source.contains(anchor)) throw StateError('mock SDK $unit has no "$anchor"');
    test.newFile(path, source.replaceFirst(anchor, '$anchor\n$addition'));
  }

  patch('core/core.dart', 'sealed class num implements Comparable<num> {',
      '  String toStringAsFixed(int fractionDigits);');
  patch('core/core.dart', 'abstract final class double extends num {', '  String toStringAsFixed(int fractionDigits);');
  patch('convert/convert.dart', 'const JsonCodec json = JsonCodec();', 'dynamic jsonDecode(String source) => null;');
  patch(
    'async/async.dart',
    'abstract interface class Timer {',
    '  factory Timer.periodic(Duration duration, void Function(Timer timer) callback) => throw 0;\n'
        '  void cancel();',
  );
  patch('io/io.dart', 'abstract final class Platform {', '  static bool get isIOS => false;');
}

/// Writes minimal `bloc`, `flutter_bloc` and `provider` packages (needs the
/// flutter stubs of [addStubPackages] too).
void addBlocPackages(AnalysisRuleTest test) {
  test.newPackage('bloc').addFile('lib/bloc.dart', r'''
abstract class BlocBase<S> {
  BlocBase(S state);
  S get state => throw 0;
  Stream<S> get stream => throw 0;
  bool get isClosed => false;
  void emit(S state) {}
  Future<void> close() async {}
}

abstract class Cubit<S> extends BlocBase<S> {
  Cubit(super.state);
}
''');
  test.newPackage('provider').addFile('lib/provider.dart', r'''
import 'package:flutter/widgets.dart';

extension ReadContext on BuildContext {
  T read<T>() => throw 0;
}

extension WatchContext on BuildContext {
  T watch<T>() => throw 0;
}

extension SelectContext on BuildContext {
  R select<T, R>(R Function(T value) selector) => throw 0;
}
''');
  test.newPackage('flutter_bloc').addFile('lib/flutter_bloc.dart', r'''
import 'package:bloc/bloc.dart';
import 'package:flutter/widgets.dart';

export 'package:bloc/bloc.dart';
export 'package:provider/provider.dart' show ReadContext, WatchContext, SelectContext;

class BlocProvider<T extends BlocBase<Object?>> extends Widget {
  const BlocProvider({required T Function(BuildContext context) create, Widget? child});
  const BlocProvider.value({required T value, Widget? child});
  static T of<T extends BlocBase<Object?>>(BuildContext context) => throw 0;
}

class BlocBuilder<B extends BlocBase<S>, S> extends Widget {
  const BlocBuilder({required Widget Function(BuildContext context, S state) builder});
}

class MultiBlocProvider extends Widget {
  const MultiBlocProvider({required List<Widget> providers, Widget? child});
}
''');
}

/// Writes minimal `bloc_presentation` and `go_router` packages and the app's
/// dialog helper `Utils.showCustomModalBottomSheet` (lib/utils/utils.dart).
void addPresentationPackages(AnalysisRuleTest test) {
  test.newPackage('bloc_presentation').addFile('lib/bloc_presentation.dart', r'''
import 'package:flutter/widgets.dart';

class BlocPresentationListener<B, E> extends Widget {
  const BlocPresentationListener({required void Function(BuildContext context, E event) listener, Widget? child});
}
''');
  test.newPackage('go_router').addFile('lib/go_router.dart', r'''
import 'package:flutter/widgets.dart';

extension GoRouterHelper on BuildContext {
  void go(String location) {}
  void goNamed(String name) {}
  Future<T?> push<T extends Object?>(String location) async => null;
  void pop<T extends Object?>([T? result]) {}
  bool canPop() => true;
}
''');
  test.newFile('${test.testPackageLibPath}/utils/utils.dart', r'''
import 'package:flutter/widgets.dart';

class Utils {
  static Future<T?> showCustomModalBottomSheet<T>({required BuildContext context, Object? builder}) async => null;
}
''');
}

/// App classes the architecture rules refer to: `BaseCubit` and `AlertCubit`.
void addAppBlocClasses(AnalysisRuleTest test) {
  test.newFile('${test.testPackageLibPath}/bloc/global/base/base_cubit.dart', r'''
import 'package:flutter_bloc/flutter_bloc.dart';

abstract class BaseCubit<S> extends Cubit<S> {
  BaseCubit(super.initialState);
}
''');
  test.newFile('${test.testPackageLibPath}/bloc/global/alert/alert_cubit.dart', r'''
import 'package:test/bloc/global/base/base_cubit.dart';

class AlertCubit extends BaseCubit<void> {
  AlertCubit() : super(null);
  void showSuccess(String message) {}
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
  'Icon', 'Column',
];

const _dialogFunctions = <String>[
  'showDialog', 'showModalBottomSheet', 'showGeneralDialog', 'showAdaptiveDialog', //
  'showCupertinoDialog', 'showCupertinoModalPopup', 'showBottomSheet',
  'showDatePicker', 'showTimePicker', 'showDateRangePicker',
];

final _flutterStubs = '''
abstract class BuildContext {
  bool get mounted => true;
}

class Widget {
  const Widget();
}

abstract class StatelessWidget extends Widget {
  const StatelessWidget();
  Widget build(BuildContext context);
}

abstract class StatefulWidget extends Widget {
  const StatefulWidget();
}

abstract class State<T extends StatefulWidget> {
  BuildContext get context => throw 0;
  void initState() {}
  void didChangeDependencies() {}
  void dispose() {}
  void setState(void Function() fn) {}
  Widget build(BuildContext context);
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

class Text extends Widget {
  const Text(String data, {TextStyle? style});
}

class SizedBox extends Widget {
  const SizedBox({double? width, double? height, Widget? child});
}

class EdgeInsets {
  const EdgeInsets.all(double value);
  const EdgeInsets.symmetric({double horizontal = 0, double vertical = 0});
  const EdgeInsets.only({double left = 0, double top = 0, double right = 0, double bottom = 0});
  static const zero = EdgeInsets.all(0);
}

class Radius {
  const Radius.circular(double radius);
}

class BorderRadius {
  const BorderRadius.all(Radius radius);
  BorderRadius.circular(double radius);
}

class FontWeight {
  const FontWeight._(this.value);
  final int value;
  static const bold = FontWeight._(700);
}

class TextStyle {
  const TextStyle({double? fontSize, FontWeight? fontWeight, double? letterSpacing, double? height, Object? color});
  TextStyle copyWith({double? fontSize, FontWeight? fontWeight, double? letterSpacing, double? height, Object? color}) =>
      this;
}

typedef DebugPrintCallback = void Function(String? message, {int? wrapWidth});

DebugPrintCallback debugPrint = (message, {wrapWidth}) {};

class Size {
  const Size(this.width, this.height);
  final double width;
  final double height;
}

class MediaQueryData {
  Size get size => const Size(0, 0);
}

class MediaQuery extends Widget {
  const MediaQuery();
  static MediaQueryData of(BuildContext context) => MediaQueryData();
  static Size sizeOf(BuildContext context) => const Size(0, 0);
  static double widthOf(BuildContext context) => 0;
}

class BoxConstraints {
  double get maxWidth => 0;
}

class LayoutBuilder extends Widget {
  const LayoutBuilder({required Widget Function(BuildContext context, BoxConstraints constraints) builder});
}

const bool kIsWeb = false;

enum TargetPlatform { android, iOS }

TargetPlatform get defaultTargetPlatform => TargetPlatform.android;

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
