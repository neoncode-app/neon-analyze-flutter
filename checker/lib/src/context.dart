import 'dart:io';

import 'package:neon_check/src/config.dart';

/// Which files a run looks at.
enum ScopeMode {
  /// Everything (`--all`, CI).
  all,

  /// Files changed against the branch base, plus uncommitted and untracked.
  changed,

  /// Files staged for commit (pre-commit hook).
  staged,

  /// An explicit list (`--files`, editor hooks).
  files,
}

/// Everything a step needs to know about the run.
final class CheckContext {
  CheckContext({
    required this.root,
    required this.config,
    required this.mode,
    required this.changedFiles,
    required this.deletedFiles,
    required this.fix,
    required this.ci,
    this.base,
  });

  /// Absolute app root, without a trailing slash.
  final String root;

  final CheckConfig config;

  final ScopeMode mode;

  /// Root-relative paths of existing files in scope (empty in [ScopeMode.all]).
  final Set<String> changedFiles;

  /// Root-relative paths deleted in scope, so their baseline entries go away.
  final Set<String> deletedFiles;

  /// Whether auto-fix steps may change files.
  final bool fix;

  /// CI: auto-fix steps only check, the baseline is never written.
  final bool ci;

  /// The branch the work is compared against (`--base`, else
  /// `branch.<name>.neonBase`, else `default_base`); `null` when none resolves.
  final String? base;

  bool get isAll => mode == ScopeMode.all;

  /// Whether [file] (root-relative) is in scope.
  bool inScope(String file) => isAll || changedFiles.contains(file) || deletedFiles.contains(file);

  /// Root-relative Dart files in scope, generated files excluded.
  List<String> get dartFiles {
    if (isAll) {
      return [
        for (final dir in config.sourceDirs)
          if (Directory('$root/$dir').existsSync())
            for (final entity in Directory('$root/$dir').listSync(recursive: true))
              if (entity is File && _isSourceDart(entity.path)) relative(entity.path),
      ]..sort();
    }
    return [
      for (final file in changedFiles)
        if (_isSourceDart(file) && config.sourceDirs.any((dir) => file.startsWith('$dir/'))) file,
    ]..sort();
  }

  static bool _isSourceDart(String path) =>
      path.endsWith('.dart') && !path.endsWith('.g.dart') && !path.endsWith('.freezed.dart');

  /// Whether anything in scope lives under one of [prefixes].
  bool touches(Iterable<String> prefixes) =>
      isAll || [...changedFiles, ...deletedFiles].any((file) => prefixes.any(file.startsWith));

  String relative(String path) {
    final normalized = path.replaceAll(r'\', '/');
    return normalized.startsWith('$root/') ? normalized.substring(root.length + 1) : normalized;
  }

  String absolute(String relativePath) => '$root/$relativePath';

  /// Every Dart file under `lib/` (some checks always need the whole picture).
  List<String> get allLibDartFiles => [
        if (Directory('$root/lib').existsSync())
          for (final entity in Directory('$root/lib').listSync(recursive: true))
            if (entity is File && entity.path.endsWith('.dart')) relative(entity.path),
      ]..sort();
}

/// The base branch recorded for the current branch (`branch.<name>.neonBase`),
/// or `null`.
String? recordedBase(String root) {
  final branch = Process.runSync('git', ['rev-parse', '--abbrev-ref', 'HEAD'], workingDirectory: root);
  if (branch.exitCode != 0) return null;
  final recorded = Process.runSync(
    'git',
    ['config', 'branch.${(branch.stdout as String).trim()}.neonBase'],
    workingDirectory: root,
  );
  final value = recorded.exitCode == 0 ? (recorded.stdout as String).trim() : '';
  return value.isEmpty ? null : value;
}

/// The merge base of HEAD and [base] (tried as given, then as `origin/<base>`),
/// or `null` when neither ref exists.
String? mergeBase(String root, String base) {
  for (final ref in [base, 'origin/$base']) {
    final result = Process.runSync('git', ['merge-base', 'HEAD', ref], workingDirectory: root);
    if (result.exitCode == 0) return (result.stdout as String).trim();
  }
  return null;
}

/// Resolves the changed / staged files of the git checkout at [root].
({Set<String> existing, Set<String> deleted}) gitScope(String root, ScopeMode mode, {String? base}) {
  List<String> git(List<String> args) {
    final result = Process.runSync('git', args, workingDirectory: root);
    if (result.exitCode != 0) throw StateError('git ${args.join(' ')} failed: ${result.stderr}');
    return (result.stdout as String).split('\n').where((line) => line.trim().isNotEmpty).toList();
  }

  final existing = <String>{};
  final deleted = <String>{};
  if (mode == ScopeMode.staged) {
    existing.addAll(git(['diff', '--cached', '--name-only', '--diff-filter=ACMR']));
    deleted.addAll(git(['diff', '--cached', '--name-only', '--diff-filter=D']));
  } else {
    final branch = git(['rev-parse', '--abbrev-ref', 'HEAD']).first;
    final recorded = Process.runSync('git', ['config', 'branch.$branch.neonBase'], workingDirectory: root);
    final baseBranch = base ?? (recorded.exitCode == 0 ? (recorded.stdout as String).trim() : null);
    if (baseBranch == null || baseBranch.isEmpty) {
      throw StateError('No base branch: branch.$branch.neonBase is not set. Pass --base <branch> or use --all.');
    }
    final mergeBase = git(['merge-base', 'HEAD', baseBranch]).first;
    existing
      ..addAll(git(['diff', '--name-only', '--diff-filter=ACMR', mergeBase]))
      ..addAll(git(['ls-files', '--others', '--exclude-standard']));
    deleted.addAll(git(['diff', '--name-only', '--diff-filter=D', mergeBase]));
  }
  existing.removeWhere((file) => !File('$root/$file').existsSync());
  return (existing: existing, deleted: deleted);
}
