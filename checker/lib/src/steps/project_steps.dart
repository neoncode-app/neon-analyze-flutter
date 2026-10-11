import 'dart:io';

import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/finding.dart';
import 'package:neon_check/src/process.dart';
import 'package:neon_check/src/step.dart';
import 'package:neon_check/src/steps/translation_steps.dart';

int _lineOf(List<String> lines, Pattern pattern) {
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].contains(pattern)) return i + 1;
  }
  return 1;
}

/// Step 11: every asset path the registry names exists, and every asset file
/// is used somewhere.
final class AssetsStep extends CheckStep {
  const AssetsStep();

  @override
  String get name => 'assets';

  @override
  String get description => 'AppAssets paths exist; unused asset files';

  @override
  Set<String> get rules => const {'asset_missing', 'asset_unused'};

  @override
  bool appliesTo(CheckContext context) =>
      context.config.assetRegistries.isNotEmpty &&
      context.touches([...context.config.assetRegistries, ...context.config.assetDirs, 'lib/']);

  static final _assetLiteral = RegExp(r"""['"](assets/[^'"$]+)['"]""");

  /// `'assets/icons/doordrop/$name.svg'`: a path built at runtime.
  static final _assetTemplate = RegExp(r"""['"](assets/[^'"]*\$[^'"]*)['"]""");

  static RegExp _templatePattern(String template) {
    final parts = template.split(RegExp(r'\$\{[^}]*\}|\$\w+'));
    return RegExp('^${parts.map(RegExp.escape).join('[^/]+')}\$');
  }

  @override
  Future<StepResult> run(CheckContext context) async {
    final findings = <Finding>[];
    for (final registry in context.config.assetRegistries) {
      final lines = File(context.absolute(registry)).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final match in _assetLiteral.allMatches(lines[i])) {
          final path = match.group(1) ?? '';
          if (!File(context.absolute(path)).existsSync()) {
            findings.add(
              Finding(rule: 'asset_missing', file: registry, line: i + 1, message: '`$path` does not exist'),
            );
          }
        }
      }
    }
    if (context.isAll) {
      final sources = [for (final file in context.allLibDartFiles) File(context.absolute(file)).readAsStringSync()];
      final referenced = {
        for (final source in sources)
          for (final match in _assetLiteral.allMatches(source)) match.group(1) ?? '',
      };
      final templates = [
        for (final source in sources)
          for (final match in _assetTemplate.allMatches(source)) _templatePattern(match.group(1) ?? ''),
      ];
      for (final dir in context.config.assetDirs) {
        final directory = Directory(context.absolute(dir));
        if (!directory.existsSync()) continue;
        for (final entity in directory.listSync(recursive: true)) {
          if (entity is! File || entity.uri.pathSegments.last.startsWith('.')) continue;
          final path = context.relative(entity.path);
          if (!referenced.contains(path) && !templates.any((pattern) => pattern.hasMatch(path))) {
            findings.add(
              Finding(rule: 'asset_unused', file: path, message: 'no code references this asset; delete it or use it'),
            );
          }
        }
      }
    }
    return StepResult(findings: findings, findingsScope: context.isAll ? (_) => true : null);
  }
}

/// Step 12: the widget catalog index is regenerated from the sources.
/// Auto-fix: keeps the regenerated index; with `--ci` restores it and fails.
final class CatalogIndexStep extends CheckStep {
  const CatalogIndexStep();

  @override
  bool get autoFix => true;

  @override
  String get name => 'catalog_index';

  @override
  String get description => 'widget catalog index up to date (auto-fix: runs the generator)';

  @override
  Set<String> get rules => const {'catalog_index_stale', 'catalog_generator'};

  @override
  bool appliesTo(CheckContext context) => context.config.hasCatalog && context.touches(context.config.catalogInputs);

  @override
  Future<StepResult> run(CheckContext context) async {
    final index = File(context.absolute(context.config.catalogIndex));
    final before = index.existsSync() ? index.readAsStringSync() : '';
    final result = await runProcess(context.root, 'dart', ['run', context.config.catalogGenerator]);
    if (result.exitCode != 0) {
      if (before.isNotEmpty) index.writeAsStringSync(before);
      return StepResult(
        findings: [
          Finding(
            rule: 'catalog_generator',
            file: context.config.catalogGenerator,
            message: result.stderr.trim().replaceAll('\n', ' | '),
          ),
        ],
      );
    }
    final after = index.readAsStringSync();
    if (after == before) return const StepResult();
    if (context.fix) return StepResult(fixed: [context.config.catalogIndex]);
    index.writeAsStringSync(before);
    return StepResult(
      findings: [
        Finding(
          rule: 'catalog_index_stale',
          file: context.config.catalogIndex,
          message: 'stale; run `dart run ${context.config.catalogGenerator}`',
        ),
      ],
    );
  }
}

