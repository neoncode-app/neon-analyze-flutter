import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// A bloc or cubit is constructed only inside a provider's `create:`
/// callback: `BlocProvider(create: (_) => XCubit(...)..load())` in the router
/// or shell, or `Utils.showCustomModalBottomSheet(create: ...)` for a dialog.
///
/// Then the provider owns it: it is created when the route or dialog opens
/// and closed when it goes away (NCR0000014 decisions 1 and 4).
///
/// The one exception is the app startup (layout role `app_root`, default
/// `lib/app/bootstrap.dart`): the app-wide cubits the router's redirect reads
/// (session, alert, auth) exist before the router does, so the startup builds
/// them and provides them above it with `BlocProvider<X>.value`.
class CubitCreatedInProvider extends AnalysisRule {
  CubitCreatedInProvider() : super(name: 'cubit_created_in_provider', description: _desc);

  static const _desc = 'Construct blocs and cubits only in a provider create callback.';

  static const LintCode code = LintCode(
    'cubit_created_in_provider',
    '[NEON] {0} is constructed outside a provider; create it in '
        "BlocProvider(create: (_) => {0}(...)..load()) in the route, or Utils.showCustomModalBottomSheet(create:).",
    correctionMessage: 'Move the construction into the create: callback that provides it.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addInstanceCreationExpression(this, _Visitor(this, RuleLayout.of(context)));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final path = unitPath(node);
    if (!isAppSource(path) || layout.isIn(path, LayoutRole.appRoot) || !isBloc(node.staticType)) return;
    if (_insideCreate(node)) return;
    rule.reportAtNode(node.constructorName, arguments: [node.constructorName.type.name.lexeme]);
  }

  /// Whether [node] is (part of) the result of a function passed as `create:`.
  static bool _insideCreate(AstNode node) {
    for (AstNode? current = node.parent; current != null; current = current.parent) {
      if (current is FunctionExpression) {
        final argument = current.parent;
        return argument is NamedExpression && argument.name.label.name == 'create';
      }
      if (current is FunctionBody && current.parent is! FunctionExpression) return false;
    }
    return false;
  }
}
