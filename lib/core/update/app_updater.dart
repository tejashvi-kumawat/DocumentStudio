import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:document_studio/app/app_version.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

/// A newer release on GitHub and the installer asset for this platform.
class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.tag,
    required this.notes,
    required this.pageUrl,
    this.assetName,
    this.assetUrl,
    this.assetSize,
    this.sha256,
  });

  final String version;
  final String tag;
  final String notes;
  final String pageUrl;
  final String? assetName;
  final String? assetUrl;
  final int? assetSize;

  /// From the release asset's `digest` (GitHub publishes it); verified after
  /// download when present.
  final String? sha256;

  bool get canInstall => assetUrl != null;
}

/// Checks GitHub Releases for a newer version and installs it:
///
/// * Windows — downloads `…-Setup.exe` (Inno Setup), verifies it, runs it
///   silently (`/SILENT /SUPPRESSMSGBOXES /NORESTART /SP-
///   /CLOSEAPPLICATIONS`), quits so files can be replaced, and starts the
///   new version when the installer is done.
/// * macOS — downloads the `.dmg` and opens it.
/// * Linux — downloads the `.deb` and opens it with the system installer.
///
/// Same release assets WinGet / Homebrew use — nothing else is hosted.
class AppUpdater {
  AppUpdater._();
  static final AppUpdater instance = AppUpdater._();

  static const _api =
      'https://api.github.com/repos/$kGithubOwner/$kGithubRepo/releases/latest';

  final ValueNotifier<AppUpdate?> available = ValueNotifier(null);

  /// Installed version (package metadata; falls back to [kAppVersion]).
  Future<String> currentVersion() async {
    try {
      final v = (await PackageInfo.fromPlatform()).version;
      if (v.isNotEmpty) return v;
    } catch (_) {}
    return kAppVersion;
  }

  /// Newer release, or null when up to date / offline.
  Future<AppUpdate?> check({Duration timeout = const Duration(seconds: 12)}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(Uri.parse(_api));
      req.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'DocumentStudio-Updater');
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      final j = jsonDecode(body) as Map<String, dynamic>;
      if (j['draft'] == true || j['prerelease'] == true) return null;
      final tag = (j['tag_name'] as String?) ?? '';
      final version = tag.replaceFirst(RegExp(r'^[vV]'), '');
      if (compareVersions(version, await currentVersion()) <= 0) {
        available.value = null;
        return null;
      }
      final asset = _assetFor(
        (j['assets'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>(),
      );
      final digest = asset?['digest'] as String?;
      final update = AppUpdate(
        version: version,
        tag: tag,
        notes: (j['body'] as String?) ?? '',
        pageUrl: (j['html_url'] as String?) ?? kReleasesUrl,
        assetName: asset?['name'] as String?,
        assetUrl: asset?['browser_download_url'] as String?,
        assetSize: (asset?['size'] as num?)?.toInt(),
        sha256: digest != null && digest.startsWith('sha256:')
            ? digest.substring(7).toLowerCase()
            : null,
      );
      available.value = update;
      return update;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, dynamic>? _assetFor(List<Map<String, dynamic>> assets) {
    bool ends(Map<String, dynamic> a, String s) =>
        ((a['name'] as String?) ?? '').toLowerCase().endsWith(s);
    Map<String, dynamic>? first(bool Function(Map<String, dynamic>) f) {
      for (final a in assets) {
        if (f(a)) return a;
      }
      return null;
    }

    if (Platform.isWindows) return first((a) => ends(a, '-setup.exe'));
    if (Platform.isMacOS) return first((a) => ends(a, '.dmg'));
    if (Platform.isLinux) {
      return first((a) => ends(a, '_amd64.deb')) ??
          first((a) => ends(a, '.appimage'));
    }
    return null;
  }

  /// Downloads the installer ([onProgress] 0..1), verifies size and SHA-256,
  /// then hands over to it. Returns an error message, or null on success
  /// (on Windows the app exits right after starting the installer).
  Future<String?> downloadAndInstall(
    AppUpdate u, {
    void Function(double fraction)? onProgress,
    bool Function()? cancelled,
  }) async {
    final url = u.assetUrl;
    if (url == null) return 'No installer for this system in the release.';
    final dir = await Directory.systemTemp.createTemp('ds_update_');
    final file = File(p.join(dir.path, u.assetName ?? 'update'));
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, 'DocumentStudio-Updater');
      final res = await req.close();
      if (res.statusCode != 200) return 'Download failed (${res.statusCode}).';
      final total = res.contentLength > 0 ? res.contentLength : (u.assetSize ?? 0);
      final sink = file.openWrite();
      final hashOut = _DigestSink();
      final hasher = sha256.startChunkedConversion(hashOut);
      var got = 0;
      await for (final chunk in res) {
        if (cancelled?.call() ?? false) {
          await sink.close();
          return 'Cancelled.';
        }
        sink.add(chunk);
        hasher.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress?.call(got / total);
      }
      await sink.close();
      hasher.close();
      if (u.assetSize != null && got != u.assetSize) {
        return 'The download is incomplete. Try again.';
      }
      final digest = hashOut.value.toString();
      if (u.sha256 != null && digest != u.sha256) {
        return 'The download did not match the published checksum. '
            'Nothing was installed.';
      }
      return await _launch(file);
    } catch (e) {
      return 'Update failed: $e';
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> _launch(File installer) async {
    if (Platform.isWindows) {
      // A tiny script waits for the silent install, then starts the new
      // version (the installer's own launch is skipped in silent mode).
      final exe = Platform.resolvedExecutable;
      final script = File(p.join(installer.parent.path, 'update.cmd'));
      await script.writeAsString(
        '@echo off\r\n'
        'start "" /wait "${installer.path}" /SILENT /SUPPRESSMSGBOXES '
        '/NORESTART /SP- /CLOSEAPPLICATIONS\r\n'
        'start "" "$exe"\r\n',
      );
      await Process.start(
        'cmd',
        ['/c', script.path],
        mode: ProcessStartMode.detached,
      );
      // Quit so the installer can replace our files.
      Timer(const Duration(milliseconds: 600), () => exit(0));
      return null;
    }
    if (Platform.isMacOS) {
      await Process.run('open', [installer.path]);
      return null;
    }
    if (Platform.isLinux) {
      if (installer.path.toLowerCase().endsWith('.appimage')) {
        await Process.run('chmod', ['+x', installer.path]);
      }
      await Process.run('xdg-open', [installer.path]);
      return null;
    }
    return 'Updating is not supported on this system.';
  }
}

/// Semantic-version compare (`1.10.0` > `1.9.2`); extra labels ignored.
int compareVersions(String a, String b) {
  List<int> parts(String v) => [
        for (final s in v.split(RegExp(r'[.+-]')).take(3))
          int.tryParse(s) ?? 0,
      ];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final xi = i < x.length ? x[i] : 0;
    final yi = i < y.length ? y[i] : 0;
    if (xi != yi) return xi.compareTo(yi);
  }
  return 0;
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
