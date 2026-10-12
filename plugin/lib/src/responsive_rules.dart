import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// Responsiveness goes through `app_responsive.dart` only (layout role
/// `responsive`)
/// (`context.screenSize`, `ResponsiveBuilder`, `context.responsiveValue`).

const _replacement =
    'context.screenSize / ResponsiveBuilder / context.responsiveValue (lib/utils/ui/app_responsive.dart)';

/// No `MediaQuery.sizeOf/widthOf/heightOf(...)` and no `MediaQuery...size`
/// outside `app_responsive.dart`.
class NoMediaQuerySize extends AnalysisRule {
  NoMediaQuerySize() : super(name: 'no_media_query_size', description: _desc);

  static const _desc = 'Read the screen size only through app_responsive.dart.';

  static const LintCode code = LintCode(
    'no_media_query_size',
    '[NEON] `{0}` reads the screen size; use $_replacement.',
    correctionMessage: 'Decide by AppScreenSize, not by pixels.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _MediaQueryVisitor(this, RuleLayout.of(context));
    registry
      ..addMethodInvocation(this, visitor)
      ..addPropertyAccess(this, visitor)
      ..addPrefixedIdentifier(this, visitor);
  }
}

class _MediaQueryVisitor extends SimpleAstVisitor<void> {
  _MediaQueryVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  bool _applies(AstNode node) {
    final path = unitPath(node);
    return isAppSource(path) && !layout.isIn(path, LayoutRole.responsive);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (!const {'sizeOf', 'widthOf', 'heightOf', 'maybeSizeOf'}.contains(node.methodName.name)) return;
    final owner = node.methodName.element?.enclosingElement;
    if (owner?.name != 'MediaQuery' || !isFromPackage(owner, 'flutter') || !_applies(node)) return;
    rule.reportAtNode(node, arguments: [node.toSource()]);
  }

  void _checkSize(Expression node, Expression? target, String property) {
    if (property != 'size' || target == null) return;
    final type = target.staticType?.element;
    if (type?.name != 'MediaQueryData' || !isFromPackage(type, 'flutter') || !_applies(node)) return;
    rule.reportAtNode(node, arguments: [node.toSource()]);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) => _checkSize(node, node.realTarget, node.propertyName.name);

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) => _checkSize(node, node.prefix, node.identifier.name);
}

/// No `kIsWeb` in UI code: the layout follows the screen size, not the
/// platform.
class NoKIsWebInUi extends AnalysisRule {
  NoKIsWebInUi() : super(name: 'no_kisweb_in_ui', description: _desc);

  static const _desc = 'UI does not branch on kIsWeb.';

  static const LintCode code = LintCode(
    'no_kisweb_in_ui',
    '[NEON] kIsWeb in UI code; decide the layout by screen size with $_replacement.',
    correctionMessage: 'A narrow browser window gets the phone layout, a tablet app the wide one.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addSimpleIdentifier(this, _KIsWebVisitor(this, RuleLayout.of(context)));
  }
}

class _KIsWebVisitor extends SimpleAstVisitor<void> {
  _KIsWebVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name != 'kIsWeb' || node.parent is Combinator) return;
    if (!isFromPackage(node.element, 'flutter') || !layout.isUi(unitPath(node))) return;
    rule.reportAtNode(node);
  }
}

/// No `Platform.isX` (dart:io) and no `defaultTargetPlatform` in UI code.
class NoPlatformInUi extends AnalysisRule {
  NoPlatformInUi() : super(name: 'no_platform_in_ui', description: _desc);

  static const _desc = 'UI does not branch on the platform.';

  static const LintCode code = LintCode(
    'no_platform_in_ui',
    '[NEON] `{0}` in UI code; the layout follows the screen size ($_replacement). '
        'Platform differences belong to the flavour or a service.',
    correctionMessage: 'Move the platform decision out of the widget.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _PlatformVisitor(this, RuleLayout.of(context));
    registry
      ..addPrefixedIdentifier(this, visitor)
      ..addSimpleIdentifier(this, visitor);
  }
}

