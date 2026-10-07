import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:document_studio/core/isolate/run_isolated.dart';
import 'package:document_studio/core/pdf/pdf_document_cache.dart';
import 'package:document_studio/core/perf/render_budget.dart';
import 'package:document_studio/core/storage/disk_lru_cache.dart';
import 'package:document_studio/core/storage/linux_document_portal.dart';
import 'package:document_studio/core/storage/storage_cache_manager.dart';
import 'package:document_studio/core/storage/storage_paths.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/page_management/page_thumb_render_gate.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

/// PNG-encode a BGRA thumbnail off the UI isolate.
///
/// Top-level so the isolate closure does not capture a cache instance
/// (`object is unsendable`).
Uint8List encodePageThumbnailPng((int width, int height, Uint8List bgra) args) {
  final (width, height, bgra) = args;
  final frame = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: bgra.buffer,
    bytesOffset: bgra.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.bgra,
  );
  return Uint8List.fromList(img.encodePng(frame, level: 1));
}

/// In-flight thumbnail the caller can drop when its cell scrolls away.
class PageThumbJob {
  PageThumbJob(
    this.future,
    this._cancel, {
    required this._isDecoding,
    required this._listen,
    required this._unlisten,
  });

  final Future<Uint8List?> future;
  final void Function() _cancel;
  final bool Function() _isDecoding;
  final void Function(void Function() listener) _listen;
  final void Function(void Function() listener) _unlisten;
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  /// True only while this page's decode holds a render slot.
  bool get isDecoding => _isDecoding();

  void addListener(void Function() listener) => _listen(listener);

  void removeListener(void Function() listener) => _unlisten(listener);

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancel();
  }
}

/// Page thumbnails (PNG) for the workspace / organize grids.
///
/// Memory LRU → disk LRU → one shared [PdfDocumentCache] open. Only pages
/// a caller still wants are rendered, at most 2–3 at a time, at the requested
/// pixel width (never the full page). [PdfDocumentCache.use] is always called
/// with `loadAllPages: false`.
class PageThumbnailCache {
  PageThumbnailCache({PageThumbRenderGate? gate})
    : _gate = gate ?? _defaultGate() {
    StorageCacheManager.instance.registerMemoryCache(clear);
  }

  static PageThumbRenderGate _defaultGate() {
    final budget = RenderBudget.current;
    final hinted = budget.tier == DeviceTier.high
        ? 3
        : budget.renderConcurrency;
    return PageThumbRenderGate(concurrency: clampThumbnailConcurrency(hinted));
  }

  static final DiskLruCache _disk = DiskLruCache(
    StorageArea.thumbnails,
    maxBytes: StorageCacheManager.limits[StorageArea.thumbnails]!,
    extension: 'png',
  );

  final PageThumbRenderGate _gate;
  final LinkedHashMap<String, Uint8List> _memory = LinkedHashMap();
  int _memoryBytes = 0;
  final Map<String, String> _lastKeyByIdentity = {};
  final Map<String, _ThumbSession> _sessions = {};
  final Map<String, Future<String>> _hostInflight = {};
  final Map<String, Future<String>> _versionInflight = {};
  final Map<String, _VersionMemo> _versionMemo = {};

  static const _versionTtl = Duration(seconds: 2);
  static const _maxEdge = 1600.0;

  static String _identity(LocalFileRef file, int page1, String? password) =>
      '${file.path}#$page1#${password ?? ''}';

  /// Sync memory hit for the last successful render of this page.
  Uint8List? peek(LocalFileRef file, int pageNumber1Based, {String? password}) {
    final id = _identity(file, pageNumber1Based, password);
    final last = _lastKeyByIdentity[id];
    if (last == null) return null;
    final hit = _memory.remove(last);
    if (hit == null) return null;
    _memory[last] = hit;
    return hit;
  }

