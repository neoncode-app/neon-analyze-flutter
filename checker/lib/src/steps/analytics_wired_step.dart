import 'dart:io';

import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/finding.dart';
import 'package:neon_check/src/step.dart';
import 'package:yaml/yaml.dart';

/// The app is wired to `neon_flutter_analytics` (NCR0000050): `pubspec.yaml`
/// depends on it (`dependencies:`, not `dev_dependencies:`) and code under
/// `lib/` initialises it, attaches the router and wraps the app in the scope.
/// A commented-out call does not count.
///
/// Each missing piece is one `analytics_wired` finding (no baseline: an app
/// with the pack starts at zero). The step reads the whole of `lib/` whatever
/// the run's scope.
final class AnalyticsWiredStep extends CheckStep {
  const AnalyticsWiredStep();

  static const package = 'neon_flutter_analytics';

  static const readme = 'https://github.com/neoncode-app/neon-flutter-analytics#wiring-an-app';

  /// What code under `lib/` must contain: the text named in the message, and
  /// the pattern that finds it (`AnalyticsScope(` must not match
  /// `MyAnalyticsScope(`).
  static final calls = <String, RegExp>{
    'NeonAnalytics.init(': RegExp(r'\bNeonAnalytics\.init\('),
    'NeonAnalytics.attachRouter(': RegExp(r'\bNeonAnalytics\.attachRouter\('),
    'AnalyticsScope(': RegExp(r'\bAnalyticsScope\('),
  };

  @override
  String get name => 'analytics_wired';

  @override
  String get description => 'the app depends on $package, initialises it, attaches the router and has the scope';

  @override
  Set<String> get rules => const {'analytics_wired'};

  @override
  bool appliesTo(CheckContext context) => context.touches(const ['lib/', 'pubspec.yaml']);

  /// Whether the pubspec [source] lists [package] under `dependencies:`.
  static bool dependsOnPackage(String source) {
    Object? yaml;
    try {
      yaml = loadYaml(source);
    } on YamlException {
      return false;
    }
    final dependencies = yaml is YamlMap ? yaml['dependencies'] : null;
    return dependencies is YamlMap && dependencies.containsKey(package);
  }

  /// [source] without comment lines and trailing comments.
  static String withoutComments(String source) => [
        for (final line in source.split('\n'))
          if (!line.trimLeft().startsWith('//')) line.split(' // ').first,
      ].join('\n');

  /// The keys of [calls] that none of [sources] contains.
  static List<String> missingCalls(Iterable<String> sources) {
    final code = [for (final source in sources) withoutComments(source)];
    return [
      for (final MapEntry(key: call, value: pattern) in calls.entries)
        if (!code.any(pattern.hasMatch)) call,
    ];
  }

  @override
  Future<StepResult> run(CheckContext context) async {
    const file = 'pubspec.yaml';
    final pubspec = File(context.absolute(file));
    final sources = [
      for (final path in context.allLibDartFiles)
        if (!path.endsWith('.g.dart')) File(context.absolute(path)).readAsStringSync(),
    ];
    return StepResult(
      findings: [
        if (!pubspec.existsSync() || !dependsOnPackage(pubspec.readAsStringSync()))
          const Finding(
            rule: 'analytics_wired',
            file: file,
            message: '`$package` is not in dependencies; add it, see its README: $readme',
          ),
        for (final call in missingCalls(sources))
          Finding(
            rule: 'analytics_wired',
            file: 'lib',
            message: 'no `$call` under lib/; wire the app as the README of $package says: $readme',
          ),
      ],
      findingsScope: (_) => true,
    );
  }
}
