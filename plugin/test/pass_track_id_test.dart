import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/pass_track_id.dart';
import 'package:neon_lints/src/support/rule_layout.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/expect.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(PassTrackIdTest);
  });
}

const _kit = r'''
class AppTapArea {
  const AppTapArea({
    this.trackId,
    this.trackLabel,
    this.tracked = true,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onChanged,
    this.onToggle,
    this.onPanEnd,
    this.onHorizontalDragEnd,
    this.onVerticalDragEnd,
    this.onHover,
  });
  const AppTapArea.icon({this.onTap, this.trackId})
      : trackLabel = null,
        tracked = true,
        onDoubleTap = null,
        onLongPress = null,
        onChanged = null,
        onToggle = null,
        onPanEnd = null,
        onHorizontalDragEnd = null,
        onVerticalDragEnd = null,
        onHover = null;
  final String? trackId;
  final String? trackLabel;
  final bool tracked;
  final Object? onTap;
  final Object? onDoubleTap;
  final Object? onLongPress;
  final Object? onChanged;
  final Object? onToggle;
  final Object? onPanEnd;
  final Object? onHorizontalDragEnd;
  final Object? onVerticalDragEnd;
  final Object? onHover;
}

class IconTap extends AppTapArea {
  const IconTap({super.onTap, super.trackId});
}

class SegmentSwitch {
  const SegmentSwitch({this.leftTrackId, this.rightTrackId, this.onChanged});
  final String? leftTrackId;
  final String? rightTrackId;
  final Object? onChanged;
}

class CustomButton {
  const CustomButton({this.label, this.onTap});
  final String? label;
  final Object? onTap;
}

class PositionalId {
  const PositionalId(this.trackId, {this.onTap});
  final String? trackId;
  final Object? onTap;
}

void handler() {}
''';

