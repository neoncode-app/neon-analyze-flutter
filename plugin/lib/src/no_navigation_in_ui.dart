import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// UI code (`lib/pages`, `lib/features`, `lib/global_widgets`) does not
/// navigate with go_router itself: a tap calls a cubit method, the cubit
/// emits `NavigateTo`, and `PresentationEventHandler` (or the router)
/// navigates.
///
/// `context.pop()` is allowed in exactly two places: a presentation listener
/// branch handling `CloseDialog`, and a dialog's pure Cancel, a callback whose
/// whole body is `context.pop()` without a result.
class NoNavigationInUi extends AnalysisRule {
  NoNavigationInUi() : super(name: 'no_navigation_in_ui', description: _desc);

  static const _desc = 'Navigate through presentation events, not from UI code.';

  static const LintCode code = LintCode(
    'no_navigation_in_ui',
    '[NEON] context.{0} in UI code; call a cubit method that emits NavigateTo (or CloseDialog) and let '
        'PresentationEventHandler navigate.',
    correctionMessage: 'Emit a presentation event from the cubit instead.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addMethodInvocation(this, _Visitor(this, RuleLayout.of(context)));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (!layout.isUi(unitPath(node))) return;
    final method = node.methodName.element;
    final owner = method?.enclosingElement;
    if (owner is! ExtensionElement || owner.name != 'GoRouterHelper' || !isFromPackage(owner, 'go_router')) return;
    final name = node.methodName.name;
    if (name == 'canPop') return;
    if (name == 'pop' && (_isPureCancel(node) || _handlesCloseDialog(node))) return;
    rule.reportAtNode(node, arguments: [name]);
  }

  /// `() => context.pop()` or `() { context.pop(); }`, no result.
  static bool _isPureCancel(MethodInvocation node) {
    if (node.argumentList.arguments.isNotEmpty) return false;
    final parent = node.parent;
    if (parent is ExpressionFunctionBody) return true;
    return parent is ExpressionStatement &&
        parent.parent is Block &&
        (parent.parent as Block).statements.length == 1 &&
        parent.parent?.parent is BlockFunctionBody;
  }

  /// Inside `if (event is CloseDialog)` or `case CloseDialog():`.
  static bool _handlesCloseDialog(AstNode node) {
    for (AstNode? current = node.parent; current != null; current = current.parent) {
      if (current is IfStatement) {
        final condition = current.expression.unParenthesized;
        if (condition is IsExpression && condition.type.toSource() == 'CloseDialog') return true;
      }
      if (current is SwitchPatternCase && current.guardedPattern.pattern.toSource().startsWith('CloseDialog')) {
        return true;
      }
      if (current is FunctionBody) return false;
    }
    return false;
  }
}
