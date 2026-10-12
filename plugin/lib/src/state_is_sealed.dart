import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// The state type of a `BaseCubit<S>` is a `sealed` class hierarchy
/// (`Initial / Loading / Loaded / Error`), so `switch (state)` in the UI is
/// exhaustive. Cubits in an app-wide folder (layout role `app_wide_cubits`,
/// default `lib/bloc/<app>/app_wide/`:
/// rules, session, alert, upgrade, publish, notifications) are exempt.
class StateIsSealed extends AnalysisRule {
  StateIsSealed() : super(name: 'state_is_sealed', description: _desc);

  static const _desc = 'Page cubit states are sealed class hierarchies.';

  static const LintCode code = LintCode(
    'state_is_sealed',
    '[NEON] the state `{0}` of this cubit is not a sealed class; declare '
        '`sealed class {0}` with Initial / Loading / Loaded / Error subclasses.',
    correctionMessage:
        'Make the state a sealed class hierarchy, or move an app-wide cubit to lib/bloc/<app>/app_wide/.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addClassDeclaration(this, _Visitor(this, RuleLayout.of(context)));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final path = unitPath(node);
    if (!isAppSource(path) || layout.isIn(path, LayoutRole.appWideCubits)) return;
    final element = node.declaredFragment?.element;
    if (element == null || element.isAbstract || element.name == 'BaseCubit') return;
    final baseCubit = supertypeNamed(node, 'BaseCubit');
    if (baseCubit == null || baseCubit.typeArguments.isEmpty) return;
    final state = baseCubit.typeArguments.first.element;
    if (state is ClassElement && state.isSealed) return;
    final extendsClause = node.extendsClause;
    rule.reportAtNode(
      extendsClause?.superclass ?? node,
      arguments: [baseCubit.typeArguments.first.getDisplayString()],
    );
  }
}
