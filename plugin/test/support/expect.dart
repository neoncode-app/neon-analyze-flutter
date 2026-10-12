import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
// ExpectedDiagnostic is not exported from the public library.
// ignore: implementation_imports
import 'package:analyzer_testing/src/analysis_rule/pub_package_resolution.dart';

/// Expected lints at each of [flagged] in [source] (after the first [after],
/// when given), found in order: each
/// text is searched for after the end of the previous one, so `Dialog` after
/// `AlertDialog` points at the second widget, not inside the first.
List<ExpectedDiagnostic> lintsAt(
  AnalysisRuleTest test,
  String source,
  List<String> flagged, {
  List<Pattern> messageContainsAll = const [],
  String? after,
}) {
  final expected = <ExpectedDiagnostic>[];
  var from = after == null ? 0 : source.indexOf(after);
  if (from < 0) throw ArgumentError('"$after" not found in:\n$source');
  for (final text in flagged) {
    final offset = source.indexOf(text, from);
    if (offset < 0) throw ArgumentError('"$text" not found after offset $from in:\n$source');
    expected.add(test.lint(offset, text.length, messageContainsAll: messageContainsAll));
    from = offset + text.length;
  }
  return expected;
}
