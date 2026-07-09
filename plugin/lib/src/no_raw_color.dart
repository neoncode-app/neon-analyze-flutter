import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
// LintCode is not in the public API surface yet.
import 'package:analyzer/src/dart/error/lint_codes.dart';

/// Forbids raw colors in widget code: `Color(0x...)` literals and
/// `Colors.<named>` references. Colors must be resolved through the theme
/// (e.g. `context.appColors`, `context.defaultColors`).
///
/// Allowed:
///  * theme token files themselves (where the palette is defined),
///  * the semantic constants `Colors.white`, `Colors.black`,
///    `Colors.transparent` (and their `black87`/`white70`-style variants).
class NoRawColor extends AnalysisRule {
  NoRawColor() : super(name: 'no_raw_color', description: _desc);

  static const _desc =
      'Do not use raw colors; resolve them through the theme.';

  static const LintCode _code = LintCode(
    'no_raw_color',
    '[NEON] do not use raw colors; resolve them through the theme '
        '(context.appColors / context.defaultColors).',
    correctionMessage:
        'Replace this raw color with a theme token from AppColors.',
    severity: DiagnosticSeverity.WARNING,
  );

  // Files that legitimately define raw color values (the token source).
  static const _allowedSuffixes = <String>[
    '/theme/app_colors.dart',
    '/theme/app_shadows.dart',
    '/theme/app_text_styles.dart',
    '/ui/app_icon.dart',
  ];

  // Semantic named colors that carry meaning beyond the palette.
  static const _allowedNamed = <String>{
    'white',
    'white70',
    'white60',
    'white54',
    'white38',
    'white30',
    'white24',
    'white12',
    'white10',
    'black',
    'black87',
    'black54',
    'black45',
    'black38',
    'black26',
    'black12',
    'transparent',
  };

  @override
  DiagnosticCode get diagnosticCode => _code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final path = context.definingUnit.file.path;
    if (_allowedSuffixes.any(path.endsWith)) return;
    final visitor = _Visitor(this);
    registry.addInstanceCreationExpression(this, visitor);
    registry.addPrefixedIdentifier(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final typeName = node.constructorName.type.name.lexeme;
    if (typeName == 'Color') {
      rule.reportAtNode(node);
    }
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    // Matches `Colors.grey`, `Colors.red`, etc.
    if (node.prefix.name != 'Colors') return;
    if (NoRawColor._allowedNamed.contains(node.identifier.name)) return;
    rule.reportAtNode(node);
  }
}
