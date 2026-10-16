import 'dart:io';

import 'package:neon_check/src/context.dart';
import 'package:neon_check/src/finding.dart';
import 'package:neon_check/src/step.dart';
import 'package:neon_lints/layout.dart';

/// A feature serves several places (NCC0000060, rule doc `feature_placement`):
/// a feature that only one page uses is a part of that page.
///
/// A feature is the entry file of a piece in the layout role `features`
/// (`lib/features/<product>/<feature>/<feature>.dart`, the file named like
/// its folder) that declares a `{@category Feature}` class. Its users are the
/// files under `lib/` outside the feature's folder that import or export the
/// entry file directly (`package:<app>/...` or a relative URI). A user in the
/// layout role `pages` counts as its page: the folder down to the first
/// segment ending in `_page` (`lib/pages/vernak/vernak_cards_page/`); a file
/// of the pages role in no page folder (an app's shared `pages/<app>/widgets/`,
/// a label builder) and every file outside the pages role (a shell, a router,
/// another feature) count as other users.
///
/// A feature with exactly one page among its users and no other user is a
/// `feature_used_once` finding at its Feature class. The step always reads
/// every file, so every baseline entry of the rule is checked and lowered.
final class FeatureUsedOnceStep extends CheckStep {
  const FeatureUsedOnceStep();

  @override
  String get name => 'feature_used_once';

  @override
  String get description => 'a feature (lib/features/) is used by several pages, a shell or another feature';

  @override
  Set<String> get rules => const {'feature_used_once'};

  @override
  bool appliesTo(CheckContext context) => context.touches(const ['lib/']);

  static final _directive = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true);

  static final _featureClass = RegExp(r'\{@category\s+Feature\}[^\n]*\n(?:\s*(?:///[^\n]*|@\w[^\n]*)\n)*\s*'
      r'(?:(?:abstract|base|final|sealed|interface)\s+)*class\s+(\w+)');

  @override
  Future<StepResult> run(CheckContext context) async {
    final layout = context.config.layout;
    final package = context.config.projectName;
    final files = context.allLibDartFiles.where(Layout.isAppSource).toList();
    final features = <String, ({String folder, String className, int line})>{};
    for (final file in files) {
      if (!layout.matches(LayoutRole.features, file)) continue;
      final segments = file.split('/');
      if (segments.length < 2) continue;
      final stem = segments.last.substring(0, segments.last.length - '.dart'.length);
      if (segments[segments.length - 2] != stem) continue;
      final source = File(context.absolute(file)).readAsStringSync();
      final match = _featureClass.firstMatch(source);
      if (match == null) continue;
      final line = '\n'.allMatches(source.substring(0, match.end)).length + 1;
      features[file] = (
        folder: file.substring(0, file.lastIndexOf('/') + 1),
        className: match.group(1) ?? stem,
        line: line,
      );
    }
    if (features.isEmpty) return StepResult(findingsScope: (file) => layout.matches(LayoutRole.features, file));

    final pages = <String, Set<String>>{for (final file in features.keys) file: {}};
    final others = <String, Set<String>>{for (final file in features.keys) file: {}};
    for (final file in files) {
      final source = File(context.absolute(file)).readAsStringSync();
      for (final match in _directive.allMatches(source)) {
        final target = _resolve(file, match.group(1) ?? '', package);
        final feature = target == null ? null : features[target];
        if (feature == null || file.startsWith(feature.folder)) continue;
        final page = layout.matches(LayoutRole.pages, file) ? _pageFolder(file) : null;
        (page != null ? pages[target] : others[target])?.add(page ?? file);
      }
    }

    final findings = <Finding>[];
    for (final MapEntry(key: file, value: feature) in features.entries) {
      final users = pages[file] ?? const {};
      if (users.length != 1 || (others[file] ?? const {}).isNotEmpty) continue;
      findings.add(
        Finding(
          rule: 'feature_used_once',
          file: file,
          line: feature.line,
          message: 'the feature `${feature.className}` is used only by the page `${users.single}`; '
              'move it into that page (${users.single}widgets/), features serve several pages, a shell or both '
              'administrations',
        ),
      );
    }
    return StepResult(findings: findings, findingsScope: (file) => layout.matches(LayoutRole.features, file));
  }

  /// Root-relative path of the file [uri] in [from] points at, or `null`
  /// when it is outside this package.
  static String? _resolve(String from, String uri, String package) {
    if (uri.startsWith('package:')) {
      final prefix = 'package:$package/';
      return package.isNotEmpty && uri.startsWith(prefix) ? 'lib/${uri.substring(prefix.length)}' : null;
    }
    if (uri.contains(':')) return null;
    final segments = from.split('/')..removeLast();
    for (final part in uri.split('/')) {
      if (part == '..') {
        if (segments.isNotEmpty) segments.removeLast();
      } else if (part != '.' && part.isNotEmpty) {
        segments.add(part);
      }
    }
    return segments.join('/');
  }

  /// The page folder [file] belongs to: its path down to the first folder
  /// whose name ends in `_page`, with a trailing `/`; `null` outside one.
  static String? _pageFolder(String file) {
    final segments = file.split('/')..removeLast();
    for (var i = 0; i < segments.length; i++) {
      if (segments[i].endsWith('_page')) return '${segments.sublist(0, i + 1).join('/')}/';
    }
    return null;
  }
}
