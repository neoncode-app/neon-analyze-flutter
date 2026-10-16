import 'package:analyzer/error/error.dart';
// The diagnostic codes are not exported from a public library.
// ignore: implementation_imports
import 'package:analyzer/src/diagnostic/diagnostic.dart' as diag;
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/banned_api/banned_api.dart';
import 'package:neon_lints/src/use_shared_utils.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/expect.dart';
import 'support/stub_packages.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(UseSharedUtilsTest);
  });
}

const _intl = "import 'package:intl/intl.dart';\n";
const _services = "import 'package:flutter/services.dart';\n";
const _foundation = "import 'package:flutter/foundation.dart';\n";

/// One violating source per table row, written at `lib/<path>`; `flagged`
/// lists the reported texts in source order. Every row of
/// [UseSharedUtils.rows] must appear here.
const _violations = <({String row, String path, String source, List<String> flagged})>[
  (
    row: 'DateFormat( / NumberFormat(',
    path: 'utils/dates.dart',
    source: "${_intl}Object f() => [DateFormat('d'), DateFormat.yMd(), NumberFormat(), NumberFormat.currency(), "
        'DateFormat.new];',
    flagged: ['DateFormat', 'DateFormat.yMd', 'NumberFormat', 'NumberFormat.currency', 'DateFormat.new'],
  ),
  (
    row: 'toStringAsFixed( in UI code',
    path: 'pages/price_page/price_page.dart',
    source: 'Object f(num price, double? rate) => [price.toStringAsFixed(2), rate?.toStringAsFixed(1), '
        '1.5.toStringAsFixed(0)];',
    flagged: ['price.toStringAsFixed(2)', 'rate?.toStringAsFixed(1)', '1.5.toStringAsFixed(0)'],
  ),
  (
    row: 'launchUrl( / launchUrlString( / canLaunchUrl(',
    path: 'bloc/links/links_cubit.dart',
    source: "import 'package:url_launcher/url_launcher.dart';\n"
        "import 'package:url_launcher/url_launcher_string.dart';\n"
        "Future<void> f(Uri uri) async {\n  if (await canLaunchUrl(uri)) await launchUrl(uri);\n  await launchUrlString('u');\n}",
    flagged: ['canLaunchUrl', 'launchUrl', 'launchUrlString'],
  ),
  (
    row: 'Clipboard.',
    path: 'pages/share_page/share_page.dart',
    source: '${_services}void f() {\n  Clipboard.setData(1);\n}',
    flagged: ['Clipboard.setData(1)'],
  ),
  (
    row: 'jsonDecode( outside the repository layer',
    path: 'bloc/import/import_cubit.dart',
    source: "import 'dart:convert';\nObject? f(String body) => jsonDecode(body);",
    flagged: ['jsonDecode'],
  ),
  (
    row: 'RegExp( with an e-mail or phone pattern',
    path: 'utils/helpers/contact.dart',
    source: r'''
final email = RegExp(r'^[\w.+-]+@[\w-]+\.[a-z]{2,}$');
final email2 = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9-]+$');
final phone = RegExp(r'^\+?[0-9 ]{9,15}$');
final phone2 = RegExp(r'^\+?\d+$');
final phone3 = RegExp(r'^\d{9}$', caseSensitive: false);
''',
    flagged: ['RegExp', 'RegExp', 'RegExp', 'RegExp', 'RegExp'],
  ),
  (
    row: 'kIsWeb outside UI code',
    path: 'utils/helpers/env.dart',
    source: "${_foundation}import 'package:flutter/foundation.dart' as foundation;\n"
        'bool f() => kIsWeb || foundation.kIsWeb;',
    flagged: ['kIsWeb', 'kIsWeb'],
  ),
  (
    row: 'Platform. (dart:io) outside UI code',
    path: 'repository/device_repository.dart',
    source: "import 'dart:io';\nimport 'dart:io' as io;\nbool f() => Platform.isIOS || io.Platform.isIOS;",
    flagged: ['Platform.isIOS', 'io.Platform.isIOS'],
  ),
  (
    row: 'Timer( stored in a cubit field (a debounce)',
    path: 'bloc/search/search_cubit.dart',
    source: '''
import 'dart:async';

class SearchCubit {
  final _other = Timer(Duration.zero, () {});

  void search(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {});
    _third ??= (Timer(Duration.zero, () {}));
  }

  // Declared below, so the flagged texts come first in the source.
  Timer? _debounce;
  Timer? _third;
}
''',
    flagged: ['Timer', 'Timer', 'Timer'],
  ),
];

