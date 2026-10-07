import 'dart:async';
import 'dart:io';

import 'package:document_studio/core/perf/perf_log.dart';
import 'package:document_studio/core/storage/linux_document_portal.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

/// A reference-counted handle on a shared [PdfDocument].
///
/// Call [release] exactly once when done; the document stays open while any
/// lease is alive and for a short idle period afterwards so re-opening the same
/// file (tab switch, tool panel, validation → viewer) is free.
class PdfDocumentLease {
  PdfDocumentLease._(this._cache, this._entry);

  final PdfDocumentCache _cache;
  final _DocEntry _entry;
  bool _released = false;

  PdfDocument get document => _entry.document!;

  /// `path|size:mtime` — changes whenever the file bytes on disk change.
  String get version => _entry.version;

  String get path => _entry.path;

  bool get isReleased => _released;

  /// Loads real sizes for every page (progressive open only measures page 1).
  Future<void> ensureAllPagesLoaded() => _entry.ensureAllPagesLoaded();

  void release() {
    if (_released) return;
    _released = true;
    _cache._release(_entry);
  }
}

class _DocEntry {
  _DocEntry(this.key, this.path, this.version);

  final String key;
  final String path;
  final String version;
  late final Future<PdfDocument> opening;
  PdfDocument? document;
  int refs = 0;
  Timer? idleTimer;
  int lastUsedUs = 0;
  bool disposed = false;
  Future<void>? _allPages;

  Future<void> ensureAllPagesLoaded() {
    final doc = document;
    if (doc == null || doc.pages.every((pg) => pg.isLoaded)) {
      return Future.value();
    }
    return _allPages ??= PerfLog.time(
      'pdf.loadAllPages ${p.basename(path)} (${doc.pages.length} pages)',
      () => doc.loadPagesProgressively(),
    );
  }
}

/// Process-wide cache so one file is opened once, no matter how many
/// consumers (validation, viewer, thumbnails, organize grid, text export) need
/// it at the same time.
///
/// Documents are keyed by path + size + mtime (+ password), so an edited file
/// is a new entry; stale versions are disposed once their last lease goes.
class PdfDocumentCache {
  PdfDocumentCache._();

  static final PdfDocumentCache instance = PdfDocumentCache._();

  /// How long an unreferenced document stays open.
  Duration idleTtl = const Duration(minutes: 3);

  /// Max unreferenced documents kept open (native memory cap).
  int maxIdleDocuments = 5;

  final Map<String, _DocEntry> _entries = {};

  static Future<String> versionOf(String path) async {
    path = LinuxDocumentPortal.resolveSync(path);
    if (LinuxDocumentPortal.isPortalPath(path)) {
      path = await LinuxDocumentPortal.resolve(path);
    }
    return _versionSyncResolved(path);
  }

  /// Sync version so [acquire] can insert the cache entry before any await.
  /// An await before `putIfAbsent` let portal vs `ds_sess_*` opens each start
  /// `pdf.open`. Failed statx is not cached.
  static String _versionSyncResolved(String path) {
    FileStat? st;
    try {
      st = File(path).statSync();
    } catch (_) {}
    final size = st?.size ?? 0;
    final mtime = st?.modified.microsecondsSinceEpoch ?? 0;
    // statx, not `stat(1)`: the Flutter snap often cannot spawn /usr/bin/stat,
    // and a path-string key made the FUSE path, the host file, and the
    // sanitized session hardlink three different documents.
    final inode = LinuxDocumentPortal.fileIdSync(path);
    if (inode != null) return '$inode|$size:$mtime';
    return '$path|$size:$mtime';
  }

  /// Opens (or reuses) [path]. Throws the pdfrx open error (e.g.
  /// [PdfPasswordException]) when the document cannot be opened.
  Future<PdfDocumentLease> acquire(
    String path, {
    String? password,
    bool loadAllPages = false,
  }) async {
    // Resolve BEFORE version/key so portal FUSE never gets its own cache entry.
    // xattr resolve is sync; only a miss awaits, and that miss is not cached.
    path = LinuxDocumentPortal.resolveSync(path);
    if (LinuxDocumentPortal.isPortalPath(path)) {
      path = await LinuxDocumentPortal.resolve(path);
    }
    final version = _versionSyncResolved(path);
    final key = '$version|${password ?? ''}';

    // putIfAbsent is sync: the versionOf await above is the only race window,
    // and a second check + putIfAbsent collapses duplicate opens.
    var entry = _entries[key];
    entry ??= _entries.putIfAbsent(key, () {
      final created = _DocEntry(key, path, version);
      created.opening = PerfLog.time(
        'pdf.open ${p.basename(path)}',
        () => PdfDocument.openFile(
          path,
          passwordProvider: _oneShotPassword(password),
          useProgressiveLoading: true,
        ),
      );
      _disposeStaleVersions(path, keep: key);
      return created;
    });

    final e = entry;
    e.refs++;
    e.idleTimer?.cancel();
    e.idleTimer = null;
    e.lastUsedUs = DateTime.now().microsecondsSinceEpoch;
    try {
      e.document ??= await e.opening;
    } catch (_) {
      e.refs--;
      if (identical(_entries[key], e)) _entries.remove(key);
      rethrow;
    }
    final lease = PdfDocumentLease._(this, e);
    if (loadAllPages) await e.ensureAllPagesLoaded();
    return lease;
  }

