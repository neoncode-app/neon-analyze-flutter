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

// The API environment is fixed by the build (NCC0000068, NCC0000076, rule doc
// `api_environment`): every value that differs per environment is written on
// the ApiEnvironment enum, and the one decision point is the enum's resolver,
// `static final ApiEnvironment current = resolve(const String.fromEnvironment('API_ENV'),
// isRelease: kReleaseMode);`. Nothing assigns, persists or switches it later.

const _enumName = 'ApiEnvironment';

/// The field of the enum that holds the build's environment.
const _resolverField = 'current';

/// The compile-time define that names the environment.
const _define = 'API_ENV';

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

/// Whether [node] sits inside the declaration of the enum ApiEnvironment.
bool _inEnvironmentEnum(AstNode node) =>
    node.thisOrAncestorOfType<EnumDeclaration>()?.namePart.typeName.lexeme == _enumName;

/// Whether [node] sits inside the initializer of the enum's resolver field
/// (`static final ApiEnvironment current = ...`).
bool _inResolver(AstNode node) {
  if (!_inEnvironmentEnum(node)) return false;
  final field = node.thisOrAncestorOfType<FieldDeclaration>();
  if (field == null || !field.isStatic) return false;
  return field.fields.variables.any((variable) => variable.name.lexeme == _resolverField);
}

/// The build mode (`kReleaseMode`, `kDebugMode`, `kProfileMode`) is read
/// nowhere but in the resolver of ApiEnvironment, no condition branches on
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
        "decision point is ApiEnvironment.current = resolve(const String.fromEnvironment('API_ENV'), "
        'isRelease: kReleaseMode).',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _ValuesVisitor(this, RuleLayout.of(context));
    registry
      ..addSimpleIdentifier(this, visitor)
      ..addConditionalExpression(this, visitor)
      ..addIfStatement(this, visitor)
      ..addIfElement(this, visitor)
      ..addSwitchStatement(this, visitor)
      ..addSwitchExpression(this, visitor);
  }
}

class _ValuesVisitor extends SimpleAstVisitor<void> {
  _ValuesVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  bool _inScope(AstNode node) => layout.isAppSource(unitPath(node));

  void _check(AstNode node, Expression condition) {
    final finder = _ConditionFinder();
    condition.accept(finder);
    final reason = finder.reason;
    if (reason == null || !_inScope(node)) return;
    rule.reportAtNode(condition, arguments: ['a branch on $reason']);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (!_buildModes.contains(node.name) || node.inDeclarationContext() || !_inScope(node)) return;
    if (node.name == 'kReleaseMode' && _inResolver(node)) return;
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
    if (!_isEnvironment(subject.staticType) || !_inScope(node) || _inEnvironmentEnum(node)) return;
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

/// The environment is fixed by the build and nothing changes it at runtime:
///
/// - no assignment to an ApiEnvironment (`ApiConfig.environment = ...`,
///   `environmentOverride = ...`) and no mutable field or top-level variable of
///   that type (a setter in disguise);
/// - `String.fromEnvironment('API_ENV')` is read only by the enum's resolver;
/// - no `setBaseUrl(...)` re-points the API client at runtime;
/// - no environment choice is persisted: a key such as `api_environment` or
///   `key_api_environment` is used only to delete what an older build stored
///   (an argument of `remove` / `delete`).
class ApiEnvironmentFixedByBuild extends AnalysisRule {
  ApiEnvironmentFixedByBuild() : super(name: 'api_environment_fixed_by_build', description: _desc);

  static const _desc = 'The API environment is fixed by the build (API_ENV); nothing switches or persists it.';

  static const LintCode code = LintCode(
    'api_environment_fixed_by_build',
    '[NEON] {0}; the API environment is fixed by the build (API_ENV) and never switched at runtime.',
    correctionMessage: 'Read ApiConfig.environment (ApiEnvironment.current, resolved once from '
        "const String.fromEnvironment('API_ENV')). Build TEST and PROD with --dart-define=API_ENV=test|prod "
        '(tool/build.sh --env, f-build build.config); no switch, no persisted choice, no setter.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _FixedVisitor(this, RuleLayout.of(context));
    registry
      ..addAssignmentExpression(this, visitor)
      ..addFieldDeclaration(this, visitor)
      ..addTopLevelVariableDeclaration(this, visitor)
      ..addInstanceCreationExpression(this, visitor)
      ..addMethodInvocation(this, visitor)
      ..addSimpleStringLiteral(this, visitor);
  }
}

class _FixedVisitor extends SimpleAstVisitor<void> {
  _FixedVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  /// A storage key that holds an environment choice.
  static final _persistedKey = RegExp(r'^(key_)?(api_env|api_environment|apiEnv|apiEnvironment)$');

  bool _inScope(AstNode node) => layout.isAppSource(unitPath(node));

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    if (!_isEnvironment(node.writeType) || !_inScope(node)) return;
    rule.reportAtNode(node, arguments: ['an assignment to the environment']);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) => _checkVariables(node.fields);

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) => _checkVariables(node.variables);

  void _checkVariables(VariableDeclarationList list) {
    if (list.isFinal || list.isConst || !_inScope(list)) return;
    for (final variable in list.variables) {
      if (!_isEnvironment(variable.declaredFragment?.element.type)) continue;
      rule.reportAtToken(variable.name, arguments: ['a mutable environment `${variable.name.lexeme}`']);
    }
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final constructor = node.constructorName;
    if (constructor.type.name.lexeme != 'String' || constructor.name?.name != 'fromEnvironment') return;
    final arguments = node.argumentList.arguments;
    final first = arguments.isEmpty ? null : arguments.first;
    if (first is! SimpleStringLiteral || first.value != _define) return;
    if (!_inScope(node) || _inResolver(node)) return;
    rule.reportAtNode(node, arguments: ['$_define read outside ApiEnvironment.$_resolverField']);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name != 'setBaseUrl' || !_inScope(node)) return;
    rule.reportAtNode(node.methodName, arguments: ['the API client re-pointed at runtime (setBaseUrl)']);
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (!_persistedKey.hasMatch(node.value) || !_inScope(node) || _isDeletion(node)) return;
    rule.reportAtNode(node, arguments: ['a persisted environment choice (${node.toSource()})']);
  }

  /// Whether [literal] is the key argument of a `remove(...)` / `delete(key: ...)`
  /// call: deleting what an older build persisted is allowed.
  static bool _isDeletion(SimpleStringLiteral literal) {
    var argument = literal.parent;
    if (argument is NamedExpression) argument = argument.parent;
    final invocation = argument is ArgumentList ? argument.parent : null;
    return invocation is MethodInvocation && const {'remove', 'delete'}.contains(invocation.methodName.name);
  }
}
