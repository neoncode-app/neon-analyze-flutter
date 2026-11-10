import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// A component without visible text reports under the name its caller gives
/// it (`neon_flutter_analytics`, NCR0000050).
///
/// The signal is the component itself: a resolved constructor that declares a
/// named parameter `trackId` or `leftTrackId` (a two-sided control), so the
/// rule needs no configuration and works in any app. A creation that passes
/// one of [callbacks] with anything but the literal `null` must name the
/// element: `trackId`, `trackLabel` (a site named by its label), or both
/// `leftTrackId` and `rightTrackId`, each with anything but the literal
/// `null`. The literal `tracked: false` is the other way out, for a component
/// that reports its own event. Code outside `lib/` and generated files are
/// skipped.
class PassTrackId extends AnalysisRule {
  PassTrackId() : super(name: 'pass_track_id', description: _desc);

  static const _desc = 'A component with a trackId parameter is told what the element is whenever it is given a '
      'callback.';

  static const LintCode code = LintCode(
    'pass_track_id',
    '[NEON] {0} is given `{1}` but nothing names this element for analytics.',
    correctionMessage: "Name the element: `trackId: 'home.search_open'` (`trackLabel:` where a label names it, "
        '`leftTrackId:` with `rightTrackId:` on a two-sided control), or pass `tracked: false` when the component '
        'reports its own event.',
    severity: DiagnosticSeverity.WARNING,
  );

  /// The arguments that make an element something a user interacts with.
  static const callbacks = {
    'onTap',
    'onDoubleTap',
    'onLongPress',
    'onChanged',
    'onToggle',
    'onPanEnd',
    'onHorizontalDragEnd',
    'onVerticalDragEnd',
  };

  /// The named parameters that make a constructor one the rule applies to.
  static const triggers = {'trackId', 'leftTrackId'};

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
    final constructor = node.constructorName.element;
    if (constructor == null) return;
    if (!constructor.formalParameters.any((formal) => formal.isNamed && PassTrackId.triggers.contains(formal.name))) {
      return;
    }
    if (!layout.isAppSource(unitPath(node))) return;
    final passed = {
      for (final argument in node.argumentList.arguments.whereType<NamedExpression>())
        argument.name.label.name: argument.expression.unParenthesized,
    };
    bool given(String name) => passed.containsKey(name) && passed[name] is! NullLiteral;
    if (given('trackId') || given('trackLabel') || (given('leftTrackId') && given('rightTrackId'))) return;
    if (passed['tracked'] case BooleanLiteral(value: false)) return;
    final callback = PassTrackId.callbacks.where(given).firstOrNull;
    if (callback == null) return;
    rule.reportAtNode(node.constructorName, arguments: [node.constructorName.type.name.lexeme, callback]);
  }
}
