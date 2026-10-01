import 'dart:io';

import 'package:document_studio/core/desktop/desktop_engine_resolver.dart';
import 'package:path/path.dart' as p;

/// A certificate the user can select for DSC signing (local only — never uploaded).
sealed class MachineCertificateSource {
  const MachineCertificateSource();

  String get displayLabel;
}

/// A `.p12` / `.pfx` file discovered under a common folder or picked by the user.
class P12CertificateSource extends MachineCertificateSource {
  const P12CertificateSource({
    required this.path,
    required this.displayName,
    this.fromScan = false,
  });

  final String path;
  final String displayName;
  final bool fromScan;

  @override
  String get displayLabel => displayName;
}

/// An NSS nickname from `~/.pki/nssdb` or a Firefox profile `cert9.db`.
class NssNicknameCertificateSource extends MachineCertificateSource {
  const NssNicknameCertificateSource({
    required this.nickname,
    required this.nssDir,
    required this.dbLabel,
  });

  final String nickname;

  /// Directory passed to `certutil -d sql:` / `pdfsig -nssdir` (contains cert9.db).
  final String nssDir;
  final String dbLabel;

  @override
  String get displayLabel => '$nickname ($dbLabel)';
}

/// Scans only well-known folders for PKCS#12 files and lists NSS nicknames.
///
/// Never walks the whole filesystem. Optional [extraFolder] is a single
/// user-chosen directory.
class MachineCertificateScanner {
  MachineCertificateScanner({
    DesktopEngineResolver? resolver,
    Future<ProcessResult> Function(String exe, List<String> args)? run,
    String? homeDirectory,
  })  : _resolver = resolver ?? desktopEngineResolver,
        _run = run ??
            ((exe, args) => Process.run(
                  exe,
                  args,
                  stdoutEncoding: systemEncoding,
                  stderrEncoding: systemEncoding,
                )),
        _home = homeDirectory ?? Platform.environment['HOME'];

  final DesktopEngineResolver _resolver;
  final Future<ProcessResult> Function(String exe, List<String> args) _run;
  final String? _home;

  static const _p12Extensions = {'.p12', '.pfx'};

  /// Common locations only (Documents, Downloads, ~/.pki) plus [extraFolder].
  Future<List<P12CertificateSource>> scanP12Files({String? extraFolder}) async {
    final home = _home;
    if (home == null || home.isEmpty) {
      return _scanDir(extraFolder);
    }
    final dirs = <String>[
      p.join(home, 'Documents'),
      p.join(home, 'Downloads'),
      p.join(home, '.pki'),
      if (extraFolder != null && extraFolder.trim().isNotEmpty) extraFolder.trim(),
    ];
    final seen = <String>{};
    final out = <P12CertificateSource>[];
    for (final dir in dirs) {
      for (final hit in await _scanDir(dir)) {
        if (seen.add(hit.path)) out.add(hit);
      }
    }
    out.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return out;
  }

  Future<List<P12CertificateSource>> _scanDir(String? dirPath) async {
    if (dirPath == null || dirPath.isEmpty) return const [];
    final dir = Directory(dirPath);
    if (!await dir.exists()) return const [];
    final out = <P12CertificateSource>[];
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (!_p12Extensions.contains(ext)) continue;
        out.add(
          P12CertificateSource(
            path: entity.path,
            displayName: p.basename(entity.path),
            fromScan: true,
          ),
        );
      }
    } catch (_) {
      // Permission / IO — skip that folder quietly.
    }
    return out;
  }

  /// NSS DBs we will query: `~/.pki/nssdb` and Firefox profiles with `cert9.db`.
  Future<List<NssNicknameCertificateSource>> listNssNicknames() async {
    final certutil = await _resolver.resolveCertutil();
    if (certutil == null) return const [];
    final dbs = await _discoverNssDirs();
    final out = <NssNicknameCertificateSource>[];
    for (final db in dbs) {
      final nicks = await _listNicknamesInDb(certutil, db.path);
      for (final nick in nicks) {
        out.add(
          NssNicknameCertificateSource(
            nickname: nick,
            nssDir: db.path,
            dbLabel: db.label,
          ),
        );
      }
    }
    return out;
  }

  Future<List<({String path, String label})>> _discoverNssDirs() async {
    final home = _home;
    if (home == null || home.isEmpty) return const [];
    final found = <({String path, String label})>[];
    final pki = p.join(home, '.pki', 'nssdb');
    if (await File(p.join(pki, 'cert9.db')).exists() ||
        await File(p.join(pki, 'cert8.db')).exists()) {
      found.add((path: pki, label: '~/.pki/nssdb'));
    }
    final firefox = Directory(p.join(home, '.mozilla', 'firefox'));
    if (await firefox.exists()) {
      try {
        await for (final entity in firefox.list(followLinks: false)) {
          if (entity is! Directory) continue;
          final cert9 = File(p.join(entity.path, 'cert9.db'));
          if (!await cert9.exists()) continue;
          found.add((
            path: entity.path,
            label: 'Firefox ${p.basename(entity.path)}',
          ));
        }
      } catch (_) {}
    }
    return found;
  }

  Future<List<String>> _listNicknamesInDb(String certutil, String nssDir) async {
    final r = await _run(certutil, ['-d', 'sql:$nssDir', '-L']);
    if (r.exitCode != 0) return const [];
    final lines = r.stdout.toString().split('\n');
    final nicks = <String>[];
    var pastHeader = false;
    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) continue;
      if (line.contains('Certificate Nickname') ||
          line.contains('Trust Attributes') ||
          line.contains('SSL,S/MIME')) {
        pastHeader = true;
        continue;
      }
      if (!pastHeader && line.startsWith('---')) continue;
      // Format: "<nickname padded>  trust,trust,trust"
      final match = RegExp(r'^(.+?)\s{2,}([uCpP],)').firstMatch(line);
      if (match != null) {
        final nick = match.group(1)!.trim();
        if (nick.isNotEmpty) nicks.add(nick);
        continue;
      }
      // Fallback: take everything before the last whitespace-separated trust blob.
      final parts = line.split(RegExp(r'\s{2,}'));
      if (parts.length >= 2) {
        final nick = parts.first.trim();
        if (nick.isNotEmpty && !nick.toLowerCase().contains('nickname')) {
          nicks.add(nick);
        }
      }
    }
    return nicks;
  }
}
