import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/finding.dart';
import 'package:neon_check/src/step.dart';

/// No null-assertion operator `!` in generated code (NCI0000028).
///
/// The shared `analysis_options.yaml` excludes `*.g.dart` from `dart analyze`,
/// so the `analyze` step never sees `avoid_bang` there, while the IDE reports
/// it in every generated file it opens. This step closes that gap: it parses
/// every generated file of the source dirs and reports each `!`, regardless of
/// what changed, with no baseline. The usual source is json_serializable's
/// encoding of a non-nullable enum (`_$XEnumMap[instance.x]!`); an enum that
/// encodes itself (`toJson()`) is written as `instance.x.toJson()` instead.
final class GeneratedBangStep extends CheckStep {
  const GeneratedBangStep();

  @override
  String get name => 'generated_bang';

  @override
  String get description => 'no `!` in generated code (*.g.dart, *.freezed.dart, *.gen.dart)';

  @override
  Set<String> get rules => const {'generated_bang'};

  static const _suffixes = ['.g.dart', '.freezed.dart', '.gen.dart'];

  /// A cheap prefilter: an identifier, `)` or `]` followed by `!` that is no `!=`.
  static final _maybeBang = RegExp(r'[\w)\]]!(?!=)');

  static const _message = r'`!` in generated code. json_serializable writes `_$XEnumMap[value]!` for a '
      'non-nullable enum: give the enum its wire value and let it encode itself (`final String json;`, '
      "`@JsonEnum(valueField: 'json')`, `String toJson() => json;`), then run build_runner";

  @override
  Future<StepResult> run(CheckContext context) async {
    final findings = <Finding>[];
    for (final dir in context.config.sourceDirs) {
      final directory = Directory(context.absolute(dir));
      if (!directory.existsSync()) continue;
      for (final entity in directory.listSync(recursive: true)) {
        if (entity is! File || !_suffixes.any(entity.path.endsWith)) continue;
        final file = context.relative(entity.path);
        for (final line in bangLines(entity.readAsStringSync())) {
          findings.add(Finding(rule: 'generated_bang', file: file, line: line, message: _message));
        }
      }
    }
    return StepResult(findings: findings, findingsScope: (_) => true);
  }

  /// The 1-based lines of every `!` operator in [source].
  static List<int> bangLines(String source) {
    if (!_maybeBang.hasMatch(source)) return const [];
    final result = parseString(content: source, throwIfDiagnostics: false);
    final visitor = _BangVisitor();
    result.unit.accept(visitor);
    return [for (final offset in visitor.offsets) result.lineInfo.getLocation(offset).lineNumber];
  }
}

class _BangVisitor extends RecursiveAstVisitor<void> {
  final offsets = <int>[];

  @override
  void visitPostfixExpression(PostfixExpression node) {
    if (node.operator.lexeme == '!') offsets.add(node.operator.offset);
    super.visitPostfixExpression(node);
  }
}
