import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';

/// A `stream.listen(...)` inside a bloc or cubit is stored in a field and
/// that field is cancelled in `close()`. Otherwise the subscription outlives
/// the cubit and keeps calling into a closed one.
class CancelSubscriptionsInClose extends AnalysisRule {
  CancelSubscriptionsInClose() : super(name: 'cancel_subscriptions_in_close', description: _desc);

  static const _desc = 'Store stream subscriptions of a cubit in a field and cancel them in close().';

  static const LintCode code = LintCode(
    'cancel_subscriptions_in_close',
    '[NEON] {0}; store the subscription in a field and cancel it in close(): '
        '`await _sub?.cancel(); return super.close();`.',
    correctionMessage: 'Assign the listen() result to a StreamSubscription field and cancel it in close().',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addMethodInvocation(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name != 'listen' || !isAppSource(unitPath(node))) return;
    final target = node.realTarget;
    if (target == null || !isSubtypeOf(target.staticType, 'Stream', package: null)) return;
    final cubit = enclosingClass(node);
    final cubitElement = cubit?.declaredFragment?.element;
    if (cubit == null || cubitElement == null || !isBloc(cubitElement.thisType)) return;

    final field = _assignedField(node, cubitElement);
    if (field == null) {
      rule.reportAtNode(node, arguments: ['the subscription is not stored in a field']);
      return;
    }
    if (!_cancelledInClose(cubit, field.name ?? '')) {
      rule.reportAtNode(node, arguments: ['`${field.name}` is never cancelled in close()']);
    }
  }

  /// The field of [cubit] that `field = stream.listen(...)` (or `??=`)
  /// assigns, if any.
  static FieldElement? _assignedField(MethodInvocation node, ClassElement cubit) {
    final parent = node.parent;
    if (parent is! AssignmentExpression || parent.rightHandSide != node) return null;
    final element = parent.writeElement;
    final field = element is PropertyAccessorElement ? element.variable : element;
    return field is FieldElement && field.enclosingElement == cubit ? field : null;
  }

  static bool _cancelledInClose(ClassDeclaration cubit, String field) {
    final members = switch (cubit.body) {
      BlockClassBody(:final members) => members,
      _ => const <ClassMember>[],
    };
    for (final member in members) {
      if (member is MethodDeclaration && member.name.lexeme == 'close') {
        final source = member.body.toSource();
        return RegExp('\\b$field\\s*(\\?|!)?\\s*\\.\\s*cancel\\(').hasMatch(source);
      }
    }
    return false;
  }
}
