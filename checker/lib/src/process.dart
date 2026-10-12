import 'dart:io';

/// Runs [executable] in [root] and returns its exit code and combined output.
Future<({int exitCode, String stdout, String stderr})> runProcess(
  String root,
  String executable,
  List<String> args,
) async {
  final result = await Process.run(executable, args, workingDirectory: root);
  return (exitCode: result.exitCode, stdout: result.stdout as String, stderr: result.stderr as String);
}

/// Splits [items] into chunks so a command line stays well under the OS limit.
Iterable<List<T>> chunks<T>(List<T> items, [int size = 400]) sync* {
  for (var i = 0; i < items.length; i += size) {
    yield items.sublist(i, i + size > items.length ? items.length : i + size);
  }
}
