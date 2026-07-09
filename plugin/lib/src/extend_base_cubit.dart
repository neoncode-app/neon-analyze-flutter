import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
// LintCode is not in the public API surface yet.
import 'package:analyzer/src/dart/error/lint_codes.dart';

/// Requires every Cubit to extend `BaseCubit`, never `Cubit<T>` directly.
///
/// `BaseCubit` wires up shared behaviour (safe emit, presentation events);
/// extending `Cubit` directly bypasses it.
class ExtendBaseCubit extends AnalysisRule {
  ExtendBaseCubit() : super(name: 'extend_base_cubit', description: _desc);

  static const _desc = 'Cubits must extend BaseCubit, not Cubit directly.';

  static const LintCode _code = LintCode(
    'extend_base_cubit',
    '[NEON] cubits must extend BaseCubit, not Cubit directly.',
    correctionMessage:
        'Change `extends Cubit<...>` to `extends BaseCubit<...>`.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => _code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addClassDeclaration(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final superclass = node.extendsClause?.superclass;
    if (superclass == null) return;
    // Allow BaseCubit itself to extend Cubit.
    if (node.name.lexeme == 'BaseCubit') return;
    if (superclass.name.lexeme == 'Cubit') {
      rule.reportAtNode(superclass);
    }
  }
}
