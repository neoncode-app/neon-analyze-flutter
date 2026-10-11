import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';

/// `BlocProvider` / `MultiBlocProvider` only in the router and shell
/// (`lib/flavors/**`) and inside the dialog helper (`lib/utils/utils.dart`,
/// `Utils.showCustomModalBottomSheet(create:)`).
///
/// Pages never provide cubits themselves (NCR0000014 decisions 1, 2 and 4).
class ProviderInRouter extends AnalysisRule {
  ProviderInRouter() : super(name: 'provider_in_router', description: _desc);

  static const _desc = 'Provide cubits only in the router, the shell and the dialog helper.';

  static const LintCode code = LintCode(
    'provider_in_router',
    '[NEON] {0} outside the router; provide page cubits in the route builder '
        '(lib/flavors/<flavor>/<flavor>_router.dart) and dialog cubits with Utils.showCustomModalBottomSheet(create:).',
    correctionMessage: 'Move the provider into the route builder or the dialog helper call.',
    severity: DiagnosticSeverity.WARNING,
  );

  static const owners = ['flavors/', 'utils/utils.dart'];

  static const _providers = {'BlocProvider', 'MultiBlocProvider'};

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
    final path = unitPath(node);
    if (!isAppSource(path) || ProviderInRouter.owners.any((owner) => isUnderLib(path, owner))) return;
    final element = node.constructorName.element?.enclosingElement;
    if (element == null ||
        !ProviderInRouter._providers.contains(element.name) ||
        !isFromPackage(element, 'flutter_bloc')) {
      return;
    }
    rule.reportAtNode(node.constructorName, arguments: [node.constructorName.toSource()]);
  }
}
