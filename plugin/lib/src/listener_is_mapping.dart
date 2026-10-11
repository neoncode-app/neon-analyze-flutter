import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';

/// A `BlocPresentationListener`'s `listener:` only maps an event to a dialog
/// or a navigation: it branches on `event is X` (or `switch (event)`), makes
/// one call per branch (a show function, the shared handler,
/// `PresentationEventHandler.handleEvent`) and returns. It declares no
/// variables, reads no cubit (not even its own) and has no other branching:
/// everything the dialog needs travels in the event.
///
/// Allowed shapes:
/// * `if (event is X) showX(context, event);` (optionally with `return;`),
/// * `if (await handleShared(context, event)) return;`,
/// * `switch (event) { case X(): showX(...); ... }`,
/// * a fallback call, `return;`, `return call(...);`.
class ListenerIsMapping extends AnalysisRule {
  ListenerIsMapping() : super(name: 'listener_is_mapping', description: _desc);

  static const _desc = 'Presentation listeners only map events to dialogs or navigation.';

  static const LintCode code = LintCode(
    'listener_is_mapping',
    '[NEON] the presentation listener {0}; it may only map `event is X` to one show call. '
        'Put what the dialog needs into the event in the cubit.',
    correctionMessage: 'Move this logic into the cubit that emits the event.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addFunctionExpression(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  late Element? _event;

  void _report(AstNode node, String what) => rule.reportAtNode(node, arguments: [what]);

  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (!isAppSource(unitPath(node)) || !isPresentationListener(node)) return;
    final parameters = node.parameters?.parameters ?? const <FormalParameter>[];
    _event = parameters.length > 1 ? parameters[1].declaredFragment?.element : null;
    final body = node.body;
    switch (body) {
      case ExpressionFunctionBody():
        _checkCall(body.expression);
      case BlockFunctionBody():
        _checkStatements(body.block.statements, topLevel: true);
      default:
        break;
    }
  }

  void _checkStatements(List<Statement> statements, {required bool topLevel}) {
    var calls = 0;
    for (final statement in statements) {
      switch (statement) {
        case ReturnStatement(:final expression):
          if (expression != null) _checkCall(expression);
        case ExpressionStatement(:final expression):
          calls++;
          if (!topLevel && calls > 1) {
            _report(statement, 'makes more than one call in a branch');
          } else {
            _checkCall(expression);
          }
        case IfStatement():
          _checkIf(statement);
        case SwitchStatement():
          _checkSwitch(statement);
        case VariableDeclarationStatement():
          _report(statement, 'declares a variable');
        default:
          _report(statement, 'contains logic (${statement.runtimeType.toString().replaceAll('Impl', '')})');
      }
    }
  }

  void _checkIf(IfStatement statement) {
    final condition = statement.expression;
    if (_isEventTypeTest(condition)) {
      _checkBranch(statement.thenStatement);
    } else if (_isSharedHandlerCall(condition)) {
      final then = statement.thenStatement;
      final isBareReturn = (then is ReturnStatement && then.expression == null) ||
          (then is Block && then.statements.length == 1 && then.statements.single is ReturnStatement);
      if (!isBareReturn) _report(then, 'does more than return after the shared handler');
    } else {
      _report(condition, 'branches on something other than the event type');
      return;
    }
    final otherwise = statement.elseStatement;
    if (otherwise != null) {
      if (otherwise is IfStatement) {
        _checkIf(otherwise);
      } else {
        _checkBranch(otherwise);
      }
    }
  }

  void _checkBranch(Statement branch) {
    if (branch is Block) {
      _checkStatements(branch.statements, topLevel: false);
    } else {
      _checkStatements([branch], topLevel: false);
    }
  }

  void _checkSwitch(SwitchStatement statement) {
    final subject = statement.expression;
    if (!(subject is SimpleIdentifier && subject.element == _event)) {
      _report(subject, 'switches on something other than the event');
      return;
    }
    for (final member in statement.members) {
      _checkStatements(
        [
          for (final each in member.statements)
            if (each is! BreakStatement) each,
        ],
        topLevel: false,
      );
    }
  }

  /// `event is X` (or `event is! X`).
  bool _isEventTypeTest(Expression condition) {
    final test = condition.unParenthesized;
    return test is IsExpression &&
        test.expression is SimpleIdentifier &&
        (test.expression as SimpleIdentifier).element == _event;
  }

  /// `[await] handler(context, event)`, a shared handler returning bool.
  bool _isSharedHandlerCall(Expression condition) {
    var call = condition.unParenthesized;
    if (call is AwaitExpression) call = call.expression;
    if (call is! MethodInvocation) return false;
    return call.argumentList.arguments.any((argument) => argument is SimpleIdentifier && argument.element == _event);
  }

  /// A call is fine unless it is awaited, or reads a cubit or touches
  /// AlertCubit anywhere. (Only the shared handler in an `if` condition may
  /// be awaited, see [_isSharedHandlerCall].)
  void _checkCall(Expression expression) {
    if (expression is AwaitExpression) {
      _report(expression,
          'awaits `${expression.expression.toSource().split('(').first}`; the listener never waits for a dialog');
    }
    final unwrapped = expression is AwaitExpression ? expression.expression : expression;
    if (unwrapped is! InvocationExpression && unwrapped is! InstanceCreationExpression) {
      _report(expression, 'computes `${expression.toSource()}` instead of making one call');
      return;
    }
    final finder = _StateReadFinder();
    expression.accept(finder);
    for (final read in finder.reads) {
      _report(read, 'reads a cubit (`${read.toSource()}`)');
    }
  }
}

/// Collects provider reads and bloc / AlertCubit typed values in a subtree.
class _StateReadFinder extends RecursiveAstVisitor<void> {
  final reads = <AstNode>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (isProviderRead(node)) {
      reads.add(node);
      return;
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (isBloc(node.staticType)) {
      reads.add(node);
      return;
    }
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (isBloc(node.staticType)) {
      reads.add(node);
      return;
    }
    super.visitPrefixedIdentifier(node);
  }
}
