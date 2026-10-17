import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

// Routers hold only routes (NCC0000061, decided by Filip 2026-10-16). Shells,
// guards, the page factory and labels are pieces of their own under
// lib/flavors/<flavor>/; every GoRoute builds its page through the flavour's
// page factory (`vernakPage(state, access:, transition:, page:)`), which
// declares the access explicitly and applies the AppPageTransition.

/// The page types of Flutter and go_router a router never builds by hand:
/// the page factory owns them.
const _handBuiltPages = {'NoTransitionPage', 'MaterialPage', 'CupertinoPage', 'CustomTransitionPage'};

/// Whether [name] opens a dialog or sheet (`show`, `showX`).
bool _isShow(String name) =>
    name == 'show' || (name.length > 4 && name.startsWith('show') && name[4] == name[4].toUpperCase());

/// A router file (layout role `routers`) declares routes and nothing else:
/// no class, mixin, enum or extension, no top-level function but the one
/// building the GoRouter, no dialog opened (`show*` called) and no `tr()`.
class RouterOnlyRoutes extends AnalysisRule {
  RouterOnlyRoutes() : super(name: 'router_only_routes', description: _desc);

  static const _desc = 'A router file holds only routes: no classes, helpers, dialogs or translations.';

  static const LintCode code = LintCode(
    'router_only_routes',
    '[NEON] the router {0}; a router file holds only its routes.',
    correctionMessage: 'Move shells, guards, the page factory and labels into their own pieces under '
        'lib/flavors/<flavor>/ (component_folder_with_skeleton), open dialogs through a cubit presentation event, '
        'and translate where the text is drawn.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _RouterVisitor(this, RuleLayout.of(context));
    registry
      ..addCompilationUnit(this, visitor)
      ..addMethodInvocation(this, visitor);
  }
}

class _RouterVisitor extends SimpleAstVisitor<void> {
  _RouterVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  bool _isRouter(AstNode node) {
    final path = unitPath(node);
    return layout.isAppSource(path) && layout.isIn(path, LayoutRole.routers);
  }

  @override
  void visitCompilationUnit(CompilationUnit node) {
    if (!_isRouter(node)) return;
    var builderSeen = false;
    for (final declaration in node.declarations) {
      switch (declaration) {
        case TopLevelVariableDeclaration():
          break;
        case FunctionDeclaration():
          final returnType = declaration.declaredFragment?.element.returnType;
          final buildsRouter =
              returnType?.element?.name == 'GoRouter' && isFromPackage(returnType?.element, 'go_router');
          if (buildsRouter && !builderSeen) {
            builderSeen = true;
            continue;
          }
          rule.reportAtToken(declaration.name, arguments: ['declares the function ${declaration.name.lexeme}']);
        case NamedCompilationUnitMember():
          rule.reportAtToken(declaration.name, arguments: ['declares ${declaration.name.lexeme}']);
        case ExtensionDeclaration():
          final name = declaration.name;
          if (name == null) {
            rule.reportAtNode(declaration, arguments: ['declares an extension']);
          } else {
            rule.reportAtToken(name, arguments: ['declares ${name.lexeme}']);
          }
        default:
          rule.reportAtNode(declaration, arguments: ['declares something besides routes']);
      }
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (name != 'tr' && !_isShow(name)) return;
    if (!_isRouter(node)) return;
    rule.reportAtNode(node.methodName, arguments: [name == 'tr' ? 'translates (tr())' : 'opens a dialog ($name)']);
  }
}

/// Every `GoRoute` of a router builds its page with `pageBuilder:` returning
/// the flavour's page factory (a function of a `*_page_factory.dart`); a
/// `builder:` or a hand-built `NoTransitionPage` / `MaterialPage` /
/// `CupertinoPage` / `CustomTransitionPage` is a finding. `ShellRoute`
/// keeps its `builder:`.
class RouteUsesPageFactory extends AnalysisRule {
  RouteUsesPageFactory() : super(name: 'route_uses_page_factory', description: _desc);

  static const _desc = 'Every GoRoute builds its page through the flavour\'s page factory.';

  static const LintCode code = LintCode(
    'route_uses_page_factory',
    '[NEON] {0}; every GoRoute uses pageBuilder: returning the page factory of its flavour.',
    correctionMessage: 'Write `pageBuilder: (context, state) => <flavor>Page(state, access: ..., page: ...)`; '
        'the factory (lib/flavors/<flavor>/<flavor>_page_factory/) declares the access and applies the '
        'AppPageTransition.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addInstanceCreationExpression(this, _RouteVisitor(this, RuleLayout.of(context)));
  }
}

class _RouteVisitor extends SimpleAstVisitor<void> {
  _RouteVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final path = unitPath(node);
    if (!layout.isAppSource(path) || !layout.isIn(path, LayoutRole.routers)) return;
    final type = node.constructorName.element?.enclosingElement;
    final name = type?.name;
    if (name == null) return;
    if (_handBuiltPages.contains(name)) {
      rule.reportAtNode(node.constructorName, arguments: ['the router builds a $name by hand']);
      return;
    }
    if (name != 'GoRoute' || !isFromPackage(type, 'go_router')) return;
    for (final argument in node.argumentList.arguments.whereType<NamedExpression>()) {
      final label = argument.name.label.name;
      if (label == 'builder') {
        rule.reportAtNode(argument.name.label, arguments: ['a GoRoute uses builder:']);
      } else if (label == 'pageBuilder' && !_returnsFactory(argument.expression)) {
        rule.reportAtNode(argument.name.label, arguments: ['a GoRoute pageBuilder: does not return the page factory']);
      }
    }
  }

  /// Whether the function [expression] returns a call of a page factory on
  /// every path.
  bool _returnsFactory(Expression expression) {
    if (expression is! FunctionExpression) return false;
    final body = expression.body;
    final returned = switch (body) {
      ExpressionFunctionBody() => [body.expression],
      BlockFunctionBody() => [
          for (final statement in body.block.statements)
            if (statement is ReturnStatement) statement.expression,
        ],
      _ => const <Expression?>[],
    };
    return returned.isNotEmpty && returned.every(_isFactoryCall);
  }

  bool _isFactoryCall(Expression? expression) {
    if (expression is! MethodInvocation) return false;
    final element = expression.methodName.element;
    if (element is! TopLevelFunctionElement) return false;
    final source = element.library.firstFragment.source.fullName.replaceAll(r'\', '/');
    return source.endsWith('_page_factory.dart');
  }
}
