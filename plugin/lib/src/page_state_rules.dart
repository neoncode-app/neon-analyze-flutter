import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// Rules on `State` classes and widgets in pages: no local UI state, no
/// logic, no editor plumbing. Selection, filters and search live in the
/// cubit; a page `State` exists only to own controllers.

/// The members a page State may declare besides fields.
const _lifecycle = {
  'initState',
  'didChangeDependencies',
  'didUpdateWidget',
  'deactivate',
  'activate',
  'dispose',
  'reassemble',
  'build',
  // WidgetsBindingObserver: the app lifecycle is lifecycle too.
  'didChangeAppLifecycleState',
};

bool _inPagesOrFeatures(RuleLayout layout, String path) =>
    layout.isIn(path, LayoutRole.pages) || layout.isIn(path, LayoutRole.features);

bool _isFlutterState(ClassDeclaration node) {
  final state = supertypeNamed(node, 'State');
  return state != null && isFromPackage(state.element, 'flutter');
}

/// No `setState` in `lib/pages` or `lib/features`.
class NoSetStateInPages extends AnalysisRule {
  NoSetStateInPages() : super(name: 'no_setstate_in_pages', description: _desc);

  static const _desc = 'Pages keep no local state; the cubit does.';

  static const LintCode code = LintCode(
    'no_setstate_in_pages',
    '[NEON] setState in a page; keep selection, filters and search in the cubit and render its state '
        'with BlocBuilder.',
    correctionMessage: 'Add a cubit method that emits the new state and call it here.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addMethodInvocation(this, _SetStateVisitor(this, RuleLayout.of(context)));
  }
}

class _SetStateVisitor extends SimpleAstVisitor<void> {
  _SetStateVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name != 'setState') return;
    final path = unitPath(node);
    if (!isAppSource(path) || !(layout.isIn(path, LayoutRole.pages) || layout.isIn(path, LayoutRole.features))) return;
    final owner = node.methodName.element?.enclosingElement;
    if (owner?.name != 'State' || !isFromPackage(owner, 'flutter')) return;
    rule.reportAtNode(node.methodName);
  }
}

/// A page or feature `State` (layout roles `pages`, `features`) declares only
/// lifecycle methods and `build`: no private helpers, no getters, no event
/// handlers.
class NoPrivateMethodsInPageState extends AnalysisRule {
  NoPrivateMethodsInPageState() : super(name: 'no_private_methods_in_page_state', description: _desc);

  static const _desc = 'A page or feature State has only lifecycle methods and build.';

  static const LintCode code = LintCode(
    'no_private_methods_in_page_state',
    '[NEON] `{0}` in a page or feature State; a page or feature State has only lifecycle methods and build. '
        'Logic goes into the cubit, pieces of UI into widget classes.',
    correctionMessage: 'Move the logic into a cubit method, or the UI into its own widget.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addMethodDeclaration(this, _MethodVisitor(this, RuleLayout.of(context)));
  }
}

class _MethodVisitor extends SimpleAstVisitor<void> {
  _MethodVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.isStatic || _lifecycle.contains(node.name.lexeme)) return;
    final path = unitPath(node);
    if (!isAppSource(path) || !_inPagesOrFeatures(layout, path)) return;
    final owner = enclosingClass(node);
    if (owner == null || !_isFlutterState(owner)) return;
    rule.reportAtToken(node.name, arguments: [node.name.lexeme]);
  }
}

/// A page or feature `StatefulWidget` (layout roles `pages`, `features`)
/// exists only to own controllers: every field of its State is a controller,
/// focus node, timer, subscription or key.
///
/// Heuristic (types matched by name): `*Controller`, `FocusNode`, `Timer`,
/// `StreamSubscription`, `GlobalKey`, `*Notifier`, `*Recognizer` (a gesture
/// recognizer of a text span, which the State must dispose). A State with no field at
/// all has no reason to exist either.
class StatefulPageOnlyForControllers extends AnalysisRule {
  StatefulPageOnlyForControllers() : super(name: 'stateful_page_only_for_controllers', description: _desc);

  static const _desc = 'StatefulWidget in pages and features only to own controllers.';

  static const LintCode code = LintCode(
    'stateful_page_only_for_controllers',
    '[NEON] page or feature State `{0}` {1}; a StatefulWidget in a page or feature only owns controllers '
        '(TextEditingController, FocusNode, ...). Keep everything else in the cubit, or use a StatelessWidget.',
    correctionMessage: 'Move the field into the cubit state, or make the widget stateless.',
    severity: DiagnosticSeverity.WARNING,
  );

  static bool isControllerType(String name) =>
      name.endsWith('Controller') ||
      name.endsWith('Notifier') ||
      name.endsWith('Recognizer') ||
      const {'FocusNode', 'Timer', 'StreamSubscription', 'GlobalKey'}.contains(name);

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addClassDeclaration(this, _StatefulVisitor(this, RuleLayout.of(context)));
  }
}

class _StatefulVisitor extends SimpleAstVisitor<void> {
  _StatefulVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final path = unitPath(node);
    if (!isAppSource(path) || !_inPagesOrFeatures(layout, path) || !_isFlutterState(node)) return;
    final element = node.declaredFragment?.element;
    if (element == null) return;
    final fields = element.fields.where((field) => !field.isStatic && field.isOriginDeclaration).toList();
    final name = element.name ?? '';
    if (fields.isEmpty) {
      rule.reportAtToken(node.name, arguments: [name, 'owns nothing']);
      return;
    }
    final others = [
      for (final field in fields)
        if (!StatefulPageOnlyForControllers.isControllerType(field.type.element?.name ?? '')) field.name ?? '',
    ];
    if (others.isNotEmpty) rule.reportAtToken(node.name, arguments: [name, 'holds ${others.join(', ')}']);
  }
}

/// No editor controller and no `.validate()` in pages: the editor owns its
/// save bar, validates itself and calls `onSubmit(data)` with valid data; the
/// page passes `onSubmit: cubit.save`.
class NoEditorControllerInPages extends AnalysisRule {
  NoEditorControllerInPages() : super(name: 'no_editor_controller_in_pages', description: _desc);

  static const _desc = 'Editors validate and submit themselves.';

  static const LintCode code = LintCode(
    'no_editor_controller_in_pages',
    '[NEON] {0} in a page; the editor validates itself and calls onSubmit(data) with valid data. '
        'Pass onSubmit: cubit.save.',
    correctionMessage: 'Remove the controller and validate() from the page.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _EditorVisitor(this, RuleLayout.of(context));
    registry
      ..addNamedType(this, visitor)
      ..addMethodInvocation(this, visitor);
  }
}

class _EditorVisitor extends SimpleAstVisitor<void> {
  _EditorVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  bool _inPages(AstNode node) {
    final path = unitPath(node);
    return isAppSource(path) && layout.isIn(path, LayoutRole.pages);
  }

  @override
  void visitNamedType(NamedType node) {
    final element = node.element;
    if (element is! InterfaceElement || !(element.name ?? '').endsWith('EditorController')) return;
    if (_inPages(node)) rule.reportAtNode(node, arguments: ['`${element.name}`']);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name != 'validate' || node.argumentList.arguments.isNotEmpty || !_inPages(node)) return;
    rule.reportAtNode(node, arguments: ['`${node.toSource()}`']);
  }
}
