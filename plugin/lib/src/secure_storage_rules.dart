import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

// The secure store (NCC0000069, rule doc `secure_storage`): one owner (the
// layout role `secure_storage`, default lib/repository/shared_prefs_repository.dart),
// every platform option set explicitly, and only the secret keys listed under
// `secure_storage_keys:` in neon_check.yaml are written.

const _package = 'flutter_secure_storage';

bool _isSecureStorage(Element? element) => element?.name == 'FlutterSecureStorage' && isFromPackage(element, _package);

/// `FlutterSecureStorage(` is constructed only by the secure store owner.
class SecureStorageOnlyInRepository extends AnalysisRule {
  SecureStorageOnlyInRepository() : super(name: 'secure_storage_only_in_repository', description: _desc);

  static const _desc = 'FlutterSecureStorage is constructed only in the secure store repository.';

  static const LintCode code = LintCode(
    'secure_storage_only_in_repository',
    '[NEON] FlutterSecureStorage constructed outside the secure store ({0}).',
    correctionMessage: 'Read and write secrets through the secure store repository (SharedPrefsRepository); '
        'settings that are no secret go to Hive (DeviceSettingsRepository).',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addInstanceCreationExpression(this, _OwnerVisitor(this, RuleLayout.of(context)));
  }
}

class _OwnerVisitor extends SimpleAstVisitor<void> {
  _OwnerVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (!_isSecureStorage(node.constructorName.element?.enclosingElement)) return;
    final path = unitPath(node);
    if (!layout.isAppSource(path) || layout.isIn(path, LayoutRole.secureStorage)) return;
    rule.reportAtNode(node.constructorName, arguments: [layout.describe(LayoutRole.secureStorage)]);
  }
}

/// Every `FlutterSecureStorage(` passes every platform option explicitly:
/// `aOptions: AndroidOptions(storageNamespace: | sharedPreferencesName:)`,
/// `iOptions: IOSOptions(accountName:, accessibility:)`,
/// `mOptions: MacOsOptions(accountName:, accessibility:)` and
/// `webOptions: WebOptions(dbName:)`.
class SecureStorageOptions extends AnalysisRule {
  SecureStorageOptions() : super(name: 'secure_storage_options', description: _desc);

  static const _desc = 'FlutterSecureStorage sets every platform option explicitly.';

  static const LintCode code = LintCode(
    'secure_storage_options',
    '[NEON] FlutterSecureStorage misses {0}.',
    correctionMessage: "Pass aOptions: AndroidOptions(storageNamespace: '<App>Prefs'), iOptions: IOSOptions("
        "accountName: '<App>Keychain', accessibility: KeychainAccessibility.first_unlock), mOptions: MacOsOptions("
        "accountName:, accessibility:) and webOptions: WebOptions(dbName: '<App>Secure', publicKey: '<App>'); "
        'the names never change once shipped.',
    severity: DiagnosticSeverity.WARNING,
  );

  /// Option argument -> its options class -> the arguments it needs (a `|`
  /// separates alternatives).
  static const required = <String, (String, List<String>)>{
    'aOptions': ('AndroidOptions', ['storageNamespace|sharedPreferencesName']),
    'iOptions': ('IOSOptions', ['accountName', 'accessibility']),
    'mOptions': ('MacOsOptions', ['accountName', 'accessibility']),
    'webOptions': ('WebOptions', ['dbName']),
  };

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addInstanceCreationExpression(this, _OptionsVisitor(this, RuleLayout.of(context)));
  }
}

class _OptionsVisitor extends SimpleAstVisitor<void> {
  _OptionsVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  static Map<String, Expression> _named(ArgumentList list) => {
        for (final argument in list.arguments.whereType<NamedExpression>())
          argument.name.label.name: argument.expression,
      };

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (!_isSecureStorage(node.constructorName.element?.enclosingElement)) return;
    if (!layout.isAppSource(unitPath(node))) return;
    final given = _named(node.argumentList);
    final missing = <String>[];
    for (final MapEntry(key: option, value: (type, arguments)) in SecureStorageOptions.required.entries) {
      final value = given[option];
      if (value is! InstanceCreationExpression || value.constructorName.type.name.lexeme != type) {
        missing.add('$option: $type(...)');
        continue;
      }
      final inner = _named(value.argumentList);
      for (final argument in arguments) {
        final alternatives = argument.split('|');
        if (alternatives.any(inner.containsKey)) continue;
        missing.add('$type(${alternatives.join(' or ')}:)');
      }
    }
    if (missing.isEmpty) return;
    rule.reportAtNode(node.constructorName, arguments: [missing.join(', ')]);
  }
}

