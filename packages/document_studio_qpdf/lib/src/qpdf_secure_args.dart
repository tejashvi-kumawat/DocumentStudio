import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// Runs [run] with [args], keeping secrets out of the process command line.
///
/// A command line is readable by every other local user (`ps`, Task Manager,
/// /proc), so open / owner passwords must never be passed as plain arguments.
/// When [args] contain a password this writes them to a private argument file
/// (qpdf `@file`: owner-only directory and file, random name), runs qpdf with
/// just that file name, overwrites and deletes the file afterwards — even if
/// qpdf fails.
Future<T> runQpdfProtected<T>(
  List<String> args,
  Future<T> Function(List<String> safeArgs) run,
) async {
  final secret = args.any(
    (a) =>
        a.startsWith('--password=') ||
        a.startsWith('--user-password=') ||
        a.startsWith('--owner-password=') ||
        a == '--encrypt',
  );
  if (!secret || args.any((a) => a.startsWith('@'))) return run(args);
  // An argument file holds one argument per line.
  if (args.any((a) => a.contains('\n') || a.contains('\r'))) {
    throw ArgumentError('Passwords and paths cannot contain line breaks.');
  }
  final dir = await Directory.systemTemp.createTemp('dsq_');
  final name = List.generate(
    16,
    (_) => Random.secure().nextInt(36).toRadixString(36),
  ).join();
  final file = File(p.join(dir.path, name));
  try {
    if (!Platform.isWindows) {
      await Process.run('chmod', ['700', dir.path]);
    }
    await file.writeAsString(args.join('\n'), flush: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', file.path]);
    }
    return await run(['@${file.path}']);
  } finally {
    try {
      // Overwrite before unlinking so the secret does not linger on disk.
      final len = await file.length();
      await file.writeAsBytes(List.filled(len, 0), flush: true);
    } catch (_) {}
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}
