import 'dart:ffi';
import 'dart:io';

import 'package:document_studio/core/desktop/desktop_engine_resolver.dart';
import 'package:document_studio/core/storage/storage_paths.dart';
import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:path/path.dart' as p;

/// One-shot download of portable qpdf into the app-support `engines/` folder.
///
/// Not called from startup. PDF viewing does not wait on it. A second call
/// while a download is running shares that download; once the binary is
/// present, later calls do not touch the network.
class QpdfEngineFetch {
  const QpdfEngineFetch({
    this.resolver,
    this.downloadZip,
    this.unzipZip,
    this.enginesDirectory,
  });

  final DesktopEngineResolver? resolver;
  final Future<void> Function(String url, String destZip)? downloadZip;
  final Future<void> Function(String zipPath, String destDir)? unzipZip;

  /// Override for tests. Production uses app-support `engines/`.
  final String? enginesDirectory;

  static const linuxVersion = '12.2.0';
  static const windowsVersion = '12.4.2';

  static Future<String>? _ongoing;

  /// Official GitHub release zip, or null when this OS has no small portable
  /// build (macOS uses the packaging script; Android does not use qpdf).
  static String? officialZipUrl({String? operatingSystem, String? arch}) {
    final os = operatingSystem ?? Platform.operatingSystem;
    final cpu = arch ?? _cpu();
    if (os == 'android' || os == 'ios') return null;
    if (os == 'linux') {
      final zipArch = switch (cpu) {
        'x64' || 'x86_64' || 'amd64' => 'x86_64',
        'arm64' || 'aarch64' => 'aarch64',
        _ => null,
      };
      if (zipArch == null) return null;
      return 'https://github.com/qpdf/qpdf/releases/download/'
          'v$linuxVersion/qpdf-$linuxVersion-bin-linux-$zipArch.zip';
    }
    if (os == 'windows') {
      return 'https://github.com/qpdf/qpdf/releases/download/'
          'v$windowsVersion/qpdf-$windowsVersion-mingw64.zip';
    }
    return null;
  }

  /// Returns the qpdf path. Downloads at most once per missing install.
  Future<String> fetchOnce() {
    final existing = _ongoing;
    if (existing != null) return existing;
    final run = _fetch();
    _ongoing = run;
    return run.whenComplete(() {
      if (identical(_ongoing, run)) _ongoing = null;
    });
  }

  Future<String> _fetch() async {
    if (Platform.isAndroid || Platform.isIOS) {
      throw StateError(
        'This device uses the built-in PDF engine. '
        'qpdf is not installed on Android or iOS.',
      );
    }
    final found = await (resolver ?? desktopEngineResolver).resolveQpdf();
    if (found != null) return found;

    final url = officialZipUrl();
    if (url == null) {
      throw StateError(
        'No small official qpdf download is published for this system. '
        'On macOS run bash scripts/macos/package_release.sh so '
        'Contents/MacOS/engines contains qpdf.',
      );
    }

    final engines = await _enginesDir();
    await engines.create(recursive: true);
    final scratch = await Directory.systemTemp.createTemp('ds-qpdf-');
    final zipPath = p.join(scratch.path, p.basename(url));
    try {
      final get = downloadZip ?? _httpGet;
      await get(url, zipPath);
      final unpack = unzipZip ?? _unzip;
      final extracted = Directory(p.join(scratch.path, 'out'));
      await unpack(zipPath, extracted.path);
      final binary = await _findBinary(extracted);
      if (binary == null) {
        throw StateError('The qpdf download did not contain a qpdf binary.');
      }
      await _installTree(binary, engines);
    } finally {
      try {
        await scratch.delete(recursive: true);
      } catch (_) {}
    }

    final wrapper = _wrapperPath(engines.path);
    if (!File(wrapper).existsSync()) {
      throw StateError('qpdf was downloaded but the app wrapper is missing.');
    }
    await File(p.join(engines.path, '.qpdf-fetch-complete')).writeAsString(
      url,
      flush: true,
    );
    if (!debugDesktopEngineExtraRoots.contains(engines.path)) {
      debugDesktopEngineExtraRoots = [
        ...debugDesktopEngineExtraRoots,
        engines.path,
      ];
    }
    if (!debugQpdfExtraSearchRoots.contains(engines.path)) {
      debugQpdfExtraSearchRoots = [
        ...debugQpdfExtraSearchRoots,
        engines.path,
      ];
    }
    debugQpdfExecutableOverride = wrapper;
    invalidateQpdfExecutableCache();
    return wrapper;
  }

