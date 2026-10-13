import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// The dimensions design of NCR0000014: a small scale in the layout role
/// `tokens` (default `lib/utils/ui/tokens/`: AppSpacing, AppRadius, AppIconSize, AppBorder,
/// AppControlSize, AppBreakpoints, AppDialogSizes) plus one
/// `<widget>_dimens.dart` (`<Widget>Dimens`) next to each widget. The old
/// `AppDimens` is dissolved.

/// Where dimension values may be literals: the scale, the per-widget dimens
/// files (the old `app_dimens.dart` included) and the text style files.
bool _ownsDimensions(RuleLayout layout, String path) =>
    layout.isIn(path, LayoutRole.tokens) ||
    layout.isIn(path, LayoutRole.widgetDimens) ||
    path.endsWith('_text_styles.dart');

/// The library file of [element]'s declaration.
String _declaredIn(Element element) => element.library?.firstFragment.source.fullName.replaceAll(r'\', '/') ?? '';

/// A per-widget dimens class: `<Widget>Dimens` declared in a `*_dimens.dart`
/// that is not the old `app_dimens.dart`.
bool _isWidgetDimens(Element? element) =>
    element is InterfaceElement &&
    (element.name ?? '').endsWith('Dimens') &&
    _declaredIn(element).endsWith('_dimens.dart') &&
    !_declaredIn(element).endsWith('/app_dimens.dart');

/// A class of the scale (layout role `tokens`).
bool _isScaleToken(RuleLayout layout, Element? element) =>
    element is InterfaceElement && layout.isIn(_declaredIn(element), LayoutRole.tokens);

/// The class whose static member [node] reads (`AppSpacing.s16` -> AppSpacing).
InterfaceElement? _staticOwner(AstNode node) {
  final Element? element = switch (node) {
    PrefixedIdentifier() => node.identifier.element,
    PropertyAccess() => node.propertyName.element,
    _ => null,
  };
  final owner = element?.enclosingElement;
  return owner is InterfaceElement ? owner : null;
}

/// No numeric literal for a size, padding, radius or gap outside the scale
/// and the dimens files: `SizedBox(height: 8)`, `EdgeInsets.all(16)`,
/// `BorderRadius.circular(12)`, `width: 240`. Zero is allowed.
class NoRawDimension extends AnalysisRule {
  NoRawDimension() : super(name: 'no_raw_dimension', description: _desc);

  static const _desc = 'Dimensions come from the scale or the widget dimens.';

  static const LintCode code = LintCode(
    'no_raw_dimension',
    '[NEON] raw dimension `{0}`; use the scale (AppSpacing, AppRadius, AppIconSize, ... in lib/utils/ui/tokens/) '
        'or the widget\'s own <Widget>Dimens.',
    correctionMessage: 'Add the value to the widget dimens file (or use a scale step) and reference it.',
    severity: DiagnosticSeverity.WARNING,
  );

  /// Classes whose constructor arguments are dimensions.
  static const geometryClasses = {
    'EdgeInsets',
    'EdgeInsetsDirectional',
    'BorderRadius',
    'BorderRadiusDirectional',
    'Radius',
    'SizedBox',
    'Size',
    'BoxConstraints',
  };

  /// Named arguments that carry a dimension.
  static const dimensionNames = {
    'width',
    'height',
    'size',
    'iconSize',
    'radius',
    'spacing',
    'runSpacing',
    'mainAxisSpacing',
    'crossAxisSpacing',
    'elevation',
    'fontSize',
    'strokeWidth',
    'thickness',
    'indent',
    'endIndent',
    'blurRadius',
    'spreadRadius',
    'maxWidth',
    'minWidth',
    'maxHeight',
    'minHeight',
    'gap',
  };

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _RawDimensionVisitor(this, RuleLayout.of(context));
    registry
      ..addIntegerLiteral(this, visitor)
      ..addDoubleLiteral(this, visitor);
  }
}

class _RawDimensionVisitor extends SimpleAstVisitor<void> {
  _RawDimensionVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitIntegerLiteral(IntegerLiteral node) {
    if ((node.value ?? 0) != 0) _check(node);
  }

  @override
  void visitDoubleLiteral(DoubleLiteral node) {
    if (node.value != 0) _check(node);
  }

