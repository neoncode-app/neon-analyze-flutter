import 'dart:io';

import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/finding.dart';
import 'package:neon_check/src/runner.dart';
import 'package:neon_check/src/step.dart';
import 'package:neon_check/src/steps/dart_steps.dart';
import 'package:yaml/yaml.dart';

/// One rule document of the ESME context layer, as exported into the app
/// (`.claude/rules/shared/<key>.md`).
final class RuleDoc {
  const RuleDoc({
    required this.path,
    required this.key,
    required this.paths,
    required this.enforcedBy,
    required this.enforcedLine,
    required this.notEnforced,
  });

  /// Parses the exported file at [path] (root-relative [relative]).
  factory RuleDoc.parse(String relative, String source) {
    final lines = source.split('\n');
    var paths = <String>[];
    var body = 0;
    if (lines.isNotEmpty && lines.first.trim() == '---') {
      final end = lines.indexWhere((line) => line.trim() == '---', 1);
      if (end > 0) {
        final yaml = loadYaml(lines.sublist(1, end).join('\n'));
        final value = yaml is YamlMap ? yaml['paths'] : null;
        paths = value is YamlList ? [for (final item in value) '$item'] : const [];
        body = end + 1;
      }
    }
    var enforcedBy = <String>[];
    var enforcedLine = 0;
    var notEnforced = false;
    for (var i = body; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('Enforced by:')) {
        enforcedBy = [for (final match in RegExp('`([^`]+)`').allMatches(line)) match.group(1) ?? ''];
        enforcedLine = i + 1;
      } else if (line.startsWith('Not enforced:')) {
        notEnforced = true;
        enforcedLine = i + 1;
      }
    }
    final file = relative.split('/').last;
    return RuleDoc(
      path: relative,
      key: file.endsWith('.md') ? file.substring(0, file.length - 3) : file,
      paths: paths,
      enforcedBy: enforcedBy,
      enforcedLine: enforcedLine,
      notEnforced: notEnforced,
    );
  }

  /// Root-relative path of the exported file.
  final String path;

  /// The ESME key (`rule:<key>`).
  final String key;

  /// `paths:` of the rule: the files it governs.
  final List<String> paths;

  /// Checks named on the `Enforced by:` line.
  final List<String> enforcedBy;

  /// Line of `Enforced by:` / `Not enforced:`, 0 when there is none.
  final int enforcedLine;

  /// Whether the rule says it is deliberately not checked (`Not enforced:`).
  final bool notEnforced;

  /// Whether the rule governs Dart code of the app (a `lib/` or `**` glob).
  bool get governsAppCode => paths.any((glob) => glob.startsWith('lib/') || glob.startsWith('**'));
}

/// The rule documents exported into [dir] (README.md, the company overview,
/// excluded).
List<RuleDoc> loadRuleDocs(CheckContext context, String dir) {
  final folder = Directory(context.absolute(dir));
  if (!folder.existsSync()) return const [];
  return [
    for (final entity in folder.listSync()..sort((a, b) => a.path.compareTo(b.path)))
      if (entity is File && entity.path.endsWith('.md') && !entity.path.endsWith('/README.md'))
        RuleDoc.parse(context.relative(entity.path), entity.readAsStringSync()),
  ];
}

/// Every check a rule may name: neon_lints rules, neon-check steps and the
/// rule ids the steps report.
Set<String> knownCheckNames(CheckContext context) => {
      ...IgnoreCommentsStep.pluginRuleNames('${context.toolRoot}/plugin'),
      for (final step in allSteps()) ...[step.name, ...?step.rules],
    };

/// The written rules (ESME, exported to `.claude/rules/shared/`) and the
/// checks that enforce them name each other, so a rule text cannot silently
/// contradict or outlive its check.
///
/// Every rule that governs app code (`paths:` under `lib/` or `**`) ends with
/// `Enforced by: \`check\`, ...` or `Not enforced: <why>`, and every check it
/// names exists. The fix is always in ESME (`context_update`), never in the
/// exported file, which the next session overwrites. Skips when the app has
/// no export (CI).
final class RuleDocsStep extends CheckStep {
  const RuleDocsStep();

  @override
  String get name => 'rule_docs';

  @override
  String get description => 'every written rule names the checks that enforce it, and they exist';

  @override
  Set<String> get rules => const {'rule_doc_unlinked', 'rule_doc_unknown_check'};

  @override
  bool appliesTo(CheckContext context) => Directory(context.absolute(context.config.ruleDocsDir)).existsSync();

  @override
  Future<StepResult> run(CheckContext context) async {
    final known = knownCheckNames(context);
    final findings = <Finding>[];
    for (final doc in loadRuleDocs(context, context.config.ruleDocsDir)) {
      for (final check in doc.enforcedBy.where((check) => !known.contains(check))) {
        findings.add(
          Finding(
            rule: 'rule_doc_unknown_check',
            file: doc.path,
            line: doc.enforcedLine,
            message: 'rule:${doc.key} names `$check`, which is no neon_lints rule or neon-check step; '
                'correct the rule in ESME (context_update), not this exported file',
          ),
        );
      }
      if (doc.governsAppCode && doc.enforcedLine == 0) {
        findings.add(
          Finding(
            rule: 'rule_doc_unlinked',
            file: doc.path,
            message: 'rule:${doc.key} governs app code but names no check; end it in ESME with '
                '"Enforced by: `<check>`, ..." or "Not enforced: <why>"',
          ),
        );
      }
    }
    return StepResult(findings: findings, findingsScope: (_) => true);
  }
}
