import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// Architecture layering of the widget kit and the UI (ADMINISTRATION.md 1a
/// and 1g).

/// The widget kit (layout role `global_widgets`) never imports pages or
/// features (roles `pages`, `features`).
class GlobalWidgetsLayering extends AnalysisRule {
  GlobalWidgetsLayering() : super(name: 'global_widgets_layering', description: _desc);

  static const _desc = 'Global widgets never import pages or features.';

  static const LintCode code = LintCode(
    'global_widgets_layering',
    '[NEON] a global widget imports {0}; global_widgets/ must not depend on pages/ or features/. '
        'Pass texts and callbacks in as parameters.',
    correctionMessage: 'Remove the import and take the value as a parameter.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addImportDirective(this, _LayeringVisitor(this, RuleLayout.of(context)));
  }
}

class _LayeringVisitor extends SimpleAstVisitor<void> {
  _LayeringVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitImportDirective(ImportDirective node) {
    final path = unitPath(node);
    if (!isAppSource(path) || !layout.isIn(path, LayoutRole.globalWidgets)) return;
    final target = importedPath(node) ?? '';
    for (final role in const [LayoutRole.pages, LayoutRole.features]) {
      if (layout.isIn(target, role)) {
        rule.reportAtNode(node.uri, arguments: ['${role.key}/']);
        return;
      }
    }
  }
}

/// A `{@category Component | Layout | Pattern}` widget draws from its
/// parameters and the theme only: its file imports no cubit (layout role
/// `bloc`),
/// `package:bloc` or `package:flutter_bloc`, and it reads no provider.
class ComponentHasNoStateAccess extends AnalysisRule {
  ComponentHasNoStateAccess() : super(name: 'component_has_no_state_access', description: _desc);

  static const _desc = 'Components, layouts and patterns do not read app state.';

  static const LintCode code = LintCode(
    'component_has_no_state_access',
    '[NEON] {0} in a {1} widget; components, layouts and patterns draw from parameters and the theme only. '
        'Read state in the page (or make it a Feature).',
    correctionMessage: 'Pass the data in as parameters.',
    severity: DiagnosticSeverity.WARNING,
  );

  static const statelessTiers = {'Component', 'Layout', 'Pattern'};

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addCompilationUnit(this, _StateAccessVisitor(this, RuleLayout.of(context)));
  }
}

class _StateAccessVisitor extends SimpleAstVisitor<void> {
  _StateAccessVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    final path = unitPath(node);
    if (!isAppSource(path)) return;
    final tiers = {
      for (final declaration in node.declarations.whereType<ClassDeclaration>())
        if (ComponentHasNoStateAccess.statelessTiers.contains(categoryOf(declaration.declaredFragment?.element)))
          categoryOf(declaration.declaredFragment?.element) ?? '',
    };
    if (tiers.isEmpty) return;
    final tier = tiers.first;
    for (final directive in node.directives.whereType<ImportDirective>()) {
      final uri = directive.uri.stringValue ?? '';
      final target = importedPath(directive) ?? '';
      if (uri.startsWith('package:flutter_bloc/') ||
          uri.startsWith('package:bloc/') ||
          layout.isIn(target, LayoutRole.bloc)) {
        rule.reportAtNode(directive.uri, arguments: ['an import of `$uri`', tier]);
      }
    }
    for (final declaration in node.declarations.whereType<ClassDeclaration>()) {
      if (!ComponentHasNoStateAccess.statelessTiers.contains(categoryOf(declaration.declaredFragment?.element))) {
        continue;
      }
      final finder = _ReadFinder();
      declaration.accept(finder);
      for (final read in finder.reads) {
        rule.reportAtNode(read, arguments: ['`${read.toSource()}`', tier]);
      }
    }
  }
}

class _ReadFinder extends RecursiveAstVisitor<void> {
  final reads = <MethodInvocation>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (isProviderRead(node)) reads.add(node);
    super.visitMethodInvocation(node);
  }
}

/// UI code (pages, features, the widget kit) never uses a repository (a class
/// declared in the layout role `repository`): data comes from the
/// cubit.
class NoRepositoryInUi extends AnalysisRule {
  NoRepositoryInUi() : super(name: 'no_repository_in_ui', description: _desc);

  static const _desc = 'UI code reads data through cubits, never repositories.';

  static const LintCode code = LintCode(
    'no_repository_in_ui',
    '[NEON] `{0}` in UI code; pages and widgets get data from their cubit. Inject the repository into the cubit.',
    correctionMessage: 'Move the repository call into a cubit method.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addNamedType(this, _RepositoryVisitor(this, RuleLayout.of(context)));
  }
}

