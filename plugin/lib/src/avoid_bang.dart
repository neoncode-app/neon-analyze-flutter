import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
// LintCode is not in the public API surface yet.
import 'package:analyzer/src/dart/error/lint_codes.dart';

/// Flags the null-assertion operator `!`.
///
/// Neon Code rule: never use `!`; use an explicit null check or a null-aware
/// pattern instead. `!` bypasses null safety and can crash at runtime.
class AvoidBang extends AnalysisRule {
  AvoidBang() : super(name: 'avoid_bang', description: _desc);

  static const _desc = 'Avoid the null-assertion operator `!`.';

  static const LintCode _code = LintCode(
    'avoid_bang',
    '[NEON] avoid the null-assertion operator `!` — it bypasses null safety '
        'and can crash at runtime.',
    correctionMessage:
        'Use an explicit null check (if (x != null)) or a null-aware pattern.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => _code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addPostfixExpression(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitPostfixExpression(PostfixExpression node) {
    if (node.operator.lexeme == '!') {
      rule.reportAtNode(node);
    }
  }
}
