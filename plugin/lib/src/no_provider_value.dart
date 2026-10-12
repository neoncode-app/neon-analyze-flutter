import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';

/// No `BlocProvider.value(value: _cubit)` where the cubit is a field of a
/// widget `State`: the State then owns a cubit's lifetime by hand. Create it
/// in a provider instead (`BlocProvider(create: ...)` in the route, or the
/// dialog helper's `create:`).
class NoProviderValue extends AnalysisRule {
  NoProviderValue() : super(name: 'no_provider_value', description: _desc);

  static const _desc = 'Do not provide a cubit held in a State with BlocProvider.value.';

  static const LintCode code = LintCode(
    'no_provider_value',
    '[NEON] BlocProvider.value provides `{0}`, a cubit held in this State; create it with '
        'BlocProvider(create: ...) in the route or Utils.showCustomModalBottomSheet(create:).',
    correctionMessage: 'Remove the field and let a provider create and close the cubit.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addInstanceCreationExpression(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (!isAppSource(unitPath(node))) return;
    final constructor = node.constructorName.element;
    final provider = constructor?.enclosingElement;
    if (constructor?.name != 'value' || provider?.name != 'BlocProvider' || !isFromPackage(provider, 'flutter_bloc')) {
      return;
    }
    final stateClass = enclosingClass(node);
    if (stateClass == null || supertypeNamed(stateClass, 'State') == null) return;
    for (final argument in node.argumentList.arguments) {
      if (argument is! NamedExpression || argument.name.label.name != 'value') continue;
      final value = argument.expression;
      final element = switch (value) {
        SimpleIdentifier() => value.element,
        PropertyAccess(target: ThisExpression()) => value.propertyName.element,
        _ => null,
      };
      final field = element is PropertyAccessorElement ? element.variable : element;
      if (field is FieldElement && !field.isStatic && field.enclosingElement == stateClass.declaredFragment?.element) {
        rule.reportAtNode(value, arguments: [value.toSource()]);
      }
    }
  }
}