class _RepositoryVisitor extends SimpleAstVisitor<void> {
  _RepositoryVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitNamedType(NamedType node) {
    final element = node.element;
    if (element is! InterfaceElement || !layout.isUi(unitPath(node))) return;
    final declaredIn = element.library.firstFragment.source.fullName.replaceAll(r'\', '/');
    if (layout.isIn(declaredIn, LayoutRole.repository)) rule.reportAtNode(node, arguments: [element.name ?? '']);
  }
}

/// `package:http` and `package:dio` only in the API layer, never in UI code.
class NoHttpInUi extends AnalysisRule {
  NoHttpInUi() : super(name: 'no_http_in_ui', description: _desc);

  static const _desc = 'HTTP clients only in the API layer.';

  static const LintCode code = LintCode(
    'no_http_in_ui',
    '[NEON] UI code imports `{0}`; HTTP belongs to the API layer (request models, repositories, services). '
        'Call it from a cubit.',
    correctionMessage: 'Move the request into the API layer and call it from the cubit.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addImportDirective(this, _HttpVisitor(this, RuleLayout.of(context)));
  }
}

class _HttpVisitor extends SimpleAstVisitor<void> {
  _HttpVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitImportDirective(ImportDirective node) {
    final uri = node.uri.stringValue ?? '';
    if (!(uri.startsWith('package:http/') || uri.startsWith('package:dio/')) || !layout.isUi(unitPath(node))) return;
    rule.reportAtNode(node.uri, arguments: [uri]);
  }
}

/// Every public widget under `lib/global_widgets` and `lib/features` names
/// its tier as the last line of its doc comment: `{@category X}` with X one
/// of Component, Layout, Behavior, Pattern, Template, Feature, Skeleton.
/// (`src/` parts and the catalog previews are not catalog widgets.)
class GlobalWidgetHasCategory extends AnalysisRule {
  GlobalWidgetHasCategory() : super(name: 'global_widget_has_category', description: _desc);

  static const _desc = 'Kit widgets name their tier with {@category}.';

  static const LintCode code = LintCode(
    'global_widget_has_category',
    '[NEON] `{0}` has no valid tier; end its doc comment with `/// {@category X}` '
        '(Component, Layout, Behavior, Pattern, Template, Feature, Skeleton).',
    correctionMessage: 'Add the {@category} line (ADMINISTRATION.md 1g).',
    severity: DiagnosticSeverity.WARNING,
  );

  static const tiers = {'Component', 'Layout', 'Behavior', 'Pattern', 'Template', 'Feature', 'Skeleton'};

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addClassDeclaration(this, _CategoryVisitor(this, RuleLayout.of(context)));
  }
}

class _CategoryVisitor extends SimpleAstVisitor<void> {
  _CategoryVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final path = unitPath(node);
    if (!isAppSource(path) || !(layout.isIn(path, LayoutRole.globalWidgets) || layout.isIn(path, LayoutRole.features)))
      return;
    if (path.contains('/src/') || path.contains('/widget_catalog/previews/')) return;
    final name = node.name.lexeme;
    if (name.startsWith('_')) return;
    final superclass = node.extendsClause?.superclass.element;
    if (superclass == null ||
        !const {'StatelessWidget', 'StatefulWidget'}.contains(superclass.name) ||
        !isFromPackage(superclass, 'flutter')) {
      return;
    }
    final category = categoryOf(node.declaredFragment?.element);
    final comment = node.documentationComment?.tokens.map((token) => token.lexeme.trim()).toList() ?? const [];
    final lastLine = comment.isEmpty ? '' : comment.last;
    if (category == null || !GlobalWidgetHasCategory.tiers.contains(category) || !lastLine.contains('{@category')) {
      rule.reportAtToken(node.name, arguments: [name]);
    }
  }
}

/// A file under a kit's `src/` folder is imported only from inside that kit
/// (the folder containing `src/`); everything else imports the public widget.
class KitSrcInternal extends AnalysisRule {
  KitSrcInternal() : super(name: 'kit_src_internal', description: _desc);

  static const _desc = 'Kit internals under src/ stay inside the kit.';

  static const LintCode code = LintCode(
    'kit_src_internal',
    '[NEON] `{0}` is an internal part of a kit; import the kit\'s public widget instead.',
    correctionMessage: 'Import the public library next to the src/ folder.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addImportDirective(this, _SrcVisitor(this, RuleLayout.of(context)));
  }
}

class _SrcVisitor extends SimpleAstVisitor<void> {
  _SrcVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitImportDirective(ImportDirective node) {
    final path = unitPath(node);
    if (!isAppSource(path)) return;
    final target = importedPath(node) ?? '';
    if (!layout.isIn(target, LayoutRole.globalWidgets)) return;
    final src = target.indexOf('/src/');
    if (src < 0) return;
    final kit = target.substring(0, src + 1);
    if (!path.startsWith(kit)) rule.reportAtNode(node.uri, arguments: [node.uri.stringValue ?? target]);
  }
}