@reflectiveTest
class UseSharedUtilsTest extends AnalysisRuleTest {
  // Fields and locals of the snippets are not all read.
  @override
  List<DiagnosticCode> get ignoredDiagnosticCodes => [
        ...super.ignoredDiagnosticCodes,
        diag.unusedImport,
        diag.unusedField,
        diag.unusedLocalVariable,
        diag.unusedElement,
      ];

  @override
  void setUp() {
    rule = UseSharedUtils();
    addStubPackages(this);
    super.setUp();
    patchMockSdk(this);
  }

  BannedApi _row(String label) => UseSharedUtils.rows.singleWhere((row) => row.label == label);

  Future<void> _expectIn(String relativePath, String source, List<String> flagged, {List<Pattern> message = const []}) {
    final path = '$testPackageLibPath/$relativePath';
    newFile(path, source);
    return assertDiagnosticsInFile(path, lintsAt(this, source, flagged, messageContainsAll: message));
  }

  Future<void> _expectNoneIn(String relativePath, String source) {
    final path = '$testPackageLibPath/$relativePath';
    newFile(path, source);
    return assertNoDiagnosticsInFile(path);
  }

  void test_every_row_has_a_violation_case() {
    expect(
      _violations.map((violation) => violation.row).toSet(),
      UseSharedUtils.rows.map((row) => row.label).toSet(),
    );
  }

  Future<void> test_violation_per_row_names_the_api_and_the_replacement() async {
    for (final violation in _violations) {
      final row = _row(violation.row);
      await _expectIn(violation.path, violation.source, violation.flagged, message: [row.label, row.replacement]);
    }
  }

  // Row 1.
  Future<void> test_formatting_with_a_held_date_format_is_clean() async {
    await _expectNoneIn('utils/dates.dart', '${_intl}String f(DateFormat format) => format.format(DateTime.now());');
  }

  // Row 2.
  Future<void> test_to_string_as_fixed_outside_ui_is_clean() async {
    const source = 'String f(num price) => price.toStringAsFixed(2);';
    await _expectNoneIn('bloc/price/price_cubit.dart', source);
    await _expectNoneIn('utils/helpers/money.dart', source);
  }

  Future<void> test_to_string_as_fixed_in_features_and_kit_is_flagged() async {
    const source = 'String f(double price) => price.toStringAsFixed(2);';
    await _expectIn('features/cart/cart.dart', source, ['price.toStringAsFixed(2)']);
    await _expectIn('global_widgets/global/app_price/app_price.dart', source, ['price.toStringAsFixed(2)']);
  }

  Future<void> test_other_number_methods_are_clean() async {
    await _expectNoneIn('pages/price_page/price_page.dart', 'Object f(num price) => [price.toString(), price.abs()];');
  }

  // Row 3.
  Future<void> test_app_function_named_launch_url_is_clean() async {
    await _expectNoneIn(
      'utils/links.dart',
      'Future<bool> launchUrl(Uri url) async => true;\nFuture<void> f(Uri u) async => launchUrl(u);',
    );
  }

  // Row 4.
  Future<void> test_file_declaring_app_copy_field_owns_the_clipboard() async {
    const source = '${_services}class AppCopyField {\n  void copy() => Clipboard.setData(1);\n}';
    await _expectNoneIn('global_widgets/global/app_copy_field/app_copy_field.dart', source);
  }

  Future<void> test_file_declaring_app_copy_button_owns_the_clipboard() async {
    const source = '${_services}class AppCopyButton {\n  void copy() => Clipboard.setData(1);\n}';
    await _expectNoneIn('widgets/copy.dart', source);
  }

