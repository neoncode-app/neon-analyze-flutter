import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';

/// The `build()` of a page (`*Page` widget, or its `*PageState`, in
/// `lib/pages`) returns, through the allowed wrappers, a widget whose class
/// doc comment ends with `{@category Template}` (AdminLayout, AppContentPage,
/// AppEditorScaffold, ...). The category is read from the resolved class, so
/// a newly added template counts without editing this rule.
class PageUsesTemplate extends AnalysisRule {
  PageUsesTemplate() : super(name: 'page_uses_template', description: _desc);

  static const _desc = 'Pages are composed from a Template widget.';

  static const LintCode code = LintCode(
    'page_uses_template',
    '[NEON] the page builds `{0}`, not a template; return a {@category Template} widget '
        '(AppContentPage, AdminLayout, AppEditorScaffold) through BlocProvider / BlocBuilder / BlocPresentationListener.',
    correctionMessage: 'Wrap the page content in a template widget.',
    severity: DiagnosticSeverity.WARNING,
  );

  /// Widgets that only pass their child through (package:flutter_bloc and
  /// package:bloc_presentation).
  static const wrappers = {
    'BlocProvider',
    'MultiBlocProvider',
    'BlocBuilder',
    'BlocConsumer',
    'BlocListener',
    'MultiBlocListener',
    'BlocSelector',
    'BlocPresentationListener',
  };

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addMethodDeclaration(this, _TemplateVisitor(this));
  }
}

class _TemplateVisitor extends SimpleAstVisitor<void> {
  _TemplateVisitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme != 'build') return;
    final path = unitPath(node);
    if (!isAppSource(path) || !isUnderLib(path, 'pages/')) return;
    final className = enclosingClass(node)?.name.lexeme ?? '';
    final bare = className.startsWith('_') ? className.substring(1) : className;
    if (!bare.endsWith('Page') && !bare.endsWith('PageState')) return;
    for (final returned in _returnedExpressions(node.body)) {
      _check(returned);
    }
  }

  void _check(Expression expression) {
    final value = expression.unParenthesized;
    if (value is ConditionalExpression) {
      _check(value.thenExpression);
      _check(value.elseExpression);
      return;
    }
    if (value is! InstanceCreationExpression) {
      rule.reportAtNode(value, arguments: [value.toSource()]);
      return;
    }
    final widget = value.constructorName.element?.enclosingElement;
    final name = widget?.name ?? '';
    if (PageUsesTemplate.wrappers.contains(name) &&
        (isFromPackage(widget, 'flutter_bloc') || isFromPackage(widget, 'bloc_presentation'))) {
      for (final argument in value.argumentList.arguments) {
        if (argument is! NamedExpression) continue;
        final label = argument.name.label.name;
        if (label == 'child') _check(argument.expression);
        final builder = argument.expression;
        if ((label == 'builder') && builder is FunctionExpression) {
          _returnedExpressions(builder.body).forEach(_check);
        }
      }
      return;
    }
    if (categoryOf(widget) == 'Template') return;
    rule.reportAtNode(value.constructorName, arguments: [name]);
  }

  /// Every expression [body] returns (an expression body, or each
  /// `return x;` not inside a nested function).
  static List<Expression> _returnedExpressions(FunctionBody body) {
    if (body is ExpressionFunctionBody) return [body.expression];
    final collector = _ReturnCollector();
    body.accept(collector);
    return collector.returned;
  }
}

class _ReturnCollector extends RecursiveAstVisitor<void> {
  final returned = <Expression>[];

  @override
  void visitReturnStatement(ReturnStatement node) {
    final expression = node.expression;
    if (expression != null) returned.add(expression);
  }

  // Returns inside nested closures belong to those closures.
  @override
  void visitFunctionExpression(FunctionExpression node) {}
}

/// Where a page uses `AppContentPage`, it passes both `title:` and
/// `subtitle:` (every content page has both, ADMINISTRATION.md 1b).
class PageHasTitleSubtitle extends AnalysisRule {
  PageHasTitleSubtitle() : super(name: 'page_has_title_subtitle', description: _desc);

  static const _desc = 'AppContentPage gets both a title and a subtitle.';

  static const LintCode code = LintCode(
    'page_has_title_subtitle',
    '[NEON] AppContentPage without {0}; every content page passes title: and subtitle: '
        '(tr keys <app>_<page>_title / _subtitle).',
    correctionMessage: 'Add the missing argument and its translation keys.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addInstanceCreationExpression(this, _TitleVisitor(this));
  }
}

class _TitleVisitor extends SimpleAstVisitor<void> {
  _TitleVisitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.element?.enclosingElement.name != 'AppContentPage') return;
    if (!isAppSource(unitPath(node))) return;
    final given = {
      for (final argument in node.argumentList.arguments)
        if (argument is NamedExpression && argument.expression is! NullLiteral) argument.name.label.name,
    };
    final missing = [
      for (final name in ['title', 'subtitle'])
        if (!given.contains(name)) '$name:',
    ];
    if (missing.isNotEmpty) rule.reportAtNode(node.constructorName, arguments: [missing.join(' and ')]);
  }
}
