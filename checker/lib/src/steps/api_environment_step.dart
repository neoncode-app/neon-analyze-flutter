import 'dart:io';

import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/finding.dart';
import 'package:neon_check/src/step.dart';

/// The API environment is fixed by the build (NCC0000068, NCC0000076, rule doc
/// `api_environment`). The step reads the `ApiEnvironment` enum under `lib/`
/// (the file declaring `enum ApiEnvironment`) and checks that:
///
/// - it declares a `test` and a `prod` constant;
/// - the `prod` `baseUrl` and `webOrigin` contain no `test`;
/// - the `test` `baseUrl` contains `test`;
/// - the two `apiKey`s differ;
/// - it resolves the build's environment from the compile-time define
///   (`String.fromEnvironment('API_ENV')`, `api_environment.define`);
/// - no code under `lib/` declares a runtime switch: an environment switch,
///   picker, sheet, selector, toggle, override or switch policy
///   (`ApiEnvironmentSwitch`, `environmentSwitch`, `environmentOverride`,
///   `_ApiEnvironmentSheet`, `_pickApiEnvironment`);
/// - every build entry the app has (`api_environment.build_entries`: the build
///   script, f-build's `build.config`) passes the define, and at least one
///   exists.
///
/// Each failed check is one `api_environment` finding (no baseline: an app
/// with the pack starts at zero).
final class ApiEnvironmentStep extends CheckStep {
  const ApiEnvironmentStep();

  @override
  String get name => 'api_environment';

  @override
  String get description =>
      'ApiEnvironment maps test and prod the right way round, the build fixes it (API_ENV), nothing switches it';

  @override
  Set<String> get rules => const {'api_environment'};

  @override
  bool appliesTo(CheckContext context) => context.touches(['lib/', ...context.config.apiEnvironmentBuildEntries]);

  static final _enum = RegExp(r'enum\s+ApiEnvironment\s*\{');

  static final _constant = RegExp(r'(?:^|,)\s*(\w+)\s*\(([^;]*?)\)\s*(?=,|;)');

  static final _argument = RegExp(r'''(\w+)\s*:\s*['"]([^'"]*)['"]''');

  /// An identifier that names a runtime environment switch.
  static final _switch = RegExp(
    r'\b\w*(?:[Ee]nvironment(?:Switch|Picker|Sheet|Selector|Toggle|Chooser|Override|Policy)'
    r'|(?:pick|choose|select|switch)\w*Environment)\w*\b',
  );

  /// The string arguments of each constant of the `ApiEnvironment` enum in
  /// [source]: constant name -> argument name -> value.
  static Map<String, Map<String, String>> parseEnum(String source) {
    final start = _enum.firstMatch(source);
    if (start == null) return const {};
    final body = source.substring(start.end);
    final end = body.indexOf(';');
    final constants = end < 0 ? body : body.substring(0, end + 1);
    return {
      for (final match in _constant.allMatches(constants))
        match.group(1) ?? '': {
          for (final argument in _argument.allMatches(match.group(2) ?? ''))
            argument.group(1) ?? '': argument.group(2) ?? '',
        },
    };
  }

  /// The findings for the enum [values] (from [parseEnum]) declared in [file].
  static List<Finding> checkValues(String file, Map<String, Map<String, String>> values) {
    Finding finding(String message) => Finding(rule: 'api_environment', file: file, message: message);
    final test = values['test'];
    final prod = values['prod'];
    if (test == null || prod == null) {
      return [finding('ApiEnvironment declares no `test` and `prod` constant')];
    }
    return [
      for (final field in const ['baseUrl', 'webOrigin'])
        if ((prod[field] ?? '').toLowerCase().contains('test'))
          finding('the prod $field `${prod[field]}` points at a test backend'),
      if (!(test['baseUrl'] ?? '').toLowerCase().contains('test'))
        finding('the test baseUrl `${test['baseUrl'] ?? ''}` does not point at a test backend'),
      if (test['apiKey'] == null || test['apiKey'] == prod['apiKey'])
        finding('the test and prod apiKey must both be set and differ'),
    ];
  }

  /// Whether the enum [source] resolves the environment from the [define].
  static bool readsDefine(String source, String define) =>
      RegExp('String\\.fromEnvironment\\(\\s*[\'"]${RegExp.escape(define)}[\'"]').hasMatch(source);

  /// The runtime switches declared in [source] (comments skipped), as
  /// `(line, identifier)`.
  static List<(int, String)> switches(String source) {
    final lines = source.split('\n');
    return [
      for (var index = 0; index < lines.length; index++)
        if (!lines[index].trimLeft().startsWith('//'))
          for (final match in _switch.allMatches(lines[index].split(' // ').first)) (index + 1, match.group(0) ?? ''),
    ];
  }

  /// The findings for the build entries of [context]: each one that exists
  /// passes the [define], and at least one exists.
  static List<Finding> checkBuildEntries(CheckContext context, String define) {
    final entries = context.config.apiEnvironmentBuildEntries;
    if (entries.isEmpty) return const [];
    final existing = [
      for (final entry in entries)
        if (File(context.absolute(entry)).existsSync()) entry,
    ];
    if (existing.isEmpty) {
      return [
        Finding(
          rule: 'api_environment',
          file: entries.first,
          message: 'no build entry (${entries.join(', ')}) exists to pass $define; a release build must state its '
              'environment',
        ),
      ];
    }
    return [
      for (final entry in existing)
        if (!File(context.absolute(entry)).readAsStringSync().contains(define))
          Finding(
            rule: 'api_environment',
            file: entry,
            message: 'the build entry passes no $define (--dart-define=$define=test|prod; in f-build\'s build.config '
                'DART_DEFINES_${define}_test=test and DART_DEFINES_${define}_prod=prod)',
          ),
    ];
  }

  @override
  Future<StepResult> run(CheckContext context) async {
    final define = context.config.apiEnvironmentDefine;
    final findings = <Finding>[];
    String? enumFile;
    for (final file in context.allLibDartFiles) {
      if (file.endsWith('.g.dart')) continue;
      final source = File(context.absolute(file)).readAsStringSync();
      if (enumFile == null && _enum.hasMatch(source)) {
        enumFile = file;
        findings.addAll(checkValues(file, parseEnum(source)));
        if (!readsDefine(source, define)) {
          findings.add(Finding(
            rule: 'api_environment',
            file: file,
            message: "ApiEnvironment does not resolve the build's environment from "
                "String.fromEnvironment('$define') (the one decision point, `ApiEnvironment.current`)",
          ));
        }
      }
      for (final (line, identifier) in switches(source)) {
        findings.add(Finding(
          rule: 'api_environment',
          file: file,
          line: line,
          message: 'a runtime environment switch (`$identifier`); the build alone decides the environment '
              '($define), no switch, picker or override',
        ));
      }
    }
    if (enumFile == null) {
      findings.add(const Finding(
        rule: 'api_environment',
        file: 'lib',
        message: 'no `enum ApiEnvironment` under lib/; the environment values live on it',
      ));
    }
    findings.addAll(checkBuildEntries(context, define));
    return StepResult(findings: findings);
  }
}
