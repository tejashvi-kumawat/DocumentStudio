import 'dart:async';

import 'package:document_studio/core/pdf/pdf_document_cache.dart';
import 'package:document_studio/core/storage/linux_document_portal.dart';
import 'package:pdfrx/pdfrx.dart';

/// Holds a [PdfDocumentCache] lease and exposes it as a [PdfDocumentRef]
/// for `PdfViewer`.
///
/// The viewer, validation, thumbnails, text search and OCR all share the same
/// native [PdfDocument]: remounting the viewer (layout mode change, tab
/// switch) or opening a panel never re-parses the file. The ref never
/// disposes the document itself; the cache does once the last lease is gone.
///
/// `load(forceReload: true)` (soft reload after an in-place save) acquires
/// the file's current version (the cache keys on path + size + mtime) and
/// releases the previous one.
///
/// Create it in `initState` (or when the path/password changes) and call
/// [dispose] from the owning widget's `dispose`.
class SharedPdfDocumentHandle {
  SharedPdfDocumentHandle(String path, {this.password})
      : path = LinuxDocumentPortal.resolveSync(path),
        _initial = PdfDocumentCache.instance.acquire(
          LinuxDocumentPortal.resolveSync(path),
          password: password,
        ) {
    _initial?.ignore();
  }

  /// Host path when [path] was an xdg-document-portal FUSE path.
  final String path;
  final String? password;

  /// Started eagerly so the open overlaps the viewer's first layout.
  Future<PdfDocumentLease>? _initial;
  PdfDocumentLease? _current;
  bool _disposed = false;

  /// Stable per path+password so remounts reuse the same listenable / document.
  late final PdfDocumentRef ref = PdfDocumentRefByLoader(
    (_) => _load(),
    key: PdfDocumentRefKey(path, ['ds-shared', password ?? '']),
    autoDispose: false,
  );

  Future<PdfDocument> _load() async {
    final pending = _initial;
    _initial = null;
    final lease = await (pending ??
        PdfDocumentCache.instance.acquire(path, password: password));
    if (_disposed) {
      lease.release();
      return lease.document;
    }
    final previous = _current;
    _current = lease;
    previous?.release();
    return lease.document;
  }

  bool matches(String path, String? password) =>
      this.path == path && this.password == password;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _current?.release();
    _current = null;
    final pending = _initial;
    _initial = null;
    if (pending != null) {
      unawaited(pending.then((l) => l.release(), onError: (Object _) {}));
    }
  }
}
