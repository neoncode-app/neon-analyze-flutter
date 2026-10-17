/// Where an app keeps each kind of code.
///
/// The neon_lints rules and the neon_check runner never hard-code a folder:
/// they ask for a [LayoutRole] ("the pages", "the providers file") and the
/// app's [Layout] answers with path patterns. Every role has a default that
/// follows the shared Neon Code structure; an app whose structure differs
/// overrides only that role in the `layout:` section of its `neon_check.yaml`:
///
/// ```yaml
/// layout:
///   providers: lib/app/app_providers.dart   # one pattern or a list
///   routing: [lib/app/]
/// ```
///
/// Patterns are relative to the package root and use `/`:
///
/// * a pattern ending in `/` is a folder and matches everything below it;
/// * any other pattern matches one file;
/// * `*` matches within one path segment, `**/` any number of folders;
/// * `{name}` matches within one path segment like `*`, and every later
///   `{name}` must repeat the same text (`lib/flavors/{f}/{f}_router.dart`).
///
/// This library has no analyzer dependency, so the check runner imports it
/// too and both sides read the same defaults.
library;

import 'package:yaml/yaml.dart';

/// A kind of code whose location the rules and the checks depend on.
enum LayoutRole {
  pages('pages', ['lib/pages/'], 'Pages: one screen each, composed from templates.'),
  subtitledPages(
    'subtitled_pages',
    ['lib/pages/'],
    'Pages whose AppContentPage carries a subtitle under the title (page_has_title_subtitle).',
  ),
  features('features', ['lib/features/'], 'Feature widgets: read state (cubit, repository) or drive a flow.'),
  globalWidgets('global_widgets', ['lib/global_widgets/'], 'The widget kit: draws from parameters and the theme.'),
  bloc('bloc', ['lib/bloc/'], 'Cubits and their states.'),
  appWideCubits('app_wide_cubits', ['lib/bloc/*/app_wide/'], 'App-wide cubits provided by the shell.'),
  repository('repository', ['lib/repository/'], 'Repositories: the only code that talks to the API and storage.'),
  secureStorage(
    'secure_storage',
    ['lib/repository/shared_prefs_repository.dart'],
    'The secure store owner: the only FlutterSecureStorage, tokens only (keys in secure_storage_keys:).',
  ),
  model('model', ['lib/model/'], 'Data models and serialization.'),
  hive('hive', ['lib/hive/'],
      'Hive adapters (hive_adapters.dart, the generated registrar) and shared box declarations.'),
  enums(
    'enums',
    ['lib/model/enums/*/'],
    'Scope folders of the enums (common or a project): lib/model/enums/<scope>/<name>.dart, one enum per file.',
  ),
  roleEnums('role_enums', ['lib/model/enums/'], 'Role enums, the only place backend role strings appear.'),
  providers('providers', ['lib/flavors/{flavor}/{flavor}_providers.dart'], 'Typed context getters (context.xCubit).'),
  routing('routing', ['lib/flavors/'], 'Routing and shells: the only place cubits are provided.'),
  appRoot(
    'app_root',
    ['lib/app/bootstrap.dart'],
    'The app startup: builds the app-wide cubits and repositories the router needs and provides them above it.',
  ),
  routers('routers', ['lib/flavors/{flavor}/{flavor}_router.dart'], 'Files that declare the GoRoutes.'),
  dialogHelper('dialog_helper', ['lib/utils/utils.dart'], 'The one dialog helper (Utils.showCustomModalBottomSheet).'),
  tokens('tokens', ['lib/utils/ui/tokens/'], 'The dimension scale (AppSpacing, AppRadius, ...).'),
  widgetDimens('widget_dimens', ['lib/**/*_dimens.dart'], 'Per-widget dimensions (<Widget>Dimens).'),
  legacyDimens('legacy_dimens', ['lib/**/app_dimens.dart'], 'The old AppDimens, dissolved during the migration.'),
  textStyles(
    'text_styles',
    ['lib/**/*_text_styles.dart', 'lib/utils/ui/app_style.dart'],
    'Named text styles and the skin that assembles them.',
  ),
  colors(
    'colors',
    [
      '**/theme/',
      '**/ui/app_icon.dart',
      '**/ui/app_style.dart',
      'lib/model/',
      '**/color_editor*',
      '**/color_editor*/',
      // vernakapp: the contrast maths test needs arbitrary colour values.
      '**/test/readable_accent_test.dart',
      // Test fixtures: colour values that are inputs of a test, not UI colours.
      'test/support/',
    ],
    'Files that may define raw colors (theme, serialization, the color picker, test fixtures).',
  ),
  assetsRegistry('assets_registry', ['lib/**/app_assets.dart'], "The asset registry, the only place for 'assets/...'."),
  logger('logger', ['lib/utils/helpers/log_utils.dart'], 'The app logger, the only place for debugPrint.'),
  responsive('responsive', ['lib/utils/ui/app_responsive.dart'], 'Screen size classes and breakpoints.'),
  catalogPreviews('catalog_previews', ['lib/**/widget_catalog/previews/'], 'Widget catalog previews (sample texts).');

