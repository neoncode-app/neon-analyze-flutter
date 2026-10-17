import 'dart:io';

import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/finding.dart';
import 'package:neon_check/src/step.dart';

/// The API environment can never be swapped (NCC0000068, rule doc
/// `api_environment`). The step reads the `ApiEnvironment` enum under `lib/`
/// (the file declaring `enum ApiEnvironment`) and checks that:
///
/// - it declares a `test` and a `prod` constant;
/// - the `prod` `baseUrl` and `webOrigin` contain no `test`;
/// - the `test` `baseUrl` contains `test`;
/// - the two `apiKey`s differ;
/// - every flavour (`lib/flavors/<f>/<f>_flavor.dart`) declares its
///   `environmentSwitch` policy.
///
/// Each failed check is one `api_environment` finding (no baseline: an app
/// with the pack starts at zero).
final class ApiEnvironmentStep extends CheckStep {
  const ApiEnvironmentStep();

  @override
  String get name => 'api_environment';

  @override
  String get description =>
      'the ApiEnvironment enum maps test and prod the right way round, every flavour has a policy';

  @override
  Set<String> get rules => const {'api_environment'};

  @override
  bool appliesTo(CheckContext context) => context.touches(const ['lib/']);

  static final _enum = RegExp(r'enum\s+ApiEnvironment\s*\{');

  static final _constant = RegExp(r'(?:^|,)\s*(\w+)\s*\(([^;]*?)\)\s*(?=,|;)');

  static final _argument = RegExp(r'''(\w+)\s*:\s*['"]([^'"]*)['"]''');

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

  @override
  Future<StepResult> run(CheckContext context) async {
    final findings = <Finding>[];
    String? enumFile;
    for (final file in context.allLibDartFiles) {
      final source = File(context.absolute(file)).readAsStringSync();
      if (!_enum.hasMatch(source)) continue;
      enumFile = file;
      findings.addAll(checkValues(file, parseEnum(source)));
      break;
    }
    if (enumFile == null) {
      findings.add(const Finding(
        rule: 'api_environment',
        file: 'lib',
        message: 'no `enum ApiEnvironment` under lib/; the environment values live on it',
      ));
    }
    final flavors = Directory(context.absolute('lib/flavors'));
    if (flavors.existsSync()) {
      for (final dir in flavors.listSync().whereType<Directory>()) {
        final flavor = dir.path.split(Platform.pathSeparator).last;
        final file = 'lib/flavors/$flavor/${flavor}_flavor.dart';
        final config = File(context.absolute(file));
        if (!config.existsSync()) continue;
        if (config.readAsStringSync().contains('environmentSwitch')) continue;
        findings.add(Finding(
          rule: 'api_environment',
          file: file,
          message:
              'the flavour declares no `environmentSwitch` (ApiEnvironmentSwitchPolicy none / rootOnly / everyone)',
        ));
      }
    }
    return StepResult(findings: findings);
  }
}