  Future<Directory> _enginesDir() async {
    final override = enginesDirectory;
    if (override != null) return Directory(override);
    final storage = StoragePaths.maybeInstance ?? await StoragePaths.init();
    return Directory(p.join(storage.root.path, 'engines'));
  }

  static String _wrapperPath(String enginesDir) {
    if (Platform.isWindows) return p.join(enginesDir, 'qpdf.cmd');
    return p.join(enginesDir, 'qpdf');
  }

  static String _cpu() {
    final arch = Abi.current().toString();
    if (arch.contains('X64') || arch.contains('x64')) return 'x86_64';
    if (arch.contains('Arm64') || arch.contains('arm64')) return 'arm64';
    return arch;
  }

  static Future<void> _httpGet(String url, String destZip) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw StateError(
          'qpdf download failed (HTTP ${response.statusCode}).',
        );
      }
      final sink = File(destZip).openWrite();
      await response.pipe(sink);
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _unzip(String zipPath, String destDir) async {
    await Directory(destDir).create(recursive: true);
    if (Platform.isWindows) {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          "Expand-Archive -LiteralPath '$zipPath' -DestinationPath '$destDir' -Force",
        ],
      );
      if (result.exitCode != 0) {
        throw StateError('Could not unpack the qpdf zip.');
      }
      return;
    }
    final unzip = await Process.run('unzip', ['-q', '-o', zipPath, '-d', destDir]);
    if (unzip.exitCode == 0) return;
    final python = await Process.run(
      'python3',
      ['-m', 'zipfile', '-e', zipPath, destDir],
    );
    if (python.exitCode != 0) {
      throw StateError('Could not unpack the qpdf zip (need unzip or python3).');
    }
  }

  static Future<File?> _findBinary(Directory root) async {
    final names = Platform.isWindows ? ['qpdf.exe', 'qpdf'] : ['qpdf'];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (names.contains(p.basename(entity.path))) return entity;
    }
    return null;
  }

  static Future<void> _installTree(File binary, Directory engines) async {
    final binDir = Directory(p.join(engines.path, 'bin'));
    final libDir = Directory(p.join(engines.path, 'lib'));
    await binDir.create(recursive: true);
    await libDir.create(recursive: true);
    final leaf = p.basename(binary.path);
    final destBin = File(p.join(binDir.path, leaf));
    await binary.copy(destBin.path);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', destBin.path]);
    }
    final siblingLib = Directory(p.join(binary.parent.parent.path, 'lib'));
    if (siblingLib.existsSync()) {
      await for (final entity in siblingLib.list(followLinks: false)) {
        if (entity is File) {
          await entity.copy(p.join(libDir.path, p.basename(entity.path)));
        }
      }
    }
    final wrapper = File(_wrapperPath(engines.path));
    if (Platform.isWindows) {
      await wrapper.writeAsString(
        '@echo off\r\n'
        'set "ROOT=%~dp0"\r\n'
        'set "PATH=%ROOT%bin;%ROOT%lib;%PATH%"\r\n'
        '"%ROOT%bin\\$leaf" %*\r\n',
        flush: true,
      );
    } else {
      await wrapper.writeAsString(
        '#!/usr/bin/env bash\n'
        'ROOT="\$(cd "\$(dirname "\$0")" && pwd)"\n'
        'export LD_LIBRARY_PATH="\$ROOT/lib:\${LD_LIBRARY_PATH:-}"\n'
        'exec "\$ROOT/bin/$leaf" "\$@"\n',
        flush: true,
      );
      await Process.run('chmod', ['+x', wrapper.path]);
    }
  }
}
