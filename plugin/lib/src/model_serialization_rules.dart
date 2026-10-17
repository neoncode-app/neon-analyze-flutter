import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/model_layout_rules.dart' show classMembers, hasJsonSerializable, isJsonConverter;
import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

// Every model serializes through json_serializable, and no model field is
// dynamic (NCC0000066). Special cases go through @JsonKey(fromJson:, toJson:,
// defaultValue:, unknownEnumValue:), @JsonEnum and the converters of
// package:neon_flutter_utils/json.dart; the project defaults (explicit_to_json,
// checked, include_if_null) are in the app's build.yaml.

/// The `fromJson` constructor or static method of a class.
bool _isFromJson(ClassMember member) => switch (member) {
      ConstructorDeclaration(:final name?) => name.lexeme == 'fromJson',
      MethodDeclaration() => member.isStatic && member.name.lexeme == 'fromJson',
      _ => false,
    };

/// The `toJson` instance method of a class.
bool _isToJson(ClassMember member) =>
    member is MethodDeclaration && !member.isStatic && !member.isGetter && member.name.lexeme == 'toJson';

/// The one expression [body] returns: `=> e` or `{ return e; }`.
Expression? _returned(FunctionBody? body) => switch (body) {
      ExpressionFunctionBody() => body.expression,
      BlockFunctionBody(block: Block(statements: [ReturnStatement(:final expression)])) => expression,
      _ => null,
    };

/// Whether [expression] calls the generated function `_$<Class><suffix>`
/// (`_$UserFromJson(json)`, `_$UserToJson(this)`).
bool _callsGenerated(Expression? expression, String suffix) {
  final name = switch (expression) {
    MethodInvocation(target: null) => expression.methodName.name,
    FunctionExpressionInvocation(function: SimpleIdentifier(:final name)) => name,
    _ => null,
  };
  return name != null && name.startsWith(r'_$') && name.endsWith(suffix);
}

/// In the model role, a class with a `fromJson` constructor / static method or
/// a `toJson` method is a model: it is annotated `@JsonSerializable` and those
/// members return the generated `_$XFromJson(json)` / `_$XToJson(this)`.
/// A `JsonConverter` implementation is no model. Enums serialize through
/// `@JsonEnum` and are not checked here.
class ModelUsesJsonSerializable extends AnalysisRule {
  ModelUsesJsonSerializable() : super(name: 'model_uses_json_serializable', description: _desc);

  static const _desc = 'Models serialize through json_serializable: @JsonSerializable and the generated functions.';

  static const LintCode code = LintCode(
    'model_uses_json_serializable',
    '[NEON] {0}; every model serializes through json_serializable.',
    correctionMessage: 'Annotate the model @JsonSerializable(), add `part \'<file>.g.dart\';`, make fromJson '
        'return _\$XFromJson(json) and toJson return _\$XToJson(this), and express special cases with '
        '@JsonKey(fromJson:, toJson:, defaultValue:, unknownEnumValue:), @JsonEnum and the converters of '
        'package:neon_flutter_utils/json.dart; then run build_runner.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addClassDeclaration(this, _SerializableVisitor(this, RuleLayout.of(context)));
  }
}

class _SerializableVisitor extends SimpleAstVisitor<void> {
  _SerializableVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final path = unitPath(node);
    if (!layout.isAppSource(path) || !layout.isIn(path, LayoutRole.model) || isJsonConverter(node)) return;
    final members = classMembers(node);
    final fromJson = members.where(_isFromJson).toList();
    final toJson = members.where(_isToJson).toList();
    if (fromJson.isEmpty && toJson.isEmpty) return;
    final name = node.namePart.typeName;
    if (!hasJsonSerializable(node)) {
      rule.reportAtToken(name, arguments: ['the model ${name.lexeme} is not annotated @JsonSerializable']);
    }
    for (final member in fromJson) {
      final body = member is ConstructorDeclaration ? member.body : (member as MethodDeclaration).body;
      if (_callsGenerated(_returned(body), 'FromJson')) continue;
      final at = member is ConstructorDeclaration ? member.name : (member as MethodDeclaration).name;
      if (at == null) continue;
      rule.reportAtToken(at,
          arguments: ['${name.lexeme}.fromJson does not return the generated _\$${name.lexeme}FromJson']);
    }
    for (final member in toJson.cast<MethodDeclaration>()) {
      if (_callsGenerated(_returned(member.body), 'ToJson')) continue;
      rule.reportAtToken(
        member.name,
        arguments: ['${name.lexeme}.toJson does not return the generated _\$${name.lexeme}ToJson'],
      );
    }
  }
}