  const LayoutRole(this.key, this.defaults, this.description);

  /// Key in the `layout:` section of `neon_check.yaml`.
  final String key;

  /// Patterns used when the app does not override the role.
  final List<String> defaults;

  /// One line, for `neon-check explain`.
  final String description;

  static LayoutRole? byKey(String key) {
    for (final role in values) {
      if (role.key == key) return role;
    }
    return null;
  }
}

/// The resolved layout of one app.
final class Layout {
  Layout._(this._patterns, this.unknownKeys);

  /// The shared Neon Code structure: every role at its default.
  factory Layout.defaults() => Layout._({for (final role in LayoutRole.values) role: role.defaults}, const []);

  /// The layout described by the `layout:` section of a `neon_check.yaml`
  /// source; roles it does not name keep their defaults. A source that does
  /// not parse yields the defaults.
  factory Layout.fromConfigSource(String? source) {
    if (source == null) return Layout.defaults();
    Object? yaml;
    try {
      yaml = loadYaml(source);
    } on YamlException {
      return Layout.defaults();
    }
    final section = yaml is YamlMap ? yaml['layout'] : null;
    return Layout.fromMap(section is Map ? section : const {});
  }

  /// The layout described by a parsed `layout:` map.
  factory Layout.fromMap(Map<Object?, Object?> section) {
    final patterns = {for (final role in LayoutRole.values) role: role.defaults};
    final unknown = <String>[];
    for (final entry in section.entries) {
      final key = '${entry.key}';
      final role = LayoutRole.byKey(key);
      if (role == null) {
        unknown.add(key);
        continue;
      }
      final value = entry.value;
      patterns[role] = value is List ? [for (final item in value) '$item'] : ['$value'];
    }
    return Layout._(patterns, unknown);
  }

  final Map<LayoutRole, List<String>> _patterns;

  /// Keys of the `layout:` section that name no role (a typo).
  final List<String> unknownKeys;

  List<String> patterns(LayoutRole role) => _patterns[role] ?? role.defaults;

  /// Whether the root-relative [path] belongs to [role].
  bool matches(LayoutRole role, String path) => patterns(role).any((pattern) => matchesLayoutPattern(pattern, path));

  /// App code: a root-relative file under `lib/` that is not generated.
  static bool isAppSource(String path) =>
      path.startsWith('lib/') && !path.endsWith('.g.dart') && !path.endsWith('.freezed.dart');

  /// UI code: pages, features and the widget kit.
  bool isUi(String path) =>
      matches(LayoutRole.pages, path) || matches(LayoutRole.features, path) || matches(LayoutRole.globalWidgets, path);

  /// The patterns of [role] for a message (`lib/a/, lib/b.dart`).
  String describe(LayoutRole role) => patterns(role).join(', ');
}

final _patternCache = <String, RegExp>{};

/// Whether the root-relative [path] matches the layout [pattern] (see the
/// library documentation for the syntax).
bool matchesLayoutPattern(String pattern, String path) {
  final regex = _patternCache.putIfAbsent(pattern, () {
    final folder = pattern.endsWith('/');
    final buffer = StringBuffer('^');
    final named = <String>{};
    for (var i = 0; i < pattern.length; i++) {
      final char = pattern[i];
      if (pattern.startsWith('**/', i)) {
        buffer.write('(?:.*/)?');
        i += 2;
      } else if (pattern.startsWith('**', i)) {
        buffer.write('.*');
        i++;
      } else if (char == '*') {
        buffer.write('[^/]*');
      } else if (char == '{' && pattern.indexOf('}', i) > i + 1) {
        final end = pattern.indexOf('}', i);
        final name = pattern.substring(i + 1, end).replaceAll(RegExp('[^A-Za-z0-9]'), '');
        buffer.write(named.add(name) ? '(?<$name>[^/]+)' : '\\k<$name>');
        i = end;
      } else {
        buffer.write(RegExp.escape(char));
      }
    }
    if (!folder) buffer.write(r'$');
    return RegExp(buffer.toString());
  });
  return regex.hasMatch(path);
}
