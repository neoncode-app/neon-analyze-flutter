import 'dart:io';

/// A Dart directive that links a file to another (`import`, `export`, `part`,
/// not `part of`), with every URI it names (conditional imports name several).
final _directive = RegExp(r'''^[ \t]*(?:import|export|part(?![ \t]+of\b))\b([^;]*);''', multiLine: true);
final _uri = RegExp(r'''['"]([^'"]+\.dart)['"]''');

/// The root-relative files [file] links to, given its [source]: `package:`
/// URIs of the app itself ([packageName]) resolve under `lib/`, relative URIs
/// against the file's folder; `dart:` and other packages are not app files.
Set<String> directDependencies(String file, String source, String packageName) {
  final folder = file.contains('/') ? file.substring(0, file.lastIndexOf('/')) : '';
  final prefix = 'package:$packageName/';
  final result = <String>{};
  for (final directive in _directive.allMatches(source)) {
    for (final uri in _uri.allMatches(directive.group(1) ?? '')) {
      final target = uri.group(1) ?? '';
      if (target.startsWith(prefix)) {
        result.add('lib/${target.substring(prefix.length)}');
      } else if (!target.contains(':')) {
        result.add(normalizePath(folder.isEmpty ? target : '$folder/$target'));
      }
    }
  }
  return result;
}

/// [path] with `.` and `..` segments folded.
String normalizePath(String path) {
  final parts = <String>[];
  for (final part in path.split('/')) {
    if (part == '..' && parts.isNotEmpty) {
      parts.removeLast();
    } else if (part != '.' && part.isNotEmpty) {
      parts.add(part);
    }
  }
  return parts.join('/');
}

/// The test files of [tests] whose import closure (imports, exports and parts,
/// followed through the app) contains one of [changed], or that are changed
/// themselves. [read] returns a root-relative file's source, `null` when it
/// does not exist (a deleted file still counts: a test importing it no longer
/// compiles).
Set<String> impactedTests({
  required Iterable<String> tests,
  required Set<String> changed,
  required String packageName,
  required String? Function(String file) read,
}) {
  final dependencies = <String, Set<String>>{};
  Set<String> dependenciesOf(String file) => dependencies.putIfAbsent(file, () {
        final source = read(file);
        return source == null ? const <String>{} : directDependencies(file, source, packageName);
      });

  final reached = <String, bool>{};
  bool reaches(String start) {
    // Iterative depth-first walk; every file is decided once for all tests.
    final known = reached[start];
    if (known != null) return known;
    final seen = <String>{};
    final pending = [start];
    var hit = false;
    while (pending.isNotEmpty && !hit) {
      final file = pending.removeLast();
      if (!seen.add(file)) continue;
      if (changed.contains(file) || reached[file] == true) {
        hit = true;
        break;
      }
      for (final next in dependenciesOf(file)) {
        if (reached[next] != false) pending.add(next);
      }
    }
    // A miss proves nothing about files cut off by the early exit, so only the
    // start is recorded on a hit; on a miss the whole visited set is clean.
    if (hit) {
      reached[start] = true;
    } else {
      for (final file in seen) {
        reached[file] = false;
      }
    }
    return hit;
  }

  return {
    for (final test in tests)
      if (reaches(test)) test,
  };
}

/// Root-relative `_test.dart` files under [testDir] of the app at [root].
List<String> testFilesIn(String root, String testDir) {
  final directory = Directory('$root/$testDir');
  if (!directory.existsSync()) return const [];
  return [
    for (final entity in directory.listSync(recursive: true))
      if (entity is File && entity.path.endsWith('_test.dart')) entity.path.substring(root.length + 1),
  ]..sort();
}
