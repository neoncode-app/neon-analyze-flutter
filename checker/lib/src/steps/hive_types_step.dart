import 'dart:io';

import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/finding.dart';
import 'package:neon_check/src/process.dart';
import 'package:neon_check/src/step.dart';
import 'package:neon_lints/layout.dart';
import 'package:yaml/yaml.dart';

/// The Hive adapters follow one convention (NCC0000070, rule doc
/// `storage_hive`): hive_ce's `@GenerateAdapters` in `lib/hive/hive_adapters.dart`
/// lists every stored type, the generated schema `lib/hive/hive_adapters.g.yaml`
/// (stable typeIds and field indexes) is committed and lists exactly those
/// types, no class carries the old `@HiveType` annotation, and the generated
/// registrar is passed to `NeonHive.init` (`registerAdapters()` inside the
/// call) in the app startup.
///
/// An app without `lib/hive/hive_adapters.dart` and without any Hive
/// annotation is not checked. Every failed check is one `hive_types` finding.
final class HiveTypesStep extends CheckStep {
  const HiveTypesStep();

  static const adaptersFile = 'lib/hive/hive_adapters.dart';

  static const schemaFile = 'lib/hive/hive_adapters.g.yaml';

  @override
  String get name => 'hive_types';

  @override
  String get description =>
      'every stored type in lib/hive/hive_adapters.dart, its schema committed, the registrar used';

  @override
  Set<String> get rules => const {'hive_types'};

  @override
  bool appliesTo(CheckContext context) => context.touches(const ['lib/']);

  static final _spec = RegExp(r'AdapterSpec<(\w+)>');

  static final _hiveType = RegExp(r'@HiveType\s*\(');

  static final _init = RegExp(r'NeonHive\.init\s*\(([\s\S]*?)\);');

  /// The types listed by `AdapterSpec<T>()` in [adapters].
  static Set<String> specTypes(String adapters) =>
      {for (final match in _spec.allMatches(adapters)) match.group(1) ?? ''};

  /// The type names of the generated schema [yaml].
  static Set<String> schemaTypes(String yaml) {
    final parsed = loadYaml(yaml);
    final types = parsed is YamlMap ? parsed['types'] : null;
    return types is YamlMap ? {for (final key in types.keys) '$key'} : {};
  }

  /// Whether [source] passes the generated registrar to `NeonHive.init`.
  static bool passesRegistrar(String source) =>
      _init.allMatches(source).any((match) => (match.group(1) ?? '').contains('registerAdapters()'));

  @override
  Future<StepResult> run(CheckContext context) async {
    final findings = <Finding>[];
    Finding finding(String file, String message, [int line = 1]) =>
        Finding(rule: 'hive_types', file: file, line: line, message: message);

    final annotated = <String, int>{};
    for (final file in context.allLibDartFiles) {
      final source = File(context.absolute(file)).readAsStringSync();
      final match = _hiveType.firstMatch(source);
      if (match != null) annotated[file] = '\n'.allMatches(source.substring(0, match.start)).length + 1;
    }
    final adapters = File(context.absolute(adaptersFile));
    if (!adapters.existsSync()) {
      if (annotated.isEmpty) return const StepResult();
      return StepResult(findings: [
        finding(adaptersFile, 'missing: list the stored types with @GenerateAdapters([AdapterSpec<T>()]) here'),
      ]);
    }
    for (final MapEntry(key: file, value: line) in annotated.entries) {
      findings.add(finding(file, '@HiveType: list the type in $adaptersFile (AdapterSpec) instead', line));
    }

    final specs = specTypes(adapters.readAsStringSync());
    final schema = File(context.absolute(schemaFile));
    if (!schema.existsSync()) {
      findings.add(finding(schemaFile, 'missing: run build_runner and commit the generated schema'));
    } else {
      final tracked = await runProcess(context.root, 'git', ['ls-files', '--error-unmatch', schemaFile]);
      if (tracked.exitCode != 0)
        findings.add(finding(schemaFile, 'not committed: the schema keeps the typeIds stable'));
      final types = schemaTypes(schema.readAsStringSync());
      for (final type in specs.difference(types)) {
        findings.add(finding(schemaFile, '$type is listed in $adaptersFile but not in the schema; run build_runner'));
      }
      for (final type in types.difference(specs)) {
        findings.add(finding(schemaFile, '$type is in the schema but no longer listed in $adaptersFile'));
      }
    }

    final roots = context.config.layout.patterns(LayoutRole.appRoot);
    final startup = [
      for (final pattern in roots)
        if (File(context.absolute(pattern)).existsSync()) pattern,
    ];
    final passed = startup.any((file) => passesRegistrar(File(context.absolute(file)).readAsStringSync()));
    if (!passed) {
      findings.add(finding(
        startup.firstOrNull ?? 'lib',
        'NeonHive.init does not get the generated registrar: registerAdapters: (hive) => hive.registerAdapters()',
      ));
    }
    return StepResult(findings: findings);
  }
}