  Future<void> test_copy_folder_without_the_class_does_not_own_the_clipboard() async {
    const source = '${_services}class CopyHelper {\n  void copy() => Clipboard.setData(1);\n}';
    await _expectIn('global_widgets/global/app_copy_field/widgets/helper.dart', source, ['Clipboard.setData(1)']);
  }

  // Row 5.
  Future<void> test_repository_may_decode_json() async {
    await _expectNoneIn(
      'repository/api_repository.dart',
      "import 'dart:convert';\nObject? f(String body) => jsonDecode(body);",
    );
  }

  Future<void> test_json_encode_is_clean() async {
    await _expectNoneIn(
        'bloc/export/export_cubit.dart', "import 'dart:convert';\nString f(Object o) => jsonEncode(o);");
  }

  // Row 6.
  Future<void> test_other_patterns_are_clean() async {
    await _expectNoneIn('utils/helpers/patterns.dart', r'''
final digits = RegExp(r'^\d+$');
final slug = RegExp(r'[a-z0-9-]+');
final mention = RegExp('@');
final decimal = RegExp(r'^[0-9]+([.,][0-9]{1,2})?$');
final hex = RegExp(r'^#?[0-9a-fA-F]{6}$');
String domain = 'x';
final built = RegExp('^.+@$domain\\.cz');
''');
  }

  // Row 7.
  Future<void> test_kisweb_and_platform_in_ui_are_left_to_the_ui_rules() async {
    await _expectNoneIn('pages/home_page/home_page.dart', '${_foundation}bool f() => kIsWeb;');
    await _expectNoneIn('features/shell/shell.dart', "import 'dart:io';\nbool f() => Platform.isIOS;");
    await _expectNoneIn('global_widgets/global/app_x/app_x.dart', '${_foundation}bool f() => kIsWeb;');
  }

  Future<void> test_kisweb_and_platform_in_bloc_are_flagged() async {
    await _expectIn('bloc/app/app_cubit.dart', '${_foundation}bool f() => kIsWeb;', ['kIsWeb']);
    await _expectIn('bloc/app/device_cubit.dart', "import 'dart:io';\nbool f() => Platform.isIOS;", ['Platform.isIOS']);
  }

  Future<void> test_show_combinator_is_not_flagged() async {
    await _expectNoneIn('utils/env.dart', "import 'package:flutter/foundation.dart' show kIsWeb;\nvoid f() {}");
  }

  Future<void> test_app_variable_named_kisweb_is_clean() async {
    await _expectNoneIn('utils/env.dart', 'const kIsWeb = true;\nbool f() => kIsWeb;');
  }

  // Row 8.
  Future<void> test_periodic_and_local_timers_are_clean() async {
    await _expectNoneIn('bloc/clock/clock_cubit.dart', '''
import 'dart:async';

class ClockCubit {
  Timer? _ticker;

  void start() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {});
    final once = Timer(Duration.zero, () {});
    unawaited(Future<void>.value());
  }
}
''');
  }

  Future<void> test_timer_field_outside_bloc_is_clean() async {
    await _expectNoneIn('utils/helpers/delay.dart', '''
import 'dart:async';

class Delay {
  Timer? _timer;

  void run() => _timer = Timer(Duration.zero, () {});
}
''');
  }

  Future<void> test_app_class_named_timer_is_clean() async {
    await _expectNoneIn('bloc/race/race_cubit.dart', '''
class Timer {
  Timer(Object a, Object b);
}

class RaceCubit {
  Timer? _timer;

  void start() => _timer = Timer(1, 2);
}
''');
  }

  // Shared.
  Future<void> test_generated_file_is_skipped() async {
    await _expectNoneIn('model/catalog.g.dart', "import 'dart:convert';\nObject? f(String body) => jsonDecode(body);");
  }

  Future<void> test_files_outside_lib_are_skipped() async {
    final path = '$testPackageRootPath/test/json_test.dart';
    newFile(path, "import 'dart:convert';\nObject? f(String body) => jsonDecode(body);");
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_app_class_named_date_format_is_clean() async {
    await _expectNoneIn(
        'utils/dates.dart', 'class DateFormat {\n  DateFormat(String p);\n}\nObject f() => DateFormat("d");');
  }
}
