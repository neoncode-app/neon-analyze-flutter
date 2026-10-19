import 'dart:io';

import 'package:neon_lints/layout.dart';
import 'package:yaml/yaml.dart';

/// How the integration flows are selected in a run.
enum IntegrationMode {
  /// No integration flow runs.
  off,

  /// The flows of the suites the change touches.
  affected,

  /// Every flow.
  all,

  /// The affected flows, started detached so the run does not wait for them;
  /// the next run reports their result (`stop` trigger, NCC0000075).
  background;

  static IntegrationMode parse(Object? value, IntegrationMode fallback) {
    for (final mode in values) {
      if (mode.name == '$value') return mode;
    }
    return fallback;
  }
}

/// One named group of rules and steps (`packs.yaml`).
final class Pack {
  const Pack({
    required this.name,
    required this.description,
    required this.rules,
    required this.steps,
    this.where = const {},
  });

  final String name;
  final String description;

  /// neon_lints rule names.
  final List<String> rules;

  /// neon-check step names.
  final List<String> steps;

  /// Which code a rule is about: layout role keys or `ui`; a rule not listed
  /// is about all app code.
  final Map<String, List<String>> where;

  /// Whether [rule] is about a file with [roles] (role keys, `ui` included).
  bool ruleApplies(String rule, Set<String> roles) {
    final scope = where[rule];
    return scope == null || scope.any(roles.contains);
  }
}

/// When a run happens (`triggers:`): what it looks at and what it runs.
final class Trigger {
  const Trigger({
    required this.name,
    required this.scope,
    required this.steps,
    required this.ci,
    required this.integration,
  });

  final String name;

  /// `files`, `changed`, `staged` or `all`.
  final String scope;

  /// Step names, or a single `all` / `static`.
  final List<String> steps;

  final bool ci;

  final IntegrationMode integration;
}

/// What the tool finds out about an app by looking at it.
final class ProjectFacts {
  const ProjectFacts({
    this.name = '',
    this.flavors = const [],
    this.languages = const [],
    this.platforms = const [],
  });

