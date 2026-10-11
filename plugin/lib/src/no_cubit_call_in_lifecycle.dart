import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';

/// No cubit method call directly in `initState`, `didChangeDependencies` or
/// `build`. A cubit loads in its provider (`create: (_) => X(...)..load()`);
/// `build` only renders. Calls inside callbacks defined there (`onPressed:
/// () => cubit.save()`) run later and are fine.
class NoCubitCallInLifecycle extends AnalysisRule {
  NoCubitCallInLifecycle() : super(name: 'no_cubit_call_in_lifecycle', description: _desc);

  static const _desc = 'Do not call cubit methods in widget lifecycle methods.';

  static const LintCode code = LintCode(
    'no_cubit_call_in_lifecycle',
    '[NEON] {0}() is called in {1}; load in the provider instead: '
        'BlocProvider(create: (_) => XCubit(...)..load()).',
    correctionMessage: 'Move the call into the create: callback, or into a user-action callback.',
    severity: DiagnosticSeverity.WARNING,
  );

  static const lifecycleMethods = {'initState', 'didChangeDependencies', 'build'};

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
    if (!isAppSource(unitPath(node))) return;
    final target = node.realTarget;
    if (target == null || !isBloc(target.staticType)) return;
    final method = _directLifecycleMethod(node);
    if (method == null) return;
    final widgetClass = enclosingClass(method);
    if (widgetClass == null) return;
    final isWidgetCode = supertypeNamed(widgetClass, 'State') != null || supertypeNamed(widgetClass, 'Widget') != null;
    if (!isWidgetCode) return;
    rule.reportAtNode(node.methodName, arguments: [node.methodName.name, method.name.lexeme]);
  }

  /// The lifecycle method whose own body contains [node], not counting
  /// closures defined inside it.
  static MethodDeclaration? _directLifecycleMethod(AstNode node) {
    for (AstNode? current = node.parent; current != null; current = current.parent) {
      if (current is FunctionExpression) return null;
      if (current is MethodDeclaration) {
        return NoCubitCallInLifecycle.lifecycleMethods.contains(current.name.lexeme) ? current : null;
      }
    }
    return null;
  }
}
