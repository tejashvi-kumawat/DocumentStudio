import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

const _customModulesKey = 'ds_pkcs11_custom_modules_v1';

/// Common PKCS#11 module filenames / paths across Linux and macOS.
const kBuiltinPkcs11Candidates = <String>[
  // p11-kit proxy aggregates trust + tokens
  '/usr/lib/x86_64-linux-gnu/p11-kit-proxy.so',
  '/usr/lib/p11-kit-proxy.so',
  '/usr/lib64/p11-kit-proxy.so',
  '/opt/homebrew/lib/p11-kit-proxy.dylib',
  '/usr/local/lib/p11-kit-proxy.dylib',
  // OpenSC
  '/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so',
  '/usr/lib/opensc-pkcs11.so',
  '/usr/lib64/opensc-pkcs11.so',
  '/usr/lib/x86_64-linux-gnu/pkcs11/opensc-pkcs11.so',
  '/Library/OpenSC/lib/opensc-pkcs11.so',
  '/opt/homebrew/lib/opensc-pkcs11.so',
  // SafeNet / Gemalto eToken
  '/usr/lib/libeTPkcs11.so',
  '/usr/lib64/libeTPkcs11.so',
  '/usr/lib/x86_64-linux-gnu/libeTPkcs11.so',
  // Feitian / castle
  '/usr/lib/libcastle.so',
  '/usr/lib64/libcastle.so',
  '/usr/lib/libcastle.1.0.0.so',
  // Feitian ePass2003
  '/usr/lib/libeps2003csp11.so',
  '/usr/lib/libePass2003CSP11.so',
  '/usr/lib64/libeps2003csp11.so',
  // NSS softokn (used with nssParams for ~/.pki/nssdb)
  '/usr/lib/x86_64-linux-gnu/libsoftokn3.so',
  '/usr/lib/libsoftokn3.so',
  '/usr/lib64/libsoftokn3.so',
  '/usr/lib/x86_64-linux-gnu/nss/libsoftokn3.so',
];

/// Discover PKCS#11 module paths: p11-kit modules, common vendor paths, user-added.
class Pkcs11Modules {
  /// Paths the user added via the drivers dialog.
  static Future<List<String>> loadCustomPaths() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_customModulesKey) ?? const [];
  }

  static Future<void> saveCustomPaths(List<String> paths) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned =
        paths.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList()
          ..sort();
    await prefs.setStringList(_customModulesKey, cleaned);
  }

  static Future<void> addCustomPath(String path) async {
    final list = [...await loadCustomPaths(), path.trim()];
    await saveCustomPaths(list);
  }

  static Future<void> removeCustomPath(String path) async {
    final list = await loadCustomPaths();
    list.removeWhere((e) => e == path);
    await saveCustomPaths(list);
  }

  /// Absolute paths that currently exist on disk (deduped, order preserved).
  static Future<List<String>> discoverModulePaths() async {
    final seen = <String>{};
    final out = <String>[];

    void add(String path) {
      final n = p.normalize(path);
      if (seen.add(n) && File(n).existsSync()) out.add(n);
    }

    for (final m in _p11KitModules()) {
      add(m);
    }
    for (final c in kBuiltinPkcs11Candidates) {
      add(c);
    }
    // Also scan common pkcs11 dirs.
    for (final dir in const [
      '/usr/lib/x86_64-linux-gnu/pkcs11',
      '/usr/lib/pkcs11',
      '/usr/lib64/pkcs11',
      '/usr/local/lib/pkcs11',
    ]) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      for (final ent in d.listSync()) {
        if (ent is File &&
            (ent.path.endsWith('.so') || ent.path.endsWith('.dylib'))) {
          add(ent.path);
        }
      }
    }
    for (final c in await loadCustomPaths()) {
      add(c);
    }
    return out;
  }

  static List<String> _p11KitModules() {
    final out = <String>[];
    const dirs = [
      '/usr/share/p11-kit/modules',
      '/etc/pkcs11/modules',
      '/usr/local/share/p11-kit/modules',
    ];
    for (final dir in dirs) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      for (final ent in d.listSync()) {
        if (ent is! File || !ent.path.endsWith('.module')) continue;
        try {
          for (final line in ent.readAsLinesSync()) {
            final t = line.trim();
            if (t.toLowerCase().startsWith('module:')) {
              final mod = t.substring(7).trim();
              if (mod.isEmpty) continue;
              if (p.isAbsolute(mod)) {
                out.add(mod);
              } else {
                // Relative module names are loaded via p11-kit-proxy.
                out.add(mod);
              }
            }
          }
        } catch (_) {}
      }
    }
    return out;
  }

  /// Softoken path for NSS databases, if present.
  static String? softoknPath() {
    for (final c in kBuiltinPkcs11Candidates) {
      if (c.contains('libsoftokn3') && File(c).existsSync()) return c;
    }
    return null;
  }
}

/// Build Softoken configdir string for an NSS DB directory.
String nssReadOnlyParams(String dbDir) =>
    "configdir='sql:$dbDir' certPrefix='' keyPrefix='' secmod='secmod.db' flags=readOnly";

/// Likely NSS DB directories on this machine (Chrome, Firefox, Thunderbird).
List<String> discoverNssDbDirs() {
  final home = Platform.environment['HOME'] ?? '';
  if (home.isEmpty) return const [];
  final candidates = <String>[
    p.join(home, '.pki', 'nssdb'),
    p.join(home, 'snap', 'firefox', 'common', '.mozilla', 'firefox'),
    p.join(home, '.mozilla', 'firefox'),
    p.join(home, '.thunderbird'),
    p.join(home, 'snap', 'chromium', 'common', '.pki', 'nssdb'),
    p.join(home, '.var', 'app', 'org.mozilla.firefox', '.mozilla', 'firefox'),
  ];
  final out = <String>[];
  for (final c in candidates) {
    final d = Directory(c);
    if (!d.existsSync()) continue;
    // Direct nssdb
    if (File(p.join(c, 'cert9.db')).existsSync() ||
        File(p.join(c, 'cert8.db')).existsSync()) {
      out.add(c);
      continue;
    }
    // Firefox profiles root
    try {
      for (final ent in d.listSync()) {
        if (ent is! Directory) continue;
        if (File(p.join(ent.path, 'cert9.db')).existsSync() ||
            File(p.join(ent.path, 'cert8.db')).existsSync()) {
          out.add(ent.path);
        }
      }
    } catch (_) {}
  }
  return out;
}
