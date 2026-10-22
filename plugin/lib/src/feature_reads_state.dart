import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// A Feature reads state (NCC0000060, rule doc `feature_placement`): a widget
/// that reads no state belongs to the kit (`lib/global_widgets/**`) or is a
/// part of the one page that uses it; only a widget that reads state or
/// drives a whole flow, used by several pages, a shell or both
/// administrations, is a Feature in `lib/features/<product>/<feature>/`.
///
/// A class with `{@category Feature}` is reported when nothing in it, in its
/// `State` class and in the private classes and private top-level functions
/// of its library, parts included (the implementation it delegates to), reads
/// state. Reading state is any of:
///
/// * a typed context getter: a getter of an extension declared in a providers
///   file (layout role `providers`, `context.vernakCardsCubit`);
/// * `context.read/watch/select` or `BlocProvider.of` (reported elsewhere by
///   `use_context_getters`, still a read);
/// * a bloc or cubit type (`BlocBase` of package:bloc): a `BlocBuilder<XCubit, S>`
///   / `BlocListener` / `BlocPresentationListener` type argument, a field or
///   parameter, a cubit created in a provider's `create:`, any expression of
///   that type;
/// * any type declared in the cubits (role `bloc`, e.g. a state or a
///   presentation event) or the repositories (role `repository`);
/// * Hive read the way rule `state_ids_ui_hive` wants it: a type of
///   package:neon_flutter_hive (a `HiveEntityBuilder`, an `EntityBox`) or one
///   declared with the app's boxes (role `hive`, `VernakBoxes`);
/// * another `{@category Feature}` widget it builds (a shell built from
///   features is one, too).
class FeatureReadsState extends AnalysisRule {
  FeatureReadsState() : super(name: 'feature_reads_state', description: _desc);

  static const _desc = 'A Feature reads state; a widget that reads none belongs to the kit or to its one page.';

  static const LintCode code = LintCode(
    'feature_reads_state',
    '[NEON] the Feature `{0}` reads no state (no context getter, cubit or repository); it belongs to the kit '
        '(lib/global_widgets/), or into the one page that uses it.',
    correctionMessage: 'Move it to the kit with its texts and data as parameters (category Component, Pattern, '
        '...), or into <page>/widgets/ when only one page uses it.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final layout = RuleLayout.of(context);
    if (!layout.isAppSource(context.definingUnit.file.path)) return;
    registry.addCompilationUnit(this, _Visitor(this, layout, context));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.layout, this.context);

  final AnalysisRule rule;

  final RuleLayout layout;

  final RuleContext context;

  /// The private classes and top-level functions of the whole library.
  late final List<AstNode> _private = [
    for (final unit in context.allUnits)
      for (final declaration in unit.unit.declarations)
        if (declaration is ClassDeclaration && declaration.namePart.typeName.lexeme.startsWith('_') ||
            declaration is FunctionDeclaration && declaration.name.lexeme.startsWith('_'))
          declaration,
  ];

  @override
  void visitCompilationUnit(CompilationUnit node) {
    final classes = node.declarations.whereType<ClassDeclaration>().toList();
    for (final declaration in classes) {
      final element = declaration.declaredFragment?.element;
      if (element == null || categoryOf(element) != 'Feature') continue;
      final finder = _StateReadFinder(layout, element);
      declaration.accept(finder);
      for (final other in _private) {
        if (finder.found) break;
        if (!identical(other, declaration)) other.accept(finder);
      }
      if (!finder.found) {
        rule.reportAtToken(declaration.namePart.typeName, arguments: [element.name ?? '']);
      }
    }
  }
}

class _StateReadFinder extends RecursiveAstVisitor<void> {
  _StateReadFinder(this.layout, this.feature);

  final RuleLayout layout;

  final ClassElement feature;

  bool found = false;

  bool _declaredIn(Element? element, LayoutRole role) {
    final path = element?.library?.firstFragment.source.fullName;
    return path != null && layout.isIn(path.replaceAll(r'\', '/'), role);
  }

  bool _isStateType(DartType? type) {
    if (type is! InterfaceType) return false;
    if (isBloc(type)) return true;
    final element = type.element;
    if (_declaredIn(element, LayoutRole.bloc) || _declaredIn(element, LayoutRole.repository)) return true;
    if (isFromPackage(element, 'neon_flutter_hive') || _declaredIn(element, LayoutRole.hive)) return true;
    return element != feature && categoryOf(element) == 'Feature';
  }

  @override
  void visitNamedType(NamedType node) {
    if (found) return;
    if (_isStateType(node.type)) {
      found = true;
      return;
    }
    super.visitNamedType(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (found) return;
    if (isProviderRead(node) || _isStateType(node.staticType)) {
      found = true;
      return;
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (found) return;
    if (_isContextGetter(node.identifier.element) || _isStateType(node.staticType)) {
      found = true;
      return;
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (found) return;
    if (_isContextGetter(node.propertyName.element) || _isStateType(node.staticType)) {
      found = true;
      return;
    }
    super.visitPropertyAccess(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (found) return;
    if (_isStateType(node.staticType)) found = true;
  }

  /// A getter of an extension declared in a providers file.
  bool _isContextGetter(Element? element) =>
      element is PropertyAccessorElement &&
      element.enclosingElement is ExtensionElement &&
      _declaredIn(element, LayoutRole.providers);
}
