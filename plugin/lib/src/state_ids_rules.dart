import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/file_system.dart';

import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

// Cubit states carry ids, the UI reads entities from Hive (NCC0000071, rule
// doc `state_ids_ui_hive`). A Hive entity is a type with its own typed box:
// an `EntityBox<T>` declared in the app's lib/hive/ or lib/repository/, a
// typed box the app still opens by hand there (`Hive.openBox<T>(...)`, an app
// moving to EntityBox), or a class still annotated `@HiveType`. A value type
// that is only stored inside an entity (a branding, a style) has an adapter
// but no box, and is fine.

final _entityBox = RegExp(r'EntityBox<(\w+)>');

final _openBox = RegExp(r'openBox<(\w+)>');

final _entitiesCache = <String, ({int stamp, Set<String> types})>{};

/// The types that have an `EntityBox` or a typed `Hive.openBox<T>` in the
/// app's lib/hive/ or lib/repository/.
Set<String> _persistedTypes(RuleContext context, RuleLayout layout) {
  final provider = context.definingUnit.file.provider;
  final files = <File>[];
  void collect(Folder folder) {
    if (!folder.exists) return;
    for (final child in folder.getChildren()) {
      if (child is Folder) {
        collect(child);
      } else if (child is File && child.path.endsWith('.dart') && !child.path.endsWith('.g.dart')) {
        files.add(child);
      }
    }
  }

  collect(provider.getFolder('${layout.root}/lib/hive'));
  collect(provider.getFolder('${layout.root}/lib/repository'));
  final stamp = files.fold<int>(files.length, (sum, file) => sum + file.modificationStamp);
  final cached = _entitiesCache[layout.root];
  if (cached != null && cached.stamp == stamp) return cached.types;
  final types = <String>{};
  for (final file in files) {
    try {
      final source = file.readAsStringSync();
      types.addAll([for (final match in _entityBox.allMatches(source)) match.group(1) ?? '']);
      types.addAll([
        for (final match in _openBox.allMatches(source))
          if (match.group(1) case final type? when type != 'dynamic') type,
      ]);
    } on FileSystemException {
      continue;
    }
  }
  _entitiesCache[layout.root] = (stamp: stamp, types: types);
  return types;
}

bool _hasHiveType(InterfaceElement element) => element.metadata.annotations.any(
      (annotation) => annotation.element?.enclosingElement?.name == 'HiveType',
    );

/// The persisted entity [type] is or holds (a list, set, map value or other
/// generic argument), or `null`.
String? _entityIn(DartType? type, Set<String> persisted) {
  if (type is! InterfaceType) return null;
  final element = type.element;
  final name = element.name;
  if (name != null && !name.endsWith('Draft') && (persisted.contains(name) || _hasHiveType(element))) return name;
  for (final argument in type.typeArguments) {
    final found = _entityIn(argument, persisted);
    if (found != null) return found;
  }
  return null;
}

/// A field of a cubit state (a class of the `bloc` role named `*State` or
/// extending one) is not a Hive-persisted entity nor a collection of one: the
/// state carries ids, the UI reads the entity from Hive.
class StateCarriesIds extends AnalysisRule {
  StateCarriesIds() : super(name: 'state_carries_ids', description: _desc);

  static const _desc = 'Cubit states carry the ids of Hive entities, never the entities.';

  static const LintCode code = LintCode(
    'state_carries_ids',
    '[NEON] the state field {0} holds the Hive entity {1}; a state carries its id.',
    correctionMessage: 'Write the entity to its box through the repository and keep its id (or ordered ids) in the '
        'state; the UI reads it with HiveEntityBuilder / HiveEntitiesBuilder. A form being edited is a dedicated '
        '*Draft type.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final layout = RuleLayout.of(context);
    registry.addClassDeclaration(this, _StateVisitor(this, layout, _persistedTypes(context, layout)));
  }
}

class _StateVisitor extends SimpleAstVisitor<void> {
  _StateVisitor(this.rule, this.layout, this.persisted);

  final AnalysisRule rule;

  final RuleLayout layout;

  final Set<String> persisted;

  static bool _isState(InterfaceElement element) => [element.thisType, ...element.allSupertypes].any((type) {
        final name = type.element.name ?? '';
        return name.endsWith('State') && !isFromPackage(type.element, 'flutter');
      });

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final path = unitPath(node);
    if (!layout.isAppSource(path) || !layout.isIn(path, LayoutRole.bloc)) return;
    final element = node.declaredFragment?.element;
    if (element == null || !_isState(element)) return;
    final body = node.body;
    if (body is! BlockClassBody) return;
    for (final member in body.members.whereType<FieldDeclaration>()) {
      if (member.isStatic) continue;
      for (final variable in member.fields.variables) {
        final entity = _entityIn(variable.declaredFragment?.element.type, persisted);
        if (entity == null) continue;
        rule.reportAtToken(variable.name, arguments: [variable.name.lexeme, entity]);
      }
    }
  }
}

/// Pages and features read entities only through the neon_flutter_hive
/// builders: no member of an `EntityBox` / `KeyValueBox` is called or read
/// there (passing the box to a builder is fine).
class UiReadsEntitiesThroughBuilder extends AnalysisRule {
  UiReadsEntitiesThroughBuilder() : super(name: 'ui_reads_entities_through_builder', description: _desc);

  static const _desc = 'Pages and features read Hive entities through the neon_flutter_hive builders.';

  static const LintCode code = LintCode(
    'ui_reads_entities_through_builder',
    '[NEON] {0} reads the box directly; the UI reads entities through the neon_flutter_hive builders.',
    correctionMessage: 'Pass the box to HiveEntityBuilder (one id), HiveEntitiesBuilder (ids) or HiveValueBuilder '
        '(a key of a KeyValueBox); writes go through the repository from a cubit.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _UiVisitor(this, RuleLayout.of(context));
    registry
      ..addMethodInvocation(this, visitor)
      ..addPropertyAccess(this, visitor)
      ..addPrefixedIdentifier(this, visitor);
  }
}

class _UiVisitor extends SimpleAstVisitor<void> {
  _UiVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  static bool _isBox(DartType? type) {
    if (type is! InterfaceType) return false;
    final name = type.element.name;
    return (name == 'EntityBox' || name == 'KeyValueBox') && isFromPackage(type.element, 'neon_flutter_hive');
  }

  bool _inUi(AstNode node) {
    final path = unitPath(node);
    return layout.isAppSource(path) && (layout.isIn(path, LayoutRole.pages) || layout.isIn(path, LayoutRole.features));
  }

  void _check(AstNode node, Expression? target, String member) {
    if (!_isBox(target?.staticType) || !_inUi(node)) return;
    rule.reportAtNode(node, arguments: ['.$member']);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) => _check(node, node.realTarget, node.methodName.name);

  @override
  void visitPropertyAccess(PropertyAccess node) => _check(node, node.realTarget, node.propertyName.name);

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    // `VernakBoxes.coupons` is a static field reference (the box passed to a
    // builder); `box.values` on a local box variable is a read.
    if (node.prefix.element is! VariableElement) return;
    _check(node, node.prefix, node.identifier.name);
  }
}
