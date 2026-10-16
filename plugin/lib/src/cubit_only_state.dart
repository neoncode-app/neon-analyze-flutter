import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/banned_api/banned_api.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// State management is a Cubit extending `BaseCubit` with a sealed state, and
/// nothing else (NCC0000063): no `Bloc` with events, no `ChangeNotifier`, no
/// `StateNotifier`, no riverpod or GetX, and no `package:provider` providers
/// beside the ones flutter_bloc builds on (`BlocProvider`, `RepositoryProvider`
/// and the `context.read` / `watch` / `select` extensions stay).
///
/// The table below is the whole rule. Matching is type-resolved (declaring
/// package), so an app class called `Provider` is not flagged. A kit
/// controller (`SaveRequiredHintController extends ChangeNotifier`, like
/// Flutter's own `TextEditingController`) is local UI state of a kit
/// component, so the widget kit may extend `ChangeNotifier`; constructing a
/// bare `ChangeNotifier()` is banned everywhere. `ValueNotifier` is
/// `no_value_notifier_state`.
class CubitOnlyState extends BannedApiRule {
  CubitOnlyState() : super(name: 'cubit_only_state', description: _desc);

  static const _desc = 'Manage state with a Cubit extending BaseCubit and a sealed state, nothing else.';

  static final LintCode code = bannedApiCode('cubit_only_state', what: 'not how this app manages state');

  static const _cubit = 'a Cubit extending BaseCubit with a sealed state (one method per action, '
      'provided by the route, read through a context getter)';

  static const rows = <BannedApi>[
    BannedApi(
      label: 'extends Bloc (events)',
      replacement: _cubit,
      package: 'bloc',
      types: {'Bloc'},
      constructors: {},
      subclassing: true,
    ),
    BannedApi(
      label: 'extends / with ChangeNotifier outside the widget kit',
      replacement: _cubit,
      types: {'ChangeNotifier'},
      constructors: {},
      subclassing: true,
      exceptIn: {LayoutRole.globalWidgets},
    ),
    BannedApi(
      label: 'ChangeNotifier(',
      replacement: _cubit,
      types: {'ChangeNotifier'},
      constructors: {'new'},
    ),
    BannedApi(
      label: 'ChangeNotifierProvider / Provider / MultiProvider / Consumer (package:provider)',
      replacement: '$_cubit; BlocProvider / RepositoryProvider of flutter_bloc in the route',
      package: 'provider',
      types: {
        'Provider',
        'ChangeNotifierProvider',
        'ChangeNotifierProxyProvider',
        'ListenableProvider',
        'ListenableProxyProvider',
        'ValueListenableProvider',
        'MultiProvider',
        'ProxyProvider',
        'FutureProvider',
        'StreamProvider',
        'InheritedProvider',
        'DeferredInheritedProvider',
        'Consumer',
        'Consumer2',
        'Consumer3',
        'Consumer4',
        'Consumer5',
        'Consumer6',
        'Selector',
        'Selector2',
        'Selector3',
        'Selector4',
        'Selector5',
        'Selector6',
      },
    ),
    BannedApi(
      label: 'StateNotifier',
      replacement: _cubit,
      package: 'state_notifier',
      types: {'StateNotifier'},
      subclassing: true,
    ),
    BannedApi(
      label: 'package:riverpod',
      replacement: _cubit,
      package: 'riverpod',
      bansImport: true,
    ),
    BannedApi(
      label: 'package:flutter_riverpod',
      replacement: _cubit,
      package: 'flutter_riverpod',
      bansImport: true,
    ),
    BannedApi(
      label: 'package:hooks_riverpod',
      replacement: _cubit,
      package: 'hooks_riverpod',
      bansImport: true,
    ),
    BannedApi(
      label: 'package:get (GetX)',
      replacement: _cubit,
      package: 'get',
      bansImport: true,
    ),
  ];

  @override
  List<BannedApi> get table => rows;

  @override
  DiagnosticCode get diagnosticCode => code;
}
