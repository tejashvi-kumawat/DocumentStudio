import 'dart:async';
import 'dart:io';

import 'package:document_studio/core/perf/perf_log.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Named areas inside the app's private storage box.
enum StorageArea {
  documents('documents', 'Working copies', isCache: false),
  thumbnails('cache/thumbnails', 'Page thumbnails', isCache: true),
  pages('cache/pages', 'Rendered pages', isCache: true),
  ocr('cache/ocr', 'OCR results', isCache: true),
  textIndex('cache/text-index', 'Text index', isCache: true),
  temp('temp', 'Temporary files', isCache: true),
  signatures('signatures', 'Saved signatures', isCache: false),
  stamps('stamps', 'Stamps', isCache: false),
  templates('templates', 'Templates', isCache: false),
  digitalIds('digital-ids', 'Digital IDs (encrypted)', isCache: false),
  ocrLanguages('ocr-languages', 'OCR languages', isCache: false),
  logs('logs', 'Logs', isCache: true),
  settings('settings', 'Settings', isCache: false);

  const StorageArea(this.relativePath, this.label, {required this.isCache});

  /// Path below the storage root (cache areas below the cache root).
  final String relativePath;
  final String label;

  /// Safe to delete at any time ("Clear cache").
  final bool isCache;
}

/// Single source of truth for where Document Studio keeps its own files.
///
/// Layout (root = `getApplicationSupportDirectory()`, which is already
/// per-app and inside the sandbox container on macOS/iOS/Android):
///
/// ```text
/// <root>/documents/        managed working copies
/// <root>/signatures/       saved visual signatures
/// <root>/stamps/           custom stamp images
/// <root>/templates/        user templates
/// <root>/digital-ids/      PKCS#12 identities (encrypted, 0700)
/// <root>/ocr-languages/    downloaded Tesseract traineddata
/// <root>/settings/         app settings files
/// <cache>/cache/thumbnails page thumbnails (LRU, size-capped)
/// <cache>/cache/pages      rendered page tiles (LRU, size-capped)
/// <cache>/cache/ocr        OCR results
/// <cache>/cache/text-index text index
/// <cache>/temp/            scratch dirs for tools (cleaned on start)
/// <cache>/logs/
/// ```
///
/// On desktop `<cache>` is `<root>`, so everything lives in one box. On
/// iOS/Android/macOS it is the platform cache directory, which is excluded
/// from backups and may be purged by the OS under storage pressure.
///
/// User documents opened from elsewhere are never copied here implicitly;
/// on sandboxed macOS/iOS access to them comes from the file picker's
/// security scope (see `macos/Runner/*.entitlements`).
class StoragePaths {
  StoragePaths._(this.root, this.cacheRoot);

  final Directory root;
  final Directory cacheRoot;

  static StoragePaths? _instance;

  /// Initialized in bootstrap; null only in tests / before [init].
  static StoragePaths? get maybeInstance => _instance;

