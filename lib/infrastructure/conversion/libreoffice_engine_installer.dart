import 'dart:async';
import 'dart:io';

import 'package:document_studio/core/desktop/desktop_engine_resolver.dart';
import 'package:document_studio/core/storage/storage_paths.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Downloads LibreOffice into the app's private storage on Windows when
/// `engines/soffice` is missing. Does **not** run a system-wide installer.
///
/// Linux/macOS ship LibreOffice via the packaging scripts when practical;
/// Android never downloads native executables (Play policy).
class LibreOfficeEngineInstaller {
  LibreOfficeEngineInstaller({
    http.Client? client,
    DesktopEngineResolver? resolver,
  })  : _client = client ?? http.Client(),
        _resolver = resolver ?? desktopEngineResolver;

  final http.Client _client;
  final DesktopEngineResolver _resolver;

  /// Stable Document Foundation mirror for the Windows x86-64 MSI.
  /// Override with `DS_LIBREOFFICE_MSI_URL` when pinning a mirror.
  static String get windowsMsiUrl {
    final env = Platform.environment['DS_LIBREOFFICE_MSI_URL'];
    if (env != null && env.isNotEmpty) return env;
    // Pin a known stable version; bump deliberately when testing upgrades.
    const ver = '26.2.6';
    return 'https://download.documentfoundation.org/libreoffice/stable/'
        '$ver/win/x86_64/LibreOffice_${ver}_Win_x86-64.msi';
  }

  bool get isSupported {
    if (Platform.isAndroid || Platform.isIOS) return false;
    return Platform.isWindows;
  }

  Future<String?> resolveExisting() => _resolver.resolveSoffice();

  /// Download + silent extract/install into app storage. Reports [onProgress]
  /// with 0..1 fraction and a status message.
  Future<String> installIntoAppStorage({
    void Function(double fraction, String message)? onProgress,
  }) async {
    if (!Platform.isWindows) {
      throw StateError(
        'In-app LibreOffice install is only implemented for Windows. '
        'On Linux/macOS, rebuild so engines/ includes soffice.',
      );
    }
    onProgress?.call(0.02, 'Preparing download…');
    final root = await StoragePaths.init();
    final destRoot = Directory(p.join(root.root.path, 'engines', 'libreoffice'));
    await destRoot.create(recursive: true);
    final msiPath = p.join(root.temp.path, 'libreoffice-setup.msi');
    final url = windowsMsiUrl;
    onProgress?.call(0.05, 'Downloading LibreOffice…');
    await _download(url, msiPath, onProgress);
    onProgress?.call(0.85, 'Installing into app folder…');
    // Per-user silent install into our engines tree (not Program Files).
    final result = await Process.run(
      'msiexec',
      [
        '/i',
        msiPath,
        '/qn',
        '/norestart',
        'ALLUSERS=2',
        'MSIINSTALLPERUSER=1',
        'INSTALLDIR=${destRoot.path}',
      ],
      runInShell: true,
    );
    try {
      await File(msiPath).delete();
    } catch (_) {}
    if (result.exitCode != 0) {
      final err = result.stderr.toString().trim();
      throw StateError(
        'LibreOffice MSI install failed (exit ${result.exitCode}). $err',
      );
    }
    final soffice = File(p.join(destRoot.path, 'program', 'soffice.exe'));
    if (!await soffice.exists()) {
      // Some MSI layouts nest under LibreOffice\program.
      final nested = await _findSoffice(destRoot);
      if (nested == null) {
        throw StateError(
          'LibreOffice installed but soffice.exe was not found under '
          '${destRoot.path}',
        );
      }
      onProgress?.call(1, 'Ready');
      return nested;
    }
    // Thin engines/soffice.cmd so DesktopEngineResolver finds it next to the
    // exe when DOCUMENT_STUDIO_ENGINES points at storage engines/, or when
    // we also write a copy beside the install root.
    final engines = Directory(p.join(root.root.path, 'engines'));
    await engines.create(recursive: true);
    final wrapper = File(p.join(engines.path, 'soffice.cmd'));
    await wrapper.writeAsString(
      '@echo off\r\n"${soffice.path}" %*\r\n',
      flush: true,
    );
    onProgress?.call(1, 'Ready');
    return soffice.path;
  }

  Future<void> _download(
    String url,
    String destPath,
    void Function(double fraction, String message)? onProgress,
  ) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Download failed HTTP ${response.statusCode} for $url');
    }
    final total = response.contentLength ?? 0;
    final sink = File(destPath).openWrite();
    var received = 0;
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) {
        final frac = 0.05 + 0.75 * (received / total);
        onProgress?.call(
          frac.clamp(0.0, 0.84),
          'Downloading LibreOffice… ${(100 * received / total).toStringAsFixed(0)}%',
        );
      }
    }
    await sink.close();
  }

  Future<String?> _findSoffice(Directory root) async {
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File && p.basename(entity.path).toLowerCase() == 'soffice.exe') {
        return entity.path;
      }
    }
    return null;
  }
}
