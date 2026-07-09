import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
// LintCode is not in the public API surface yet.
import 'package:analyzer/src/dart/error/lint_codes.dart';

/// Forbids private helper methods that build and return a `Widget`
/// (`Widget _buildX()`). Such helpers should be extracted into their own
/// `Widget` subclass so the widget tree stays composable and rebuildable.
///
/// Only flags private (`_`-prefixed) declarations with an explicit `Widget`
/// return type. Overrides (e.g. `Widget build(...)`) and public factory-style
/// methods are left alone.
class NoWidgetBuilderMethod extends AnalysisRule {
  NoWidgetBuilderMethod()
      : super(name: 'no_widget_builder_method', description: _desc);

  static const _desc =
      'Do not use private helper methods that return a Widget; '
      'extract a Widget subclass instead.';

  static const LintCode _code = LintCode(
    'no_widget_builder_method',
    '[NEON] do not build widgets in private helper methods; '
        'extract a Widget subclass instead.',
    correctionMessage:
        'Replace this `Widget _build...()` helper with a dedicated Widget class.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => _code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this);
    registry.addMethodDeclaration(this, visitor);
    registry.addFunctionDeclaration(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  bool _returnsWidget(TypeAnnotation? returnType) {
    return returnType is NamedType && returnType.name.lexeme == 'Widget';
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.isGetter || node.isSetter) return;
    if (!node.name.lexeme.startsWith('_')) return;
    if (_returnsWidget(node.returnType)) {
      rule.reportAtToken(node.name);
    }
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.isGetter || node.isSetter) return;
    if (!node.name.lexeme.startsWith('_')) return;
    if (_returnsWidget(node.returnType)) {
      rule.reportAtToken(node.name);
    }
  }
}
