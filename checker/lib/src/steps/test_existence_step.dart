import 'dart:io';

import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/finding.dart';
import 'package:neon_check/src/step.dart';

/// `adminPosts` -> `admin_posts`, `appVernak` -> `app_vernak`.
String toSnakeCase(String identifier) => identifier
    .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (match) => '${match.group(1)}_${match.group(2)}')
    .toLowerCase();

/// Step: every cubit and every route has a test (NCR0000022).
///
/// A cubit `<cubits dir>/**/<name>_cubit.dart` needs a `<name>_cubit_test.dart`
/// anywhere under the test folder; a `GoRoute(path: Routes.<id>.absolutePath)`
/// in a flavour router needs `<id_snake_case>_route_test.dart` in a `routes/`
/// folder of a suite. Findings are keyed by the cubit or router file and go
/// through the ratchet: today's gaps are baselined, a new cubit or route
/// without a test fails, and a test that appears lowers the baseline.
final class TestExistenceStep extends CheckStep {
  const TestExistenceStep();

  @override
  String get name => 'test_existence';

  @override
  String get description => 'every cubit has a cubit test and every router GoRoute has a route test';

  @override
  Set<String> get rules => const {'test_missing'};

  @override
  bool appliesTo(CheckContext context) {
    final config = context.config;
    if (!config.hasTestExistence) return false;
    return context.isAll || context.touches(['${config.cubitsDir}/', ...config.routeRouters, '${config.testDir}/']);
  }

  @override
  Future<StepResult> run(CheckContext context) async {
    final config = context.config;
    final testDir = Directory(context.absolute(config.testDir));
    final testFiles = testDir.existsSync()
        ? [
            for (final entity in testDir.listSync(recursive: true))
              if (entity is File && entity.path.endsWith('_test.dart')) context.relative(entity.path),
          ]
        : <String>[];
    final testBasenames = {for (final file in testFiles) file.split('/').last};
    final findings = <Finding>[];

    final cubitsDir = Directory(context.absolute(config.cubitsDir));
    if (cubitsDir.existsSync()) {
      final cubits = [
        for (final entity in cubitsDir.listSync(recursive: true))
          if (entity is File && entity.path.endsWith(config.cubitSuffix)) context.relative(entity.path),
      ]..sort();
      for (final cubit in cubits) {
        if (config.cubitExempt.contains(cubit)) continue;
        final expected = '${cubit.split('/').last.replaceAll('.dart', '')}_test.dart';
        if (testBasenames.contains(expected)) continue;
        findings.add(
          Finding(
            rule: 'test_missing',
            file: cubit,
            message: 'no cubit test: add ${config.testDir}/<suite>/bloc/$expected (every cubit has a test, NCR0000022)',
          ),
        );
      }
    }

    final routePattern = RegExp(r'path:\s*Routes\.(\w+)\.absolutePath');
    for (final router in config.routeRouters) {
      final file = File(context.absolute(router));
      if (!file.existsSync()) continue;
      final lines = file.readAsLinesSync();
      final seen = <String>{};
      for (var i = 0; i < lines.length; i++) {
        for (final match in routePattern.allMatches(lines[i])) {
          final id = match.group(1) ?? '';
          if (!seen.add(id)) continue;
          final expected = '${toSnakeCase(id)}_route_test.dart';
          final suffix = '/${config.routeTestsFolder}/$expected';
          if (testFiles.any((test) => test.endsWith(suffix))) continue;
          findings.add(
            Finding(
              rule: 'test_missing',
              file: router,
              line: i + 1,
              message:
                  'route Routes.$id has no test: add ${config.testDir}/<suite>/${config.routeTestsFolder}/$expected '
                  '(every route has a test, NCR0000022)',
            ),
          );
        }
      }
    }
    return StepResult(
      findings: findings,
      findingsScope: (file) => file.startsWith('${config.cubitsDir}/') || config.routeRouters.contains(file),
    );
  }
}
