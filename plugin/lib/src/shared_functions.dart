import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

// Identical logic exists once (NCC0000064, rule doc `shared_functions`). The
// inline patterns below each have a shared helper; copies no pattern catches
// are found by the neon-check step `duplicates`.

const _collections = 'package:neon_flutter_utils/collections.dart';

/// Inline copies of a shared helper in cubits, features and pages:
/// set copies (`{...x}..remove(`, `{...x, y}`), replace / remove by id
/// (`.map((c) => c.id == id ? x : c)`, `[for (c in l) if (c.id == id) x else c]`,
/// `.where((c) => c.id != id)`), query matching (`trim().toLowerCase()` with
/// `.contains(`), `emitPresentation(CloseDialog())` followed by a return, and
/// the `/api/uploads` request. A `Timer` debounce field is `use_shared_utils`.
class SharedFunctions extends AnalysisRule {
  SharedFunctions() : super(name: 'shared_functions', description: _desc);

  static const _desc = 'Identical logic exists once: use the shared helper instead of an inline copy.';

  static const LintCode code = LintCode(
    'shared_functions',
    '[NEON] {0}; use {1}.',
    correctionMessage: 'Identical logic exists once (rule shared_functions): collections, dates and debounce in '
        'neon_flutter_utils, dialog helpers on BaseCubit, uploads through NeoApiImageUpload.uploadImageUrl.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _Visitor(this, RuleLayout.of(context));
    registry
      ..addSetOrMapLiteral(this, visitor)
      ..addMethodInvocation(this, visitor)
      ..addListLiteral(this, visitor)
      ..addBlock(this, visitor)
      ..addSimpleStringLiteral(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  bool _inScope(AstNode node) {
    final path = unitPath(node);
    // BaseCubit is where the dialog helpers live.
    if (!layout.isAppSource(path) || path.endsWith('/bloc/global/base/base_cubit.dart')) return false;
    return layout.isIn(path, LayoutRole.bloc) ||
        layout.isIn(path, LayoutRole.features) ||
        layout.isIn(path, LayoutRole.pages);
  }

  void _report(AstNode at, String what, String use) => rule.reportAtNode(at, arguments: [what, use]);

  @override
  void visitSetOrMapLiteral(SetOrMapLiteral node) {
    if (!node.isSet || !_inScope(node)) return;
    final spreads = node.elements.whereType<SpreadElement>().length;
    if (spreads != 1) return;
    final parent = node.parent;
    final removes = parent is CascadeExpression &&
        parent.target == node &&
        parent.cascadeSections.any((section) => section is MethodInvocation && section.methodName.name == 'remove');
    if (removes) {
      _report(node, 'a set copied to remove an element', 'toggled / removing from $_collections');
    } else if (node.elements.length > 1) {
      _report(node, 'a set copied to add an element', 'adding / toggled from $_collections');
    }
  }

  @override
  void visitListLiteral(ListLiteral node) {
    if (!_inScope(node)) return;
    for (final element in node.elements) {
      if (element is! ForElement) continue;
      final parts = element.forLoopParts;
      final body = element.body;
      if (parts is! ForEachPartsWithDeclaration || body is! IfElement || body.elseElement == null) continue;
      if (!_comparesId(body.expression, parts.loopVariable.name.lexeme, TokenType.EQ_EQ)) continue;
      _report(element, 'a list rebuilt to replace one element by id', 'replaceById / updateById from $_collections');
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    switch (name) {
      case 'map' || 'where':
        final function = node.argumentList.arguments.firstOrNull;
        if (function is! FunctionExpression) return;
        final parameter = function.parameters?.parameters.firstOrNull?.name?.lexeme;
        final body = function.body;
        if (parameter == null || body is! ExpressionFunctionBody || !_inScope(node)) return;
        final expression = body.expression;
        if (name == 'map' &&
            expression is ConditionalExpression &&
            _comparesId(expression.condition, parameter, TokenType.EQ_EQ) &&
            _isIdentifier(expression.elseExpression, parameter)) {
          _report(node.methodName, 'a list mapped to replace one element by id',
              'replaceById / updateById from $_collections');
        } else if (name == 'where' && _comparesId(expression, parameter, TokenType.BANG_EQ)) {
          _report(node.methodName, 'a list filtered to remove one element by id', 'removeById from $_collections');
        }
      case 'toLowerCase':
        final target = node.realTarget;
        if (target is! MethodInvocation || target.methodName.name != 'trim' || !_inScope(node)) return;
        final body = node.thisOrAncestorOfType<FunctionBody>();
        if (body == null || !_callsContains(body)) return;
        _report(node.methodName, 'a query normalised and matched by hand', 'matchesQuery from $_collections');
    }
  }

  @override
  void visitBlock(Block node) {
    final statements = node.statements;
    for (var i = 0; i + 1 < statements.length; i++) {
      final statement = statements[i];
      if (statements[i + 1] is! ReturnStatement || !_closesDialog(statement)) continue;
      if (!_inScope(node)) return;
      _report(statement, 'a dialog closed before a return by hand', 'closeDialogThen / closeOnSuccess of BaseCubit');
    }
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (node.value != '/api/uploads' || !_inScope(node)) return;
    _report(node, 'the upload request built by hand', 'NeoApiImageUpload.uploadImageUrl');
  }

  static bool _isIdentifier(Expression expression, String name) =>
      expression is SimpleIdentifier && expression.name == name;

  /// `<parameter>.id <op> ...` or `... <op> <parameter>.id`.
  static bool _comparesId(Expression expression, String parameter, TokenType op) {
    if (expression is! BinaryExpression || expression.operator.type != op) return false;
    bool isId(Expression side) => switch (side) {
          PrefixedIdentifier() => side.prefix.name == parameter && side.identifier.name == 'id',
          PropertyAccess(target: final SimpleIdentifier target) =>
            target.name == parameter && side.propertyName.name == 'id',
          _ => false,
        };
    return isId(expression.leftOperand) || isId(expression.rightOperand);
  }

  static bool _closesDialog(Statement statement) {
    if (statement is! ExpressionStatement) return false;
    final expression = statement.expression;
    if (expression is! MethodInvocation || expression.methodName.name != 'emitPresentation') return false;
    final argument = expression.argumentList.arguments.firstOrNull;
    return switch (argument) {
      InstanceCreationExpression() => argument.constructorName.type.name.lexeme == 'CloseDialog',
      MethodInvocation() => argument.methodName.name == 'CloseDialog',
      _ => false,
    };
  }

  static bool _callsContains(AstNode node) {
    final finder = _ContainsFinder();
    node.accept(finder);
    return finder.found;
  }
}

class _ContainsFinder extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'contains') found = true;
    super.visitMethodInvocation(node);
  }
}
