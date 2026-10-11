import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';

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

  static const uiFolders = ['pages/', 'features/', 'global_widgets/'];

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _Visitor(this);
    registry
      ..addNamedType(this, visitor)
      ..addMethodInvocation(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  bool _inUi(AstNode node) {
    final path = unitPath(node);
    return isAppSource(path) && AlertOnlyInCubit.uiFolders.any((folder) => isUnderLib(path, folder));
  }

  @override
  void visitNamedType(NamedType node) {
    if (node.name.lexeme == 'AlertCubit' && node.element?.name == 'AlertCubit' && _inUi(node)) {
      rule.reportAtNode(node);
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // `context.alertCubit.showSuccess(...)`: AlertCubit used without naming
    // the type. When the type is named in the target, visitNamedType reports.
    final target = node.realTarget;
    if (target == null || !isSubtypeOf(target.staticType, 'AlertCubit')) return;
    if (target.toSource().contains('AlertCubit') || !_inUi(node)) return;
    rule.reportAtNode(target);
  }
}