/// In the secure store owner, every `write` stores a key built from one of
/// the secret key values of `secure_storage_keys:` (neon_check.yaml). The key
/// expression is resolved through string literals, constants, interpolations
/// and the methods of the same file that build the key.
class SecureStorageKeys extends AnalysisRule {
  SecureStorageKeys() : super(name: 'secure_storage_keys', description: _desc);

  static const _desc = 'The secure store writes only the secret keys of secure_storage_keys.';

  static const LintCode code = LintCode(
    'secure_storage_keys',
    '[NEON] the secure store writes {0}, which is no secret key of secure_storage_keys ({1}).',
    correctionMessage: 'The secure store holds secrets only (tokens). Put a setting into Hive '
        '(DeviceSettingsRepository); a new secret key is added to secure_storage_keys: in neon_check.yaml.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addMethodInvocation(this, _KeysVisitor(this, RuleLayout.of(context)));
  }
}

class _KeysVisitor extends SimpleAstVisitor<void> {
  _KeysVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name != 'write') return;
    final targetType = node.realTarget?.staticType;
    if (!_isSecureStorage(targetType?.element)) return;
    final path = unitPath(node);
    if (!layout.isAppSource(path) || !layout.isIn(path, LayoutRole.secureStorage)) return;
    final key = node.argumentList.arguments
        .whereType<NamedExpression>()
        .where((argument) => argument.name.label.name == 'key')
        .firstOrNull
        ?.expression;
    if (key == null) return;
    final allowed = layout.secureStorageKeys;
    final values = <String>{};
    _collect(key, values, depth: 0);
    if (values.any(allowed.contains)) return;
    rule.reportAtNode(key, arguments: [
      values.isEmpty ? 'a key it cannot resolve (${key.toSource()})' : values.join(' / '),
      allowed.isEmpty ? 'none listed' : allowed.join(', '),
    ]);
  }

  /// Collects the constant string values [expression] is built from.
  static void _collect(AstNode expression, Set<String> values, {required int depth}) {
    if (depth > 3) return;
    switch (expression) {
      case SimpleStringLiteral():
        values.add(expression.value);
      case StringInterpolation():
        for (final element in expression.elements) {
          if (element is InterpolationExpression) _collect(element.expression, values, depth: depth + 1);
        }
      case SimpleIdentifier():
        _addConstant(expression.element, values);
      case PrefixedIdentifier():
        _addConstant(expression.element, values);
      case PropertyAccess():
        _addConstant(expression.propertyName.element, values);
      case ParenthesizedExpression():
        _collect(expression.expression, values, depth: depth + 1);
      case MethodInvocation():
        final name = expression.methodName.name;
        final unit = expression.root;
        if (unit is! CompilationUnit) return;
        final finder = _DeclarationFinder(name);
        unit.accept(finder);
        final body = finder.body;
        if (body != null) _collect(body, values, depth: depth + 1);
      case FunctionBody():
        final finder = _ExpressionCollector();
        expression.accept(finder);
        for (final found in finder.found) {
          _collect(found, values, depth: depth + 1);
        }
      default:
        break;
    }
  }

  static void _addConstant(Element? element, Set<String> values) {
    final variable = switch (element) {
      GetterElement() => element.variable,
      VariableElement() => element,
      _ => null,
    };
    final value = variable?.computeConstantValue()?.toStringValue();
    if (value != null) values.add(value);
  }
}

/// The body of the function or method [name] declared in a unit.
class _DeclarationFinder extends RecursiveAstVisitor<void> {
  _DeclarationFinder(this.name);

  final String name;

  FunctionBody? body;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme == name) body ??= node.body;
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.name.lexeme == name) body ??= node.functionExpression.body;
    super.visitFunctionDeclaration(node);
  }
}

/// The string-building expressions of a body: its string literals and
/// interpolations, and the identifiers they use.
class _ExpressionCollector extends RecursiveAstVisitor<void> {
  final List<AstNode> found = [];

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) => found.add(node);

  @override
  void visitStringInterpolation(StringInterpolation node) => found.add(node);
}