  /// Starts a render. Cancel the job when the cell leaves the prefetch window.
  PageThumbJob begin(
    LocalFileRef file,
    int pageNumber1Based, {
    double scale = 0.2,
    double? targetWidthPx,
    String? password,
    int priority = 0,
  }) {
    final sizeToken = targetWidthPx != null
        ? 'w${targetWidthPx.round()}'
        : 's${scale.toStringAsFixed(3)}';
    final group = '${file.path}#$pageNumber1Based#${password ?? ''}@$sizeToken';
    final completer = Completer<Uint8List?>();
    final existing = _sessions[group];
    if (existing != null && !existing.done) {
      existing.add(completer, priority);
      final permit = existing.permit;
      if (permit != null) _gate.reprioritize(permit, existing.priority);
      return PageThumbJob(
        completer.future,
        () => existing.remove(completer),
        isDecoding: () => existing.decoding,
        listen: existing.decodeListeners.add,
        unlisten: existing.decodeListeners.remove,
      );
    }
    final session = _ThumbSession(group)..add(completer, priority);
    _sessions[group] = session;
    unawaited(
      _run(
        session,
        file,
        pageNumber1Based,
        scale,
        targetWidthPx,
        password,
        sizeToken,
      ),
    );
    return PageThumbJob(
      completer.future,
      () => session.remove(completer),
      isDecoding: () => session.decoding,
      listen: session.decodeListeners.add,
      unlisten: session.decodeListeners.remove,
    );
  }

  /// Render one page. Prefer [begin] when the caller can cancel.
  Future<Uint8List?> render(
    LocalFileRef file,
    int pageNumber1Based, {
    double scale = 0.2,
    double? targetWidthPx,
    String? password,
    int priority = 0,
  }) {
    return begin(
      file,
      pageNumber1Based,
      scale: scale,
      targetWidthPx: targetWidthPx,
      password: password,
      priority: priority,
    ).future;
  }

  Future<void> _run(
    _ThumbSession session,
    LocalFileRef file,
    int page1,
    double scale,
    double? targetWidthPx,
    String? password,
    String sizeToken,
  ) async {
    try {
      final host = await _hostPath(file.path);
      if (session.abandoned) return;
      final resolved = host == file.path ? file : file.copyWithPath(host);
      final version = await _version(resolved.path);
      if (session.abandoned) return;
      if (version == null) {
        session.deliver(null);
        return;
      }
      final key = '$version#$page1@$sizeToken';
      final id = _identity(file, page1, password);
      final mem = _takeMemory(key);
      if (mem != null) {
        _lastKeyByIdentity[id] = key;
        session.deliver(mem);
        return;
      }
      final fromDisk = await _disk.read(key);
      if (session.abandoned) return;
      if (fromDisk != null) {
        _remember(key, fromDisk, id);
        session.deliver(fromDisk);
        return;
      }

      final permit = _gate.acquire(priority: session.priority);
      session.permit = permit;
      await permit.ready;
      if (permit.isCancelled || session.abandoned) return;
      session.setDecoding(true);
      try {
        final png = await _renderOne(
          session,
          resolved,
          page1,
          scale,
          targetWidthPx,
          password,
        );
        if (png != null) {
          _remember(key, png, id);
          unawaited(_disk.write(key, png));
        }
        if (session.abandoned) return;
        session.deliver(png);
      } finally {
        session.setDecoding(false);
        permit.release();
      }
    } catch (_) {
      session.deliver(null);
    } finally {
      if (identical(_sessions[session.groupKey], session)) {
        _sessions.remove(session.groupKey);
      }
    }
  }

  Future<Uint8List?> _renderOne(
    _ThumbSession session,
    LocalFileRef file,
    int page1,
    double scale,
    double? targetWidthPx,
    String? password,
  ) {
    return PdfDocumentCache.instance.use(
      file.path,
      (doc) async {
        if (session.abandoned) return null;
        if (page1 < 1 || page1 > doc.pages.length) return null;
        final page = doc.pages[page1 - 1];
        if (!page.isLoaded) {
          await doc.reloadPages(pageNumbersToReload: [page1]);
        }
        if (session.abandoned) return null;
        final fresh = doc.pages[page1 - 1];
        final size = _outputSize(
          fresh.width,
          fresh.height,
          targetWidthPx,
          scale,
        );
        final token = fresh.createCancellationToken();
        session.token = token;
        final pdfImage = await fresh.render(
          fullWidth: size.$1,
          fullHeight: size.$2,
          backgroundColor: 0xFFFFFFFF,
          cancellationToken: token,
        );
        if (pdfImage == null) return null;
        final w = pdfImage.width;
        final h = pdfImage.height;
        Uint8List bgra;
        try {
          if (w < 1 || h < 1 || w > _maxEdge || h > _maxEdge) return null;
          bgra = Uint8List.fromList(pdfImage.pixels);
        } finally {
          pdfImage.dispose();
        }
        if (session.abandoned) return null;
        return runIsolated(encodePageThumbnailPng, (
          w,
          h,
          bgra,
        ), debugName: 'thumb-png');
      },
      password: password,
      loadAllPages: false,
    );
  }

