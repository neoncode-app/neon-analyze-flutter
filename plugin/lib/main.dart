import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'package:neon_lints/src/avoid_bang.dart';

/// Entry point the Dart Analysis Server imports to load this plugin.
final plugin = NeonLintsPlugin();

class NeonLintsPlugin extends Plugin {
  @override
  String get name => 'neon_lints';

  @override
  void register(PluginRegistry registry) {
    // Warning rules are enabled by default (no analysis_options entry needed).
    registry.registerWarningRule(AvoidBang());
  }
}
