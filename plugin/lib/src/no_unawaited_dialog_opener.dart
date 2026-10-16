import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// No `unawaited(showX(...))` in UI and routing code (NCC0000062): a dialog
/// opener returns void and does the single `unawaited` itself (through
/// `Utils.openModalBottomSheet`), so a presentation listener calls it as
/// `if (event is X) return showX(context, event);`.
///
/// Flagged: `unawaited(...)` (dart:async) whose argument is a call of an app
/// `show*` function or method that returns a Future, reported at the opener
/// (the fix is in the opener, not here), and `unawaited(Utils.showCustomModalBottomSheet(...))`
/// outside a `show*` opener (an opener itself may wrap the helper once).
/// Genuine background work (`unawaited(cubit.load())`, `unawaited(_save())`)
/// is not a dialog opener and stays.
class NoUnawaitedDialogOpener extends AnalysisRule {
  NoUnawaitedDialogOpener() : super(name: 'no_unawaited_dialog_opener', description: _desc);

  static const _desc = 'Call a dialog opener directly; it returns void.';

  static const LintCode code = LintCode(
    'no_unawaited_dialog_opener',
    '[NEON] unawaited({0}(...)) wraps a dialog opener; {1}',
    correctionMessage: 'Make the opener `void` (it calls Utils.openModalBottomSheet) and write the listener line as '
        '`if (event is X) return showX(context, event);`.',
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
    if (node.methodName.name != 'unawaited' || node.target != null) return;
    final function = node.methodName.element;
    if (function is! TopLevelFunctionElement || function.library.uri.toString() != 'dart:async') return;
    final path = unitPath(node);
    if (!isAppSource(path) || layout.isIn(path, LayoutRole.dialogHelper)) return;
    if (!layout.isUi(path) && !layout.isIn(path, LayoutRole.routing)) return;
    final arguments = node.argumentList.arguments;
    if (arguments.length != 1) return;
    var argument = arguments.first;
    while (argument is ParenthesizedExpression) {
      argument = argument.expression;
    }
    if (argument is! MethodInvocation) return;
    final name = argument.methodName.name;
    if (isDialogHelperCall(argument)) {
      if (_insideOpener(node)) return;
      rule.reportAtNode(argument.methodName, arguments: [
        name,
        'open the dialog with Utils.openModalBottomSheet(...), which returns void, inside a void show* opener.',
      ]);
      return;
    }
    if (!callsFutureOpener(argument)) return;
    rule.reportAtNode(argument.methodName, arguments: [
      name,
      'make $name return void (opening the dialog with Utils.openModalBottomSheet) and call it without unawaited().',
    ]);
  }

  /// Whether [node] is in the body of a `show*` function or method.
  static bool _insideOpener(AstNode node) {
    for (AstNode? current = node.parent; current != null; current = current.parent) {
      final name = switch (current) {
        FunctionDeclaration() => current.name.lexeme,
        MethodDeclaration() => current.name.lexeme,
        _ => null,
      };
      if (name != null) return isOpenerName(name);
    }
    return false;
  }
}
