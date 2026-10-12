import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// UI code never branches on an enum field of a cubit state
/// (`switch (state.tab)`, `state.mode == XMode.edit`): what the page shows is
/// the state's own type, so each value is a subclass of the sealed state
/// (`XListTab`, `XArchiveTab`) and the UI switches on the state itself.
///
/// The convention it enforces: a sealed base holding the data every state
/// shows plus derived getters; final `Initial` / `Loading` / `Loaded` /
/// `Error` subclasses (and one per mode the page switches between); busy
/// markers (`isSaving`, `isLoadingMore`) only on `Loaded`. Enums that only
/// style a widget (`AppLabelVariant`, a size variant) are not state and stay;
/// an enum that is a value the user picks (a period, a filter) may stay on
/// the state as long as the UI only shows it and passes it back.
class NoStateEnumBranching extends AnalysisRule {
  NoStateEnumBranching() : super(name: 'no_state_enum_branching', description: _desc);

  static const _desc = 'The UI switches on the state type, never on an enum field of a cubit state.';

  static const LintCode code = LintCode(
    'no_state_enum_branching',
    '[NEON] the UI branches on `{0}.{1}`, an enum field of a cubit state; make each value a subclass '
        'of the sealed state and switch on the state itself.',
    correctionMessage: 'Replace the enum field with sealed state subclasses (one per value the UI shows).',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _Visitor(this, RuleLayout.of(context));
    registry
      ..addSwitchExpression(this, visitor)
      ..addSwitchStatement(this, visitor)
      ..addBinaryExpression(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitSwitchExpression(SwitchExpression node) => _check(node.expression);

  @override
  void visitSwitchStatement(SwitchStatement node) => _check(node.expression);

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final operator = node.operator.type;
    if (operator != TokenType.EQ_EQ && operator != TokenType.BANG_EQ) return;
    // Only a comparison with a constant is a branch on the value;
    // `previous.tab != current.tab` (a listenWhen) and `tier == state.tier`
    // (marking the selected entry of a list) are not.
    if (_isEnumConstant(node.rightOperand)) {
      _check(node.leftOperand);
    } else if (_isEnumConstant(node.leftOperand)) {
      _check(node.rightOperand);
    }
  }

  static bool _isEnumConstant(Expression expression) {
    final element = switch (expression) {
      PrefixedIdentifier(:final identifier) => identifier.element,
      PropertyAccess(:final propertyName) => propertyName.element,
      _ => null,
    };
    final variable = element is PropertyAccessorElement ? element.variable : element;
    return variable is FieldElement && variable.isEnumConstant;
  }

  /// Reports [expression] when it reads an enum field of a cubit state.
  void _check(Expression expression) {
    final (target, property) = switch (expression) {
      PrefixedIdentifier(:final prefix, :final identifier) => (prefix, identifier),
      PropertyAccess(:final realTarget, :final propertyName) => (realTarget, propertyName),
      _ => (null, null),
    };
    if (target == null || property == null || !layout.isUi(unitPath(expression))) return;
    if (property.staticType?.element is! EnumElement) return;
    final owner = target.staticType?.element;
    if (owner is! InterfaceElement || !_isCubitState(owner)) return;
    rule.reportAtNode(expression, arguments: [owner.name ?? '', property.name]);
  }

  /// A class named `*State` (or extending one) declared in the cubits' folder;
  /// Flutter's own `State` is not one.
  bool _isCubitState(InterfaceElement element) {
    final declaredIn = element.library.firstFragment.source.fullName.replaceAll(r'\', '/');
    if (!layout.isIn(declaredIn, LayoutRole.bloc)) return false;
    return [element.thisType, ...element.allSupertypes]
        .any((type) => (type.element.name ?? '').endsWith('State') && type.element.name != 'State');
  }
}
