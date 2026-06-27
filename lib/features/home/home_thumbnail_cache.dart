import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:document_studio/core/pdf/pdf_document_cache.dart';
import 'package:document_studio/core/perf/render_budget.dart';
import 'package:document_studio/core/storage/disk_lru_cache.dart';
import 'package:document_studio/core/storage/linux_document_portal.dart';
import 'package:document_studio/core/storage/storage_cache_manager.dart';
import 'package:document_studio/core/storage/storage_paths.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

/// First-page preview + light metadata for a Home document card.
class HomeThumbnail {
  const HomeThumbnail({
    required this.modified,
    required this.sizeBytes,
    this.image,
    this.pageCount,
    this.locked = false,
  });

  /// Encoded JPEG of page 1 (null for non-PDFs and locked files).
  final Uint8List? image;
  final int? pageCount;
  final DateTime modified;
  final int sizeBytes;

  /// Password-protected PDF (no preview without the password).
  final bool locked;
}

/// Renders page 1 of recent PDFs once, then serves them from memory / disk.
///
/// Memory LRU → `cache/thumbnails` disk LRU (size-capped, cleared by
/// Settings › Clear cache) → render through the shared [PdfDocumentCache],
/// so a card the user then opens is already parsed. Keys include path, size,
/// mtime and render width, so edited files re-render. Renders run
/// newest-request-first and requests whose card scrolled away are skipped.
class HomeThumbnailCache {
  HomeThumbnailCache({double? renderWidth})
      : renderWidth = renderWidth ?? _adaptiveWidth() {
    StorageCacheManager.instance.registerMemoryCache(clear);
  }

  final double renderWidth;

  static final DiskLruCache _images = DiskLruCache(
    StorageArea.thumbnails,
    maxBytes: StorageCacheManager.limits[StorageArea.thumbnails]!,
    extension: 'jpg',
  );
  static final DiskLruCache _meta = DiskLruCache(
    StorageArea.thumbnails,
    maxBytes: StorageCacheManager.limits[StorageArea.thumbnails]!,
    extension: 'json',
  );

  final LinkedHashMap<String, HomeThumbnail> _memory = LinkedHashMap();
  int _memoryBytes = 0;
  final _inflight = <String, Future<HomeThumbnail?>>{};
  final _lastKeyByPath = <String, String>{};
  final _waiters = <Completer<void>>[];
  int _running = 0;

  /// Card previews are ~150 logical px wide; render for the display density,
  /// smaller on low-end devices.
  static double _adaptiveWidth() {
    final views = ui.PlatformDispatcher.instance.views;
    final dpr = views.isEmpty ? 1.0 : views.first.devicePixelRatio;
    final max = RenderBudget.current.tier == DeviceTier.low ? 240.0 : 400.0;
    return (170 * dpr).clamp(200.0, max);
  }

  /// Synchronous hit (no flicker when a card rebuilds).
  HomeThumbnail? peek(String path) => _memory[_lastKeyByPath[path]];

  /// [isWanted] is polled before rendering starts; return false once the
  /// requesting card is gone so off-screen work is skipped.
  Future<HomeThumbnail?> load(
    LocalFileRef file, {
    bool Function()? isWanted,
  }) async {
    final FileStat stat;
    try {
      stat = await File(file.path).stat();
    } on FileSystemException {
      return null;
    }
    if (stat.type == FileSystemEntityType.notFound) return null;

    final key = '${file.path}|${stat.size}|'
        '${stat.modified.millisecondsSinceEpoch}|${renderWidth.round()}';
    final hit = _memory.remove(key);
    if (hit != null) {
      _memory[key] = hit;
      return hit;
    }
    return _inflight[key] ??= _resolve(file, key, stat, isWanted)
        .whenComplete(() => _inflight.remove(key));
  }

  Future<HomeThumbnail?> _resolve(
    LocalFileRef file,
    String key,
    FileStat stat,
    bool Function()? isWanted,
  ) async {
    final meta = HomeThumbnail(modified: stat.modified, sizeBytes: stat.size);
    if (!file.isPdf) {
      _remember(file.path, key, meta);
      return meta;
    }
    final cached = await _fromDisk(key, stat);
    if (cached != null) {
      _remember(file.path, key, cached);
      return cached;
    }
    final rendered = await _render(file, key, stat, isWanted);
    if (rendered == null) return null;
    _remember(file.path, key, rendered);
    return rendered;
  }

