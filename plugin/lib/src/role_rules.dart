import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// Roles are enums (`AppRole`, `NeoncodeRole`, `VernakRole` in
/// `lib/model/enum/`); their backend strings appear nowhere else.
class NoRoleLiteral extends AnalysisRule {
  NoRoleLiteral() : super(name: 'no_role_literal', description: _desc);

  static const _desc = 'Use the role enums, never role strings.';

  static const LintCode code = LintCode(
    'no_role_literal',
    "[NEON] role string '{0}'; use the role enums (AppRole, NeoncodeRole, VernakRole in lib/model/enum/).",
    correctionMessage: 'Replace the string with the enum value (e.g. AppRole.vernakAdmin).',
    severity: DiagnosticSeverity.WARNING,
  );

  /// The backend role strings (`AppRole.value` plus the platform `root`).
  static const roles = {
    'root',
    'admin',
    'neoncode-admin',
    'vernak-root',
    'vernak-admin',
    'vernak-editor',
    'vernak-service',
    'vernak-user',
  };

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addSimpleStringLiteral(this, _RoleVisitor(this, RuleLayout.of(context)));
  }
}

class _RoleVisitor extends SimpleAstVisitor<void> {
  _RoleVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (!NoRoleLiteral.roles.contains(node.value)) return;
    final path = unitPath(node);
    if (!isAppSource(path) || layout.isIn(path, LayoutRole.roleEnums)) return;
    if (node.parent is Directive || node.parent is Configuration) return;
    rule.reportAtNode(node, arguments: [node.value]);
  }
}

/// No `RoleGuard` and no access-denied widget inside `lib/pages`: who may
/// open a page is declared on its route (a rules getter evaluated against the
/// role at the active company). `context.vernakRules.*` still decides what
/// parts of a page are visible.
class NoAccessGuardInPages extends AnalysisRule {
  NoAccessGuardInPages() : super(name: 'no_access_guard_in_pages', description: _desc);

  static const _desc = 'Access is declared on the route, not inside the page.';

  static const LintCode code = LintCode(
    'no_access_guard_in_pages',
    '[NEON] {0} inside a page; declare the permission on the route '
        '((rules) => rules.canX, evaluated against the active company role).',
    correctionMessage: 'Move the guard to the route builder.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addInstanceCreationExpression(this, _GuardVisitor(this, RuleLayout.of(context)));
  }
}

class _GuardVisitor extends SimpleAstVisitor<void> {
  _GuardVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final name = node.constructorName.element?.enclosingElement.name ?? '';
    if (name != 'RoleGuard' && !name.contains('AccessDenied')) return;
    final path = unitPath(node);
    if (!isAppSource(path) || !layout.isIn(path, LayoutRole.pages)) return;
    rule.reportAtNode(node.constructorName, arguments: ['`$name`']);
  }
}