@reflectiveTest
class PassTrackIdTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = PassTrackId();
    RuleLayout.clearCache();
    super.setUp();
  }

  Future<void> test_a_callback_without_track_id_is_reported() async {
    const body = 'Object f() => AppTapArea(onTap: handler);';
    await assertDiagnostics(
      '$_kit$body',
      lintsAt(
        this,
        '$_kit$body',
        ['AppTapArea'],
        after: 'Object f()',
        messageContainsAll: ['AppTapArea', 'onTap'],
      ),
    );
  }

  Future<void> test_every_callback_needs_a_track_id() async {
    for (final (index, callback) in PassTrackId.callbacks.indexed) {
      final source = '$_kit\nObject f() => AppTapArea($callback: handler);';
      final path = '$testPackageLibPath/pages/page_$index.dart';
      newFile(path, source);
      await assertDiagnosticsInFile(
        path,
        lintsAt(this, source, ['AppTapArea'], after: 'Object f()', messageContainsAll: [callback]),
      );
    }
  }

  Future<void> test_the_correction_names_the_element() async {
    expect(PassTrackId.code.correctionMessage, contains("trackId: 'home.search_open'"));
  }

  Future<void> test_a_const_named_constructor_is_reported() async {
    const body = 'Object f() => const AppTapArea.icon(onTap: handler);';
    await assertDiagnostics('$_kit$body', lintsAt(this, '$_kit$body', ['AppTapArea.icon'], after: 'Object f()'));
  }

  Future<void> test_a_conditional_callback_is_reported() async {
    const body = 'Object f(bool on) => AppTapArea(onTap: on ? handler : null);';
    await assertDiagnostics('$_kit$body', lintsAt(this, '$_kit$body', ['AppTapArea'], after: 'Object f('));
  }

  Future<void> test_a_constructor_with_a_super_track_id_is_reported() async {
    const body = 'Object f() => IconTap(onTap: handler);';
    await assertDiagnostics('$_kit$body', lintsAt(this, '$_kit$body', ['IconTap'], after: 'Object f()'));
  }

  Future<void> test_an_import_prefix_does_not_hide_it() async {
    newFile('$testPackageLibPath/kit.dart', _kit);
    const source = "import 'kit.dart' as kit;\nObject f() => kit.AppTapArea(onTap: kit.handler);";
    await assertDiagnostics(source, lintsAt(this, source, ['kit.AppTapArea']));
  }

  Future<void> test_a_null_track_id_names_nothing() async {
    const body = 'Object f() => AppTapArea(onTap: handler, trackId: null);';
    await assertDiagnostics('$_kit$body', lintsAt(this, '$_kit$body', ['AppTapArea'], after: 'Object f()'));
  }

  Future<void> test_a_track_id_is_clean() async {
    await assertNoDiagnostics("${_kit}Object f(String id) => [AppTapArea(onTap: handler, trackId: 'a'), "
        'AppTapArea(trackId: id, onLongPress: handler)];');
  }

  Future<void> test_a_track_label_names_the_element() async {
    await assertNoDiagnostics("${_kit}Object f() => AppTapArea(onTap: handler, trackLabel: 'a');");
  }

  Future<void> test_a_null_track_label_names_nothing() async {
    const body = 'Object f() => AppTapArea(onTap: handler, trackLabel: null);';
    await assertDiagnostics('$_kit$body', lintsAt(this, '$_kit$body', ['AppTapArea'], after: 'Object f()'));
  }

  Future<void> test_tracked_false_is_clean() async {
    await assertNoDiagnostics('${_kit}Object f() => AppTapArea(onTap: handler, tracked: false);');
  }

  Future<void> test_tracked_true_is_reported() async {
    const body = 'Object f() => AppTapArea(onTap: handler, tracked: true);';
    await assertDiagnostics('$_kit$body', lintsAt(this, '$_kit$body', ['AppTapArea'], after: 'Object f()'));
  }

  Future<void> test_a_tracked_value_that_is_not_the_literal_false_is_reported() async {
    const body = 'Object f(bool on) => AppTapArea(onTap: handler, tracked: on);';
    await assertDiagnostics('$_kit$body', lintsAt(this, '$_kit$body', ['AppTapArea'], after: 'Object f('));
  }

  Future<void> test_both_sides_name_a_two_sided_control() async {
    await assertNoDiagnostics(
      "${_kit}Object f() => SegmentSwitch(onChanged: handler, leftTrackId: 'a', rightTrackId: 'b');",
    );
  }

  Future<void> test_a_two_sided_control_without_ids_is_reported() async {
    const body = 'Object f() => SegmentSwitch(onChanged: handler);';
    await assertDiagnostics(
      '$_kit$body',
      lintsAt(this, '$_kit$body', ['SegmentSwitch'], after: 'Object f()', messageContainsAll: ['onChanged']),
    );
  }

  Future<void> test_one_side_is_not_enough() async {
    const left = "Object f() => SegmentSwitch(onChanged: handler, leftTrackId: 'a');";
    await assertDiagnostics('$_kit$left', lintsAt(this, '$_kit$left', ['SegmentSwitch'], after: 'Object f()'));
    const right = "Object f() => SegmentSwitch(onChanged: handler, leftTrackId: null, rightTrackId: 'b');";
    final path = '$testPackageLibPath/pages/one_side.dart';
    newFile(path, '$_kit$right');
    await assertDiagnosticsInFile(path, lintsAt(this, '$_kit$right', ['SegmentSwitch'], after: 'Object f()'));
  }

  Future<void> test_a_two_sided_control_without_a_callback_is_clean() async {
    await assertNoDiagnostics('${_kit}Object f() => SegmentSwitch();');
  }

  Future<void> test_a_null_callback_is_clean() async {
    await assertNoDiagnostics('${_kit}Object f() => [AppTapArea(onTap: null), AppTapArea(onChanged: (null))];');
  }

  Future<void> test_no_callback_is_clean() async {
    await assertNoDiagnostics('${_kit}Object f() => [AppTapArea(), AppTapArea(onHover: handler)];');
  }

  Future<void> test_a_constructor_without_the_parameter_is_clean() async {
    await assertNoDiagnostics("${_kit}Object f() => CustomButton(label: 'a', onTap: handler);");
  }

  Future<void> test_a_positional_track_id_is_not_the_signal() async {
    await assertNoDiagnostics("${_kit}Object f() => PositionalId('a', onTap: handler);");
  }

  Future<void> test_a_generated_file_is_skipped() async {
    final path = '$testPackageLibPath/model/catalog.g.dart';
    newFile(path, '${_kit}Object f() => AppTapArea(onTap: handler);');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_files_outside_lib_are_skipped() async {
    final path = '$testPackageRootPath/test/page_test.dart';
    newFile(path, '${_kit}Object f() => AppTapArea(onTap: handler);');
    await assertNoDiagnosticsInFile(path);
  }
}
