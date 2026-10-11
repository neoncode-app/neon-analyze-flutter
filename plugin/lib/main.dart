import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'package:neon_lints/src/alert_only_in_cubit.dart';
import 'package:neon_lints/src/avoid_bang.dart';
import 'package:neon_lints/src/cancel_subscriptions_in_close.dart';
import 'package:neon_lints/src/cubit_created_in_provider.dart';
import 'package:neon_lints/src/dialog_only_in_listener.dart';
import 'package:neon_lints/src/extend_base_cubit.dart';
import 'package:neon_lints/src/listener_is_mapping.dart';
import 'package:neon_lints/src/no_cubit_call_in_lifecycle.dart';
import 'package:neon_lints/src/no_dialog_result.dart';
import 'package:neon_lints/src/no_navigation_in_ui.dart';
import 'package:neon_lints/src/no_navigator.dart';
import 'package:neon_lints/src/no_provider_value.dart';
import 'package:neon_lints/src/no_raw_asset_path.dart';
import 'package:neon_lints/src/no_raw_color.dart';
import 'package:neon_lints/src/no_status_enum_state.dart';
import 'package:neon_lints/src/no_tr_in_global_widget.dart';
import 'package:neon_lints/src/no_widget_builder_method.dart';
import 'package:neon_lints/src/page_state_rules.dart';
import 'package:neon_lints/src/provider_in_router.dart';
import 'package:neon_lints/src/state_is_sealed.dart';
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
    registry.registerWarningRule(AvoidBang());
    registry.registerWarningRule(ExtendBaseCubit());
    registry.registerWarningRule(NoWidgetBuilderMethod());
    registry.registerWarningRule(NoRawColor());
    registry.registerWarningRule(NoRawAssetPath());
    registry.registerWarningRule(NoTrInGlobalWidget());

    // Lint rules are OFF by default; an app opts in under
    // `plugins: neon_lints: diagnostics:` (see README). They encode the
    // neoncode admin architecture (go_router, the widget kit), which other
    // apps sharing this plugin do not follow.
    registry.registerLintRule(UseKitWidgets());
    registry.registerLintRule(NoNavigator());
    // NCR0000018: cubit lifecycle, providers, context getters, alerts, states.
    registry.registerLintRule(UseContextGetters());
    registry.registerLintRule(CubitCreatedInProvider());
    registry.registerLintRule(ProviderInRouter());
    registry.registerLintRule(NoCubitCallInLifecycle());
    registry.registerLintRule(NoProviderValue());
    registry.registerLintRule(CancelSubscriptionsInClose());
    registry.registerLintRule(AlertOnlyInCubit());
    registry.registerLintRule(StateIsSealed());
    registry.registerLintRule(NoStatusEnumState());
    // NCR0000019: presentation events, dialogs, navigation, no logic in UI.
    registry.registerLintRule(DialogOnlyInListener());
    registry.registerLintRule(NoDialogResult());
    registry.registerLintRule(ListenerIsMapping());
    registry.registerLintRule(NoNavigationInUi());
    registry.registerLintRule(UiCallbackCallsCubit());
    registry.registerLintRule(NoSetStateInPages());
    registry.registerLintRule(NoPrivateMethodsInPageState());
    registry.registerLintRule(StatefulPageOnlyForControllers());
    registry.registerLintRule(NoEditorControllerInPages());
  }
}
