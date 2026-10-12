import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// UI code (`lib/pages`, `lib/features`, `lib/global_widgets`) never touches
/// `AlertCubit`: the cubit method that knows the outcome shows the alert
/// (AlertCubit injected into the cubit). The toast renderer lives outside
/// these folders (`lib/app/`).
class AlertOnlyInCubit extends AnalysisRule {
  AlertOnlyInCubit() : super(name: 'alert_only_in_cubit', description: _desc);

  static const _desc = 'Show alerts from cubits, never from UI code.';

  static const LintCode code = LintCode(
    'alert_only_in_cubit',
    '[NEON] AlertCubit in UI code; inject AlertCubit into the cubit and call '
        'showSuccess / showError in the cubit method that knows the outcome.',
    correctionMessage: 'Remove the AlertCubit reference from this widget.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _Visitor(this, RuleLayout.of(context));
    registry
      ..addNamedType(this, visitor)
      ..addMethodInvocation(this, visitor)
      ..addPrefixedIdentifier(this, visitor)
      ..addPropertyAccess(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  bool _inUi(AstNode node) => layout.isUi(unitPath(node));

  @override
  void visitNamedType(NamedType node) {
    if (node.name.lexeme == 'AlertCubit' && node.element?.name == 'AlertCubit' && _inUi(node)) {
      rule.reportAtNode(node);
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // `alert.showSuccess(...)` on a variable that holds the AlertCubit. When
    // the type is named in the target, visitNamedType reports; a getter target
    // (`context.alertCubit.showSuccess`) is reported as the getter access.
    final target = node.realTarget;
    if (target == null || target is PrefixedIdentifier || target is PropertyAccess) return;
    if (!isSubtypeOf(target.staticType, 'AlertCubit')) return;
    if (target.toSource().contains('AlertCubit') || !_inUi(node)) return;
    rule.reportAtNode(target);
  }

  // `context.alertCubit`: the AlertCubit reached through a getter, whether a
  // method is called on it or it is handed to a cubit the widget builds.
  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) => _getterAccess(node, node.identifier.element);

  @override
  void visitPropertyAccess(PropertyAccess node) => _getterAccess(node, node.propertyName.element);

  void _getterAccess(Expression node, Element? element) {
    if (element is! PropertyAccessorElement || !isSubtypeOf(node.staticType, 'AlertCubit') || !_inUi(node)) return;
    rule.reportAtNode(node);
  }
}
