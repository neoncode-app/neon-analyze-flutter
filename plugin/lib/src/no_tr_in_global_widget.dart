import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
// LintCode is not in the public API surface yet.
import 'package:analyzer/src/dart/error/lint_codes.dart';

/// Forbids `tr()` translation calls inside global/reusable widgets
/// (files under `lib/global_widgets/`). Reusable widgets must stay
/// translation-agnostic: callers pass already-translated text as parameters.
///
/// Matches both `tr('key')` and `'key'.tr()`.
class NoTrInGlobalWidget extends AnalysisRule {
  NoTrInGlobalWidget()
      : super(name: 'no_tr_in_global_widget', description: _desc);

  static const _desc =
      'Global widgets must not call tr(); callers pass translated text.';

  static const LintCode _code = LintCode(
    'no_tr_in_global_widget',
    '[NEON] global widgets must not call tr(); '
        'callers pass already-translated text as parameters.',
    correctionMessage:
        'Remove the tr() call and accept the text via a constructor parameter.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => _code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final path = context.definingUnit.file.path;
    if (!path.contains('/lib/global_widgets/')) return;
    registry.addMethodInvocation(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'tr') {
      rule.reportAtNode(node.methodName);
    }
  }
}
