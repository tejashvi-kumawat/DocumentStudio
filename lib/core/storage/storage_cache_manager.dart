import 'dart:async';
import 'dart:io';
import 'dart:isolate';

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

  /// Disk caps for cache areas (LRU-trimmed to 80% when exceeded).
  static const Map<StorageArea, int> limits = {
    StorageArea.thumbnails: 128 * _mb,
    StorageArea.pages: 256 * _mb,
    // Searchable-PDF results of scans are large; keep a few recent ones.
    StorageArea.ocr: 256 * _mb,
    StorageArea.textIndex: 64 * _mb,
    StorageArea.logs: 16 * _mb,
  };

  final List<void Function()> _memoryCaches = [];

  /// In-memory caches (decoded thumbnails, …) that "Clear cache" also empties.
  void registerMemoryCache(void Function() clear) => _memoryCaches.add(clear);

  /// Cleans stale temp entries and enforces disk caps. Runs after startup.
  Future<void> startupMaintenance() async {
    final paths = StoragePaths.maybeInstance;
    if (paths == null) return;
    final sw = Stopwatch()..start();
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
