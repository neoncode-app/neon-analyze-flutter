import 'dart:convert';
import 'dart:io';

import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/finding.dart';
import 'package:neon_check/src/step.dart';

/// One language file: its flattened keys (nested maps joined with `.`), in
/// file order, with values and line numbers.
final class TranslationFile {
  TranslationFile._(this.language, this.path, this.json, this.values, this.lines);

  factory TranslationFile.load(CheckContext context, String language) {
    final path = '${context.config.translationsDir}/$language.json';
    final source = File(context.absolute(path)).readAsStringSync();
    final json = jsonDecode(source) as Map<String, dynamic>;
    final values = <String, String>{};
    void flatten(Map<String, dynamic> map, String prefix) {
      for (final entry in map.entries) {
        final key = '$prefix${entry.key}';
        final value = entry.value;
        if (value is Map<String, dynamic>) {
          flatten(value, '$key.');
        } else {
          values[key] = '$value';
        }
      }
    }

    flatten(json, '');
    return TranslationFile._(language, path, json, values, _keyLines(source));
  }

  final String language;

  /// Root-relative path.
  final String path;

  final Map<String, dynamic> json;

  /// Flattened key -> value, in file order.
  final Map<String, String> values;

  final Map<String, int> lines;

  int lineOf(String key) => lines[key] ?? 1;

  /// Line of every flattened key in a pretty-printed JSON file.
  static Map<String, int> _keyLines(String source) {
    final keyLine = RegExp(r'^\s*"((?:[^"\\]|\\.)*)"\s*:\s*(\{)?');
    final closing = RegExp(r'^\s*\},?\s*$');
    final stack = <String>[];
    final lines = <String, int>{};
    final all = source.split('\n');
    for (var i = 0; i < all.length; i++) {
      final match = keyLine.firstMatch(all[i]);
      if (match != null) {
        final key = [...stack, jsonDecode('"${match.group(1)}"') as String].join('.');
        lines[key] = i + 1;
        if (match.group(2) != null && !all[i].trimRight().endsWith('}') && !all[i].trimRight().endsWith('},')) {
          stack.add(key.split('.').last);
        }
      } else if (closing.hasMatch(all[i]) && stack.isNotEmpty) {
        stack.removeLast();
      }
    }
    return lines;
  }
}

List<TranslationFile> _load(CheckContext context) => [
      for (final language in context.config.languages) TranslationFile.load(context, language),
    ];

bool _touchesTranslations(CheckContext context) => context.touches([context.config.translationsDir]);

/// Every language file has the same keys.
final class TranslationParityStep extends CheckStep {
  const TranslationParityStep();

  @override
  String get name => 'translations_parity';

  @override
  String get description => 'same keys in every language file';

  @override
  Set<String> get rules => const {'translation_parity'};

  @override
  bool appliesTo(CheckContext context) => context.config.languages.isNotEmpty && _touchesTranslations(context);

  @override
  Future<StepResult> run(CheckContext context) async {
    final files = _load(context);
    final all = {for (final file in files) ...file.values.keys};
    final findings = <Finding>[
      for (final file in files)
        for (final key in all)
          if (!file.values.containsKey(key))
            Finding(
              rule: 'translation_parity',
              file: file.path,
              message:
                  'key `$key` is missing; add it here (it exists in ${files.where((other) => other.values.containsKey(key)).map((other) => other.language).join(', ')})',
            ),
    ];
    return StepResult(findings: findings, findingsScope: (file) => file.startsWith(context.config.translationsDir));
  }
}

/// No em dash, en dash, minus sign or `--` in translated texts.
final class TranslationDashesStep extends CheckStep {
  const TranslationDashesStep();

  @override
  String get name => 'translations_dashes';

  @override
  String get description => 'no — – − or -- in translation values';

  @override
  Set<String> get rules => const {'translation_dash'};

  @override
  bool appliesTo(CheckContext context) => context.config.languages.isNotEmpty && _touchesTranslations(context);

  static final _dash = RegExp('[\u2014\u2013\u2212]|--');

