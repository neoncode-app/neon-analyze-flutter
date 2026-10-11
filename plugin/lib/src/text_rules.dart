import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';

/// Text style, logging and user-visible string rules.

/// No `TextStyle(...)` and no `copyWith(fontWeight / fontSize /
/// letterSpacing / height ...)` outside the text style files
/// (`*_text_styles.dart`) and the theme assembly (`lib/utils/ui/app_style.dart`).
/// The only override is `copyWith(color: ...)`.
class NoRawTextStyle extends AnalysisRule {
  NoRawTextStyle() : super(name: 'no_raw_text_style', description: _desc);

  static const _desc = 'Text styles come from AppTextStyles.';

  static const LintCode code = LintCode(
    'no_raw_text_style',
    '[NEON] {0}; every weight / size combination is a named style in AppTextStyles '
        '(context.appText.x). Only copyWith(color: ...) is allowed here.',
    correctionMessage: 'Add a named style to app_text_styles.dart and use it.',
    severity: DiagnosticSeverity.WARNING,
  );

  static bool isOwner(String path) => path.endsWith('_text_styles.dart') || isUnderLib(path, 'utils/ui/app_style.dart');

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _TextStyleVisitor(this);
    registry
      ..addInstanceCreationExpression(this, visitor)
      ..addMethodInvocation(this, visitor);
  }
}

class _TextStyleVisitor extends SimpleAstVisitor<void> {
  _TextStyleVisitor(this.rule);

  final AnalysisRule rule;

  bool _applies(AstNode node) {
    final path = unitPath(node);
    return isAppSource(path) && !NoRawTextStyle.isOwner(path);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.element?.enclosingElement;
    if (type?.name != 'TextStyle' || !isFromPackage(type, 'flutter') || !_applies(node)) return;
    rule.reportAtNode(node.constructorName, arguments: ['`TextStyle(...)` is built by hand']);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name != 'copyWith') return;
    final target = node.realTarget?.staticType?.element;
    if (target?.name != 'TextStyle' || !isFromPackage(target, 'flutter') || !_applies(node)) return;
    final changed = [
      for (final argument in node.argumentList.arguments)
        if (argument is NamedExpression && argument.name.label.name != 'color') argument.name.label.name,
    ];
    if (changed.isNotEmpty) {
      rule.reportAtNode(node.methodName, arguments: ['copyWith changes ${changed.join(', ')}']);
    }
  }
}

/// No `debugPrint`: logging goes through the app logger
/// (`lib/utils/helpers/log_utils.dart`). (`print` is the core `avoid_print`.)
class NoDebugPrint extends AnalysisRule {
  NoDebugPrint() : super(name: 'no_debug_print', description: _desc);

  static const _desc = 'Log through the app logger, not debugPrint.';

  static const LintCode code = LintCode(
    'no_debug_print',
    '[NEON] debugPrint; log through the app logger (lib/utils/helpers/log_utils.dart).',
    correctionMessage: 'Replace it with the logger, or remove the leftover.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _DebugPrintVisitor(this);
    registry
      ..addMethodInvocation(this, visitor)
      ..addFunctionExpressionInvocation(this, visitor);
  }
}

class _DebugPrintVisitor extends SimpleAstVisitor<void> {
  _DebugPrintVisitor(this.rule);

  final AnalysisRule rule;

  void _check(SimpleIdentifier name) {
    if (name.name != 'debugPrint' || !isFromPackage(name.element, 'flutter')) return;
    final path = unitPath(name);
    if (!isAppSource(path) || isUnderLib(path, 'utils/helpers/log_utils.dart')) return;
    rule.reportAtNode(name);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) => _check(node.methodName);

  // Flutter's debugPrint is a variable of a function type, so a call is a
  // function-expression invocation.
  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    final function = node.function;
    if (function is SimpleIdentifier) _check(function);
  }
}

/// No user-visible text written directly in UI code: `Text('...')` and the
/// `label:` / `title:` / `subtitle:` / `message:` / `hintText:` / `tooltip:`
/// / ... arguments take `tr('key')` (in pages) or a String parameter (in
/// global widgets). Strings without letters (`'•'`, `'%'`) and the widget
/// catalog's preview fixtures are not texts.
class NoHardcodedUiString extends AnalysisRule {
  NoHardcodedUiString() : super(name: 'no_hardcoded_ui_string', description: _desc);

