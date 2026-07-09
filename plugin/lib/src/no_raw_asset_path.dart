import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
// LintCode is not in the public API surface yet.
import 'package:analyzer/src/dart/error/lint_codes.dart';

/// Forbids raw asset path string literals (`'assets/...'`). Asset paths must be
/// referenced through the generated `AppAssets` tokens so a moved/renamed asset
/// is a single-point change.
///
/// Allowed:
///  * the `AppAssets` definition file itself (`app_assets.dart`),
///  * `assets/translations` (the easy_localization root, configured once in
///    main.dart).
class NoRawAssetPath extends AnalysisRule {
  NoRawAssetPath() : super(name: 'no_raw_asset_path', description: _desc);

  static const _desc =
      'Do not hardcode asset path strings; use AppAssets tokens.';

  static const LintCode _code = LintCode(
    'no_raw_asset_path',
    "[NEON] do not hardcode 'assets/...' path strings; use AppAssets tokens.",
    correctionMessage: 'Reference this asset via a constant in AppAssets.',
    severity: DiagnosticSeverity.WARNING,
  );

  static const _allowedSuffixes = <String>[
    '/app_assets.dart',
  ];

  // Configured-once roots that are not per-widget asset references.
  static const _allowedExact = <String>{
    'assets/translations',
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
    registry.addSimpleStringLiteral(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    final value = node.value;
    if (!value.startsWith('assets/')) return;
    if (NoRawAssetPath._allowedExact.contains(value)) return;
    rule.reportAtNode(node);
  }
}