  @override
  Future<StepResult> run(CheckContext context) async {
    final findings = <Finding>[
      for (final file in _load(context))
        for (final entry in file.values.entries)
          if (_dash.hasMatch(entry.value))
            Finding(
              rule: 'translation_dash',
              file: file.path,
              line: file.lineOf(entry.key),
              message:
                  '`${entry.key}` contains `${_dash.firstMatch(entry.value)?.group(0)}`; use a comma, a full stop, '
                  '"od X do Y" or the common_date_range key instead',
            ),
    ];
    return StepResult(findings: findings, findingsScope: (file) => file.startsWith(context.config.translationsDir));
  }
}

/// How code refers to translation keys.
final class KeyUsage {
  KeyUsage._(this.literalKeys, this.dynamicPatterns, this.allStrings);

  /// Scans [files] (root-relative Dart files).
  factory KeyUsage.scan(CheckContext context, Iterable<String> files) {
    final literal = <(String, String, int)>[];
    final patterns = <RegExp>[];
    final strings = <String>{};
    for (final file in files) {
      final lines = File(context.absolute(file)).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // Doc and line comments show example keys, not real ones.
        if (line.trimLeft().startsWith('//')) continue;
        for (final match in _trCall.allMatches(line)) {
          final key = match.group(2) ?? match.group(3) ?? '';
          if (key.contains(r'$')) {
            final pattern = _patternOf(key);
            if (pattern != null) patterns.add(pattern);
          } else {
            literal.add((key, file, i + 1));
          }
        }
        for (final match in _anyString.allMatches(line)) {
          final value = match.group(1) ?? match.group(2) ?? '';
          if (value.contains(r'$')) {
            // A key assembled in a string and passed to tr() later.
            final pattern = _patternOf(value);
            if (pattern != null) patterns.add(pattern);
          } else {
            strings.add(value);
          }
        }
      }
    }
    return KeyUsage._(literal, patterns, strings);
  }

  /// `tr('key')`, `'key'.tr()`, `plural('key', ...)`.
  static final _trCall = RegExp(
    r"""(?:\b(?:tr|plural)\(\s*(['"])((?:(?!\1).)*)\1|'([^']*)'\.(?:tr|plural)\()""",
  );

  static final _anyString = RegExp(r"'([^'\\]*)'" '|' r'"([^"\\]*)"');

  /// `vernak_help_${name}_title` -> `^vernak_help_.+_title$`; `null` when the
  /// fixed text is too short to tell keys apart (`'$_value'` would match all).
  static RegExp? _patternOf(String template) {
    final parts = template.split(RegExp(r'\$\{[^}]*\}|\$\w+'));
    final fixedText = parts.join();
    if (fixedText.length < 4 || !RegExp('[a-z]').hasMatch(fixedText)) return null;
    return RegExp('^${parts.map(RegExp.escape).join('.+')}\$');
  }

  /// `(key, file, line)` of every literal key passed to tr().
  final List<(String, String, int)> literalKeys;

  /// Keys built at runtime, as patterns.
  final List<RegExp> dynamicPatterns;

  /// Every plain string literal (a key may be stored in a constant first).
  final Set<String> allStrings;

  late final Set<String> _literal = {for (final (key, _, _) in literalKeys) key};

  bool uses(String key) =>
      _literal.contains(key) || allStrings.contains(key) || dynamicPatterns.any((pattern) => pattern.hasMatch(key));
}

/// Every literal key passed to `tr()` exists.
final class TranslationMissingStep extends CheckStep {
  const TranslationMissingStep();

  @override
  String get name => 'translations_missing';

  @override
  String get description => "every tr('key') exists in the translations";

  @override
  Set<String> get rules => const {'translation_missing'};

  @override
  bool appliesTo(CheckContext context) =>
      context.config.languages.isNotEmpty && context.dartFiles.any((file) => file.startsWith('lib/'));

  @override
  Future<StepResult> run(CheckContext context) async {
    final primary = TranslationFile.load(context, context.config.primaryLanguage);
    final usage = KeyUsage.scan(context, context.dartFiles.where((file) => file.startsWith('lib/')));
    final findings = <Finding>[
      for (final (key, file, line) in usage.literalKeys)
        if (!primary.values.containsKey(key))
          Finding(
            rule: 'translation_missing',
            file: file,
            line: line,
            message: 'translation key `$key` does not exist; add it to ${context.config.languages.join(', ')}',
          ),
    ];
    return StepResult(findings: findings);
  }
}

