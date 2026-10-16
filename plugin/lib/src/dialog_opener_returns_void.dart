import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// A dialog opener returns `void` (NCC0000062).
///
/// A dialog never returns a result (`no_dialog_result`) and a presentation
/// listener may not await (`listener_is_mapping`), so a `Future` from an
/// opener is only ever wrapped in `unawaited(...)` by its caller. The opener
/// does that once itself, by calling `Utils.openModalBottomSheet`, and the
/// listener line is `if (event is X) return showX(context, event);`.
///
/// An opener is a top-level function or a static method whose name starts
/// with `show` (private too) and whose body opens a dialog: it calls the
/// dialog helper (`Utils.showCustomModalBottomSheet` /
/// `Utils.openModalBottomSheet`) or forwards to another app `show*` function
/// that returns a Future. The dialog helper file itself is the owner.
class DialogOpenerReturnsVoid extends AnalysisRule {
  DialogOpenerReturnsVoid() : super(name: 'dialog_opener_returns_void', description: _desc);

  static const _desc = 'A dialog opener (show* function) returns void.';

  static const LintCode code = LintCode(
    'dialog_opener_returns_void',
    '[NEON] the dialog opener {0} returns {1}; a dialog returns nothing, so an opener returns void and the '
        'listener calls it without unawaited().',
    correctionMessage: 'Declare it `void {0}(...)` and open the dialog with Utils.openModalBottomSheet(...); '
        'the listener line becomes `if (event is X) return {0}(context, event);`.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _Visitor(this, RuleLayout.of(context));
    registry
      ..addFunctionDeclaration(this, visitor)
      ..addMethodDeclaration(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  bool _applies(AstNode node) {
    final path = unitPath(node);
    return isAppSource(path) && !layout.isIn(path, LayoutRole.dialogHelper);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.parent is! CompilationUnit || !isOpenerName(node.name.lexeme) || !_applies(node)) return;
    _check(node.name.lexeme, node.declaredFragment?.element.returnType, node.functionExpression.body, node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (!node.isStatic || !isOpenerName(node.name.lexeme) || !_applies(node)) return;
    _check(node.name.lexeme, node.declaredFragment?.element.returnType, node.body, node);
  }

  void _check(String name, DartType? returnType, FunctionBody body, Declaration node) {
    if (returnType == null || returnType is VoidType) return;
    final finder = _OpensDialog();
    body.accept(finder);
    if (!finder.found) return;
    final token = switch (node) {
      FunctionDeclaration() => node.name,
      MethodDeclaration() => node.name,
      _ => node.beginToken,
    };
    rule.reportAtToken(token, arguments: [name, returnType.getDisplayString()]);
  }
}

/// Finds a dialog opening in a function body: a dialog helper call, or a call
/// of another app `show*` function returning a Future. Nested function
/// declarations are their own openers and are not searched.
class _OpensDialog extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {}

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (isDialogHelperCall(node) || callsFutureOpener(node)) {
      found = true;
      return;
    }
    super.visitMethodInvocation(node);
  }
}
