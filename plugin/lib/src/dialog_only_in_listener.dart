import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';

/// `Utils.showCustomModalBottomSheet` is called only inside a
/// `BlocPresentationListener`'s `listener:` or inside a `show*` function or
/// method (the dialog's own opener, which the listener calls).
///
/// UI never opens a dialog on its own: a tap calls a cubit method, the cubit
/// emits a presentation event, the listener maps it to the dialog.
/// Heuristic: any function whose name starts with `show` counts as an opener;
/// whether the listener really calls it is not checked across files.
class DialogOnlyInListener extends AnalysisRule {
  DialogOnlyInListener() : super(name: 'dialog_only_in_listener', description: _desc);

  static const _desc = 'Open dialogs only from a presentation listener.';

  static const LintCode code = LintCode(
    'dialog_only_in_listener',
    '[NEON] a dialog is opened outside a presentation listener; call a cubit method that emits an event, '
        'and open the dialog in BlocPresentationListener(listener:) or a show* function it calls.',
    correctionMessage: 'Emit a presentation event from the cubit and map it to this dialog in the listener.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addMethodInvocation(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final path = unitPath(node);
    if (!isAppSource(path) || isUnderLib(path, 'utils/utils.dart') || !isDialogHelperCall(node)) return;
    for (AstNode? current = node.parent; current != null; current = current.parent) {
      if (current is FunctionExpression && isPresentationListener(current)) return;
      final name = switch (current) {
        FunctionDeclaration() => current.name.lexeme,
        MethodDeclaration() => current.name.lexeme,
        _ => null,
      };
      if (name != null) {
        if (_isOpenerName(name)) return;
        break;
      }
    }
    rule.reportAtNode(node.methodName);
  }

  static bool _isOpenerName(String name) {
    final bare = name.startsWith('_') ? name.substring(1) : name;
    return bare.startsWith('show');
  }
}
