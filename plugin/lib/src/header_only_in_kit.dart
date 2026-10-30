import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';
import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// Every page / sheet / dialog header is drawn by ONE kit widget.
///
/// A header is a back arrow or a close cross on the left, a centred title and
/// an optional action on the right. An app that has such a kit widget names
/// it in `neon_check.yaml`, with what makes a hand-built one:
///
/// ```yaml
/// header:
///   use: AppHeader
///   owners: [lib/global_widgets/components/app_header/app_header.dart]
///   buttons: [AppIconButton]
///   icons: [AppIcons.arrowLeft, AppIcons.x]
/// ```
///
/// A construction of a `buttons` class (by its resolved class name, `const`
/// or not) is reported when one of its arguments, named or positional, is an
/// `icons` value written `<Type>.<member>` (an import prefix does not hide
/// it), also as a branch of a conditional or inside parentheses. The
/// `owners` (root-relative files, or folders ending with `/`) are the header
/// itself and may build it. Without a `header:` section the rule checks
/// nothing (neoncode, vernakapp).
class HeaderOnlyInKit extends AnalysisRule {
  HeaderOnlyInKit() : super(name: 'header_only_in_kit', description: _desc);

  static const _desc = 'Every page / sheet / dialog header is the one kit header widget; no hand-built back / close '
      'button outside it.';

  static const LintCode code = LintCode(
    'header_only_in_kit',
    '[NEON] A back / close button ({0}) is built outside the kit header; every header is {1}.',
    correctionMessage:
        'Use {1} (leading back / close, centred title, optional trailing action) instead of a hand-built header row.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final layout = RuleLayout.of(context);
    final header = layout.header;
    if (header == null) return;
    registry.addInstanceCreationExpression(this, _Visitor(this, layout, header));
  }

  /// The icon [expression] names when it is one of [icons] (`AppIcons.x`,
  /// `prefix.AppIcons.x`), looking into both branches of a conditional and
  /// through parentheses; `null` otherwise.
  static String? matchingIcon(Expression expression, Set<({String type, String member})> icons) {
    switch (expression) {
      case NamedExpression(:final expression):
      case ParenthesizedExpression(:final expression):
        return matchingIcon(expression, icons);
      case ConditionalExpression(:final thenExpression, :final elseExpression):
        return matchingIcon(thenExpression, icons) ?? matchingIcon(elseExpression, icons);
      case PrefixedIdentifier(:final prefix, :final identifier):
        return _match(icons, identifier, prefix.element is PrefixElement ? null : prefix.name);
      case PropertyAccess(:final target?, :final propertyName):
        final written = switch (target) {
          PrefixedIdentifier(:final identifier) => identifier.name,
          SimpleIdentifier(:final name) => name,
          _ => null,
        };
        return _match(icons, propertyName, written);
      default:
        return null;
    }
  }

  /// `<type>.<member>` when [member] (with the [written] type name, used only
  /// when [member] is unresolved) is one of [icons].
  static String? _match(Set<({String type, String member})> icons, SimpleIdentifier member, String? written) {
    final element = member.element;
    final String? type;
    if (element == null) {
      type = written;
    } else {
      final owner = element.enclosingElement;
      type = owner is InterfaceElement ? owner.name : null;
    }
    if (type == null) return null;
    final icon = (type: type, member: member.name);
    return icons.contains(icon) ? '$type.${member.name}' : null;
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.layout, this.header);

  final AnalysisRule rule;

  final RuleLayout layout;

  final HeaderConfig header;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type;
    final name = type.element?.name ?? type.name.lexeme;
    if (!header.buttons.contains(name)) return;
    final path = unitPath(node);
    final relative = layout.relative(path);
    if (relative == null || !layout.isAppSource(path) || header.isOwner(relative)) return;
    for (final argument in node.argumentList.arguments) {
      final icon = HeaderOnlyInKit.matchingIcon(argument, header.icons);
      if (icon != null) {
        rule.reportAtNode(node.constructorName, arguments: ['$name($icon)', header.use]);
        return;
      }
    }
  }
}
