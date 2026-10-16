import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/banned_api/banned_api.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// No `ValueNotifier` as app state (NCC0000063): outside the widget kit a
/// `ValueNotifier(...)` is never constructed and never extended; the value is
/// a field of a cubit's state, a cubit method changes it and the widget reads
/// it through its context getter.
///
/// `ValueNotifier` / `ValueListenable` keep two uses, neither flagged here:
/// reading one (a Hive `listenable()` through the neon-flutter-hive builders,
/// Flutter controllers that are ValueNotifiers such as `TextEditingController`
/// and `AnimationController`, which are not `ValueNotifier(` constructions),
/// and local UI state of a kit component (hover, an open menu, the crop
/// editor's gesture state), which is why the widget kit owns the API.
class NoValueNotifierState extends BannedApiRule {
  NoValueNotifierState() : super(name: 'no_value_notifier_state', description: _desc);

  static const _desc = 'No ValueNotifier as app state outside the widget kit; the cubit state holds the value.';

  static final LintCode code = bannedApiCode('no_value_notifier_state', what: 'app state outside the cubits');

  static const rows = <BannedApi>[
    BannedApi(
      label: 'ValueNotifier( / extends ValueNotifier outside the widget kit',
      replacement: 'a field of the cubit state: a cubit method changes it, the widget reads it through its '
          'context getter (local UI state of a kit component stays in lib/global_widgets)',
      types: {'ValueNotifier'},
      constructors: {'new'},
      subclassing: true,
      exceptIn: {LayoutRole.globalWidgets},
    ),
  ];

  @override
  List<BannedApi> get table => rows;

  @override
  DiagnosticCode get diagnosticCode => code;
}
