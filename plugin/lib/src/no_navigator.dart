import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/banned_api/banned_api.dart';

/// Bans the imperative `Navigator` API (`Navigator.of`, `.pop`, `.push`,
/// `.maybePop`, every other static member, and building a `Navigator`).
///
/// Navigation goes through go_router: `context.pop` closes a dialog or a
/// route, `context.go` / `context.push` navigate, and UI asks a cubit for
/// navigation with a `NavigateTo` event. Holding a `NavigatorState` type or
/// passing `useRootNavigator:` is not flagged.
///
/// No file owns this API (NCR0000014 decision 11: forbidden everywhere), so
/// the table row has no owners. Opt-in per app (`registerLintRule`): apps
/// that do not route with go_router keep `Navigator`.
class NoNavigator extends BannedApiRule {
  NoNavigator() : super(name: 'no_navigator', description: _desc);

  static const _desc = 'Navigate with go_router, never with Navigator.';

  static final LintCode code = bannedApiCode('no_navigator', what: 'imperative navigation');

  static const rows = <BannedApi>[
    BannedApi(
      label: 'Navigator',
      replacement: 'context.pop / context.go / context.push (go_router)',
      types: {'Navigator'},
    ),
  ];

  @override
  List<BannedApi> get table => rows;

  @override
  DiagnosticCode get diagnosticCode => code;
}
