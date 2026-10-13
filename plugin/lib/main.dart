import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'package:neon_lints/src/alert_only_in_cubit.dart';
import 'package:neon_lints/src/avoid_bang.dart';
import 'package:neon_lints/src/cancel_subscriptions_in_close.dart';
import 'package:neon_lints/src/cubit_created_in_provider.dart';
import 'package:neon_lints/src/dialog_only_in_listener.dart';
import 'package:neon_lints/src/dimens_rules.dart';
import 'package:neon_lints/src/extend_base_cubit.dart';
import 'package:neon_lints/src/layering_rules.dart';
import 'package:neon_lints/src/listener_is_mapping.dart';
import 'package:neon_lints/src/no_cubit_call_in_lifecycle.dart';
import 'package:neon_lints/src/no_dialog_result.dart';
import 'package:neon_lints/src/no_navigation_in_ui.dart';
import 'package:neon_lints/src/no_navigator.dart';
import 'package:neon_lints/src/no_provider_value.dart';
import 'package:neon_lints/src/no_raw_asset_path.dart';
import 'package:neon_lints/src/no_raw_color.dart';
import 'package:neon_lints/src/no_state_enum_branching.dart';
import 'package:neon_lints/src/no_status_enum_state.dart';
import 'package:neon_lints/src/no_tr_in_global_widget.dart';
import 'package:neon_lints/src/no_widget_builder_method.dart';
import 'package:neon_lints/src/page_state_rules.dart';
import 'package:neon_lints/src/page_template_rules.dart';
import 'package:neon_lints/src/piece_rules.dart';
import 'package:neon_lints/src/provider_in_router.dart';
import 'package:neon_lints/src/responsive_rules.dart';
import 'package:neon_lints/src/role_rules.dart';
import 'package:neon_lints/src/state_is_sealed.dart';
import 'package:neon_lints/src/text_rules.dart';
import 'package:neon_lints/src/ui_callback_calls_cubit.dart';
import 'package:neon_lints/src/use_context_getters.dart';
import 'package:neon_lints/src/use_kit_widgets.dart';

/// Entry point the Dart Analysis Server imports to load this plugin.
final plugin = NeonLintsPlugin();

class NeonLintsPlugin extends Plugin {
  @override
  String get name => 'neon_lints';

  @override
  void register(PluginRegistry registry) {
    // Warning rules are ON by default in every app using the plugin.
    registry
      ..registerWarningRule(AvoidBang())
      ..registerWarningRule(ExtendBaseCubit())
      ..registerWarningRule(NoWidgetBuilderMethod())
      ..registerWarningRule(NoRawColor())
      ..registerWarningRule(NoRawAssetPath())
      ..registerWarningRule(NoTrInGlobalWidget())
      // Lint rules are OFF by default; an app opts in under
      // `plugins: neon_lints: diagnostics:` (see README). They encode the
      // neoncode admin architecture (go_router, the widget kit), which other
      // apps sharing this plugin do not follow.
      ..registerLintRule(UseKitWidgets())
      ..registerLintRule(NoNavigator())
      // NCR0000018: cubit lifecycle, providers, context getters, alerts, states.
      ..registerLintRule(UseContextGetters())
      ..registerLintRule(CubitCreatedInProvider())
      ..registerLintRule(ProviderInRouter())
      ..registerLintRule(NoCubitCallInLifecycle())
      ..registerLintRule(NoProviderValue())
      ..registerLintRule(CancelSubscriptionsInClose())
      ..registerLintRule(AlertOnlyInCubit())
      ..registerLintRule(StateIsSealed())
      ..registerLintRule(NoStatusEnumState())
      ..registerLintRule(NoStateEnumBranching())
      // NCR0000019: presentation events, dialogs, navigation, no logic in UI.
      ..registerLintRule(DialogOnlyInListener())
      ..registerLintRule(NoDialogResult())
      ..registerLintRule(ListenerIsMapping())
      ..registerLintRule(NoNavigationInUi())
      ..registerLintRule(UiCallbackCallsCubit())
      ..registerLintRule(NoSetStateInPages())
      ..registerLintRule(NoPrivateMethodsInPageState())
      ..registerLintRule(StatefulPageOnlyForControllers())
      ..registerLintRule(NoEditorControllerInPages())
      // NCR0000020: page templates, layering, route-level roles, responsiveness.
      ..registerLintRule(PageUsesTemplate())
      ..registerLintRule(PageHasTitleSubtitle())
      ..registerLintRule(GlobalWidgetsLayering())
      ..registerLintRule(ComponentHasNoStateAccess())
      ..registerLintRule(NoRepositoryInUi())
      ..registerLintRule(NoHttpInUi())
      ..registerLintRule(GlobalWidgetHasCategory())
      ..registerLintRule(KitSrcInternal())
      ..registerLintRule(NoRoleLiteral())
      ..registerLintRule(NoAccessGuardInPages())
      ..registerLintRule(NoMediaQuerySize())
      ..registerLintRule(NoKIsWebInUi())
      ..registerLintRule(NoPlatformInUi())
      ..registerLintRule(NoLayoutBuilderInPages())
      ..registerLintRule(NoRawBreakpoint())
      // NCR0000021: per-widget dimens, design tokens, text style, UI strings.
      ..registerLintRule(NoRawDimension())
      ..registerLintRule(DimensPrivateToWidget())
      ..registerLintRule(ScaleOnlyInDimens())
      ..registerLintRule(NoAppDimens())
      ..registerLintRule(ComponentTakesVariant())
      // NCC0000054: one folder per piece, with its dimens and skeleton.
      ..registerLintRule(PieceInOwnFolder())
      ..registerLintRule(PieceHasSkeleton())
      ..registerLintRule(NoRawTextStyle())
      ..registerLintRule(NoDebugPrint())
      ..registerLintRule(NoHardcodedUiString())
      ..registerLintRule(NoDashInStrings());
  }
}
