import 'dart:io';

import 'package:path/path.dart' as p;

/// Extra engine roots injected at startup (e.g. app-support engines/).
List<String> debugDesktopEngineExtraRoots = <String>[];

/// Absolute path of the running process binary.
///
/// On Linux, prefers `/proc/self/exe` so `flutter run -d linux` resolves the
/// real bundle executable even when argv[0] is relative or the embedder reports
/// a non-bundle path. Falls back to [Platform.resolvedExecutable].
String resolveRunningExecutablePath({String? executablePath}) {
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

/// Resolves bundled desktop CLI engines (qpdf, tesseract, pdfsig, …) for the
/// running app.
///
/// Lookup order (bundled locations before PATH / `/usr/bin`):
/// 1. `engines/<name>` beside the executable (wrapper sets library path)
/// 2. `engines/bin/<name>` (raw binary / portable zip layout)
/// 3. Next to the executable
/// 4. Parent `engines/` and, on macOS, `Contents/Resources/engines`
/// 5. App-support `engines/` registered in [debugDesktopEngineExtraRoots]
/// 6. Flutter debug/release bundle under cwd (`build/linux/*/bundle/engines`)
/// 7. PATH (`which` on Linux/macOS, `where` on Windows) — last resort only
///
/// Windows Release output keeps engines beside `document_studio.exe`.
/// macOS `.app` keeps them in `Contents/MacOS/engines` (and may mirror
/// `Contents/Resources/engines`). Android does not use these CLIs.
class DesktopEngineResolver {
  DesktopEngineResolver({
    String? executablePath,
    this.pathLookup,
    this.fileExists,
    this.directoryExists,
  }) : executablePath = resolveRunningExecutablePath(
          executablePath: executablePath,
        );

  /// Absolute path of the running binary (override in tests).
  final String executablePath;

  /// Returns absolute path for [name] on PATH, or null.
  final Future<String?> Function(String name)? pathLookup;

  final bool Function(String path)? fileExists;
  final bool Function(String path)? directoryExists;

  String get _exeDir => p.dirname(executablePath);

  bool _exists(String path) =>
      (fileExists ?? (path) => File(path).existsSync())(path);

  bool _dirExists(String path) =>
      (directoryExists ?? (path) => Directory(path).existsSync())(path);

  /// Candidate absolute paths for a CLI named [name] (no PATH probe).
  List<String> candidatePaths(String name) {
    final dir = _exeDir;
    final names = <String>[name];
    if (Platform.isWindows) {
      names.addAll(['$name.exe', '$name.cmd', '$name.bat']);
    }
    final roots = <String>{
      p.join(dir, 'engines'),
      p.join(dir, 'engines', 'bin'),
      dir,
      p.join(dir, '..', 'engines'),
      p.join(dir, '..', 'engines', 'bin'),
      // macOS .app: MacOS/ holds the executable; Resources/engines is a mirror.
      p.join(dir, '..', 'Resources', 'engines'),
      p.join(dir, '..', 'Resources', 'engines', 'bin'),
      p.join(dir, '..', '..', 'bundle', 'engines'),
      p.join(dir, '..', '..', 'bundle', 'engines', 'bin'),
    };
    for (final extra in debugDesktopEngineExtraRoots) {
      if (extra.isEmpty) continue;
      roots.add(extra);
      roots.add(p.join(extra, 'bin'));
    }
    // flutter run cwd → build/linux/{debug,release}/bundle/engines
    final cwd = Directory.current.path;
    for (final mode in ['debug', 'release']) {
      roots.add(p.join(cwd, 'build', 'linux', 'x64', mode, 'bundle', 'engines'));
      roots.add(
        p.join(cwd, 'build', 'linux', 'x64', mode, 'bundle', 'engines', 'bin'),
      );
      roots.add(p.join(cwd, 'build', 'linux', 'arm64', mode, 'bundle', 'engines'));
      roots.add(
        p.join(cwd, 'build', 'linux', 'arm64', mode, 'bundle', 'engines', 'bin'),
      );
    }
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

  Future<String?> resolve(String name) async {
    for (final path in candidatePaths(name)) {
      if (_exists(path)) return path;
    }
    final lookup = pathLookup ?? _which;
    return lookup(name);
  }

  Future<String?> resolveQpdf() => resolve('qpdf');

  Future<String?> resolveTesseract() => resolve('tesseract');

  /// OpenSSL CLI (`openssl`) for CMS / PKCS#12 certificate signing helpers.
  Future<String?> resolveOpenSsl() => resolve('openssl');

  /// Poppler `pdfsig` for PKCS#7 PDF signatures (prefer bundled wrapper).
  Future<String?> resolvePdfsig() => resolve('pdfsig');

  /// NSS `certutil` (nickname listing / temp DB init).
  Future<String?> resolveCertutil() => resolve('certutil');

  /// NSS `pk12util` for importing `.p12`/`.pfx` into an NSS DB.
  Future<String?> resolvePk12util() => resolve('pk12util');

  Future<String?> resolveSoffice() async {
    for (final name in ['soffice', 'libreoffice']) {
      final path = await resolve(name);
      if (path != null) return path;
    }
    return null;
  }

  Future<String?> resolveFfmpeg() => resolve('ffmpeg');

  /// Directory containing `eng.traineddata` when bundled beside the binary.
  String? resolveTessdataPrefix() {
    final candidates = <String>{
      p.join(_exeDir, 'engines', 'tessdata'),
      p.join(_exeDir, 'tessdata'),
      p.join(_exeDir, 'engines', 'share', 'tessdata'),
      p.join(_exeDir, '..', 'engines', 'tessdata'),
      p.join(_exeDir, '..', '..', 'bundle', 'engines', 'tessdata'),
      p.join(_exeDir, '..', 'Resources', 'engines', 'tessdata'),
    };
    for (final extra in debugDesktopEngineExtraRoots) {
      if (extra.isEmpty) continue;
      candidates.add(p.join(extra, 'tessdata'));
    }
    final cwd = Directory.current.path;
    for (final mode in ['debug', 'release']) {
      candidates.add(
        p.join(cwd, 'build', 'linux', 'x64', mode, 'bundle', 'engines', 'tessdata'),
      );
    }
    for (final dir in candidates.map(p.normalize)) {
      if (_dirExists(dir) && _exists(p.join(dir, 'eng.traineddata'))) {
        return dir;
      }
    }
    return null;
  }

  static Future<String?> _which(String name) async {
    try {
      final result = Platform.isWindows
          ? await Process.run('where', [name], runInShell: true)
          : await Process.run('which', [name]);
      if (result.exitCode != 0) return null;
      final path = result.stdout
          .toString()
          .trim()
          .split(RegExp(r'\r?\n'))
          .first
          .trim();
      if (path.isEmpty) return null;
      return path;
    } catch (_) {
      return null;
    }
  }
}

/// Shared default resolver (override in tests via [debugDesktopEngineResolverOverride]).
DesktopEngineResolver? debugDesktopEngineResolverOverride;

DesktopEngineResolver get desktopEngineResolver =>
    debugDesktopEngineResolverOverride ?? DesktopEngineResolver();