  void _check(Literal node) {
    AstNode literal = node;
    // `-8` is a literal too.
    if (literal.parent is PrefixExpression) literal = literal.parent ?? literal;
    final parent = literal.parent;
    // A dimension name on an int parameter is a count or a byte size
    // (`VernakBannerFile(size: 1200000)`), not a length.
    final isNamedDimension = parent is NamedExpression &&
        NoRawDimension.dimensionNames.contains(parent.name.label.name) &&
        !(parent.element?.type.isDartCoreInt ?? false);
    // Any argument of a geometry class counts, named (`horizontal:`) or not.
    final argumentList = parent is NamedExpression ? parent.parent : parent;
    if (argumentList is! ArgumentList) return;
    final invocation = argumentList.parent;
    final className = switch (invocation) {
      InstanceCreationExpression() => invocation.constructorName.element?.enclosingElement.name,
      MethodInvocation() => invocation.methodName.element?.enclosingElement?.name,
      _ => null,
    };
    final isGeometry =
        NoRawDimension.geometryClasses.contains(className) && isFromPackage(_elementOf(invocation), 'flutter');
    if (!isNamedDimension && !isGeometry) return;
    final path = unitPath(node);
    if (!isAppSource(path) || _ownsDimensions(layout, path)) return;
    rule.reportAtNode(literal, arguments: [literal.toSource()]);
  }

  static Element? _elementOf(AstNode? invocation) => switch (invocation) {
        InstanceCreationExpression() => invocation.constructorName.element,
        MethodInvocation() => invocation.methodName.element,
        _ => null,
      };
}

/// A `<Widget>Dimens` class is used only by files in its widget's folder:
/// another widget never borrows its numbers.
class DimensPrivateToWidget extends AnalysisRule {
  DimensPrivateToWidget() : super(name: 'dimens_private_to_widget', description: _desc);

  static const _desc = 'A widget dimens class belongs to its own folder.';

  static const LintCode code = LintCode(
    'dimens_private_to_widget',
    '[NEON] `{0}` belongs to another widget; use your own <Widget>Dimens or the scale (lib/utils/ui/tokens/).',
    correctionMessage: 'Give this widget its own dimens, built from the scale.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _PrivateDimensVisitor(this, RuleLayout.of(context));
    registry
      ..addNamedType(this, visitor)
      ..addPrefixedIdentifier(this, visitor);
  }
}

class _PrivateDimensVisitor extends SimpleAstVisitor<void> {
  _PrivateDimensVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  void _check(AstNode node, Element? element) {
    if (!_isWidgetDimens(element) || element == null) return;
    final path = unitPath(node);
    if (!isAppSource(path)) return;
    final declared = _declaredIn(element);
    // Only the app's own dimens; a dependency's *Dimens is not a kit widget's.
    if (!layout.isAppSource(declared)) return;
    final folder = declared.substring(0, declared.lastIndexOf('/') + 1);
    if (!path.startsWith(folder)) rule.reportAtNode(node, arguments: [element.name ?? '']);
  }

  @override
  void visitNamedType(NamedType node) => _check(node, node.element);

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) => _check(node.prefix, node.prefix.element);
}

/// Pages (layout role `pages`) take only `AppSpacing` (gaps between blocks); every
/// other size belongs to a component and its dimens.
class PageDimensSpacingOnly extends AnalysisRule {
  PageDimensSpacingOnly() : super(name: 'page_dimens_spacing_only', description: _desc);

  static const _desc = 'Pages use only AppSpacing.';

  static const LintCode code = LintCode(
    'page_dimens_spacing_only',
    '[NEON] `{0}` in a page; pages use only AppSpacing for gaps between blocks. '
        'A size inside a block means a component is missing.',
    correctionMessage: 'Use an existing component, or create one with its own dimens.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _PageDimensVisitor(this, RuleLayout.of(context));
    registry
      ..addPrefixedIdentifier(this, visitor)
      ..addPropertyAccess(this, visitor);
  }
}

