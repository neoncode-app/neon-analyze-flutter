import 'dart:convert';
import 'dart:io';

import 'package:neon_check/src/finding.dart';

/// Per-rule, per-file counts of tolerated findings (the ratchet).
///
/// A count may only go down. A finding above its count fails the check; when
/// a count drops, the baseline is lowered to it, so a fixed violation can
/// never come back.
final class Baseline {
  Baseline(this._counts);

  factory Baseline.load(String path) {
    final file = File(path);
    if (!file.existsSync()) return Baseline({});
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final rules = (json['rules'] as Map<String, dynamic>?) ?? const {};
    return Baseline({
      for (final rule in rules.entries)
        rule.key: {for (final file in (rule.value as Map<String, dynamic>).entries) file.key: file.value as int},
    });
  }

  final Map<String, Map<String, int>> _counts;

  bool _dirty = false;

  bool get isDirty => _dirty;

  int allowed(String rule, String file) => _counts[rule]?[file] ?? 0;

  Iterable<String> get rules => _counts.keys;

  /// Files that have a count for [rule].
  Iterable<String> filesOf(String rule) => _counts[rule]?.keys ?? const [];

  void set(String rule, String file, int count) {
    final current = allowed(rule, file);
    if (current == count) return;
    _dirty = true;
    if (count == 0) {
      _counts[rule]?.remove(file);
      if (_counts[rule]?.isEmpty ?? false) _counts.remove(rule);
    } else {
      (_counts[rule] ??= {})[file] = count;
    }
  }

  /// Replaces the whole baseline with the counts of [findings].
  void resetTo(Iterable<Finding> findings) {
    _counts.clear();
    for (final finding in findings) {
      if (finding.hard) continue;
      final files = _counts[finding.rule] ??= {};
      files[finding.file] = (files[finding.file] ?? 0) + 1;
    }
    _dirty = true;
  }

  void save(String path) {
    final sortedRules = _counts.keys.toList()..sort();
    final json = {
      '_comment': 'Ratchet baseline written by the check runner: tolerated findings per rule and file. '
          'Counts may only go down; do not raise them by hand.',
      'rules': {
        for (final rule in sortedRules)
          rule: {for (final file in (_counts[rule]?.keys.toList() ?? <String>[])..sort()) file: _counts[rule]?[file]},
      },
    };
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(json)}\n');
    _dirty = false;
  }
}

/// The outcome of comparing one step's findings with the baseline.
final class RatchetResult {
  const RatchetResult(this.failures, this.lowered);

  /// Findings that break the check, grouped notes included.
  final List<Finding> failures;

  /// `(rule, file, from, to)` counts that went down.
  final List<(String, String, int, int)> lowered;
}

/// Compares [findings] of one step with [baseline].
///
/// [owns] says which rules the step produces; [inScope] which files the step
/// looked at, so a baseline entry outside the scope is neither checked nor
/// lowered. Rules in [zero] tolerate nothing. Counts that drop are lowered in
/// [baseline] unless [lower] is false.
RatchetResult ratchet({
  required List<Finding> findings,
  required Baseline baseline,
  required bool Function(String rule) owns,
  required bool Function(String file) inScope,
  Set<String> zero = const {},
  bool lower = true,
}) {
  final failures = <Finding>[];
  final lowered = <(String, String, int, int)>[];
  final grouped = <(String, String), List<Finding>>{};
  for (final finding in findings) {
    if (finding.hard) {
      failures.add(finding);
      continue;
    }
    (grouped[(finding.rule, finding.file)] ??= []).add(finding);
  }
  for (final entry in grouped.entries) {
    final (rule, file) = entry.key;
    final allowed = zero.contains(rule) ? 0 : baseline.allowed(rule, file);
    final actual = entry.value.length;
    if (actual > allowed) {
      failures.addAll(
        allowed == 0
            ? entry.value
            : [
                for (final finding in entry.value)
                  Finding(
                    rule: finding.rule,
                    file: finding.file,
                    line: finding.line,
                    message: '${finding.message} ($actual in this file, baseline allows $allowed)',
                  ),
              ],
      );
    } else if (actual < allowed && lower) {
      lowered.add((rule, file, allowed, actual));
    }
  }
  // Baseline entries of this step whose findings disappeared entirely.
  if (lower) {
    for (final rule in baseline.rules.where(owns).toList()) {
      for (final file in baseline.filesOf(rule).toList()) {
        if (!inScope(file) || grouped.containsKey((rule, file))) continue;
        lowered.add((rule, file, baseline.allowed(rule, file), 0));
      }
    }
  }
  if (failures.isEmpty) {
    for (final (rule, file, _, to) in lowered) {
      baseline.set(rule, file, to);
    }
  }
  return RatchetResult(failures, failures.isEmpty ? lowered : const []);
}
