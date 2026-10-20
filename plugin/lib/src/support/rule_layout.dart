import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/file_system/file_system.dart';

import 'package:neon_lints/layout.dart';
import 'package:yaml/yaml.dart';

export 'package:neon_lints/layout.dart' show Layout, LayoutRole;

/// The [Layout] of the package a rule is analysing, with its root, so a rule
/// asks "is this file a page" instead of hard-coding `lib/pages/`.
///
/// The `layout:` section is read from the package's `neon_check.yaml`
/// through the analyzer's resource provider (so tests can provide one) and
/// cached until the file changes.
final class RuleLayout {
  RuleLayout(this.root, this.layout,
      {this.secureStorageKeys = const [], this.preset, this.kit = const {}, this.backActions = const {}});

  /// The layout of the package [context] analyses.
  factory RuleLayout.of(RuleContext context) {
    final file = context.definingUnit.file;
    final root = _rootOf(context, file.path.replaceAll(r'\', '/'));
    final config = file.provider.getFile('$root/$configFileName');
    final stamp = config.exists ? config.modificationStamp : -1;
    final cached = _cache[root];
    if (cached != null && cached.stamp == stamp) return cached.layout;
    String? source;
    if (stamp >= 0) {
      try {
        source = config.readAsStringSync();
      } on FileSystemException {
        source = null;
      }
    }
    final layout = RuleLayout(
      root,
      Layout.fromConfigSource(source, flavorsFolder: file.provider.getFolder('$root/lib/flavors').exists),
      secureStorageKeys: _secureStorageKeys(source),
      preset: _preset(source),
      kit: kitOf(source),
      backActions: _backActions(source),
    );
    _cache[root] = (stamp: stamp, layout: layout);
    return layout;
  }

  static const configFileName = 'neon_check.yaml';

  /// `secure_storage_keys:` of the config: the key VALUES the secure store
  /// may write (rule secure_storage_keys).
  static List<String> _secureStorageKeys(String? source) {
    if (source == null) return const [];
    Object? yaml;
    try {
      yaml = loadYaml(source);
    } on YamlException {
      return const [];
    }
    final value = yaml is YamlMap ? yaml['secure_storage_keys'] : null;
    return value is YamlList ? [for (final item in value) '$item'] : const [];
  }

  static String? _preset(String? source) {
    final yaml = _yaml(source);
    final value = yaml is YamlMap ? yaml['preset'] : null;
    return value == null ? null : '$value';
  }

  /// The `kit:` section of a config: which kit widget of the app replaces each
  /// banned raw API, by row id (rule use_kit_widgets):
  ///
  /// ```yaml
  /// kit:
  ///   gesture_detector: {use: AppTapArea, owners: [lib/global_widgets/behaviors/app_tap_area/]}
  /// ```
  ///
  /// Owners are root-relative files or folders (a folder ends with `/`).
  static Map<String, KitReplacement> kitOf(String? source) {
    final yaml = _yaml(source);
    final section = yaml is YamlMap ? yaml['kit'] : null;
    if (section is! YamlMap) return const {};
    return {
      for (final entry in section.entries)
        if (entry.value is YamlMap)
          '${entry.key}': KitReplacement(
            '${(entry.value as YamlMap)['use'] ?? ''}',
            switch ((entry.value as YamlMap)['owners']) {
              final YamlList list => [for (final item in list) '$item'],
              final Object value => ['$value'],
              null => const [],
            },
          ),
    };
  }

  /// `back_actions:` of a config: widget class -> the parameter holding the
  /// action the system back must run too (rule pop_scope_matches_back_action).
  static Map<String, String> _backActions(String? source) {
    final yaml = _yaml(source);
    final section = yaml is YamlMap ? yaml['back_actions'] : null;
    if (section is! YamlMap) return const {};
    return {for (final entry in section.entries) '${entry.key}': '${entry.value}'};
  }

  static Object? _yaml(String? source) {
    if (source == null) return null;
    try {
      return loadYaml(source);
    } on YamlException {
      return null;
    }
  }

  static final _cache = <String, ({int stamp, RuleLayout layout})>{};

  /// Forgets every cached config. Tests need it: each test gets a fresh
  /// in-memory file system whose modification stamps start over, so a config
  /// written by an earlier test would otherwise be served again.
  static void clearCache() => _cache.clear();

  static String _rootOf(RuleContext context, String path) {
    final packageRoot = context.package?.root.path.replaceAll(r'\', '/');
    if (packageRoot != null && path.startsWith('$packageRoot/')) return packageRoot;
    final lib = path.indexOf('/lib/');
    return lib < 0 ? path.substring(0, path.lastIndexOf('/')) : path.substring(0, lib);
  }

  /// Absolute package root, without a trailing slash.
  final String root;

  final Layout layout;

  /// Key values the secure store may write (`secure_storage_keys:`).
  final List<String> secureStorageKeys;

  /// `preset:` of the config (`admin`, `app`), or `null`.
  final String? preset;

  /// The app's kit, by row id of use_kit_widgets (`kit:`).
  final Map<String, KitReplacement> kit;

  /// Widgets whose action the system back runs too, with the parameter that
  /// holds it (`back_actions:`).
  final Map<String, String> backActions;

  /// [path] (absolute) relative to the root, or `null` outside the package.
  String? relative(String path) {
    final normalized = path.replaceAll(r'\', '/');
    return normalized.startsWith('$root/') ? normalized.substring(root.length + 1) : null;
  }

  /// App code: a file of this package under `lib/` that is not generated.
  bool isAppSource(String path) {
    final rel = relative(path);
    return rel != null && Layout.isAppSource(rel);
  }

  /// Whether the absolute [path] is a file of this package in [role].
  bool isIn(String path, LayoutRole role) {
    final rel = relative(path);
    return rel != null && layout.matches(role, rel);
  }

  /// App UI code: pages, features and the widget kit.
  bool isUi(String path) {
    final rel = relative(path);
    return rel != null && Layout.isAppSource(rel) && layout.isUi(rel);
  }

  /// Absolute folder of a role whose first pattern is a plain folder
  /// (`lib/bloc/` -> `<root>/lib/bloc/`), for import-target checks.
  List<String> absoluteFolders(LayoutRole role) => [
        for (final pattern in layout.patterns(role))
          if (pattern.endsWith('/') && !pattern.contains('*')) '$root/$pattern',
      ];

  /// The patterns of [role], for a message.
  String describe(LayoutRole role) => layout.describe(role);
}

/// The kit widget an app uses instead of one banned raw API (`kit:` entry).
final class KitReplacement {
  const KitReplacement(this.use, this.owners);

  /// The widget to use, named in the message (`AppTapArea`).
  final String use;

  /// Root-relative files and folders that implement it (may use the raw API).
  final List<String> owners;
}
