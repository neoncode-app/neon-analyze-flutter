import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// An `on*:` callback in a page (`lib/pages`) carries no logic. It is one of:
/// * a cubit-method tear-off: `onTap: cubit.save`,
/// * one cubit-method call: `onTap: () => cubit.save(item)`,
/// * forwarding a callback parameter: `onTap: widget.onTap`,
///   `onTap: () => onSelect(item)`,
/// * a dialog's pure Cancel: `onCancel: () => context.pop()`,
/// * `null`.
/// No `if`, no `await`, no second statement, no other function call.
/// A named argument that is not a function (`onAccentColor: colors.onPrimary`,
/// a colour named after its role) is no callback and is not checked.
class UiCallbackCallsCubit extends AnalysisRule {
  UiCallbackCallsCubit() : super(name: 'ui_callback_calls_cubit', description: _desc);

  static const _desc = 'Page callbacks only call one cubit method or forward a callback.';

  static const LintCode code = LintCode(
    'ui_callback_calls_cubit',
    '[NEON] `{0}:` {1}; a page callback is a cubit-method tear-off (cubit.save), one cubit-method call, '
        'or a forwarded callback parameter. Move the logic into the cubit.',
    correctionMessage: 'Add a cubit method that does this and call it here.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addNamedExpression(this, _Visitor(this, RuleLayout.of(context)));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitNamedExpression(NamedExpression node) {
    final name = node.name.label.name;
    if (!RegExp(r'^on[A-Z]').hasMatch(name) || !layout.isIn(unitPath(node), LayoutRole.pages)) return;
    if (!isAppSource(unitPath(node))) return;
    if (!_isCallbackParameter(node)) return;
    final problem = _problem(node.expression);
    if (problem != null) rule.reportAtNode(node, arguments: [name, problem]);
  }

  /// The argument fills a function-typed parameter (or one the analyzer could
  /// not resolve, which stays checked).
  static bool _isCallbackParameter(NamedExpression node) {
    final type = node.element?.type;
    if (type == null) return true;
    return type is FunctionType || type is DynamicType;
  }

  /// Why [value] is not an allowed callback, or null when it is.
  static String? _problem(Expression value) {
    if (value is NullLiteral) return null;
    if (_isTearOffOrForward(value)) return null;
    if (value is FunctionExpression) {
      final body = value.body;
      if (body.isAsynchronous) return 'is async';
      final Expression? single = switch (body) {
        ExpressionFunctionBody() => body.expression,
        BlockFunctionBody(block: Block(statements: [ExpressionStatement(:final expression)])) => expression,
        BlockFunctionBody(block: Block(statements: [])) => null,
        _ => null,
      };
      if (body is BlockFunctionBody && body.block.statements.isEmpty) return null;
      if (single == null) return 'has more than one statement';
      return _isAllowedCall(single) ? null : 'calls `${_calleeOf(single)}`, not a cubit method';
    }
    if (value is ConditionalExpression) return 'chooses a callback with a condition';
    return 'is `${value.toSource()}`';
  }

  static String _calleeOf(Expression expression) => switch (expression) {
        MethodInvocation(:final methodName) => methodName.name,
        FunctionExpressionInvocation(:final function) => function.toSource(),
        _ => expression.toSource(),
      };

  /// `cubit.save` (method tear-off of a bloc) or a function-typed parameter /
  /// field (`onTap`, `widget.onTap`).
  static bool _isTearOffOrForward(Expression value) {
    final Element? element = switch (value) {
      SimpleIdentifier() => value.element,
      PrefixedIdentifier() => value.identifier.element,
      PropertyAccess() => value.propertyName.element,
      _ => null,
    };
    if (element is MethodElement) {
      final owner = element.enclosingElement;
      return owner is InterfaceElement && isBloc(owner.thisType);
    }
    return _isCallbackVariable(element);
  }

  static bool _isCallbackVariable(Element? element) {
    final variable = element is PropertyAccessorElement ? element.variable : element;
    if (variable is! VariableElement) return false;
    final type = variable.type;
    return type is FunctionType && (variable is FormalParameterElement || variable is FieldElement);
  }

  static bool _isAllowedCall(Expression expression) {
    // `unawaited(cubit.save())`: the discarded_futures form of one call.
    if (expression is MethodInvocation &&
        expression.methodName.name == 'unawaited' &&
        expression.realTarget == null &&
        expression.argumentList.arguments.length == 1) {
      return _isAllowedCall(expression.argumentList.arguments.single);
    }
    if (expression is MethodInvocation) {
      final target = expression.realTarget;
      // One cubit-method call.
      if (target != null && isBloc(target.staticType)) return true;
      // Forwarding a callback field: `widget.onSelect(item)`, `onSelect(item)`,
      // `widget.onTap?.call()`.
      if (_isCallbackVariable(expression.methodName.element)) return true;
      if (expression.methodName.name == 'call' && target != null && _isTearOffOrForward(target)) return true;
      // A dialog's pure Cancel.
      final owner = expression.methodName.element?.enclosingElement;
      if (expression.methodName.name == 'pop' &&
          expression.argumentList.arguments.isEmpty &&
          owner is ExtensionElement &&
          owner.name == 'GoRouterHelper') {
        return true;
      }
      return false;
    }
    if (expression is FunctionExpressionInvocation) {
      final function = expression.function;
      return _isTearOffOrForward(function) ||
          _isCallbackVariable(switch (function) {
            SimpleIdentifier() => function.element,
            PrefixedIdentifier() => function.identifier.element,
            PropertyAccess() => function.propertyName.element,
            _ => null,
          });
    }
    return false;
  }
}
