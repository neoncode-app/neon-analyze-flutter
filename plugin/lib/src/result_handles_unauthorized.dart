import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';

/// `Result.when(...)` of package:neonapi without an `unauthorized:` argument
/// runs no branch for an `Unauthorized` result and returns null, so a load
/// that emitted its loading state stays on the skeleton after a 401
/// (NCI0000022). `handleError(error:, success:)` routes `Unauthorized` to
/// `error`; a `when` that really wants the third case names it.
class ResultHandlesUnauthorized extends AnalysisRule {
  ResultHandlesUnauthorized() : super(name: 'result_handles_unauthorized', description: _desc);

  static const _desc = 'Result.when(...) without unauthorized: swallows a 401; use handleError.';

  static const LintCode code = LintCode(
    'result_handles_unauthorized',
    '[NEON] Result.when(...) without `unauthorized:` runs no branch on a 401, so the caller hangs in its '
        'loading state; use result.handleError(error: ..., success: ...).',
    correctionMessage: 'Replace with handleError(error:, success:), which routes Unauthorized to error, '
        'or pass an explicit unauthorized: callback.',
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
    if (node.methodName.name != 'when') return;
    if (!isAppSource(unitPath(node))) return;
    final target = node.realTarget;
    if (target == null || !isSubtypeOf(target.staticType, 'Result', package: 'neonapi')) return;
    final hasUnauthorized = node.argumentList.arguments.any(
      (argument) => argument is NamedExpression && argument.name.label.name == 'unauthorized',
    );
    if (hasUnauthorized) return;
    rule.reportAtNode(node.methodName);
  }
}
