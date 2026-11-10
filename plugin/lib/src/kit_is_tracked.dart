import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// The base components users interact with report to analytics
/// (`neon_flutter_analytics`, NCR0000050).
///
/// Every interaction of an app passes through a few kit widgets, the owners of
/// the `neon_check.yaml` `kit:` rows in [rows]. Each of those files references
/// `NeonAnalytics` in code (a comment or a string does not count; a part of the
/// same library does). A folder owner (it ends with `/`) stands for its entry
/// file, `<folder>/<folder>.dart`. An app that declares none of the rows is not
/// checked.
class KitIsTracked extends AnalysisRule {
  KitIsTracked() : super(name: 'kit_is_tracked', description: _desc);

  static const _desc = 'The kit widgets users interact with report to NeonAnalytics.';

  static const LintCode code = LintCode(
    'kit_is_tracked',
    '[NEON] This file is the `{0}` kit widget but never references NeonAnalytics, so its interactions are not counted.',
    correctionMessage:
        "Wrap the callback it already has: `onTap: NeonAnalytics.onTap(onTap, id: trackId, component: 'AppTapArea')`.",
    severity: DiagnosticSeverity.WARNING,
  );

  /// The `kit:` rows whose widgets take the user's taps, swipes and input.
  static const rows = ['gesture_detector', 'ink_well', 'buttons', 'switches', 'checkboxes', 'text_fields'];

  /// The tracked row of [kit] that owns the root-relative [relative], or
  /// `null`.
  static String? rowOwning(Map<String, KitReplacement> kit, String relative) {
    for (final row in rows) {
      if (kit[row]?.owners.any((owner) => _isOwner(owner, relative)) ?? false) return row;
    }
    return null;
  }

  static bool _isOwner(String owner, String relative) {
    if (!owner.endsWith('/')) return relative == owner;
    final folder = owner.substring(0, owner.length - 1);
    return relative == '$owner${folder.substring(folder.lastIndexOf('/') + 1)}.dart';
  }

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final layout = RuleLayout.of(context);
    if (!rows.any(layout.kit.containsKey)) return;
    registry.addCompilationUnit(this, _Visitor(this, layout, context));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.layout, this.context);

  final AnalysisRule rule;

  final RuleLayout layout;

  final RuleContext context;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    final path = unitPath(node);
    final relative = layout.relative(path);
    if (relative == null || !layout.isAppSource(path)) return;
    final row = KitIsTracked.rowOwning(layout.kit, relative);
    if (row == null) return;
    final finder = _ReferenceFinder();
    for (final unit in context.allUnits) {
      unit.unit.declarations.accept(finder);
    }
    if (finder.found) return;
    final token = node.declarations.whereType<ClassDeclaration>().firstOrNull?.namePart.typeName ?? node.beginToken;
    rule.reportAtToken(token, arguments: [row]);
  }
}

/// Finds a use of `NeonAnalytics` in the code it visits.
class _ReferenceFinder extends RecursiveAstVisitor<void> {
  static const _name = 'NeonAnalytics';

  bool found = false;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == _name) found = true;
  }

  @override
  void visitNamedType(NamedType node) {
    if (node.name.lexeme == _name) found = true;
    super.visitNamedType(node);
  }
}