/// Step 13: every widget in the folders that require one has a live preview
/// on the catalog page.
final class CatalogPreviewsStep extends CheckStep {
  const CatalogPreviewsStep();

  @override
  String get name => 'catalog_previews';

  @override
  String get description => 'every global widget has a catalog preview';

  @override
  Set<String> get rules => const {'catalog_preview_missing'};

  @override
  bool appliesTo(CheckContext context) =>
      context.config.hasCatalog &&
      context.touches([...context.config.catalogPreviewRequired, context.config.catalogPreviews]);

  @override
  Future<StepResult> run(CheckContext context) async {
    final index = File(context.absolute(context.config.catalogIndex)).readAsStringSync();
    final entry = RegExp(r"name: '(\w+)',\s*path: '([^']+)'");
    final previewKey = RegExp(r"^\s*'(\w+)':\s*\(", multiLine: true);
    final previews = <String>{
      for (final entity in Directory(context.absolute(context.config.catalogPreviews)).listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          for (final match in previewKey.allMatches(entity.readAsStringSync())) match.group(1) ?? '',
    };
    final findings = <Finding>[];
    for (final match in entry.allMatches(index)) {
      final name = match.group(1) ?? '';
      final path = match.group(2) ?? '';
      if (!context.config.catalogPreviewRequired.any(path.startsWith) || previews.contains(name)) continue;
      final lines = File(context.absolute(path)).readAsLinesSync();
      findings.add(
        Finding(
          rule: 'catalog_preview_missing',
          file: path,
          line: _lineOf(lines, 'class $name'),
          message: '`$name` has no catalog preview; add one to ${context.config.catalogPreviews}/previews_*.dart',
        ),
      );
    }
    return StepResult(findings: findings, findingsScope: (_) => true);
  }
}

/// Step 14: every typed context getter (`lib/flavors/<f>/<f>_providers.dart`)
/// reads a cubit that the flavour's router or shell actually provides.
/// Passes trivially while no providers file exists.
final class ProvidersStep extends CheckStep {
  const ProvidersStep();

  @override
  String get name => 'providers';

  @override
  String get description => 'context getters match cubits provided in the router / shell';

  @override
  Set<String> get rules => const {'provider_missing'};

  @override
  bool appliesTo(CheckContext context) =>
      context.config.providerFlavors.isNotEmpty && context.touches(['lib/flavors/']);

  @override
  Future<StepResult> run(CheckContext context) async {
    final findings = <Finding>[];
    final getter = RegExp(r'(\w+)\s+get\s+\w+\s*=>');
    final provided = RegExp(r'BlocProvider<(\w+)>|create:\s*\([^)]*\)\s*=>\s*(\w+)\(');
    for (final flavor in context.config.providerFlavors) {
      final providersPath = 'lib/flavors/$flavor/${flavor}_providers.dart';
      final providersFile = File(context.absolute(providersPath));
      if (!providersFile.existsSync()) continue;
      final providedTypes = <String>{
        for (final entity in Directory(context.absolute('lib/flavors/$flavor')).listSync(recursive: true))
          if (entity is File && entity.path.endsWith('.dart') && !entity.path.endsWith('_providers.dart'))
            for (final match in provided.allMatches(entity.readAsStringSync())) match.group(1) ?? match.group(2) ?? '',
      };
      final lines = providersFile.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final match = getter.firstMatch(lines[i]);
        final type = match?.group(1);
        if (type == null || !type.endsWith('Cubit') || providedTypes.contains(type)) continue;
        findings.add(
          Finding(
            rule: 'provider_missing',
            file: providersPath,
            line: i + 1,
            message: '`$type` is never provided in lib/flavors/$flavor; provide it in the router or shell',
          ),
        );
      }
    }
    return StepResult(findings: findings, findingsScope: (file) => file.startsWith('lib/flavors/'));
  }
}

/// Step 15: every page of the configured folder has a help dialog (`onHelp`)
/// and every help entry has all its translation keys.
final class PageHelpStep extends CheckStep {
  const PageHelpStep();

  @override
  String get name => 'page_help';

  @override
  String get description => 'every Vernak page has onHelp and its help translation keys';

  @override
  Set<String> get rules => const {'page_help_missing', 'page_help_key_missing'};

  @override
  bool appliesTo(CheckContext context) =>
      context.config.hasPageHelp &&
      context.touches([context.config.pageHelpPages, context.config.translationsDir, context.config.pageHelpEnum]);