  static const _desc = 'User-visible texts go through tr().';

  static const LintCode code = LintCode(
    'no_hardcoded_ui_string',
    "[NEON] hardcoded text '{0}'; use tr('key') with the key in every language file "
        '(a global widget takes the text as a String parameter).',
    correctionMessage: 'Add a translation key to cs / en / sk and use tr().',
    severity: DiagnosticSeverity.WARNING,
  );

  static const textArguments = {
    'label',
    'title',
    'subtitle',
    'message',
    'description',
    'hintText',
    'labelText',
    'helperText',
    'tooltip',
    'text',
    'placeholder',
    'semanticLabel',
    'emptyMessage',
    'actionLabel',
  };

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addSimpleStringLiteral(this, _UiStringVisitor(this));
  }
}

class _UiStringVisitor extends SimpleAstVisitor<void> {
  _UiStringVisitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (RegExp(r'\p{L}', unicode: true).allMatches(node.value).length < 2) return;
    final parent = node.parent;
    final isTextArgument = switch (parent) {
      NamedExpression() => NoHardcodedUiString.textArguments.contains(parent.name.label.name),
      ArgumentList(parent: InstanceCreationExpression(:final constructorName)) =>
        constructorName.element?.enclosingElement.name == 'Text' &&
            parent.arguments.first == node &&
            isFromPackage(constructorName.element, 'flutter'),
      _ => false,
    };
    if (!isTextArgument) return;
    final path = unitPath(node);
    if (!isUiSource(path) || path.contains('/widget_catalog/previews/')) return;
    final shown = node.value.length > 40 ? '${node.value.substring(0, 40)}...' : node.value;
    rule.reportAtNode(node, arguments: [shown]);
  }
}

/// No em dash, en dash or minus sign in string literals: they read as
/// machine-written. Logging and error messages are allow-listed.
class NoDashInStrings extends AnalysisRule {
  NoDashInStrings() : super(name: 'no_dash_in_strings', description: _desc);

  static const _desc = 'No typographic dashes in strings.';

  static const LintCode code = LintCode(
    'no_dash_in_strings',
    '[NEON] the string contains `{0}`; use a comma, a full stop, "od X do Y" or the common_date_range key.',
    correctionMessage: 'Rewrite the text without the dash.',
    severity: DiagnosticSeverity.WARNING,
  );

  static final _dash = RegExp('[—–−]');

  /// Calls whose string arguments are logs or developer-facing messages.
  static const logCalls = {
    'debugPrint',
    'print',
    'log',
    'logInfo',
    'logError',
    'logWarning',
    'StateError',
    'ArgumentError',
    'Exception',
    'FlutterError',
    'UnimplementedError',
    'UnsupportedError',
    'AssertionError',
  };

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _DashVisitor(this);
    registry
      ..addSimpleStringLiteral(this, visitor)
      ..addStringInterpolation(this, visitor);
  }
}

class _DashVisitor extends SimpleAstVisitor<void> {
  _DashVisitor(this.rule);

  final AnalysisRule rule;

  void _check(StringLiteral node, String text) {
    final match = NoDashInStrings._dash.firstMatch(text);
    if (match == null || node.parent is Directive || node.parent is StringInterpolation) return;
    if (!isAppSource(unitPath(node)) || _isLogArgument(node)) return;
    rule.reportAtNode(node, arguments: [match.group(0) ?? '']);
  }

  static bool _isLogArgument(AstNode node) {
    for (AstNode? current = node.parent; current != null; current = current.parent) {
      final name = switch (current) {
        MethodInvocation() => current.methodName.name,
        FunctionExpressionInvocation(function: SimpleIdentifier(:final name)) => name,
        InstanceCreationExpression() => current.constructorName.type.name.lexeme,
        AssertStatement() || AssertInitializer() => 'AssertionError',
        _ => null,
      };
      if (name != null) return NoDashInStrings.logCalls.contains(name);
      if (current is Statement || current is FunctionBody) return false;
    }
    return false;
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) => _check(node, node.value);

  @override
  void visitStringInterpolation(StringInterpolation node) => _check(
        node,
        node.elements.whereType<InterpolationString>().map((part) => part.value).join(),
      );
}
