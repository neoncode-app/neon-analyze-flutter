import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// Only the widget kit (layout role `global_widgets`) takes its texts as
/// `String` parameters or `*Labels` objects; it is translation-agnostic.
/// Features and pages call `tr('key')` where they draw the text, define no
/// `*Labels` class and receive no translated texts from their host. When a
/// feature's wording differs per administration, it picks the key from
/// `FlavorConfig`, not from a parameter (NCC0000059).
///
/// Matches:
///
/// * a class whose name ends in `Labels` declared in a page or a feature
///   (layout roles `pages`, `features`);
/// * a field or a plain constructor parameter whose type is a class named
///   `*Labels` on a class with `{@category Feature}`, or on a widget (a
///   Flutter `Widget` subclass) in a page. A field formal (`this.labels`) is
///   reported once, at its field; a super formal at the class declaring the
///   field.
class LabelsOnlyInKit extends AnalysisRule {
  LabelsOnlyInKit() : super(name: 'labels_only_in_kit', description: _desc);

  static const _desc = 'Only the widget kit takes *Labels objects; features and pages call tr() where they draw.';

  static const LintCode code = LintCode(
    'labels_only_in_kit',
    '[NEON] {0}; features and pages call tr() where they draw; per-flavour wording comes from FlavorConfig.',
    correctionMessage: 'Call tr(\'key\') where the text is drawn and drop the *Labels class or parameter; '
        'when the wording differs per administration, pick the key from FlavorConfig.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final layout = RuleLayout.of(context);
    final path = context.definingUnit.file.path;
    if (!layout.isAppSource(path)) return;
    if (!layout.isIn(path, LayoutRole.pages) && !layout.isIn(path, LayoutRole.features)) return;
    registry.addClassDeclaration(this, _Visitor(this, inPages: layout.isIn(path, LayoutRole.pages)));
  }
}

bool _isLabelsName(String? name) => name != null && name.endsWith('Labels') && name != 'Labels';

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, {required this.inPages});

  final AnalysisRule rule;

  final bool inPages;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final nameToken = node.namePart.typeName;
    final name = nameToken.lexeme;
    if (_isLabelsName(name)) {
      rule.reportAtToken(nameToken, arguments: ['`$name` is a *Labels class outside the widget kit']);
      return;
    }
    final element = node.declaredFragment?.element;
    if (element == null) return;
    final isFeature = categoryOf(element) == 'Feature';
    final isPageWidget = inPages && isSubtypeOf(element.thisType, 'Widget', package: 'flutter');
    if (!isFeature && !isPageWidget) return;
    final owner = isFeature ? 'the Feature `$name`' : 'the page widget `$name`';
    final body = node.body;
    if (body is! BlockClassBody) return;
    for (final member in body.members) {
      if (member is FieldDeclaration && !member.isStatic) {
        final type = member.fields.type;
        if (type is NamedType && _isLabelsName(type.element?.name)) {
          rule.reportAtNode(type, arguments: ['$owner takes a `${type.element?.name}`']);
        }
      } else if (member is ConstructorDeclaration) {
        for (final parameter in member.parameters.parameters) {
          final plain = parameter is DefaultFormalParameter ? parameter.parameter : parameter;
          if (plain is! SimpleFormalParameter) continue;
          final type = plain.type;
          if (type is NamedType && _isLabelsName(type.element?.name)) {
            rule.reportAtNode(type, arguments: ['$owner takes a `${type.element?.name}`']);
          }
        }
      }
    }
  }
}

