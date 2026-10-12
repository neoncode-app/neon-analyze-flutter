import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/file_system/file_system.dart';

import 'package:neon_lints/layout.dart';

export 'package:neon_lints/layout.dart' show Layout, LayoutRole;

/// The [Layout] of the package a rule is analysing, with its root, so a rule
/// asks "is this file a page" instead of hard-coding `lib/pages/`.
///
/// The `layout:` section is read from the package's `neon_check.yaml`
/// through the analyzer's resource provider (so tests can provide one) and
/// cached until the file changes.
final class RuleLayout {
  RuleLayout(this.root, this.layout);

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
    final layout = RuleLayout(root, Layout.fromConfigSource(source));
    _cache[root] = (stamp: stamp, layout: layout);
    return layout;
  }

  static const configFileName = 'neon_check.yaml';

  static final _cache = <String, ({int stamp, RuleLayout layout})>{};

  static String _rootOf(RuleContext context, String path) {
    final packageRoot = context.package?.root.path.replaceAll(r'\', '/');
    if (packageRoot != null && path.startsWith('$packageRoot/')) return packageRoot;
    final lib = path.indexOf('/lib/');
    return lib < 0 ? path.substring(0, path.lastIndexOf('/')) : path.substring(0, lib);
  }

  /// Absolute package root, without a trailing slash.
  final String root;

  final Layout layout;

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
