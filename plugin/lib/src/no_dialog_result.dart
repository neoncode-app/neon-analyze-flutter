import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// A dialog returns nothing: the result of opening it is never used. No
/// `final x = await show...`, no `if (await show...)`, no `.then(...)`, and no
/// code after an awaited dialog. The dialog's buttons call a cubit method
/// themselves (its own cubit, or a cubit-method callback carried by the
/// presentation event).
///
/// A dialog opening is `Utils.showCustomModalBottomSheet` or any `show*`
/// function or method returning a Future and given a `BuildContext` (the
/// dialog wrappers); a `show*` without a context, such as a system
/// notification, opens no dialog.
class NoDialogResult extends AnalysisRule {
  NoDialogResult() : super(name: 'no_dialog_result', description: _desc);

  static const _desc = 'Never use the result of a dialog.';

  static const LintCode code = LintCode(
    'no_dialog_result',
    '[NEON] {0} uses the result of {1}; a dialog returns nothing. Its buttons call the cubit '
        '(its own cubit, or a cubit-method callback carried by the presentation event).',
    correctionMessage: 'Move the follow-up into the cubit method the dialog button calls.',
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

  static bool _opensDialog(MethodInvocation node) {
    if (isDialogHelperCall(node)) return true;
    final name = node.methodName.name;
    final type = node.staticType;
    return name.startsWith('show') && type != null && type.isDartAsyncFuture && passesBuildContext(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final path = unitPath(node);
    if (!isAppSource(path) || layout.isIn(path, LayoutRole.dialogHelper) || !_opensDialog(node)) return;
    final name = node.methodName.name;
    AstNode expression = node;
    var parent = node.parent;
    if (parent is AwaitExpression) {
      expression = parent;
      parent = parent.parent;
    }
    while (parent is ParenthesizedExpression) {
      expression = parent;
      parent = parent.parent;
    }
    switch (parent) {
      // `show(...);` or `await show(...);`: fine unless more code follows.
      case ExpressionStatement():
        if (expression is AwaitExpression && _followedByCode(parent)) {
          rule.reportAtNode(node.methodName, arguments: ['code after the awaited dialog', name]);
        }
      // Forwarding the Future (`return show(...)`, `=> show(...)`,
      // `unawaited(show(...))`) leaves the result unused here.
      case ReturnStatement() || ExpressionFunctionBody():
        return;
      case ArgumentList(parent: MethodInvocation(methodName: SimpleIdentifier(name: 'unawaited'))):
        return;
      case MethodInvocation(methodName: SimpleIdentifier(name: 'then' || 'whenComplete')):
        rule.reportAtNode(node.methodName, arguments: ['.${parent.methodName.name}()', name]);
      default:
        rule.reportAtNode(node.methodName, arguments: ['this expression', name]);
    }
  }

  /// Whether a statement other than a bare `return;` follows [statement] in
  /// its block.
  static bool _followedByCode(Statement statement) {
    final block = statement.parent;
    if (block is! Block) return false;
    final following = block.statements.skipWhile((each) => each != statement).skip(1);
    return following.any((each) => !(each is ReturnStatement && each.expression == null));
  }
}