/// No `dynamic` in models: a field, constructor parameter or getter of a
/// class (or enum, mixin) in the model role is never `dynamic`, `Object` /
/// `Object?`, or a type with one of those as a type argument
/// (`Map<String, dynamic>`, `List<dynamic>`, `Map<String, Object?>`).
///
/// Allowed: the `Map<String, dynamic> json` parameter of a `fromJson` factory
/// (the generator's entry point), methods (`toJson()` returns
/// `Map<String, dynamic>`), `this.x` / `super.x` parameters (their field is
/// reported once), and a getter overriding an inherited one (`body` /
/// `queryParameters` of a neonapi request), whose type is set by its supertype.
class NoDynamicInModels extends AnalysisRule {
  NoDynamicInModels() : super(name: 'no_dynamic_in_models', description: _desc);

  static const _desc = 'No dynamic, Object? or Map<String, dynamic> fields, parameters or getters in models.';

  static const LintCode code = LintCode(
    'no_dynamic_in_models',
    "[NEON] {0} of {1} is '{2}'; a model field, constructor parameter or getter has a concrete type.",
    correctionMessage: 'Give it a typed model or a concrete type (a nested @JsonSerializable class, an enum, '
        'List<X>, Map<String, X>); keep Map<String, dynamic> only as the fromJson parameter and the toJson result.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _DynamicVisitor(this, RuleLayout.of(context));
    registry
      ..addClassDeclaration(this, visitor)
      ..addEnumDeclaration(this, visitor)
      ..addMixinDeclaration(this, visitor);
  }
}

/// Whether [type] is `dynamic`, `Object` / `Object?`, or has one of those
/// among its type arguments (recursively).
bool isLooseType(DartType? type) {
  if (type == null || type is InvalidType) return false;
  if (type is DynamicType || type.isDartCoreObject) return true;
  return type is InterfaceType && type.typeArguments.any(isLooseType);
}

class _DynamicVisitor extends SimpleAstVisitor<void> {
  _DynamicVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final body = node.body;
    _check(node, node.namePart.typeName.lexeme, body is BlockClassBody ? body.members : const []);
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    final body = node.body;
    _check(node, node.namePart.typeName.lexeme, body.members);
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) => _check(node, node.name.lexeme, node.body.members);

  void _check(AstNode node, String owner, List<ClassMember> members) {
    final path = unitPath(node);
    if (!layout.isAppSource(path) || !layout.isIn(path, LayoutRole.model)) return;
    for (final member in members) {
      switch (member) {
        case FieldDeclaration():
          for (final variable in member.fields.variables) {
            final type = variable.declaredFragment?.element.type;
            if (!isLooseType(type)) continue;
            _report(variable.name, 'the field ${variable.name.lexeme}', owner, type);
          }
        case ConstructorDeclaration():
          final isFromJson = member.name?.lexeme == 'fromJson';
          for (final parameter in member.parameters.parameters) {
            final simple = parameter is DefaultFormalParameter ? parameter.parameter : parameter;
            if (simple is FieldFormalParameter || simple is SuperFormalParameter) continue;
            final type = simple.declaredFragment?.element.type;
            if (!isLooseType(type)) continue;
            if (isFromJson && _isJsonMap(type)) continue;
            final name = simple.name;
            if (name == null) continue;
            _report(name, 'the constructor parameter ${name.lexeme}', owner, type);
          }
        case MethodDeclaration(isGetter: true):
          if (member.metadata.any((annotation) => annotation.name.name == 'override')) continue;
          // An inherited getter (NeoRequest.queryParameters) keeps the type its
          // supertype declares, with or without the @override annotation.
          if (_overridesInherited(node, member.name.lexeme)) continue;
          final type = member.declaredFragment?.element.returnType;
          if (!isLooseType(type)) continue;
          _report(member.name, 'the getter ${member.name.lexeme}', owner, type);
        default:
          break;
      }
    }
  }

  /// Whether a supertype of the class [node] declares a getter [name].
  bool _overridesInherited(AstNode node, String name) {
    final element = switch (node) {
      ClassDeclaration() => node.declaredFragment?.element,
      EnumDeclaration() => node.declaredFragment?.element,
      MixinDeclaration() => node.declaredFragment?.element,
      _ => null,
    };
    if (element == null) return false;
    return element.allSupertypes.any((supertype) => supertype.getGetter(name) != null);
  }

  /// `Map<String, dynamic>`, the json parameter of a generated `fromJson`.
  bool _isJsonMap(DartType? type) =>
      type is InterfaceType &&
      type.isDartCoreMap &&
      type.typeArguments.length == 2 &&
      type.typeArguments.first.isDartCoreString &&
      type.typeArguments.last is DynamicType;

  void _report(Token at, String what, String owner, DartType? type) =>
      rule.reportAtToken(at, arguments: [what, owner, type?.getDisplayString() ?? 'dynamic']);
}