/// Keys no code uses. Reported, and deleted from every language file
/// only with `--prune-translations` (a key used in a way the scan cannot see
/// would otherwise disappear silently).
final class TranslationUnusedStep extends CheckStep {
  const TranslationUnusedStep({this.prune = false});

  final bool prune;

  @override
  String get name => 'translations_unused';

  @override
  String get description => 'translation keys no code uses (--prune-translations deletes them)';

  @override
  Set<String> get rules => const {'translation_unused'};

  @override
  bool appliesTo(CheckContext context) => context.config.languages.isNotEmpty && context.isAll;

  @override
  Future<StepResult> run(CheckContext context) async {
    final files = _load(context);
    final primary = files.firstWhere((file) => file.language == context.config.primaryLanguage);
    final usage = KeyUsage.scan(context, context.allLibDartFiles);
    final allowed = context.config.translationsAllowedUnused;
    bool isAllowed(String key) => allowed.any(
          (entry) => entry.endsWith('*') ? key.startsWith(entry.substring(0, entry.length - 1)) : key == entry,
        );
    final unused = [
      for (final key in primary.values.keys)
        if (!usage.uses(key) && !isAllowed(key)) key,
    ];
    if (prune && context.fix && unused.isNotEmpty) {
      for (final file in files) {
        for (final key in unused) {
          _remove(file.json, key.split('.'));
        }
        _write(context, file.path, file.json);
      }
      return StepResult(fixed: [for (final file in files) file.path]);
    }
    final findings = <Finding>[
      for (final key in unused)
        Finding(
          rule: 'translation_unused',
          file: primary.path,
          line: primary.lineOf(key),
          message: '`$key` is not used by any code; delete it from every language file (--prune-translations)',
        ),
    ];
    return StepResult(findings: findings);
  }

  static void _remove(Map<String, dynamic> json, List<String> path) {
    if (path.length == 1) {
      json.remove(path.first);
      return;
    }
    final child = json[path.first];
    if (child is Map<String, dynamic>) _remove(child, path.sublist(1));
  }
}

/// Every language file lists its keys in the primary file's order.
/// Auto-fix: reorders the other files.
final class TranslationOrderStep extends CheckStep {
  const TranslationOrderStep();

  @override
  bool get autoFix => true;

  @override
  String get name => 'translations_order';

  @override
  String get description => 'keys in the same order in every language file (auto-fix)';

  @override
  Set<String> get rules => const {'translation_order'};

  @override
  bool appliesTo(CheckContext context) => context.config.languages.length > 1 && _touchesTranslations(context);

  @override
  Future<StepResult> run(CheckContext context) async {
    final files = _load(context);
    final primary = files.firstWhere((file) => file.language == context.config.primaryLanguage);
    final findings = <Finding>[];
    final fixed = <String>[];
    for (final file in files) {
      if (file == primary) continue;
      final ordered = _orderLike(file.json, primary.json);
      if (jsonEncode(ordered) == jsonEncode(file.json)) continue;
      if (context.fix) {
        _write(context, file.path, ordered);
        fixed.add(file.path);
      } else {
        findings.add(
          Finding(
            rule: 'translation_order',
            file: file.path,
            message: 'keys are not in the order of ${primary.path}; run neon-analyze-flutter/bin/neon-check locally',
          ),
        );
      }
    }
    return StepResult(findings: findings, fixed: fixed);
  }

  /// [map] with keys in [template]'s order; keys the template lacks go last.
  static Map<String, dynamic> _orderLike(Map<String, dynamic> map, Map<String, dynamic> template) {
    final result = <String, dynamic>{};
    for (final key in [
      ...template.keys.where(map.containsKey),
      ...map.keys.where((key) => !template.containsKey(key))
    ]) {
      final value = map[key];
      final templateValue = template[key];
      result[key] = value is Map<String, dynamic> && templateValue is Map<String, dynamic>
          ? _orderLike(value, templateValue)
          : value;
    }
    return result;
  }
}

void _write(CheckContext context, String path, Map<String, dynamic> json) {
  File(context.absolute(path)).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(json)}\n');
}
