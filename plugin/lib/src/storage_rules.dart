import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

// Hive is the only data store (NCC0000070, rule doc `storage_hive`):
// repositories (and lib/hive/) own the boxes, the UI reads through the
// neon_flutter_hive builders, and no other store is imported.

bool _isStorageElement(Element? element) =>
    isFromPackage(element, 'hive_ce') || isFromPackage(element, 'neon_flutter_hive') || isFromPackage(element, 'hive');

/// `Hive.box` / `Hive.openBox`, `EntityBox(` / `KeyValueBox(` and a box's
/// `.listenable(` only in the `repository` and `hive` roles.
class HiveOnlyInRepositories extends AnalysisRule {
  HiveOnlyInRepositories() : super(name: 'hive_only_in_repositories', description: _desc);

  static const _desc = 'Hive boxes are owned by repositories; the UI reads through the neon_flutter_hive builders.';

  static const LintCode code = LintCode(
    'hive_only_in_repositories',
    '[NEON] {0} outside the repositories and lib/hive/.',
    correctionMessage: 'Declare and open boxes in a repository (or lib/hive/), write through it, and read in the UI '
        'with HiveEntityBuilder / HiveEntitiesBuilder / HiveValueBuilder.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _OwnerVisitor(this, RuleLayout.of(context));
    registry
      ..addMethodInvocation(this, visitor)
      ..addInstanceCreationExpression(this, visitor);
  }
}

class _OwnerVisitor extends SimpleAstVisitor<void> {
  _OwnerVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  bool _inScope(AstNode node) {
    final path = unitPath(node);
    return layout.isAppSource(path) && !layout.isIn(path, LayoutRole.repository) && !layout.isIn(path, LayoutRole.hive);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    final String what;
    if (name == 'box' || name == 'openBox' || name == 'openLazyBox' || name == 'lazyBox') {
      final target = node.realTarget;
      if (target is! SimpleIdentifier || target.name != 'Hive') return;
      if (!_isStorageElement(target.element)) return;
      what = 'Hive.$name';
    } else if (name == 'listenable') {
      final type = node.realTarget?.staticType;
      if (type == null || !_isStorageElement(type.element)) return;
      what = 'a box .listenable(';
    } else {
      return;
    }
    if (!_inScope(node)) return;
    rule.reportAtNode(node.methodName, arguments: [what]);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.element?.enclosingElement;
    final name = type?.name;
    if ((name != 'EntityBox' && name != 'KeyValueBox') || !isFromPackage(type, 'neon_flutter_hive')) return;
    if (!_inScope(node)) return;
    rule.reportAtNode(node.constructorName, arguments: ['$name(']);
  }
}

/// No other local store than Hive through neon_flutter_hive: imports of
/// `shared_preferences`, `sqflite`, `drift`, `isar` or the bare `hive`
/// package, and `window.localStorage`, are findings in app code.
class StorageHiveOnly extends AnalysisRule {
  StorageHiveOnly() : super(name: 'storage_hive_only', description: _desc);

  static const _desc = 'Hive (through neon_flutter_hive) is the only local data store.';

  static const LintCode code = LintCode(
    'storage_hive_only',
    '[NEON] {0}; Hive through neon_flutter_hive is the only local store.',
    correctionMessage: 'Store data in a typed box of neon_flutter_hive (EntityBox, KeyValueBox) owned by a '
        'repository; secrets go to the secure store (rule secure_storage).',
    severity: DiagnosticSeverity.WARNING,
  );

  static const banned = ['shared_preferences', 'sqflite', 'drift', 'isar', 'hive'];

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _StoreVisitor(this, RuleLayout.of(context));
    registry
      ..addImportDirective(this, visitor)
      ..addPrefixedIdentifier(this, visitor)
      ..addPropertyAccess(this, visitor);
  }
}

class _StoreVisitor extends SimpleAstVisitor<void> {
  _StoreVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitImportDirective(ImportDirective node) {
    final uri = node.uri.stringValue ?? '';
    if (!uri.startsWith('package:')) return;
    final package = uri.substring('package:'.length).split('/').first;
    if (!StorageHiveOnly.banned.contains(package) || !layout.isAppSource(unitPath(node))) return;
    rule.reportAtNode(node.uri, arguments: ['the import of package:$package']);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) => _checkLocalStorage(node, node.prefix.name, node.identifier);

  @override
  void visitPropertyAccess(PropertyAccess node) {
    final target = node.realTarget;
    if (target is SimpleIdentifier) _checkLocalStorage(node, target.name, node.propertyName);
  }

  void _checkLocalStorage(AstNode node, String target, SimpleIdentifier property) {
    if (target != 'window' || property.name != 'localStorage' || !layout.isAppSource(unitPath(node))) return;
    rule.reportAtNode(node, arguments: ['window.localStorage']);
  }
}
