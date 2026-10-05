import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:document_studio/core/pdf/pdf_document_cache.dart';
import 'package:document_studio/core/perf/perf_log.dart';
import 'package:document_studio/core/storage/disk_lru_cache.dart';
import 'package:document_studio/core/storage/storage_paths.dart';
import 'package:flutter/painting.dart';

/// Per-area disk usage for Settings › Storage.
class StorageUsage {
  const StorageUsage(this.bytesByArea, this.rootPath, this.cacheRootPath);

  final Map<StorageArea, int> bytesByArea;
  final String rootPath;
  final String cacheRootPath;

  int get total => bytesByArea.values.fold(0, (a, b) => a + b);

  int get cacheTotal => bytesByArea.entries
      .where((e) => e.key.isCache)
      .fold(0, (a, e) => a + e.value);
}

/// Size limits, LRU eviction, usage reporting and "Clear cache".
class StorageCacheManager {
  StorageCacheManager._();

  static final StorageCacheManager instance = StorageCacheManager._();

  static const _mb = 1024 * 1024;

  static const _gb = 1024 * _mb;

  /// SharedPreferences key: user cache budget in GB, 0 / absent = automatic.
  static const budgetPrefKey = 'cache_budget_gb_v1';

  /// Total disk budget for caches. Automatic = 20% of free space, 1–7 GB.
  static int budgetBytes = 6 * _gb;

  /// Applies the user setting ([gb] 0 = auto) against [freeBytes] of disk.
  static void configure({required int gb, int? freeBytes}) {
    final free = freeBytes;
    var b = gb > 0 ? gb * _gb : (free == null ? 6 * _gb : (free ~/ 5));
    if (gb <= 0) b = b.clamp(1 * _gb, 7 * _gb);
    if (free != null && b > free ~/ 2) b = math.max(512 * _mb, free ~/ 2);
    budgetBytes = b;
  }

  /// Free bytes on the volume holding [path], or null when unknown.
  static Future<int?> freeDiskBytes(String path) async {
    try {
      if (Platform.isWindows) {
        final drive = path.length > 1 && path[1] == ':' ? path[0] : 'C';
        final r = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          '(Get-PSDrive -Name $drive).Free',
        ]);
        return int.tryParse(r.stdout.toString().trim());
      }
      final r = await Process.run('df', ['-Pk', path]);
      final lines = r.stdout.toString().trim().split('\n');
      if (lines.length < 2) return null;
      final cols = lines.last.split(RegExp(r'\s+'));
      final kb = int.tryParse(cols[3]);
      return kb == null ? null : kb * 1024;
    } catch (_) {
      return null;
    }
  }

  /// Disk caps for cache areas (LRU-trimmed to 80% when exceeded), carved out
  /// of [budgetBytes].
  static Map<StorageArea, int> get limits => {
        StorageArea.thumbnails: budgetBytes ~/ 10,
        StorageArea.pages: budgetBytes * 4 ~/ 10,
        // Searchable-PDF results of scans are large.
        StorageArea.ocr: budgetBytes * 4 ~/ 10,
        StorageArea.textIndex: budgetBytes ~/ 10,
        StorageArea.logs: 32 * _mb,
      };

  static int _userGb = 0;

  /// Called at startup and when the user changes the budget in Settings.
  static void setUserGb(int gb) => _userGb = gb;

  final List<void Function()> _memoryCaches = [];

  /// In-memory caches (decoded thumbnails, …) that "Clear cache" also empties.
  void registerMemoryCache(void Function() clear) => _memoryCaches.add(clear);

  /// Cleans stale temp entries and enforces disk caps. Runs after startup.
  Future<void> startupMaintenance() async {
    final paths = StoragePaths.maybeInstance;
    if (paths == null) return;
    final sw = Stopwatch()..start();
    configure(
      gb: _userGb,
      freeBytes: await freeDiskBytes(paths.root.path),
    );
    final removed = await paths.cleanTemp();
    var freed = 0;
    for (final e in limits.entries) {
      freed += await trimDirectoryLru(paths.dir(e.key).path, e.value);
    }
    PerfLog.log(
      'storage.maintenance (temp entries removed: $removed, '
      'cache freed: ${freed ~/ 1024} KB)',
      sw.elapsed,
    );
  }

  Future<StorageUsage?> usage() async {
    final paths = StoragePaths.maybeInstance ?? await StoragePaths.init();
    final dirs = {
      for (final a in StorageArea.values) a.index: paths.dir(a).path,
    };
    final sizes = await Isolate.run(() {
      final out = <int, int>{};
      for (final e in dirs.entries) {
        var total = 0;
        final d = Directory(e.value);
        if (d.existsSync()) {
          try {
            for (final f in d.listSync(recursive: true, followLinks: false)) {
              if (f is File) {
                try {
                  total += f.lengthSync();
                } catch (_) {}
              }
            }
          } catch (_) {}
        }
        out[e.key] = total;
      }
      return out;
    });
    // Nested areas (cache/…) are listed separately, not double-counted: no
    // area directory contains another one.
    return StorageUsage(
      {for (final e in sizes.entries) StorageArea.values[e.key]: e.value},
      paths.root.path,
      paths.cacheRoot.path,
    );
  }

  /// Deletes every cache area. Temp entries younger than 10 minutes survive
  /// (a running tool may still be writing there).
  Future<void> clearCaches() async {
    final paths = StoragePaths.maybeInstance ?? await StoragePaths.init();
    for (final area in StorageArea.values) {
      if (!area.isCache || area == StorageArea.temp) continue;
      final dir = paths.dir(area);
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
        await dir.create(recursive: true);
      } catch (_) {}
    }
    await paths.cleanTemp(olderThan: const Duration(minutes: 10));
    for (final clear in _memoryCaches) {
      try {
        clear();
      } catch (_) {}
    }
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    PdfDocumentCache.instance.trimIdle();
  }
}
