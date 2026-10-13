import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/rule_layout.dart';

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

  static const _desc = 'Do not hardcode asset path strings; use AppAssets tokens.';

  static const LintCode _code = LintCode(
    'no_raw_asset_path',
    "[NEON] do not hardcode 'assets/...' path strings; use AppAssets tokens.",
    correctionMessage: 'Reference this asset via a constant in AppAssets.',
    severity: DiagnosticSeverity.WARNING,
  );

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
    final layout = RuleLayout.of(context);
    final path = context.definingUnit.file.path;
    // App code only: tests and tools read files (fixtures, translations)
    // through dart:io; they reference no bundled asset. The registry (layout
    // role `assets_registry`) is where the paths are declared.
    if (!layout.isAppSource(path) || layout.isIn(path, LayoutRole.assetsRegistry)) return;
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