  /// Decode size is the requested pixel width, capped so a bad page box
  /// cannot allocate a full-page bitmap.
  static (double, double) _outputSize(
    double pageW,
    double pageH,
    double? targetWidthPx,
    double scale,
  ) {
    final havePage = pageW > 1 && pageH > 1;
    var outW = (targetWidthPx != null && havePage)
        ? targetWidthPx
        : (havePage ? pageW * scale : (targetWidthPx ?? 128));
    var outH = havePage ? pageH * (outW / pageW) : outW * 1.3;
    if (outW > _maxEdge || outH > _maxEdge) {
      final edge = outW > outH ? outW : outH;
      final fit = _maxEdge / edge;
      outW *= fit;
      outH *= fit;
    }
    if (outW < 1) outW = 1;
    if (outH < 1) outH = 1;
    return (outW, outH);
  }

  Future<String> _hostPath(String path) {
    if (!LinuxDocumentPortal.isPortalPath(path)) return Future.value(path);
    final existing = _hostInflight[path];
    if (existing != null) return existing;
    late final Future<String> fut;
    fut = LinuxDocumentPortal.resolve(path).then(
      (host) {
        if (host == path && identical(_hostInflight[path], fut)) {
          _hostInflight.remove(path);
        }
        return host;
      },
      onError: (Object _) {
        if (identical(_hostInflight[path], fut)) _hostInflight.remove(path);
        return path;
      },
    );
    _hostInflight[path] = fut;
    return fut;
  }

  Future<String?> _version(String path) async {
    final memo = _versionMemo[path];
    if (memo != null && DateTime.now().difference(memo.at) < _versionTtl) {
      return memo.value;
    }
    final pending = _versionInflight[path];
    if (pending != null) {
      try {
        return await pending;
      } catch (_) {
        return null;
      }
    }
    final fut = PdfDocumentCache.versionOf(path);
    _versionInflight[path] = fut;
    try {
      final value = await fut;
      _versionMemo[path] = _VersionMemo(value, DateTime.now());
      return value;
    } catch (_) {
      return null;
    } finally {
      if (identical(_versionInflight[path], fut)) _versionInflight.remove(path);
    }
  }

  Uint8List? _takeMemory(String key) {
    final hit = _memory.remove(key);
    if (hit == null) return null;
    _memory[key] = hit;
    return hit;
  }

  void _remember(String key, Uint8List png, String id) {
    final previous = _memory.remove(key);
    if (previous != null) _memoryBytes -= previous.length;
    _memory[key] = png;
    _memoryBytes += png.length;
    _lastKeyByIdentity[id] = key;
    final cap = RenderBudget.current.thumbnailMemoryBytes;
    while (_memoryBytes > cap && _memory.length > 1) {
      final oldest = _memory.keys.first;
      _memoryBytes -= _memory.remove(oldest)!.length;
    }
  }

  void clear() {
    _memory.clear();
    _memoryBytes = 0;
    _lastKeyByIdentity.clear();
    _versionMemo.clear();
    _hostInflight.clear();
  }
}

class _VersionMemo {
  _VersionMemo(this.value, this.at);

  final String value;
  final DateTime at;
}

class _ThumbSession {
  _ThumbSession(this.groupKey);

  final String groupKey;
  int priority = 0;
  int listeners = 0;
  bool done = false;
  bool abandoned = false;
  bool decoding = false;
  PageThumbPermit? permit;
  PdfPageRenderCancellationToken? token;
  final List<Completer<Uint8List?>> waiters = [];
  final List<void Function()> decodeListeners = [];

  void setDecoding(bool value) {
    if (decoding == value) return;
    decoding = value;
    for (final listener in List<void Function()>.of(decodeListeners)) {
      listener();
    }
  }

  void add(Completer<Uint8List?> waiter, int priority) {
    listeners++;
    if (priority > this.priority) this.priority = priority;
    waiters.add(waiter);
  }

  void remove(Completer<Uint8List?> waiter) {
    listeners--;
    if (!waiter.isCompleted) waiter.complete(null);
    waiters.remove(waiter);
    if (listeners <= 0) {
      abandoned = true;
      permit?.cancel();
      final renderToken = token;
      if (renderToken != null) renderToken.cancel();
    }
  }

  void deliver(Uint8List? png) {
    if (done) return;
    done = true;
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete(png);
    }
    waiters.clear();
  }
}
