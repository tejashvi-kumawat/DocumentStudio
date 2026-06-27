import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/core/isolate/run_isolated.dart';
import 'package:document_studio/core/pdf/pdf_document_cache.dart';
import 'package:document_studio/core/storage/linux_document_portal.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_markup_io.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_parser.dart';
import 'package:pdfrx/pdfrx.dart';

final Uint8List _dsKey = Uint8List.fromList(latin1.encode('/$kDsMarkupKey'));

Uint8List? _stripped(Uint8List bytes) {
  final out = stripEditableAnnotsForDisplay(bytes);
  return identical(out, bytes) ? null : out;
}

/// Document shown by the page viewer.
///
/// Fresh open: cache-only (no /DSMarkup probe, no full-file rewrite). First
/// paint reuses the validation warm lease. After Apply / soft-reload, a
/// **64KB tail** probe may strip DS overlay annots so they are not drawn twice.
class MarkupDisplayDocumentHandle {
  MarkupDisplayDocumentHandle(
    String path, {
    this.password,
    /// Fresh open of a user file: skip probe so open is one cache acquire.
    this.skipDsMarkupProbe = true,
    String? identityPath,
  }) : _loadPath = LinuxDocumentPortal.resolveSync(path),
       identityPath = LinuxDocumentPortal.resolveSync(identityPath ?? path) {
    // First paint reads the canonical source. A session hardlink is renamed
    // (`(Vol 1)` → `_Vol 1_`) and must not be a second pdf.open.
    _initial = PdfDocumentCache.instance.acquire(
      this.identityPath,
      password: password,
    );
    _initial?.ignore();
    _pinListenable();
  }

  static final Map<String, _SharedDisplay> _shared = {};

  static String _sharedKey(String identityPath, String? password) =>
      '${LinuxDocumentPortal.resolveSync(identityPath)}|${password ?? ''}';

  /// One handle per source path so a viewer remount does not open the PDF
  /// again or build a second [PdfDocumentRefKey].
  static MarkupDisplayDocumentHandle retain({
    required String identityPath,
    String? password,
  }) {
    final key = _sharedKey(identityPath, password);
    final slot = _shared.putIfAbsent(
      key,
      () => _SharedDisplay(
        MarkupDisplayDocumentHandle(
          LinuxDocumentPortal.resolveSync(identityPath),
          password: password,
          identityPath: identityPath,
          skipDsMarkupProbe: true,
        ),
      ),
    );
    slot.drop?.cancel();
    slot.drop = null;
    slot.refs++;
    return slot.handle;
  }

  /// Drops a [retain] when the viewer unmounts. A rebuild in the same turn
  /// retains again before the handle (and its pdfrx listenable) is released.
  static void release(String identityPath, {String? password}) {
    final key = _sharedKey(identityPath, password);
    final slot = _shared[key];
    if (slot == null) return;
    if (slot.refs > 0) slot.refs--;
    if (slot.refs > 0) return;
    slot.drop?.cancel();
    slot.drop = Timer(const Duration(seconds: 2), () {
      if (slot.refs > 0) return;
      if (!identical(_shared[key], slot)) return;
      _shared.remove(key);
      slot.handle.dispose();
    });
  }

  /// Stable identity for [PdfDocumentRefKey] — resolved **source** path.
  /// Never a portal FUSE path and never a mutating working temp when the
  /// working file is only a hardlink of the source.
  final String identityPath;

  final String? password;

  /// When true, every load is cache-only (no tail probe / full-file strip).
  /// Viewer open always uses this — overlay draws DS markup; first paint must
  /// not rewrite a large book.
  final bool skipDsMarkupProbe;

  String _loadPath;
  Future<PdfDocumentLease>? _initial;
  PdfDocumentLease? _lease;
  PdfDocument? _own;
  bool _disposed = false;
  void Function()? _unpin;

  String get path => _loadPath;

  /// Keyed by resolved [identityPath] only — working-path changes must not
  /// create a second listenable or remount [PdfViewer].
  late final PdfDocumentRef ref = PdfDocumentRefByLoader(
    (_) => _load(),
    key: PdfDocumentRefKey(identityPath, ['ds-display', password ?? '']),
    autoDispose: false,
  );