  @override
  Future<StepResult> run(CheckContext context) async {
    final config = context.config;
    final findings = <Finding>[];
    for (final entity in Directory(context.absolute(config.pageHelpPages)).listSync()) {
      final file = context.relative(entity.path);
      final name = file.split('/').last;
      if (entity is! File ||
          !name.startsWith(config.pageHelpPagePrefix) ||
          !name.endsWith('_page.dart') ||
          config.pageHelpExempt.contains(name)) {
        continue;
      }
      if (!entity.readAsStringSync().contains('onHelp')) {
        findings.add(
          Finding(
            rule: 'page_help_missing',
            file: file,
            message: 'the page has no "?" help; pass onHelp to AppContentPage (VernakPageHelp)',
          ),
        );
      }
    }
    // Keys of every standard help entry: `<prefix><name>_title`, `_subtitle`,
    // `_ov<n>_title/_desc` per icon, `_faq_q/a<n>`, `_step_t/d<n>`.
    final source = File(context.absolute(config.pageHelpEnum)).readAsStringSync();
    final entry = RegExp(
      r'^\s{2}(\w+)\(\s*icons:\s*\[(.*?)\],\s*faqCount:\s*(\d+),\s*stepCount:\s*(\d+),?\s*\)',
      multiLine: true,
      dotAll: true,
    );
    final enumLines = source.split('\n');
    final languages = [for (final language in config.languages) TranslationFile.load(context, language)];
    for (final match in entry.allMatches(source)) {
      final page = match.group(1) ?? '';
      final icons = (match.group(2) ?? '').split(',').where((icon) => icon.trim().isNotEmpty).length;
      final faq = int.parse(match.group(3) ?? '0');
      final steps = int.parse(match.group(4) ?? '0');
      final key = '${config.pageHelpKeyPrefix}$page';
      final required = [
        '${key}_title',
        '${key}_subtitle',
        for (var i = 1; i <= icons; i++) ...['${key}_ov${i}_title', '${key}_ov${i}_desc'],
        for (var i = 1; i <= faq; i++) ...['${key}_faq_q$i', '${key}_faq_a$i'],
        for (var i = 1; i <= steps; i++) ...['${key}_step_t$i', '${key}_step_d$i'],
      ];
      for (final language in languages) {
        for (final requiredKey in required) {
          if (language.values.containsKey(requiredKey)) continue;
          findings.add(
            Finding(
              rule: 'page_help_key_missing',
              file: config.pageHelpEnum,
              line: _lineOf(enumLines, RegExp('^\\s{2}$page\\(')),
              message: '`$requiredKey` is missing in ${language.path}',
            ),
          );
        }
      }
    }
    return StepResult(findings: findings, findingsScope: (_) => true);
  }
}

/// Step 16: generated code (`*.g.dart`) matches its sources. Runs
/// build_runner; with `--ci` restores the files and fails on a difference.
final class GeneratedCodeStep extends CheckStep {
  const GeneratedCodeStep();

  @override
  bool get autoFix => true;

  @override
  String get name => 'generated';

  @override
  String get description => '*.g.dart match their sources (auto-fix: build_runner)';

  @override
  Set<String> get rules => const {'generated_stale', 'build_runner'};

  static final _part = RegExp(r"^part '[^']+\.g\.dart';", multiLine: true);

  @override
  bool appliesTo(CheckContext context) =>
      context.config.generatedEnabled &&
      (context.isAll ||
          context.dartFiles.any(
            (file) =>
                File(context.absolute(file)).existsSync() &&
                _part.hasMatch(File(context.absolute(file)).readAsStringSync()),
          ));

  Map<String, String> _snapshot(CheckContext context) => {
        for (final entity in Directory(context.absolute('lib')).listSync(recursive: true))
          if (entity is File && entity.path.endsWith('.g.dart'))
            context.relative(entity.path): entity.readAsStringSync(),
      };

  @override
  Future<StepResult> run(CheckContext context) async {
    final before = _snapshot(context);
    final result = await runProcess(context.root, 'dart', [
      'run',
      'build_runner',
      'build',
      '--delete-conflicting-outputs',
    ]);
    if (result.exitCode != 0) {
      return StepResult(
        findings: [
          Finding(
            rule: 'build_runner',
            file: 'pubspec.yaml',
            message: 'build_runner failed: ${result.stderr.trim().split('\n').take(5).join(' | ')}',
          ),
        ],
      );
    }
    final after = _snapshot(context);
    // The catalog index is a .g.dart written by its own generator.
    final changed = [
      for (final file in {...before.keys, ...after.keys})
        if (before[file] != after[file] && file != context.config.catalogIndex) file,
    ];
    if (changed.isEmpty || context.fix) return StepResult(fixed: changed);
    for (final file in changed) {
      final original = before[file];
      if (original == null) {
        File(context.absolute(file)).deleteSync();
      } else {
        File(context.absolute(file)).writeAsStringSync(original);
      }
    }
    return StepResult(
      findings: [
        for (final file in changed)
          Finding(rule: 'generated_stale', file: file, message: 'out of date; run `dart run build_runner build`'),
      ],
    );
  }
}
