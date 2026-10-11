import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';

/// Bans `context.read<X>()`, `context.watch<X>()`, `context.select<X, T>()`
/// and `BlocProvider.of<X>(context)` outside the flavour's providers file
/// (`lib/flavors/<flavor>/<flavor>_providers.dart`).
///
/// Every cubit is reached through one typed getter defined once per flavour
/// (`context.alertCubit`), so the set of things a page can read is listed in
/// one place (NCR0000014 decision 3).
class UseContextGetters extends AnalysisRule {
  UseContextGetters() : super(name: 'use_context_getters', description: _desc);

  static const _desc = 'Reach cubits through the typed context getters of the flavour.';

  static const LintCode code = LintCode(
    'use_context_getters',
    '[NEON] {0} reads a provider directly; use the typed getter (context.xCubit) from '
        'lib/flavors/<flavor>/<flavor>_providers.dart.',
    correctionMessage: 'Add the getter to the providers file if it is missing, then call it here.',
    severity: DiagnosticSeverity.WARNING,
  );

  static const _contextExtensions = {'ReadContext', 'WatchContext', 'SelectContext'};

  /// The providers file of a flavour, the only place allowed to read.
  static bool isProvidersFile(String path) => RegExp(r'/lib/flavors/(\w+)/\1_providers\.dart$').hasMatch(path);

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addMethodInvocation(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final UseContextGetters rule;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final path = unitPath(node);
    if (!isAppSource(path) || UseContextGetters.isProvidersFile(path)) return;
    final method = node.methodName.element;
    if (method is! MethodElement) return;
    final owner = method.enclosingElement;
    final viaContext = owner is ExtensionElement &&
        UseContextGetters._contextExtensions.contains(owner.name) &&
        isFromPackage(owner, 'provider');
    final viaOf = method.name == 'of' &&
        method.isStatic &&
        owner is InterfaceElement &&
        owner.name == 'BlocProvider' &&
        isFromPackage(owner, 'flutter_bloc');
    if (viaContext || viaOf) {
      rule.reportAtNode(node, arguments: [viaOf ? 'BlocProvider.of' : 'context.${method.name}']);
    }
  }
}
