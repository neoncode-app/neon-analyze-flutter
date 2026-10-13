import 'dart:convert';
import 'dart:io';

import 'package:neon_check/src/config.dart';
import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/steps/rule_docs_step.dart';
import 'package:neon_lints/layout.dart';

/// `neon-check brief <file>`: what a file must follow, written for the AI
/// BEFORE it edits the file, so the code comes out right the first time
/// instead of being fixed after the checks fail.
///
/// The file's kind (its layout roles), the rules of the enabled packs that
/// are about that kind (texts from `plugin/rule_catalog.json`, generated from
/// the rules), the gates the file must pass (tests, coverage, flows, help,
/// catalog) and the written ESME rules that govern its path. Empty for files
/// the checks do not cover.
String brief(CheckConfig config, String toolRoot, String file) {
  final root = config.root ?? '';
  if (!file.endsWith('.dart') || !Layout.isAppSource(file)) return '';
  final layout = config.layout;
  final roles = {
    for (final role in LayoutRole.values)
      if (layout.matches(role, file)) role.key,
    if (layout.isUi(file)) 'ui',
  };
  final catalogFile = File('$toolRoot/plugin/rule_catalog.json');
  final catalog = catalogFile.existsSync()
      ? ((jsonDecode(catalogFile.readAsStringSync()) as Map<String, Object?>)['rules'] as Map<String, Object?>? ?? {})
      : const <String, Object?>{};
  final diagnostics = config.diagnostics;
  final enabled = config.enabledPacks.toSet();

  final kind = [
    for (final role in LayoutRole.values)
      if (roles.contains(role.key)) role.key,
  ];
  final out = StringBuffer()
    ..writeln('[neon-check] Before you write $file: it is '
        '${kind.isEmpty ? 'app code' : kind.map((role) => '`$role`').join(', ')}'
        '${roles.contains('ui') ? ' (UI code)' : ''}. Write it so these pass the first time; '
        'every finding comes back as `file:line rule: message` and blocks the turn.');

  out.writeln('Rules checked in this file:');
  for (final pack in config.allPacks.where((pack) => enabled.contains(pack.name))) {
    for (final rule in pack.rules) {
      if (diagnostics[rule] == 'false' || !pack.ruleApplies(rule, roles)) continue;
      final entry = catalog[rule];
      // A correction with a placeholder names its replacement only in the finding.
      final correction = entry is Map<String, Object?> ? '${entry['correction']}' : '';
      final text = entry is Map<String, Object?>
          ? '${entry['description']} ${correction.contains('{') ? '' : correction}'.trim()
          : '(no catalog entry)';
      out.writeln('- $rule: $text');
    }
  }

  final name = file.split('/').last;
  final gates = <String>[
    if (config.packEnabled('bloc') && name.endsWith(config.cubitSuffix))
      'a cubit test `${name.replaceAll('.dart', '_test.dart')}` under ${config.testDir}/ that drives the changed lines '
          '(${config.coverageMinPercent} % of changed lines covered)',
    if (config.packEnabled('go_router') && layout.matches(LayoutRole.routers, file))
      'every GoRoute has `${config.testDir}/<suite>/${config.routeTestsFolder}/<route_id>_route_test.dart`',
    if (config.requireFlowForPages &&
        layout.matches(LayoutRole.pages, file) &&
        name.endsWith('_page.dart') &&
        !file.contains('/widgets/'))
      'an integration flow in ${config.integrationDir}/ that opens this page',
    for (final help in config.pageHelpEntries)
      if (file.startsWith('${help.pages}/') && name.startsWith(help.pagePrefix) && name.endsWith('_page.dart'))
        '`help:` on AppContentPage and the `${help.keyPrefix}<page>_*` keys (${help.enumFile.split('/').last})',
    if (config.packEnabled('catalog') && config.catalogPreviewRequired.any((dir) => file.startsWith('$dir/')))
      'a catalog preview in ${config.catalogPreviews}/ for every public widget',
    if (config.packEnabled('flavors') && layout.matches(LayoutRole.providers, file))
      'every getter reads a cubit the router or shell next to it provides',
    if (config.languages.isNotEmpty && roles.contains('ui'))
      "every tr('key') exists in ${config.languages.join(', ')} (${config.translationsDir}), no dashes in the texts",
  ];
  if (gates.isNotEmpty) {
    out.writeln('This file also needs:');
    for (final gate in gates) {
      out.writeln('- $gate');
    }
  }

  final context = CheckContext(
    root: root,
    config: config,
    mode: ScopeMode.files,
    changedFiles: {file},
    deletedFiles: const {},
    fix: false,
    ci: true,
    toolRoot: toolRoot,
  );
  final docs = [
    for (final doc in loadRuleDocs(context, config.ruleDocsDir))
      if (doc.paths.any((glob) => matchesLayoutPattern(glob, file))) doc.key,
  ];
  if (docs.isNotEmpty) {
    out.writeln('Written rules for this path (${config.ruleDocsDir}, the why): ${docs.join(', ')}.');
  }
  return out.toString().trimRight();
}