  /// Retarget bytes path after working-copy materialization. Same inode
  /// (hardlink) is a no-op for the cache; [forceReload] after Apply reads
  /// new bytes when the inode actually changes.
  void updateLoadPath(String path) {
    final resolved = LinuxDocumentPortal.resolveSync(path);
    if (resolved == _loadPath) return;
    final sameBytes = LinuxDocumentPortal.sameFileSync(resolved, _loadPath) ||
        LinuxDocumentPortal.sameFileSync(resolved, identityPath);
    _loadPath = resolved;
    if (sameBytes) {
      // Remember the hardlink so copy-on-write (same path, new inode) is what
      // a later soft-reload reads. Do not open the renamed path now.
      return;
    }
    // Do not start a second eager acquire here — soft-reload / next _load
    // will pick up the path. Starting one caused a third pdf.open when the
    // working file was a distinct copy.
  }

  /// Keeps the pdfrx listenable alive across viewer remounts. Without this,
  /// the last PdfViewer listener drops the ref and the next mount logs
  /// another `PdfDocument initial load` and opens the file again.
  void _pinListenable() {
    _unpin = ref.resolveListenable().addListener(() {});
  }

  /// Source path while the working file is still the same inode. After the
  /// hardlink is broken, [_loadPath] is the new bytes.
  String get _openPath =>
      LinuxDocumentPortal.sameFileSync(_loadPath, identityPath)
          ? identityPath
          : _loadPath;

  Future<PdfDocument> _load() async {
    final resolved = _openPath;

    final pending = _initial ??
        PdfDocumentCache.instance.acquire(resolved, password: password);
    _initial = null;

    if (skipDsMarkupProbe) {
      final lease = await pending;
      if (_disposed) {
        lease.release();
        return lease.document;
      }
      _swap(lease: lease);
      return lease.document;
    }

    // Optional strip path (tests / future callers): 64KB tail only.
    final probe = _tailContains64k(resolved, _dsKey);
    final lease = await pending;
    final hasDs = await probe;
    if (_disposed) {
      lease.release();
      return lease.document;
    }

    if (hasDs) {
      try {
        final bytes = await File(resolved).readAsBytes();
        final display = await runIsolated(_stripped, bytes);
        if (display != null) {
          lease.release();
          final pw = password;
          final doc = await PdfDocument.openData(
            display,
            passwordProvider: pw == null ? null : () => pw,
            sourceName: '$identityPath#ds-display',
            useProgressiveLoading: true,
          );
          if (_disposed) {
            unawaited(doc.dispose());
            return doc;
          }
          _swap(own: doc);
          return doc;
        }
      } catch (_) {
        // Fall through to the cached original.
      }
    }

    _swap(lease: lease);
    return lease.document;
  }

  void _abandonInitialLease() {
    final pending = _initial;
    _initial = null;
    if (pending != null) {
      unawaited(pending.then((l) => l.release(), onError: (Object _) {}));
    }
  }

  void _swap({PdfDocument? own, PdfDocumentLease? lease}) {
    final prevOwn = _own;
    final prevLease = _lease;
    _own = own;
    _lease = lease;
    if (_disposed) {
      _release(own, lease);
      return;
    }
    Timer(const Duration(seconds: 3), () => _release(prevOwn, prevLease));
  }

  static void _release(PdfDocument? own, PdfDocumentLease? lease) {
    lease?.release();
    if (own != null) unawaited(own.dispose());
  }

  /// Last 64KB only — DS markup is appended; never scan the book body.
  static Future<bool> _tailContains64k(String path, Uint8List needle) async {
    if (needle.isEmpty) return false;
    return runIsolated(_tailContainsIsolate, _TailProbeArgs(path, needle));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final unpin = _unpin;
    _unpin = null;
    unpin?.call();
    _abandonInitialLease();
    final own = _own, lease = _lease;
    _own = null;
    _lease = null;
    Timer(const Duration(seconds: 1), () => _release(own, lease));
  }
}

class _SharedDisplay {
  _SharedDisplay(this.handle);
  final MarkupDisplayDocumentHandle handle;
  int refs = 0;
  Timer? drop;
}

class _TailProbeArgs {
  _TailProbeArgs(this.path, this.needle);
  final String path;
  final Uint8List needle;
}

bool _tailContainsIsolate(_TailProbeArgs args) {
  final needle = args.needle;
  final raf = File(args.path).openSync();
  try {
    final length = raf.lengthSync();
    if (length <= 0) return false;
    const chunk = 64 * 1024;
    final tailLen = length < chunk ? length : chunk;
    raf.setPositionSync(length - tailLen);
    final buf = raf.readSync(tailLen);
    return indexOfBytes(buf, needle) >= 0;
  } finally {
    raf.closeSync();
  }
}
