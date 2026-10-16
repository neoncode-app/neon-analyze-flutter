import 'dart:io';

import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/finding.dart';
import 'package:neon_check/src/step.dart';
import 'package:neon_lints/layout.dart';

/// One canonical `lib/` tree (NCC0000058): directly under `lib/` there are
/// only the folders of the layout roles (`tree.folders` of the base preset,
/// plus the `tree.optional` folders the app switches on with `tree: use:`)
/// and the entrypoints (`main.dart`, `main_<flavor>.dart`). Every other
/// folder or file there is a `layout_tree` finding: a folder is reported once
/// as `lib/<name>/`, a file as itself (generated ones included, e.g.
/// `hive_registrar.g.dart` belongs in `lib/hive/`).
final class LayoutTreeStep extends CheckStep {
  const LayoutTreeStep();

  @override
  String get name => 'layout_tree';

  @override
  String get description => 'lib/ holds only the role folders of the canonical tree and the entrypoints';

  @override
  Set<String> get rules => const {'layout_tree'};

  @override
  bool appliesTo(CheckContext context) => context.config.hasTree && context.touches(const ['lib/']);

  @override
  Future<StepResult> run(CheckContext context) async {
    final config = context.config;
    final lib = Directory(context.absolute('lib'));
    if (!lib.existsSync()) return const StepResult();
    final allowed = config.treeAllowedFolders.toSet();
    final folders = config.treeAllowedFolders.map((folder) => '$folder/').join(', ');
    final findings = <Finding>[];
    final entries = lib.listSync()..sort((a, b) => a.path.compareTo(b.path));
    for (final entity in entries) {
      final name = entity.uri.pathSegments.where((segment) => segment.isNotEmpty).last;
      if (name.startsWith('.')) continue;
      if (entity is Directory) {
        if (allowed.contains(name)) continue;
        final optional = config.treeOptional.contains(name);
        findings.add(
          Finding(
            rule: 'layout_tree',
            file: 'lib/$name/',
            message: optional
                ? '`lib/$name/` is an optional folder this app does not use; '
                    'switch it on with `tree: {use: [$name]}` in neon_check.yaml or move its code into a role folder'
                : '`lib/$name/` is no folder of the lib/ tree ($folders); move its code into the role it belongs to',
          ),
        );
      } else if (entity is File) {
        if (config.treeEntrypoints.any((pattern) => matchesLayoutPattern(pattern, name))) continue;
        findings.add(
          Finding(
            rule: 'layout_tree',
            file: 'lib/$name',
            message: 'only the entrypoints (${config.treeEntrypoints.join(', ')}) sit directly in lib/; '
                'move `$name` into the role folder it belongs to',
          ),
        );
      }
    }
    // The whole tree is looked at on every run, so every baseline entry of
    // the rule is checked and lowered.
    return StepResult(findings: findings, findingsScope: (_) => true);
  }
}