class _PageDimensVisitor extends SimpleAstVisitor<void> {
  _PageDimensVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  void _check(Expression node) {
    final owner = _staticOwner(node);
    if (owner == null || owner.name == 'AppSpacing') return;
    if (!_isScaleToken(layout, owner) && !_isWidgetDimens(owner)) return;
    final path = unitPath(node);
    if (!isAppSource(path) || !layout.isIn(path, LayoutRole.pages)) return;
    rule.reportAtNode(node, arguments: [node.toSource()]);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) => _check(node);

  @override
  void visitPropertyAccess(PropertyAccess node) => _check(node);
}

/// No reference to the old `AppDimens` (`lib/utils/ui/theme/app_dimens.dart`).
/// It is dissolved into the scale and the per-widget dimens; the ratchet
/// keeps the existing uses until the migration.
class NoAppDimens extends AnalysisRule {
  NoAppDimens() : super(name: 'no_app_dimens', description: _desc);

  static const _desc = 'AppDimens is being dissolved.';

  static const LintCode code = LintCode(
    'no_app_dimens',
    '[NEON] `{0}` uses the old AppDimens; use the scale (AppSpacing, AppRadius, ... in lib/utils/ui/tokens/) '
        'or the widget\'s own <Widget>Dimens.',
    correctionMessage: 'Take the value from the scale or the widget dimens.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _AppDimensVisitor(this, RuleLayout.of(context));
    registry
      ..addPrefixedIdentifier(this, visitor)
      ..addPropertyAccess(this, visitor);
  }
}

class _AppDimensVisitor extends SimpleAstVisitor<void> {
  _AppDimensVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  void _check(Expression node) {
    final owner = _staticOwner(node);
    if (owner?.name != 'AppDimens' || owner == null || !_declaredIn(owner).endsWith('/app_dimens.dart')) return;
    final path = unitPath(node);
    if (!isAppSource(path) || layout.isIn(path, LayoutRole.legacyDimens)) return;
    rule.reportAtNode(node, arguments: [node.toSource()]);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) => _check(node);

  @override
  void visitPropertyAccess(PropertyAccess node) => _check(node);
}

/// Public constructors of a `{@category Component}` widget take `variant:`
/// (its dimens), not raw `padding` / `height` / `width` / `radius` / ...
/// parameters; otherwise every page builds its own exception. Generic
/// primitives are allow-listed.
class ComponentTakesVariant extends AnalysisRule {
  ComponentTakesVariant() : super(name: 'component_takes_variant', description: _desc);

  static const _desc = 'Components take a variant, not raw dimensions.';

  static const LintCode code = LintCode(
    'component_takes_variant',
    '[NEON] component parameter `{0}` is a raw dimension; offer named variants in <Widget>Dimens and take `variant:`.',
    correctionMessage: 'Replace the parameter with a variant of the widget dimens.',
    severity: DiagnosticSeverity.WARNING,
  );

  static const rawParameters = {
    'padding',
    'margin',
    'height',
    'width',
    'size',
    'radius',
    'borderRadius',
    'contentPadding',
    'gap',
    'spacing',
    'iconSize',
  };

  /// Generic primitives that are the place raw dimensions are applied: the
  /// box and the remote image of the four basic building blocks, the skeleton
  /// shapes and the gap.
  static const primitives = {
    'RoundedContainer',
    'AppNetworkImage',
    'SkeletonBox',
    'SkeletonLine',
    'SkeletonCircle',
    'AppGap',
  };

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addConstructorDeclaration(this, _VariantVisitor(this));
  }
}

class _VariantVisitor extends SimpleAstVisitor<void> {
  _VariantVisitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    if ((node.name?.lexeme ?? '').startsWith('_')) return;
    final widget = enclosingClass(node);
    final element = widget?.declaredFragment?.element;
    if (widget == null || element == null || ComponentTakesVariant.primitives.contains(element.name)) return;
    if (categoryOf(element) != 'Component' || !isAppSource(unitPath(node))) return;
    for (final parameter in node.parameters.parameters) {
      final name = parameter.name?.lexeme ?? '';
      if (!ComponentTakesVariant.rawParameters.contains(name)) continue;
      // `size: CustomButtonSize.pill` is the variant itself: only a number or
      // a geometry value is a raw dimension.
      final type = parameter.declaredFragment?.element.type;
      if (type != null && type.element is EnumElement) continue;
      rule.reportAtNode(parameter, arguments: [name]);
    }
  }
}
