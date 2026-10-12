/// One failure a step reports: `file:line rule: message`.
final class Finding {
  const Finding({required this.rule, required this.file, required this.message, this.line = 1, this.hard = false});

  /// Lower-case rule id: an analyzer code (`use_kit_widgets`, `unused_import`)
  /// or a check id (`translation_dash`).
  final String rule;

  /// Path relative to the app root, always with `/`.
  final String file;

  final int line;

  /// What to do about it.
  final String message;

  /// A hard finding is never baselined (compile errors, a crashed tool).
  final bool hard;

  String format() => '$file:$line $rule: $message';
}