  /// Runs [task] with a temporary lease.
  ///
  /// [loadAllPages] defaults to **false** — walking every page (FPDF_LoadPage ×
  /// N) must stay opt-in for export/OCR, never for thumbnails or open.
  Future<T> use<T>(
    String path,
    Future<T> Function(PdfDocument document) task, {
    String? password,
    bool loadAllPages = false,
  }) async {
    final lease = await acquire(
      path,
      password: password,
      loadAllPages: loadAllPages,
    );
    try {
      return await task(lease.document);
    } finally {
      lease.release();
    }
  }

  /// Drops idle documents for [path] (e.g. before the file is deleted).
  void evictPath(String path) {
    for (final e in _entries.values.toList()) {
      if (e.path == path && e.refs == 0) _dispose(e);
    }
  }

  /// Closes every idle document (low-memory / Settings › Clear cache).
  void trimIdle() {
    for (final e in _entries.values.toList()) {
      if (e.refs == 0) _dispose(e);
    }
  }

  int get openDocumentCount => _entries.length;

  void _release(_DocEntry e) {
    e.refs--;
    if (e.refs > 0) return;
    e.lastUsedUs = DateTime.now().microsecondsSinceEpoch;
    // A newer version of this file exists: nobody will ask for this one again.
    final superseded = _entries.values.any(
      (o) => o.path == e.path && o.version != e.version,
    );
    if (superseded) {
      // Short grace: in-flight renders on the old pages must drain first.
      e.idleTimer = Timer(const Duration(seconds: 3), () => _dispose(e));
      return;
    }
    e.idleTimer = Timer(idleTtl, () => _dispose(e));
    _enforceIdleCap();
  }

  void _disposeStaleVersions(String path, {required String keep}) {
    for (final e in _entries.values.toList()) {
      if (e.path == path && e.key != keep && e.refs == 0) {
        e.idleTimer?.cancel();
        e.idleTimer = Timer(const Duration(seconds: 3), () => _dispose(e));
      }
    }
  }

  void _enforceIdleCap() {
    final idle = _entries.values.where((e) => e.refs == 0).toList()
      ..sort((a, b) => a.lastUsedUs.compareTo(b.lastUsedUs));
    while (idle.length > maxIdleDocuments) {
      _dispose(idle.removeAt(0));
    }
  }

  void _dispose(_DocEntry e) {
    if (e.refs > 0 || e.disposed) return;
    e.disposed = true;
    e.idleTimer?.cancel();
    if (identical(_entries[e.key], e)) _entries.remove(e.key);
    final doc = e.document;
    e.document = null;
    if (doc != null) {
      unawaited(doc.dispose());
    } else {
      unawaited(e.opening.then((d) => d.dispose(), onError: (Object _) {}));
    }
  }

  /// Drop every cached document without waiting for native dispose to finish.
  ///
  /// Used on app quit so Windows does not stall on PDFium teardown while the
  /// window is still visible. Dispose futures are fire-and-forget.
  void disposeAllNow() {
    final entries = List<_DocEntry>.from(_entries.values);
    _entries.clear();
    for (final e in entries) {
      e.idleTimer?.cancel();
      if (e.disposed) continue;
      e.disposed = true;
      final doc = e.document;
      e.document = null;
      if (doc != null) {
        unawaited(doc.dispose());
      } else {
        unawaited(e.opening.then((d) => d.dispose(), onError: (Object _) {}));
      }
    }
  }
}

/// pdfrx keeps calling the provider while the password is wrong; answer once.
PdfPasswordProvider? _oneShotPassword(String? password) {
  if (password == null) return null;
  var asked = false;
  return () async {
    if (asked) return null;
    asked = true;
    return password;
  };
}