  static StoragePaths get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('StoragePaths.init() has not completed');
    }
    return i;
  }

  static Future<StoragePaths>? _initFuture;

  /// Resolves platform directories and creates the folder structure.
  static Future<StoragePaths> init() => _initFuture ??= _init();

  static Future<StoragePaths> _init() async {
    final sw = Stopwatch()..start();
    final support = await getApplicationSupportDirectory();
    Directory cacheBase = support;
    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid || Platform.isMacOS)) {
      try {
        cacheBase = await getApplicationCacheDirectory();
      } catch (_) {}
    }
    final paths = StoragePaths._(support, cacheBase);
    for (final area in StorageArea.values) {
      final dir = paths.dir(area);
      if (!dir.existsSync()) dir.createSync(recursive: true);
    }
    _migrateLegacyLayout(paths);
    if (!Platform.isWindows) {
      // Spawning a process costs ~20–60 ms; keep it off the startup path.
      unawaited(
        Process.run('chmod', ['700', paths.dir(StorageArea.digitalIds).path])
            .then((_) {}, onError: (Object _) {}),
      );
    }
    _instance = paths;
    PerfLog.log('startup.storagePaths', sw.elapsed);
    return paths;
  }

  Directory dir(StorageArea area) {
    final base = area.isCache ? cacheRoot : root;
    return Directory(p.joinAll([base.path, ...area.relativePath.split('/')]));
  }

  Directory get documents => dir(StorageArea.documents);
  Directory get thumbnails => dir(StorageArea.thumbnails);
  Directory get pages => dir(StorageArea.pages);
  Directory get ocr => dir(StorageArea.ocr);
  Directory get textIndex => dir(StorageArea.textIndex);
  Directory get temp => dir(StorageArea.temp);
  Directory get signatures => dir(StorageArea.signatures);
  Directory get stamps => dir(StorageArea.stamps);
  Directory get templates => dir(StorageArea.templates);
  Directory get digitalIds => dir(StorageArea.digitalIds);
  Directory get ocrLanguages => dir(StorageArea.ocrLanguages);
  Directory get logs => dir(StorageArea.logs);
  Directory get settings => dir(StorageArea.settings);

  /// Scratch directory root for tools; falls back to the OS temp dir before
  /// [init] completes (e.g. unit tests).
  static Directory get tempRoot {
    final t = _instance?.temp;
    if (t == null) return Directory.systemTemp;
    if (!t.existsSync()) t.createSync(recursive: true);
    return t;
  }

  /// `temp/<prefix>XXXX` — delete it when the job finishes.
  static Future<Directory> createTempDir(String prefix) =>
      tempRoot.createTemp(prefix);

  /// Removes scratch entries left behind by earlier runs. Entries touched in
  /// the last hour are kept so a second running instance is never disturbed.
  Future<int> cleanTemp({Duration olderThan = const Duration(hours: 1)}) async {
    final cutoff = DateTime.now().subtract(olderThan);
    var removed = 0;
    try {
      await for (final e in temp.list(followLinks: false)) {
        try {
          final st = await e.stat();
          if (st.modified.isAfter(cutoff)) continue;
          await e.delete(recursive: true);
          removed++;
        } catch (_) {}
      }
    } catch (_) {}
    return removed;
  }

  /// Old builds kept digital IDs in `digital_ids/` and a single signature PNG
  /// at the root; move them into the new layout once.
  static void _migrateLegacyLayout(StoragePaths paths) {
    try {
      final legacyIds = Directory(p.join(paths.root.path, 'digital_ids'));
      final ids = paths.digitalIds;
      if (legacyIds.existsSync()) {
        final empty = !ids.existsSync() || ids.listSync().isEmpty;
        if (empty) {
          if (ids.existsSync()) ids.deleteSync();
          legacyIds.renameSync(ids.path);
        }
      }
    } catch (e) {
      debugPrint('Storage migration (digital IDs) skipped: $e');
    }
    try {
      // Pre-sandbox thumbnails from the Home page cache.
      final oldHomeThumbs =
          Directory(p.join(paths.cacheRoot.path, 'home_thumbnails'));
      if (oldHomeThumbs.existsSync()) {
        oldHomeThumbs.deleteSync(recursive: true);
      }
    } catch (_) {}
  }
}

/// Redirects `Directory.systemTemp` (used by tools and the bundled qpdf / OCR
/// packages for scratch dirs) into the app's own `temp/` folder, so every
/// intermediate file stays inside the storage box and is cleaned on start.
base class StorageIOOverrides extends IOOverrides {
  StorageIOOverrides(this._temp);

  final Directory _temp;

  @override
  Directory getSystemTempDirectory() {
    if (!_temp.existsSync()) {
      try {
        _temp.createSync(recursive: true);
      } catch (_) {
        return super.getSystemTempDirectory();
      }
    }
    return _temp;
  }
}