  void _remember(String path, String key, HomeThumbnail t) {
    _lastKeyByPath[path] = key;
    final previous = _memory.remove(key);
    if (previous != null) _memoryBytes -= previous.image?.length ?? 0;
    _memory[key] = t;
    _memoryBytes += t.image?.length ?? 0;
    final cap = RenderBudget.current.thumbnailMemoryBytes ~/ 2;
    while ((_memoryBytes > cap || _memory.length > 200) &&
        _memory.length > 1) {
      final oldest = _memory.keys.first;
      _memoryBytes -= _memory.remove(oldest)!.image?.length ?? 0;
    }
  }

  Future<HomeThumbnail?> _fromDisk(String key, FileStat stat) async {
    final metaBytes = await _meta.read(key);
    if (metaBytes == null) return null;
    try {
      final json = jsonDecode(utf8.decode(metaBytes)) as Map<String, dynamic>;
      final locked = json['locked'] == true;
      final image = locked ? null : await _images.read(key);
      if (!locked && image == null) return null;
      return HomeThumbnail(
        modified: stat.modified,
        sizeBytes: stat.size,
        pageCount: json['pages'] as int?,
        locked: locked,
        image: image,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _slot() {
    if (_running < RenderBudget.current.renderConcurrency) {
      _running++;
      return Future.value();
    }
    final c = Completer<void>();
    _waiters.add(c);
    return c.future;
  }

  void _releaseSlot() {
    if (_waiters.isNotEmpty) {
      // LIFO: the most recently requested card is most likely on screen.
      _waiters.removeLast().complete();
    } else {
      _running--;
    }
  }

  Future<HomeThumbnail?> _render(
    LocalFileRef file,
    String key,
    FileStat stat,
    bool Function()? isWanted,
  ) async {
    await _slot();
    try {
      if (isWanted != null && !isWanted()) return null;
      var path = file.path;
      // Same rule as PdfDocumentCache: never open portal FUSE for a card.
      if (LinuxDocumentPortal.isPortalPath(path)) {
        path = await LinuxDocumentPortal.resolve(path);
      }
      final PdfDocumentLease lease;
      try {
        lease = await PdfDocumentCache.instance.acquire(path);
      } on PdfPasswordException {
        final t = HomeThumbnail(
          modified: stat.modified,
          sizeBytes: stat.size,
          locked: true,
        );
        unawaited(_writeDisk(key, t));
        return t;
      }
      try {
        final doc = lease.document;
        if (doc.pages.isEmpty) return null;
        final page = doc.pages.first;
        final scale = renderWidth / page.width;
        final image = await page.render(
          fullWidth: renderWidth,
          fullHeight: page.height * scale,
          backgroundColor: 0xFFFFFFFF,
        );
        if (image == null) return null;
        final w = image.width;
        final h = image.height;
        final bgra = Uint8List.fromList(image.pixels);
        image.dispose();
        final jpg = await Isolate.run(() {
          final frame = img.Image.fromBytes(
            width: w,
            height: h,
            bytes: bgra.buffer,
            order: img.ChannelOrder.bgra,
            numChannels: 4,
          );
          return Uint8List.fromList(img.encodeJpg(frame, quality: 82));
        });
        final t = HomeThumbnail(
          modified: stat.modified,
          sizeBytes: stat.size,
          image: jpg,
          pageCount: doc.pages.length,
        );
        unawaited(_writeDisk(key, t));
        return t;
      } finally {
        lease.release();
      }
    } catch (_) {
      return null;
    } finally {
      _releaseSlot();
    }
  }

  Future<void> _writeDisk(String key, HomeThumbnail t) async {
    final image = t.image;
    if (image != null) await _images.write(key, image);
    await _meta.write(
      key,
      Uint8List.fromList(
        utf8.encode(jsonEncode({'pages': t.pageCount, 'locked': t.locked})),
      ),
    );
  }

  void clear() {
    _memory.clear();
    _lastKeyByPath.clear();
    _memoryBytes = 0;
  }
}

final homeThumbnailCacheProvider = Provider<HomeThumbnailCache>(
  (ref) => HomeThumbnailCache(),
);
