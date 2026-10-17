import 'dart:io';

import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/finding.dart';
import 'package:neon_check/src/step.dart';
import 'package:neon_lints/layout.dart';

/// Identical logic exists once (NCC0000064, rule doc `shared_functions`):
/// copies no specific lint pattern catches are found by token clone
/// detection across `lib/`.
///
/// Every app source file under `lib/` (generated files excluded) is
/// normalised line by line: comments, blank lines, directives (`import`,
/// `export`, `part`, `library`) and lines of brackets and punctuation only are
/// dropped, whitespace is collapsed. A run of [minLines] consecutive
/// normalised lines that occurs in two places (two files, or twice in one
/// file without overlapping) is a clone. Overlapping clone windows of a file
/// merge into one region, and every region is one `duplicates` finding at its
/// first line, naming one other place of the copy. The step always reads
/// every file, so every baseline entry of the rule is checked and lowered.
final class DuplicatesStep extends CheckStep {
  const DuplicatesStep();

  /// Normalised lines a copy needs before it counts.
  static const minLines = 12;

  @override
  String get name => 'duplicates';

  @override
  String get description => 'no copy of $minLines or more identical normalised lines across lib/';

  @override
  Set<String> get rules => const {'duplicates'};

  @override
  bool appliesTo(CheckContext context) => context.touches(const ['lib/']);

  static final _punctuationOnly = RegExp(r'^[\s()\[\]{},;:.=>?]*$');

  static final _directive = RegExp(r'^(import|export|part|part of|library)\b');

  static final _space = RegExp(r'\s+');

  /// The normalised lines of [source] with their 1-based line numbers.
  static List<({String text, int line})> normalise(String source) {
    final result = <({String text, int line})>[];
    var inBlock = false;
    final lines = source.split('\n');
    for (var i = 0; i < lines.length; i++) {
      var text = lines[i].trim();
      if (inBlock) {
        final end = text.indexOf('*/');
        if (end < 0) continue;
        inBlock = false;
        text = text.substring(end + 2).trim();
      }
      if (text.startsWith('/*')) {
        final end = text.indexOf('*/');
        if (end < 0) {
          inBlock = true;
          continue;
        }
        text = text.substring(end + 2).trim();
      }
      if (text.startsWith('//')) continue;
      if (text.isEmpty || _punctuationOnly.hasMatch(text) || _directive.hasMatch(text)) continue;
      result.add((text: text.replaceAll(_space, ' '), line: i + 1));
    }
    return result;
  }

  /// Clone regions of the [files] (root-relative path to source): per file,
  /// the first line of each region and one other place of the copy.
  static Map<String, List<({int line, int length, String other, int otherLine})>> findClones(
    Map<String, String> files, {
    int window = minLines,
  }) {
    final normalised = {for (final entry in files.entries) entry.key: normalise(entry.value)};
    final paths = normalised.keys.toList()..sort();
    final windows = <int, List<({String file, int start})>>{};
    for (final path in paths) {
      final lines = normalised[path] ?? const [];
      final hashes = [for (final line in lines) line.text.hashCode];
      for (var start = 0; start + window <= lines.length; start++) {
        final key = Object.hashAll(hashes.sublist(start, start + window));
        (windows[key] ??= []).add((file: path, start: start));
      }
    }
    bool same(({String file, int start}) a, ({String file, int start}) b) {
      final left = normalised[a.file] ?? const [];
      final right = normalised[b.file] ?? const [];
      for (var i = 0; i < window; i++) {
        if (left[a.start + i].text != right[b.start + i].text) return false;
      }
      return true;
    }

    // Per file: normalised index -> one other place of the copy starting there.
    final copied = <String, Map<int, ({String file, int start})>>{};
    for (final occurrences in windows.values) {
      if (occurrences.length < 2) continue;
      for (final occurrence in occurrences) {
        final other = occurrences.where((candidate) {
          if (candidate == occurrence) return false;
          if (candidate.file == occurrence.file && (candidate.start - occurrence.start).abs() < window) return false;
          return same(candidate, occurrence);
        }).firstOrNull;
        if (other == null) continue;
        (copied[occurrence.file] ??= {})[occurrence.start] = other;
      }
    }
    final result = <String, List<({int line, int length, String other, int otherLine})>>{};
    for (final path in copied.keys.toList()..sort()) {
      final lines = normalised[path] ?? const [];
      final starts = copied[path] ?? const {};
      final sorted = starts.keys.toList()..sort();
      var regionStart = -1;
      var regionEnd = -1;
      void close() {
        if (regionStart < 0) return;
        final other = starts[regionStart];
        if (other == null) return;
        final otherLines = normalised[other.file] ?? const [];
        (result[path] ??= []).add((
          line: lines[regionStart].line,
          length: regionEnd - regionStart,
          other: other.file,
          otherLine: otherLines[other.start].line,
        ));
      }

      for (final start in sorted) {
        if (start <= regionEnd) {
          regionEnd = start + window;
          continue;
        }
        close();
        regionStart = start;
        regionEnd = start + window;
      }
      close();
    }
    return result;
  }

  @override
  Future<StepResult> run(CheckContext context) async {
    final files = {
      for (final file in context.allLibDartFiles.where(Layout.isAppSource))
        file: File(context.absolute(file)).readAsStringSync(),
    };
    final clones = findClones(files);
    return StepResult(
      findings: [
        for (final MapEntry(key: file, value: regions) in clones.entries)
          for (final region in regions)
            Finding(
              rule: 'duplicates',
              file: file,
              line: region.line,
              message: '${region.length} normalised lines are a copy of ${region.other}:${region.otherLine}; '
                  'extract the shared code once (rule shared_functions)',
            ),
      ],
    );
  }
}
