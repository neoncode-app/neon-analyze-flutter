import 'dart:io';

import 'package:yaml/yaml.dart';

/// The per-app configuration, read from `neon_check.yaml` at the app root.
///
/// Everything app-specific (languages, paths, suites) lives there, so the
/// runner itself is shared by every Neon Code Flutter app.
final class CheckConfig {
  CheckConfig._(this._yaml);

  factory CheckConfig.load(String root) {
    final file = File('$root/$fileName');
    if (!file.existsSync()) {
      throw StateError('$fileName not found in $root; every app using the check runner needs one.');
    }
    final yaml = loadYaml(file.readAsStringSync());
    return CheckConfig._(yaml is YamlMap ? yaml : YamlMap());
  }

  /// Builds a config from a YAML string (tests).
  factory CheckConfig.parse(String source) {
    final yaml = loadYaml(source);
    return CheckConfig._(yaml is YamlMap ? yaml : YamlMap());
  }

  static const fileName = 'neon_check.yaml';

  final YamlMap _yaml;

  YamlMap _section(String key) {
    final value = _yaml[key];
    return value is YamlMap ? value : YamlMap();
  }

  static List<String> _strings(Object? value) =>
      value is YamlList ? [for (final item in value) item.toString()] : const [];

  static String? _string(Object? value) => value?.toString();

  /// Base branch used by `--changed` when the branch records no `neonBase`.
  String? get defaultBase => _string(_yaml['default_base']);

  int get lineLength => (_yaml['line_length'] as int?) ?? 120;

  /// Folders `--all` formats, fixes and analyzes.
  List<String> get sourceDirs {
    final dirs = _strings(_yaml['source_dirs']);
    return dirs.isEmpty ? const ['lib', 'test', 'tool'] : dirs;
  }

  String get baselinePath => _string(_yaml['baseline']) ?? 'tool/lint_baseline.json';

  /// Path of the neon_lints plugin, to learn its rule names.
  String get pluginPath => _string(_yaml['plugin']) ?? 'neon-analyze-flutter/plugin';

  // Translations.
  YamlMap get _translations => _section('translations');
  String get translationsDir => _string(_translations['dir']) ?? 'assets/translations';
  List<String> get languages => _strings(_translations['languages']);
  String get primaryLanguage => _string(_translations['primary']) ?? languages.first;

  /// Keys (or `prefix*`) that count as used although no code names them.
  List<String> get translationsAllowedUnused => _strings(_translations['allowed_unused']);

  // Assets.
  YamlMap get _assets => _section('assets');
  List<String> get assetRegistries => _strings(_assets['registries']);
  List<String> get assetDirs => _strings(_assets['dirs']);

  // Widget catalog.
  YamlMap get _catalog => _section('catalog');
  bool get hasCatalog => _catalog.isNotEmpty;
  String get catalogGenerator => _string(_catalog['generator']) ?? '';
  String get catalogIndex => _string(_catalog['index']) ?? '';
  String get catalogPreviews => _string(_catalog['previews']) ?? '';
  List<String> get catalogInputs => _strings(_catalog['inputs']);
  List<String> get catalogPreviewRequired => _strings(_catalog['preview_required']);

  // Context getters vs provided cubits.
  List<String> get providerFlavors => _strings(_section('providers')['flavors']);

  // Page help.
  YamlMap get _pageHelp => _section('page_help');
  bool get hasPageHelp => _pageHelp.isNotEmpty;
  String get pageHelpPages => _string(_pageHelp['pages']) ?? '';
  String get pageHelpPagePrefix => _string(_pageHelp['page_prefix']) ?? '';
  List<String> get pageHelpExempt => _strings(_pageHelp['exempt']);
  String get pageHelpEnum => _string(_pageHelp['enum']) ?? '';
  String get pageHelpKeyPrefix => _string(_pageHelp['key_prefix']) ?? '';

  // Generated code.
  bool get generatedEnabled => _section('generated')['enabled'] == true;

  // Tests.
  YamlMap get _tests => _section('tests');
  String get testDir => _string(_tests['dir']) ?? 'test';

  /// The suite that always runs and owns every test outside other suites.
  String get defaultSuite => _string(_tests['default_suite']) ?? 'app';

  /// Source globs whose change runs every suite.
  List<String> get sharedSources => _strings(_tests['shared']);

  /// Named suites: their test folders and the source globs that select them.
  Map<String, ({List<String> tests, List<String> sources})> get suites {
    final suites = _tests['suites'];
    if (suites is! YamlMap) return const {};
    return {
      for (final entry in suites.entries)
        entry.key.toString(): (
          tests: _strings((entry.value as YamlMap?)?['tests']),
          sources: _strings((entry.value as YamlMap?)?['sources']),
        ),
    };
  }

  /// Command that runs the integration tests in `--all` mode, if any.
  List<String> get integrationCommand => _strings(_tests['integration_command']);
}
