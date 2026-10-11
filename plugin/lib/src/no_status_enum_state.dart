import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';

/// A cubit state carries no `XStatus` enum field next to nullable data:
/// each status is its own subclass of a sealed state (`XLoading`,
/// `XLoaded(data)`, `XError(message)`), so a state can never claim "loaded"
/// without its data.
class NoStatusEnumState extends AnalysisRule {
  NoStatusEnumState() : super(name: 'no_status_enum_state', description: _desc);

  static const _desc = 'States use sealed subclasses, not a status enum field.';

  static const LintCode code = LintCode(
    'no_status_enum_state',
    '[NEON] state field `{0}` is a status enum ({1}); make each status a subclass of a sealed state '
        '(XLoading, XLoaded(data), XError(message)).',
    correctionMessage: 'Replace the enum field with sealed state subclasses.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addFieldDeclaration(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    if (node.isStatic || !isUnderLib(unitPath(node), 'bloc/')) return;
    final stateClass = enclosingClass(node)?.declaredFragment?.element;
    if (stateClass == null || !_isState(stateClass)) return;
    for (final variable in node.fields.variables) {
      final type = variable.declaredFragment?.element.type;
      final enumElement = type?.element;
      if (enumElement is EnumElement && (enumElement.name ?? '').endsWith('Status')) {
        rule.reportAtNode(variable, arguments: [variable.name.lexeme, enumElement.name ?? '']);
      }
    }
  }

  /// A class named `*State`, or extending one, declared under lib/bloc.
  static bool _isState(ClassElement element) => [element.thisType, ...element.allSupertypes]
      .any((type) => (type.element.name ?? '').endsWith('State') && type.element.name != 'State');
}