class _PlatformVisitor extends SimpleAstVisitor<void> {
  _PlatformVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    final prefix = node.prefix.element;
    if (prefix is! ClassElement || prefix.name != 'Platform') return;
    if (prefix.library.uri.toString() != 'dart:io' || !layout.isUi(unitPath(node))) return;
    rule.reportAtNode(node, arguments: [node.toSource()]);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name != 'defaultTargetPlatform' || node.parent is Combinator) return;
    if (!isFromPackage(node.element, 'flutter') || !layout.isUi(unitPath(node))) return;
    rule.reportAtNode(node, arguments: [node.name]);
  }
}

/// `LayoutBuilder` only inside `lib/global_widgets`, for adapting a reusable
/// widget to the space it got; pages decide by screen size.
class NoLayoutBuilderInPages extends AnalysisRule {
  NoLayoutBuilderInPages() : super(name: 'no_layout_builder_in_pages', description: _desc);

  static const _desc = 'LayoutBuilder only inside global widgets.';

  static const LintCode code = LintCode(
    'no_layout_builder_in_pages',
    '[NEON] LayoutBuilder outside lib/global_widgets; pages use ResponsiveBuilder / context.screenSize, '
        'or a kit widget that adapts to its constraints (TwoPanelLayout, AppStatGrid.responsive).',
    correctionMessage: 'Use ResponsiveBuilder, or move the adaptive piece into a global widget.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addInstanceCreationExpression(this, _LayoutBuilderVisitor(this, RuleLayout.of(context)));
  }
}

class _LayoutBuilderVisitor extends SimpleAstVisitor<void> {
  _LayoutBuilderVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final widget = node.constructorName.element?.enclosingElement;
    if (widget?.name != 'LayoutBuilder' || !isFromPackage(widget, 'flutter')) return;
    final path = unitPath(node);
    if (!isAppSource(path) || layout.isIn(path, LayoutRole.globalWidgets)) return;
    rule.reportAtNode(node.constructorName);
  }
}

/// No width compared with a number (`constraints.maxWidth > 600`): the
/// breakpoints are `AppScreenSize` in app_responsive.dart.
class NoRawBreakpoint extends AnalysisRule {
  NoRawBreakpoint() : super(name: 'no_raw_breakpoint', description: _desc);

  static const _desc = 'No width compared with a numeric literal.';

  static const LintCode code = LintCode(
    'no_raw_breakpoint',
    '[NEON] `{0}` is a hand-made breakpoint; use AppScreenSize ($_replacement).',
    correctionMessage: 'Compare screen sizes (size.isAtLeast(AppScreenSize.tablet)), not pixels.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addBinaryExpression(this, _BreakpointVisitor(this, RuleLayout.of(context)));
  }
}

class _BreakpointVisitor extends SimpleAstVisitor<void> {
  _BreakpointVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  static const _comparisons = {TokenType.LT, TokenType.LT_EQ, TokenType.GT, TokenType.GT_EQ};

  @override
  void visitBinaryExpression(BinaryExpression node) {
    if (!_comparisons.contains(node.operator.type)) return;
    final left = node.leftOperand.unParenthesized;
    final right = node.rightOperand.unParenthesized;
    final hasNumber = _isNumber(left) || _isNumber(right);
    final hasWidth = _isWidth(left) || _isWidth(right);
    if (!hasNumber || !hasWidth) return;
    final path = unitPath(node);
    if (!isAppSource(path) || layout.isIn(path, LayoutRole.responsive)) return;
    rule.reportAtNode(node, arguments: [node.toSource()]);
  }

  static bool _isNumber(Expression expression) =>
      (expression is IntegerLiteral && (expression.value ?? 0) > 0) ||
      (expression is DoubleLiteral && expression.value > 0);

  /// `width`, `maxWidth`, `size.width`, `constraints.maxWidth`, ...
  static bool _isWidth(Expression expression) {
    final name = switch (expression) {
      SimpleIdentifier() => expression.name,
      PrefixedIdentifier() => expression.identifier.name,
      PropertyAccess() => expression.propertyName.name,
      _ => '',
    };
    return name == 'width' || name.endsWith('Width');
  }
}
