import 'dart:io';

import 'package:path/path.dart' as p;

bool? _tesseractCliCached;
String? _resolvedTesseractPath;
String? debugTesseractExecutableOverride;

String _runningExecutablePath(String? executablePath) {
  if (executablePath != null && executablePath.isNotEmpty) {
    return p.normalize(File(executablePath).absolute.path);
  }
  if (Platform.isLinux) {
    try {
      final self = File('/proc/self/exe').resolveSymbolicLinksSync();
      if (self.isNotEmpty) return p.normalize(self);
    } catch (_) {}
  }
  try {
    return p.normalize(
      File(Platform.resolvedExecutable).resolveSymbolicLinksSync(),
    );
  } catch (_) {
    return p.normalize(File(Platform.resolvedExecutable).absolute.path);
  }
}

List<String> tesseractBundledCandidatePaths({String? executablePath}) {
  final exe = _runningExecutablePath(executablePath);
  final dir = p.dirname(exe);
  final cwd = Directory.current.path;
  final paths = <String>[
    p.join(dir, 'tesseract'),
    p.join(dir, 'engines', 'tesseract'),
    p.join(dir, 'engines', 'bin', 'tesseract'),
    p.join(dir, '..', 'engines', 'tesseract'),
    p.join(dir, '..', '..', 'bundle', 'engines', 'tesseract'),
    p.join(cwd, 'build', 'linux', 'x64', 'debug', 'bundle', 'engines', 'tesseract'),
    p.join(
      cwd,
      'build',
      'linux',
      'x64',
      'release',
      'bundle',
      'engines',
      'tesseract',
    ),
  ];
  return paths.map(p.normalize).toList(growable: false);
}

Future<String> resolvedTesseractExecutable({
  String? executablePath,
  bool Function(String path)? fileExists,
}) async {
  final override = debugTesseractExecutableOverride;
  if (override != null) return override;
  if (_resolvedTesseractPath != null) return _resolvedTesseractPath!;
  final exists = fileExists ?? (path) => File(path).existsSync();
  for (final path
      in tesseractBundledCandidatePaths(executablePath: executablePath)) {
    if (exists(path)) {
      _resolvedTesseractPath = path;
      return path;
    }
  }
  _resolvedTesseractPath = 'tesseract';
  return _resolvedTesseractPath!;
}

/// Directory with `eng.traineddata` beside the app binary, if bundled.
String? resolvedTessdataPrefix({
  String? executablePath,
  bool Function(String path)? directoryExists,
  bool Function(String path)? fileExists,
}) {
  final exe = _runningExecutablePath(executablePath);
  final dir = p.dirname(exe);
  final dirOk = directoryExists ?? (path) => Directory(path).existsSync();
  final fileOk = fileExists ?? (path) => File(path).existsSync();
  final cwd = Directory.current.path;
  final candidates = [
    p.join(dir, 'engines', 'tessdata'),
    p.join(dir, 'tessdata'),
    p.join(dir, 'engines', 'share', 'tessdata'),
    p.join(dir, '..', 'engines', 'tessdata'),
    p.join(dir, '..', '..', 'bundle', 'engines', 'tessdata'),
    p.join(cwd, 'build', 'linux', 'x64', 'debug', 'bundle', 'engines', 'tessdata'),
    p.join(
      cwd,
      'build',
      'linux',
      'x64',
      'release',
      'bundle',
      'engines',
      'tessdata',
    ),
  ].map(p.normalize);
  for (final tess in candidates) {
    if (dirOk(tess) && fileOk(p.join(tess, 'eng.traineddata'))) {
      return tess;
    }
  }
  return null;
}

/// Whether the `tesseract` executable is bundled or on PATH.
Future<bool> isTesseractCliAvailable() async {
  if (_tesseractCliCached != null) return _tesseractCliCached!;
  try {
    final exe = await resolvedTesseractExecutable();
    final result = await Process.run(exe, ['--version']);
    _tesseractCliCached = result.exitCode == 0;
  } catch (_) {
    _tesseractCliCached = false;
  }
  return _tesseractCliCached!;
}

void resetTesseractCliAvailabilityCacheForTests() {
  _tesseractCliCached = null;
  _resolvedTesseractPath = null;
  debugTesseractExecutableOverride = null;
}
