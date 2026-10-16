import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// UI only draws; the cubit of a page or feature is its controller and emits
/// ready-to-draw data (filtered and sorted IDs, formatted numbers and dates,
/// flags). NCC0000060.
///
/// In a widget class (a Flutter `Widget` or `State` subclass) of the UI code
/// (layout roles `pages`, `features`, `global_widgets`), matches:
///
/// * a call of `where`, `firstWhere`, `sort`, `fold`, `reduce`, `any`,
///   `every` or `expand` on an `Iterable` whose element type is an app model:
///   a class declared in the layout role `model` (enums are not models here);
/// * `DateTime.now()`;
/// * arithmetic (`+ - * / ~/ %`) on numbers with an operand that reads a
///   field of an app model object (`coupon.price * 2`, `(a.total - b.total) / 2`);
///   a chain of arithmetic is reported once, at its outermost expression.
///
/// Not matched: mapping data to widgets (`.map((x) => Widget(...))`,
/// collection-for), comparisons, string concatenation, a kit component
/// computing its layout from its own number parameters, and everything
/// outside widget classes.
class NoDataLogicInUi extends AnalysisRule {
  NoDataLogicInUi() : super(name: 'no_data_logic_in_ui', description: _desc);

  static const _desc = 'UI only draws; computations over data happen in the cubit, which emits ready-to-draw data.';

  static const LintCode code = LintCode(
    'no_data_logic_in_ui',
    '[NEON] {0} in a widget; UI only draws. The cubit is the controller: it computes over the data and emits '
        'ready-to-draw values (filtered or sorted IDs, formatted numbers and dates, flags).',
    correctionMessage: 'Move the computation into the cubit and put its result into the state; pure stateless '
        'logic goes to neon_flutter_utils or lib/utils/helpers/.',
    severity: DiagnosticSeverity.WARNING,
  );

  static const iterableMethods = {'where', 'firstWhere', 'sort', 'fold', 'reduce', 'any', 'every', 'expand'};

  static const arithmetic = {
    TokenType.PLUS,
    TokenType.MINUS,
    TokenType.STAR,
    TokenType.SLASH,
    TokenType.TILDE_SLASH,
    TokenType.PERCENT,
  };

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final layout = RuleLayout.of(context);
    if (!layout.isUi(context.definingUnit.file.path)) return;
    final visitor = _Visitor(this, layout);
    registry
      ..addMethodInvocation(this, visitor)
      ..addInstanceCreationExpression(this, visitor)
      ..addBinaryExpression(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  bool _inWidgetClass(AstNode node) {
    final element = enclosingClass(node)?.declaredFragment?.element;
    if (element == null) return false;
    return isSubtypeOf(element.thisType, 'Widget', package: 'flutter') ||
        isSubtypeOf(element.thisType, 'State', package: 'flutter');
  }

  bool _isModel(DartType? type) {
    if (type is! InterfaceType) return false;
    final element = type.element;
    if (element is! ClassElement) return false;
    final path = element.library.firstFragment.source.fullName.replaceAll(r'\', '/');
    return layout.isIn(path, LayoutRole.model);
  }

  /// The element type of [type] when it is an `Iterable`.
  DartType? _elementType(DartType? type) {
    if (type is! InterfaceType) return null;
    for (final candidate in [type, ...type.allSupertypes]) {
      if (candidate.element.name == 'Iterable' && candidate.element.library.isDartCore) {
        return candidate.typeArguments.isEmpty ? null : candidate.typeArguments.first;
      }
    }
    return null;
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (!NoDataLogicInUi.iterableMethods.contains(name)) return;
    final target = node.realTarget;
    if (target == null || !_isModel(_elementType(target.staticType))) return;
    if (!_inWidgetClass(node)) return;
    rule.reportAtNode(node.methodName, arguments: ['`.$name(...)` over app model data']);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final constructor = node.constructorName;
    if (constructor.name?.name != 'now') return;
    final type = constructor.type.element;
    if (type is! InterfaceElement || type.name != 'DateTime' || !type.library.isDartCore) return;
    if (!_inWidgetClass(node)) return;
    rule.reportAtNode(node, arguments: ['`DateTime.now()`']);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    if (!_isArithmetic(node)) return;
    // A chain is reported once, at its outermost arithmetic expression.
    AstNode? parent = node.parent;
    while (parent is ParenthesizedExpression) {
      parent = parent.parent;
    }
    if (parent is BinaryExpression && _isArithmetic(parent)) return;
    final read = _modelFieldRead(node);
    if (read == null || !_inWidgetClass(node)) return;
    rule.reportAtNode(node, arguments: ['arithmetic on `${read.toSource()}`']);
  }

  bool _isArithmetic(BinaryExpression node) {
    if (!NoDataLogicInUi.arithmetic.contains(node.operator.type)) return false;
    final type = node.leftOperand.staticType;
    return type is InterfaceType && _isNumber(type);
  }

  static bool _isNumber(InterfaceType type) =>
      type.element.library.isDartCore && const {'num', 'int', 'double'}.contains(type.element.name);

  /// The first operand of the arithmetic chain [node] that reads a field of
  /// an app model object.
  Expression? _modelFieldRead(Expression node) {
    final expression = node.unParenthesized;
    if (expression is BinaryExpression && NoDataLogicInUi.arithmetic.contains(expression.operator.type)) {
      return _modelFieldRead(expression.leftOperand) ?? _modelFieldRead(expression.rightOperand);
    }
    if (expression is PrefixedIdentifier) {
      return _isField(expression.identifier.element) && _isModel(expression.prefix.staticType) ? expression : null;
    }
    if (expression is PropertyAccess) {
      final target = expression.realTarget;
      return _isField(expression.propertyName.element) && _isModel(target.staticType) ? expression : null;
    }
    return null;
  }

  static bool _isField(Element? element) => element is PropertyAccessorElement && !element.isStatic;
}
