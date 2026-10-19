import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/finding.dart';

/// One check of the runner. Steps run in a fixed order and the run stops at
/// the first step that fails.
abstract class CheckStep {
  const CheckStep();

  /// Id used by `--step`.
  String get name;

  /// One line, for `--list`.
  String get description;

  /// The rules this step reports. `null` means the analyzer, which owns every
  /// rule no other step owns.
  Set<String>? get rules;

  /// Whether the step changes files (format, fix, ordering, generators).
  /// Auto-fix steps never feed the baseline.
  bool get autoFix => false;

  /// Whether the step has anything to look at in this run.
  bool appliesTo(CheckContext context) => true;

  Future<StepResult> run(CheckContext context);
}

final class StepResult {
  const StepResult({this.findings = const [], this.fixed = const [], this.notes = const [], this.findingsScope});

  final List<Finding> findings;

  /// One-line notices for the person or model reading the run (printed before
  /// the result line), e.g. flows left running in the background.
  final List<String> notes;

  /// Files an auto-fix step changed.
  final List<String> fixed;

  /// Files whose baseline entries this run may check and lower; `null` means
  /// the context's scope.
  final bool Function(String file)? findingsScope;
}
