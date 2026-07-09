import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'package:neon_lints/src/avoid_bang.dart';
import 'package:neon_lints/src/extend_base_cubit.dart';
import 'package:neon_lints/src/no_raw_asset_path.dart';
import 'package:neon_lints/src/no_raw_color.dart';
import 'package:neon_lints/src/no_tr_in_global_widget.dart';
import 'package:neon_lints/src/no_widget_builder_method.dart';

/// Entry point the Dart Analysis Server imports to load this plugin.
final plugin = NeonLintsPlugin();

class NeonLintsPlugin extends Plugin {
  @override
  String get name => 'neon_lints';

  @override
  void register(PluginRegistry registry) {
    // Warning rules are enabled by default (no analysis_options entry needed).
    registry.registerWarningRule(AvoidBang());
    registry.registerWarningRule(ExtendBaseCubit());
    registry.registerWarningRule(NoWidgetBuilderMethod());
    registry.registerWarningRule(NoRawColor());
    registry.registerWarningRule(NoRawAssetPath());
    registry.registerWarningRule(NoTrInGlobalWidget());
  }
}