  /// Detects the facts of the app at [root].
  factory ProjectFacts.detect(String root, {String translationsDir = 'assets/translations'}) {
    final pubspec = File('$root/pubspec.yaml');
    var name = '';
    if (pubspec.existsSync()) {
      final yaml = loadYaml(pubspec.readAsStringSync());
      if (yaml is YamlMap) name = '${yaml['name'] ?? ''}';
    }
    final flavors = <String>{};
    final flavorsDir = Directory('$root/lib/flavors');
    if (flavorsDir.existsSync()) {
      for (final entity in flavorsDir.listSync()) {
        if (entity is Directory) flavors.add(entity.uri.pathSegments.where((s) => s.isNotEmpty).last);
      }
    }
    final libDir = Directory('$root/lib');
    if (libDir.existsSync()) {
      for (final entity in libDir.listSync()) {
        final match = RegExp(r'/main_(\w+)\.dart$').firstMatch(entity.path.replaceAll(r'\', '/'));
        if (entity is File && match != null) flavors.add(match.group(1) ?? '');
      }
    }
    flavors.remove('');
    final languages = <String>[];
    final translations = Directory('$root/$translationsDir');
    if (translations.existsSync()) {
      for (final entity in translations.listSync()) {
        final file = entity.uri.pathSegments.last;
        if (entity is File && file.endsWith('.json')) languages.add(file.substring(0, file.length - 5));
      }
    }
    return ProjectFacts(
      name: name,
      flavors: flavors.toList()..sort(),
      languages: languages..sort(),
      platforms: [
        for (final platform in const ['web', 'android', 'ios', 'linux', 'macos', 'windows'])
          if (Directory('$root/$platform').existsSync()) platform,
      ],
    );
  }

  final String name;
  final List<String> flavors;
  final List<String> languages;
  final List<String> platforms;
}

/// The configuration of one app: `presets/base.yaml`, then the preset the
/// app names, then the app's own `neon_check.yaml`, merged in that order
/// (maps key by key; a list or a value replaces), plus the facts the tool
/// detects ([ProjectFacts]) for everything the app does not set.
final class CheckConfig {
  CheckConfig._(
    this._yaml, {
    required this.layout,
    required this.facts,
    required this.allPacks,
    required this.packsGiven,
    required this.errors,
    this.root,
    this.presetName,
  });

  /// Loads the configuration of the app at [root]; [toolRoot] is the
  /// neon-analyze-flutter checkout that holds `packs.yaml` and `presets/`.
  factory CheckConfig.load(String root, {String? toolRoot}) {
    final file = File('$root/$fileName');
    if (!file.existsSync()) {
      throw StateError('$fileName not found in $root; create one with `neon-check init`.');
    }
    final tool = toolRoot ?? '$root/neon-analyze-flutter';
    final errors = <String>[];
    final app = _plain(_loadYaml(file.readAsStringSync(), fileName, errors));
    final appMap = app is Map<String, Object?> ? app : <String, Object?>{};
    final base = _readMap('$tool/presets/base.yaml', errors);
    final presetName = appMap['preset']?.toString();
    var preset = <String, Object?>{};
    if (presetName != null) {
      final presetFile = File('$tool/presets/$presetName.yaml');
      if (presetFile.existsSync()) {
        preset = _readMap(presetFile.path, errors);
      } else {
        final known = Directory('$tool/presets').existsSync()
            ? [
                for (final entity in Directory('$tool/presets').listSync())
                  if (entity.path.endsWith('.yaml') && !entity.path.endsWith('/base.yaml'))
                    entity.uri.pathSegments.last.replaceAll('.yaml', ''),
              ]
            : const <String>[];
        errors.add('preset `$presetName` does not exist (known: ${known.join(', ')})');
      }
    }
    for (final (name, map) in [('base', base), (presetName ?? '', preset)]) {
      if (map.containsKey('layout')) {
        errors.add('preset `$name` sets `layout:`; layout belongs only in $fileName (the plugin reads it there)');
      }
    }
    final appTree = appMap['tree'];
    if (appTree is Map<String, Object?>) {
      for (final key in appTree.keys.where((key) => key != 'use')) {
        errors.add('tree: `$key` is fixed by the base preset; an app only switches optional folders on with `use:`');
      }
    }
    final merged = _merge(_merge(base, preset), appMap);
    final layoutSection = appMap['layout'];
    final layout = Layout.fromMap(layoutSection is Map ? layoutSection : const {});
    for (final key in layout.unknownKeys) {
      errors.add('layout: `$key` is not a role (roles: ${LayoutRole.values.map((role) => role.key).join(', ')})');
    }
    final translations = merged['translations'];
    final facts = ProjectFacts.detect(
      root,
      translationsDir: translations is Map ? '${translations['dir'] ?? 'assets/translations'}' : 'assets/translations',
    );
    final config = CheckConfig._(
      merged,
      layout: layout,
      facts: facts,
      allPacks: loadPacks('$tool/packs.yaml', errors),
      packsGiven: true,
      errors: errors,
      root: root,
      presetName: presetName,
    );
    config._validate();
    return config;
  }

  /// Builds a config from a YAML string alone: no preset, no detection, and
  /// every step enabled (tests).
  factory CheckConfig.parse(String source, {List<Pack> packs = const [], ProjectFacts facts = const ProjectFacts()}) {
    final errors = <String>[];
    final yaml = _plain(_loadYaml(source, 'source', errors));
    final map = yaml is Map<String, Object?> ? yaml : <String, Object?>{};
    final layoutSection = map['layout'];
    return CheckConfig._(
      map,
      layout: Layout.fromMap(layoutSection is Map ? layoutSection : const {}),
      facts: facts,
      allPacks: packs,
      packsGiven: map.containsKey('packs'),
      errors: errors,
    );
  }

  static const fileName = 'neon_check.yaml';

  final Map<String, Object?> _yaml;

  /// The app root this config was loaded for (`null` for [CheckConfig.parse]).
  final String? root;

  /// The preset the app names, if any.
  final String? presetName;

  final Layout layout;

  final ProjectFacts facts;

  /// Every pack of `packs.yaml`, in file order.
  final List<Pack> allPacks;

  /// Whether packs decide which steps run; a [CheckConfig.parse] config
  /// without a `packs:` key runs every step.
  final bool packsGiven;

  /// Problems in the configuration itself, reported by the `config_sync`
  /// step as hard failures.
  final List<String> errors;

  // ---------------------------------------------------------------- loading

  static Object? _loadYaml(String source, String name, List<String> errors) {
    try {
      return loadYaml(source);
    } on YamlException catch (error) {
      errors.add('$name does not parse: ${error.message}');
      return null;
    }
  }

  static Map<String, Object?> _readMap(String path, List<String> errors) {
    final file = File(path);
    if (!file.existsSync()) {
      errors.add('${file.uri.pathSegments.last} is missing in the neon-analyze-flutter checkout ($path)');
      return {};
    }
    final value = _plain(_loadYaml(file.readAsStringSync(), path, errors));
    return value is Map<String, Object?> ? value : {};
  }

  /// YAML nodes as plain maps and lists, so they can be merged.
  static Object? _plain(Object? value) {
    if (value is YamlMap) return {for (final entry in value.entries) '${entry.key}': _plain(entry.value)};
    if (value is YamlList) return [for (final item in value) _plain(item)];
    return value;
  }

  /// [over] merged over [base]: maps key by key, anything else replaces.
  static Map<String, Object?> _merge(Map<String, Object?> base, Map<String, Object?> over) {
    final result = {...base};
    for (final entry in over.entries) {
      final current = result[entry.key];
      final value = entry.value;
      result[entry.key] =
          current is Map<String, Object?> && value is Map<String, Object?> ? _merge(current, value) : value;
    }
    return result;
  }

  /// The packs of `packs.yaml` at [path].
  static List<Pack> loadPacks(String path, [List<String>? errors]) {
    final file = File(path);
    if (!file.existsSync()) {
      errors?.add('packs.yaml is missing ($path)');
      return const [];
    }
    final yaml = _plain(loadYaml(file.readAsStringSync()));
    if (yaml is! Map<String, Object?>) return const [];
    return [
      for (final entry in yaml.entries)
        if (entry.value is Map<String, Object?>)
          Pack(
            name: entry.key,
            description: '${(entry.value as Map<String, Object?>)['description'] ?? ''}',
            rules: _stringsOf((entry.value as Map<String, Object?>)['rules']),
            steps: _stringsOf((entry.value as Map<String, Object?>)['steps']),
            where: {
              if ((entry.value as Map<String, Object?>)['where'] case final Map<String, Object?> where)
                for (final rule in where.entries) rule.key: _stringsOf(rule.value),
            },
          ),
    ];
  }

  void _validate() {
    final known = {for (final pack in allPacks) pack.name};
    for (final name in [..._strings(_yaml['packs']), ..._strings(_yaml['skip_packs'])]) {
      if (!known.contains(name)) errors.add('pack `$name` does not exist (packs: ${known.join(', ')})');
    }
    final rules = {for (final pack in allPacks) ...pack.rules};
    for (final rule in ruleOverrides.keys) {
      if (!rules.contains(rule)) errors.add('rules: `$rule` is not a neon_lints rule of any pack');
    }
    for (final folder in treeUse) {
      if (!treeOptional.contains(folder)) {
        errors.add('tree: `$folder` is not an optional folder of the lib/ tree (optional: ${treeOptional.join(', ')})');
      }
    }
    for (final value in ruleOverrides.values) {
      if (!const {'true', 'false', 'error', 'warning', 'info'}.contains(value)) {
        errors.add('rules: `$value` is not one of true, false, error, warning, info');
      }
    }
    if (!const {'impact', 'suites'}.contains(testsSelect)) {
      errors.add('tests.select: `$testsSelect` is not one of impact, suites');
    }
    for (final entry in _section('triggers').entries) {
      final mode = entry.value is Map<String, Object?> ? (entry.value as Map<String, Object?>)['integration'] : null;
      if (mode != null && !IntegrationMode.values.any((value) => value.name == '$mode')) {
        errors.add('triggers.${entry.key}.integration: `$mode` is not one of '
            '${IntegrationMode.values.map((value) => value.name).join(', ')}');
      }
    }
  }

  // ---------------------------------------------------------------- helpers

  Map<String, Object?> _section(String key, [Map<String, Object?>? from]) {
    final value = (from ?? _yaml)[key];
    return value is Map<String, Object?> ? value : const {};
  }

  static List<String> _stringsOf(Object? value) =>
      value is List ? [for (final item in value) '$item'] : (value == null ? const [] : ['$value']);

  static List<String> _strings(Object? value) => _stringsOf(value);

  static String? _string(Object? value) => value?.toString();

  /// [patterns] expanded to the root-relative files that exist.
  List<String> _expand(List<String> patterns) {
    final appRoot = root;
    if (appRoot == null) return const [];
    return expandLayoutPatterns(appRoot, patterns);
  }

  // ---------------------------------------------------------------- packs

  /// Names of the enabled packs.
  List<String> get enabledPacks {
    if (!packsGiven) return [for (final pack in allPacks) pack.name];
    final skipped = _strings(_yaml['skip_packs']).toSet();
    return [
      for (final name in _strings(_yaml['packs']))
        if (!skipped.contains(name)) name,
    ];
  }

  bool packEnabled(String name) => !packsGiven || enabledPacks.contains(name);

  /// Whether a step runs at all in this app: some enabled pack lists it. A
  /// step no pack lists runs (a configuration without `packs.yaml`).
  bool stepEnabled(String step) {
    if (!packsGiven) return true;
    final owners = [
      for (final pack in allPacks)
        if (pack.steps.contains(step)) pack.name
    ];
    return owners.isEmpty || owners.any(enabledPacks.contains);
  }

  /// `rules:` overrides: rule -> `true`, `false`, `error`, `warning`, `info`.
  Map<String, String> get ruleOverrides => {for (final entry in _section('rules').entries) entry.key: '${entry.value}'};

  /// Every rule of every pack with its value in `analysis_options.yaml`:
  /// `true` in an enabled pack, `false` otherwise, then the overrides.
  Map<String, String> get diagnostics {
    final enabled = enabledPacks.toSet();
    final overrides = ruleOverrides;
    return {
      for (final pack in allPacks)
        for (final rule in pack.rules) rule: overrides[rule] ?? (enabled.contains(pack.name) ? 'true' : 'false'),
    };
  }

  // ---------------------------------------------------------------- triggers

  Map<String, Trigger> get triggers => {
        for (final entry in _section('triggers').entries)
          if (entry.value is Map<String, Object?>)
            entry.key: Trigger(
              name: entry.key,
              scope: '${(entry.value as Map<String, Object?>)['scope'] ?? 'changed'}',
              steps: _strings((entry.value as Map<String, Object?>)['steps'] ?? 'all'),
              ci: (entry.value as Map<String, Object?>)['ci'] == true,
              integration:
                  IntegrationMode.parse((entry.value as Map<String, Object?>)['integration'], IntegrationMode.off),
            ),
      };

  // ---------------------------------------------------------------- general

  /// Base branch for `--changed` when the branch records no `neonBase`.
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

  /// The project name (`pubspec.yaml`), detected.
  String get projectName => facts.name;

  /// Flavours: `flavors:` if set, else the folders of `lib/flavors/` and the
  /// `lib/main_<flavor>.dart` entry points.
  List<String> get flavors {
    final configured = _strings(_yaml['flavors']);
    return configured.isNotEmpty ? configured : facts.flavors;
  }

  // ---------------------------------------------------------------- translations

  Map<String, Object?> get _translations => _section('translations');
  String get translationsDir => _string(_translations['dir']) ?? 'assets/translations';

  /// `translations.languages` if set, else the language files found.
  List<String> get languages {
    final configured = _strings(_translations['languages']);
    return configured.isNotEmpty ? configured : facts.languages;
  }

  String get primaryLanguage {
    final configured = _string(_translations['primary']);
    if (configured != null && (languages.isEmpty || languages.contains(configured))) return configured;
    return languages.isEmpty ? 'en' : languages.first;
  }

  /// Keys (or `prefix*`) that count as used although no code names them.
  List<String> get translationsAllowedUnused => _strings(_translations['allowed_unused']);

  // ---------------------------------------------------------------- assets

  Map<String, Object?> get _assets => _section('assets');

  /// Asset registries that exist (a preset names the conventional one).
  List<String> get assetRegistries => [
        for (final registry in _strings(_assets['registries']))
          if (root == null || File('$root/$registry').existsSync()) registry,
      ];
  List<String> get assetDirs => _strings(_assets['dirs']);

  // ---------------------------------------------------------------- lib/ tree

  Map<String, Object?> get _tree => _section('tree');

  /// Folders every app may have directly under `lib/` (base preset).
  List<String> get treeFolders => _strings(_tree['folders']);

  /// Folders an app has only when it lists them in `tree: use:`.
  List<String> get treeOptional => _strings(_tree['optional']);

  /// The optional folders this app switches on.
  List<String> get treeUse => _strings(_tree['use']);

  /// File name patterns allowed directly under `lib/` (`main_*.dart`).
  List<String> get treeEntrypoints => _strings(_tree['entrypoints']);

  bool get hasTree => treeFolders.isNotEmpty;

  /// The folders allowed directly under `lib/` in this app.
  List<String> get treeAllowedFolders => [...treeFolders, ...treeUse.where(treeOptional.contains)];

  // ---------------------------------------------------------------- catalog

  Map<String, Object?> get _catalog => _section('catalog');
  bool get hasCatalog => _catalog.isNotEmpty;
  String get catalogGenerator => _string(_catalog['generator']) ?? '';
  String get catalogIndex => _string(_catalog['index']) ?? '';
  String get catalogPreviews => _string(_catalog['previews']) ?? '';
  List<String> get catalogInputs => _strings(_catalog['inputs']);
  List<String> get catalogPreviewRequired => _strings(_catalog['preview_required']);

  // ---------------------------------------------------------------- providers

  /// The providers files (layout role `providers`) that exist.
  List<String> get providersFiles => _expand(layout.patterns(LayoutRole.providers));

  // ---------------------------------------------------------------- page help

  Map<String, Object?> get _pageHelp => _section('page_help');
  bool get hasPageHelp => pageHelpEntries.isNotEmpty;

  /// One entry per flavour whose help enum exists when the section uses
  /// `{flavor}`, else the section itself.
  List<PageHelpEntry> get pageHelpEntries {
    final section = _pageHelp;
    if (section.isEmpty) return const [];
    String field(String key, String flavor) => (_string(section[key]) ?? '').replaceAll('{flavor}', flavor);
    final templated = section.values.any((value) => '$value'.contains('{flavor}'));
    final entries = <PageHelpEntry>[];
    for (final flavor in templated ? flavors : const ['']) {
      final entry = PageHelpEntry(
        pages: field('pages', flavor),
        pagePrefix: field('page_prefix', flavor),
        enumFile: field('enum', flavor),
        keyPrefix: field('key_prefix', flavor),
        exempt: _strings(section['exempt']),
      );
      if (root == null || File('$root/${entry.enumFile}').existsSync()) entries.add(entry);
    }
    return entries;
  }

  // ---------------------------------------------------------------- generated

  bool get generatedEnabled => _section('generated')['enabled'] == true;

  // ---------------------------------------------------------------- tests

  Map<String, Object?> get _tests => _section('tests');
  String get testDir => _string(_tests['dir']) ?? 'test';

  /// The suite that always runs and owns every test outside other suites:
  /// `tests.default_suite`, else the project name.
  String get defaultSuite {
    final configured = _string(_tests['default_suite']);
    if (configured != null) return configured;
    return facts.name.isEmpty ? 'app' : facts.name;
  }

  /// Source globs whose change runs every suite.
  List<String> get sharedSources => _strings(_tests['shared']);

  /// How a scoped run picks its tests (`tests.select`): `impact` (default)
  /// runs the test files whose imports reach a changed file, `suites` the
  /// whole suites the changed files select. `--all` always runs everything.
  String get testsSelect => _string(_tests['select']) ?? 'impact';

  /// `flutter test --concurrency` (`tests.concurrency`); 0 = Flutter's default
  /// (half the cores), which can run a busy machine out of memory.
  int get testsConcurrency => (_tests['concurrency'] as int?) ?? 0;

  /// Named suites: their test folders and the source globs that select them.
  /// `name: [globs]` is short for `name: {tests: [test/name], sources: [globs]}`.
  Map<String, ({List<String> tests, List<String> sources})> get suites {
    final suites = _tests['suites'];
    if (suites is! Map<String, Object?>) return const {};
    return {
      for (final entry in suites.entries)
        entry.key: switch (entry.value) {
          final Map<String, Object?> map => (
              tests: map.containsKey('tests') ? _strings(map['tests']) : ['$testDir/${entry.key}'],
              sources: _strings(map['sources']),
            ),
          final Object? other => (tests: ['$testDir/${entry.key}'], sources: _strings(other)),
        },
    };
  }

  // Test existence (NCR0000022): every cubit and every route has a test.
  Map<String, Object?> get _existence => _section('existence', _tests);
  Map<String, Object?> get _cubitExistence => _section('cubits', _existence);
  Map<String, Object?> get _routeExistence => _section('routes', _existence);
  bool get hasTestExistence => _existence.isNotEmpty;

  /// Folder scanned for cubits: `tests.existence.cubits.dir`, else the first
  /// folder of the layout role `bloc`.
  String get cubitsDir {
    final configured = _string(_cubitExistence['dir']);
    if (configured != null) return configured;
    final folder = layout.patterns(LayoutRole.bloc).firstWhere((p) => p.endsWith('/'), orElse: () => 'lib/bloc/');
    return folder.substring(0, folder.length - 1);
  }

  String get cubitSuffix => _string(_cubitExistence['suffix']) ?? '_cubit.dart';
  List<String> get cubitExempt => _strings(_cubitExistence['exempt']);

  /// Router files scanned for `path: Routes.<id>.absolutePath`:
  /// `tests.existence.routes.routers`, else the files of the layout role
  /// `routers`.
  List<String> get routeRouters {
    final configured = _strings(_routeExistence['routers']);
    return configured.isNotEmpty ? configured : _expand(layout.patterns(LayoutRole.routers));
  }

  String get routeTestsFolder => _string(_routeExistence['tests_folder']) ?? 'routes';

  // Coverage of changed lines (NCR0000022).
  Map<String, Object?> get _coverage => _section('coverage', _tests);

  /// Source globs whose changed lines must be covered; empty = no coverage gate.
  List<String> get coverageSources => _strings(_coverage['sources']);
  int get coverageMinPercent => (_coverage['min_percent'] as int?) ?? 90;
  String get coverageLcov => _string(_coverage['lcov']) ?? 'coverage/lcov.info';

  // ---------------------------------------------------------------- integration

  Map<String, Object?> get _integration => _section('integration');
  String get integrationDir => _string(_integration['dir']) ?? 'integration_test';

  /// `web-server`, `device` or `none`.
  String get integrationDriver => _string(_integration['driver']) ?? 'none';
  String get integrationDevice => _string(_integration['device']) ?? '';
  String get integrationDefinesFile => _string(_integration['defines_file']) ?? '';
  bool get requireFlowForPages => _integration['require_flow_for_pages'] == true;
  List<String> get integrationExemptPages => _strings(_integration['exempt_pages']);

  /// Run several flows from ONE build (`integration.combine`): a generated
  /// target imports every flow as a group, so the app compiles once instead
  /// of once per flow. A failure is confirmed by running the failing flows
  /// on their own.
  bool get integrationCombine => _integration['combine'] == true;

  /// The app's file with `Future<void> resetBetweenFlows()`
  /// (`integration.reset`), run after every flow of a combined run so the
  /// next one starts from a fresh install; empty = no reset.
  String get integrationReset => _string(_integration['reset']) ?? '';

  /// A background run starts only with at least this much memory available
  /// (`integration.background_min_memory_mb`, MemAvailable); a busy machine
  /// leaves the flows to `--trigger ci` instead of being run out of memory.
  int get integrationBackgroundMinMemoryMb => (_integration['background_min_memory_mb'] as int?) ?? 8192;

  /// Where the ESME rules are exported (`.claude/rules/shared`).
  String get ruleDocsDir => _string(_section('rule_docs')['dir']) ?? '.claude/rules/shared';

  /// Everything, for `neon-check explain`.
  Map<String, Object?> get raw => _yaml;
}

/// One page-help configuration (`page_help:`, per flavour).
final class PageHelpEntry {
  const PageHelpEntry({
    required this.pages,
    required this.pagePrefix,
    required this.enumFile,
    required this.keyPrefix,
    required this.exempt,
  });

  final String pages;
  final String pagePrefix;
  final String enumFile;
  final String keyPrefix;
  final List<String> exempt;
}

/// Root-relative files under [root] that match any of the layout [patterns].
List<String> expandLayoutPatterns(String root, List<String> patterns) {
  final found = <String>{};
  for (final pattern in patterns) {
    // Walk only below the fixed part of the pattern.
    final wildcard = pattern.indexOf(RegExp(r'[*{]'));
    final fixed = wildcard < 0 ? pattern : pattern.substring(0, wildcard);
    final start = fixed.contains('/') ? fixed.substring(0, fixed.lastIndexOf('/')) : '';
    final file = File('$root/$pattern');
    if (wildcard < 0 && !pattern.endsWith('/')) {
      if (file.existsSync()) found.add(pattern);
      continue;
    }
    final dir = Directory(start.isEmpty ? root : '$root/$start');
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      final relative = entity.path.replaceAll(r'\', '/').substring(root.length + 1);
      if (matchesLayoutPattern(pattern, relative)) found.add(relative);
    }
  }
  return found.toList()..sort();
}
