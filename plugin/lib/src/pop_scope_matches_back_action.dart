import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// The system back runs the same action as the app's back-action widget.
///
/// An app names its widgets whose action the system back must also trigger
/// in `neon_check.yaml`, with the parameter that holds the action:
///
/// ```yaml
/// back_actions: {SubmitBar: onTap}
/// ```
///
/// A page or feature file that builds such a widget also builds a
/// `PopScope` whose `onPopInvokedWithResult` (or `onPopInvoked`) runs that
/// same action, so the hardware back and the bar do one thing. Without
/// `back_actions` the rule checks nothing (neoncode has no such widget).
///
/// The action is compared by its source: a tear-off (`cubit.save`, `onBack`)
/// or the call a closure makes (`() => cubit.save()` is `cubit.save`). An
/// action that is a field of the widget class building the bar is a callback
/// forwarded from the page that composes it, and that page carries the
/// PopScope; a file cannot see its composer, so it is not reported here.
class PopScopeMatchesBackAction extends AnalysisRule {
  PopScopeMatchesBackAction() : super(name: 'pop_scope_matches_back_action', description: _desc);

  static const _desc = 'The system back runs the same action as the back-action widget (PopScope beside it).';

  static const LintCode code = LintCode(
    'pop_scope_matches_back_action',
    '[NEON] `{0}.{1}` runs `{2}`, but no PopScope in this file runs it on the system back; the system back and '
        'the bar must do the same thing.',
    correctionMessage:
        'Wrap the page in PopScope(canPop: false, onPopInvokedWithResult: (didPop, _) { if (!didPop) {2}(); }).',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final layout = RuleLayout.of(context);
    if (layout.backActions.isEmpty) return;
    registry.addCompilationUnit(this, _Visitor(this, layout));
  }

  /// The action [expression] runs, as source: a tear-off as written, a
  /// closure by the one call it makes; `null` when it is neither (a literal
  /// `null`, a closure with several statements).
  static String? actionOf(Expression expression) {
    if (expression is SimpleIdentifier || expression is PrefixedIdentifier || expression is PropertyAccess) {
      return expression.toSource();
    }
    if (expression is FunctionExpression) {
      final body = expression.body;
      final Expression? call = switch (body) {
        ExpressionFunctionBody(:final expression) => expression,
        BlockFunctionBody(:final block) when block.statements.length == 1 => switch (block.statements.single) {
            ExpressionStatement(:final expression) => expression,
            _ => null,
          },
        _ => null,
      };
      final invocation = call is AwaitExpression ? call.expression : call;
      if (invocation is MethodInvocation) {
        final target = invocation.target;
        return target == null ? invocation.methodName.name : '${target.toSource()}.${invocation.methodName.name}';
      }
      if (invocation is FunctionExpressionInvocation) return invocation.function.toSource();
    }
    return null;
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    final path = unitPath(node);
    if (!isAppSource(path) || !(layout.isIn(path, LayoutRole.pages) || layout.isIn(path, LayoutRole.features))) {
      return;
    }
    final collector = _Collector(layout.backActions);
    node.accept(collector);
    final popSources = [for (final callback in collector.popCallbacks) callback.toSource()];
    for (final found in collector.backActions) {
      final action = PopScopeMatchesBackAction.actionOf(found.action);
      if (action == null || collector.isForwarded(found.creation, action)) continue;
      final pattern = RegExp('(^|[^A-Za-z0-9_.])${RegExp.escape(action)}(\\(|[^A-Za-z0-9_(]|\$)');
      if (popSources.any(pattern.hasMatch)) continue;
      rule.reportAtNode(found.creation.constructorName, arguments: [found.widget, found.parameter, action]);
    }
  }
}

class _Collector extends RecursiveAstVisitor<void> {
  _Collector(this.config);

  final Map<String, String> config;

  final backActions = <({InstanceCreationExpression creation, String widget, String parameter, Expression action})>[];

  final popCallbacks = <Expression>[];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final name = node.constructorName.type.name.lexeme;
    final parameter = config[name];
    if (parameter != null) {
      for (final argument in node.argumentList.arguments.whereType<NamedExpression>()) {
        if (argument.name.label.name == parameter) {
          backActions.add((creation: node, widget: name, parameter: parameter, action: argument.expression));
        }
      }
    }
    if (name == 'PopScope' && isFromPackage(node.constructorName.type.element, 'flutter')) {
      for (final argument in node.argumentList.arguments.whereType<NamedExpression>()) {
        if (const {'onPopInvokedWithResult', 'onPopInvoked'}.contains(argument.name.label.name)) {
          popCallbacks.add(argument.expression);
        }
      }
    }
    super.visitInstanceCreationExpression(node);
  }

  /// Whether [action] is a field of the class that builds [creation]: a
  /// callback forwarded from the composing page.
  bool isForwarded(AstNode creation, String action) {
    final name = action.startsWith('widget.') ? action.substring('widget.'.length) : action;
    if (name.contains('.')) return false;
    final owner = creation.thisOrAncestorOfType<ClassDeclaration>();
    if (owner == null) return false;
    final fieldsOf = <ClassDeclaration>[owner];
    // A State reads its widget's fields through `widget.`.
    final unit = creation.root;
    if (action.startsWith('widget.') && unit is CompilationUnit) {
      fieldsOf.addAll(unit.declarations.whereType<ClassDeclaration>());
    }
    return fieldsOf.any(
      (declaration) => switch (declaration.body) {
        final BlockClassBody body => body.members,
        _ => const <ClassMember>[],
      }
          .whereType<FieldDeclaration>()
          .any((field) => field.fields.variables.any((variable) => variable.name.lexeme == name)),
    );
  }
}
