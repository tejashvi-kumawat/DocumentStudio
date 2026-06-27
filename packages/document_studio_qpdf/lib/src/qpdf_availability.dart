import 'dart:io';

import 'package:path/path.dart' as p;

String? _resolvedQpdfPath;
bool? _pageBoxEditCached;
bool? _qpdfAvailableCached;

/// Override for tests (absolute path or `qpdf`).
String? debugQpdfExecutableOverride;

/// Candidate locations for a bundled `qpdf` next to the running binary.
///
/// Prefer `engines/qpdf` (wrapper that sets `LD_LIBRARY_PATH`) over
/// `engines/bin/qpdf` (raw ELF that fails without the wrapper on Linux).
List<String> qpdfBundledCandidatePaths({String? executablePath}) {
  final exe = executablePath ?? Platform.resolvedExecutable;
  final dir = p.dirname(exe);
  final names = <String>['qpdf'];
  if (Platform.isWindows) {
    names.addAll(['qpdf.exe', 'qpdf.cmd', 'qpdf.bat']);
  }
  final roots = <String>[
    p.join(dir, 'engines'),
    p.join(dir, 'engines', 'bin'),
    dir,
    p.join(dir, '..', 'engines'),
    p.join(dir, '..', 'engines', 'bin'),
    // macOS .app: Resources/engines when MacOS/ holds the executable.
    p.join(dir, '..', 'Resources', 'engines'),
    p.join(dir, '..', 'Resources', 'engines', 'bin'),
  ];
  final out = <String>[];
  final seen = <String>{};
  for (final root in roots) {
    for (final n in names) {
      final path = p.normalize(p.join(root, n));
      if (seen.add(path)) out.add(path);
    }
  }
  return out;
}

/// Absolute path to qpdf when resolved, otherwise the bare name for PATH.
Future<String> resolvedQpdfExecutable({
  String? executablePath,
  bool Function(String path)? fileExists,
}) async {
  final override = debugQpdfExecutableOverride;
  if (override != null) return override;
  if (_resolvedQpdfPath != null) return _resolvedQpdfPath!;

  final exists = fileExists ?? (path) => File(path).existsSync();
  for (final path in qpdfBundledCandidatePaths(executablePath: executablePath)) {
    if (exists(path)) {
      _resolvedQpdfPath = path;
      return path;
    }
  }
  _resolvedQpdfPath = 'qpdf';
  return _resolvedQpdfPath!;
}

/// Whether a usable `qpdf` binary is bundled or on PATH.
Future<bool> isQpdfCliAvailable() async {
  if (_qpdfAvailableCached != null) return _qpdfAvailableCached!;
  try {
    final exe = await resolvedQpdfExecutable();
    final result = await Process.run(exe, ['--version']);
    _qpdfAvailableCached = result.exitCode == 0;
  } catch (_) {
    _qpdfAvailableCached = false;
  }
  return _qpdfAvailableCached!;
}

/// Whether this qpdf build can edit page CropBox (JSON update path).
Future<bool> isQpdfCliPageBoxEditAvailable() async {
  if (_pageBoxEditCached != null) return _pageBoxEditCached!;
  // Crop uses --json-output / --update-from-json, available on modern qpdf.
  _pageBoxEditCached = await isQpdfCliAvailable();
  return _pageBoxEditCached!;
}

/// Clears cached capability probes (tests).
void resetQpdfCliCapabilityCacheForTests() {
  _pageBoxEditCached = null;
  _qpdfAvailableCached = null;
  _resolvedQpdfPath = null;
  debugQpdfExecutableOverride = null;
}
