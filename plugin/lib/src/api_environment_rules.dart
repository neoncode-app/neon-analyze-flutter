import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

// The API environment can never be swapped (NCC0000068, rule doc
// `api_environment`): every value that differs per environment is written on
// the ApiEnvironment enum, and the one decision point is
// `FlavorConfig.defaultApiEnvironment => kReleaseMode ? ApiEnvironment.prod :
// ApiEnvironment.test`.

const _enumName = 'ApiEnvironment';

const _buildModes = {'kReleaseMode', 'kDebugMode', 'kProfileMode'};

bool _isEnvironment(DartType? type) => type is InterfaceType && type.element.name == _enumName;

/// An `ApiEnvironment.x` constant.
bool _isEnvironmentConstant(Expression expression) {
  final prefix = switch (expression) {
    PrefixedIdentifier() => expression.prefix.name,
    PropertyAccess(target: SimpleIdentifier(:final name)) => name,
    _ => null,
  };
  return prefix == _enumName && _isEnvironment(expression.staticType);
}

/// The build mode (`kReleaseMode`, `kDebugMode`, `kProfileMode`) is read
/// nowhere but in the one default getter, no condition branches on
/// `isProduction` or compares an environment with an ApiEnvironment constant,
/// and no `switch` runs over ApiEnvironment outside the enum: a value that
/// differs per environment is a field of ApiEnvironment.
class ApiEnvironmentValuesOnEnum extends AnalysisRule {
  ApiEnvironmentValuesOnEnum() : super(name: 'api_environment_values_on_enum', description: _desc);

  static const _desc = 'Values that differ per API environment live on ApiEnvironment; no branch picks them.';

  static const LintCode code = LintCode(
    'api_environment_values_on_enum',
    '[NEON] {0}; a value that differs per environment is a field of ApiEnvironment.',
    correctionMessage: 'Read the value from ApiConfig.environment (a field of the ApiEnvironment enum). The only '
        'decision point is FlavorConfig.defaultApiEnvironment => kReleaseMode ? ApiEnvironment.prod : '
        'ApiEnvironment.test.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _Visitor(this, RuleLayout.of(context));
    registry
      ..addSimpleIdentifier(this, visitor)
      ..addConditionalExpression(this, visitor)
      ..addIfStatement(this, visitor)
      ..addIfElement(this, visitor)
      ..addSwitchStatement(this, visitor)
      ..addSwitchExpression(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  bool _inScope(AstNode node) => layout.isAppSource(unitPath(node));

  void _check(AstNode node, Expression condition) {
    final finder = _ConditionFinder();
    condition.accept(finder);
    final reason = finder.reason;
    if (reason == null || !_inScope(node) || _isTheDefault(node)) return;
    rule.reportAtNode(condition, arguments: ['a branch on $reason']);
  }

  /// `defaultApiEnvironment => kReleaseMode ? ApiEnvironment.prod : ApiEnvironment.test`.
  static bool _isTheDefault(AstNode node) {
    if (node is! ConditionalExpression) return false;
    final getter = node.thisOrAncestorOfType<MethodDeclaration>();
    if (getter == null || !getter.isGetter || getter.name.lexeme != 'defaultApiEnvironment') return false;
    final condition = node.condition;
    final then = node.thenExpression;
    final otherwise = node.elseExpression;
    return condition is SimpleIdentifier &&
        condition.name == 'kReleaseMode' &&
        _isEnvironmentConstant(then) &&
        then.toSource().endsWith('.prod') &&
        _isEnvironmentConstant(otherwise);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (!_buildModes.contains(node.name) || node.inDeclarationContext() || !_inScope(node)) return;
    final conditional = node.parent;
    if (conditional is ConditionalExpression && conditional.condition == node && _isTheDefault(conditional)) return;
    rule.reportAtNode(node, arguments: ['${node.name} decides a value']);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) => _check(node, node.condition);

  @override
  void visitIfStatement(IfStatement node) => _check(node, node.expression);

  @override
  void visitIfElement(IfElement node) => _check(node, node.expression);

  @override
  void visitSwitchStatement(SwitchStatement node) => _checkSwitch(node, node.expression);

  @override
  void visitSwitchExpression(SwitchExpression node) => _checkSwitch(node, node.expression);

  void _checkSwitch(AstNode node, Expression subject) {
    if (!_isEnvironment(subject.staticType) || !_inScope(node)) return;
    final declaring = node.thisOrAncestorOfType<EnumDeclaration>();
    if (declaring != null && declaring.namePart.typeName.lexeme == _enumName) return;
    rule.reportAtNode(subject, arguments: ['a switch over ApiEnvironment']);
  }
}

/// Finds what a condition branches on: `isProduction`, or an ApiEnvironment
/// compared with one of its constants (a build-mode constant is reported on
/// its own).
class _ConditionFinder extends RecursiveAstVisitor<void> {
  String? reason;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (reason == null && node.name == 'isProduction') reason = node.name;
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final op = node.operator.type;
    if (reason == null &&
        (op == TokenType.EQ_EQ || op == TokenType.BANG_EQ) &&
        (_isEnvironmentConstant(node.leftOperand) || _isEnvironmentConstant(node.rightOperand))) {
      reason = 'the environment (${node.toSource()})';
    }
    super.visitBinaryExpression(node);
  }
}
