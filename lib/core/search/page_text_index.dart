import 'dart:async';
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

/// Compact per-page "which trigrams occur here" filter plus a private,
/// fully-loaded copy of the document used for all-page text work.
///
/// The viewer opens documents with page measuring *on demand*, so the viewer's
/// own pages are only "loaded" once the user has scrolled to them; searching
/// through them only ever covered visited pages. This index owns a separate
/// [PdfDocument] and loads every page itself (in the background, yielding to
/// rendering), so search and text tools see the whole document.
///
/// The filter stores 8 Kbit per page (1 KB; a 50 000-page file costs ~50 MB,
/// never the text itself). A query can only be on pages whose filter contains
/// every trigram of the query — false positives are harmless, misses impossible.
class PageTextIndex {
  PageTextIndex({required this.path, this.password, this.isBusy});

  final String path;
  final String? password;

  /// While true (user scrolling / zooming) background work waits.
  final bool Function()? isBusy;

  /// Filter size per page; shrinks for huge documents so the whole index
  /// stays around 10–50 MB (8 Kbit ≤ 5 000 pages, 4 Kbit ≤ 20 000, else 2 Kbit).
  int _bits = 8192;
  static final Uint8List _noText = Uint8List(0);

  PdfDocument? _doc;
  Future<PdfDocument?>? _opening;
  final Map<int, Uint8List> _filters = {};
  int _generation = 0;
  bool _complete = false;
  bool _disposed = false;

  bool get isComplete => _complete;
  int get indexedPages => _filters.length;

  /// The private document (opened on first use).
  Future<PdfDocument?> document() => _opening ??= _open();

  Future<PdfDocument?> _open() async {
    try {
      final doc = await PdfDocument.openFile(
        path,
        passwordProvider: password == null ? null : () async => password,
        useProgressiveLoading: true,
      );
      if (_disposed) {
        await doc.dispose();
        return null;
      }
      return _doc = doc;
    } catch (_) {
      return null;
    }
  }

  /// Loads page [n] (waiting for the private document's own loading, never
  /// the viewer's) and returns it, or null.
  Future<PdfPage?> pageLoaded(int n) async {
    final doc = await document();
    if (doc == null || n < 1 || n > doc.pages.length) return null;
    // Start measuring around the requested page if nothing is loading yet.
    final page = doc.pages[n - 1];
    if (page.isLoaded) return page;
    unawaited(
      doc.loadPagesProgressively(
        startPageNumber: n,
        loadUnitDuration: const Duration(milliseconds: 40),
        onPageLoadProgress: (loaded, total, _) =>
            !_disposed && !doc.pages[n - 1].isLoaded,
      ),
    );
    return page.waitForLoaded(timeout: const Duration(seconds: 20));
  }

  /// True when [page] is known not to contain [needle] (already normalized
  /// with [normalize]).
  bool excludes(int page, String needle) {
    final f = _filters[page];
    if (f == null) return false;
    if (identical(f, _noText)) return true;
    if (needle.length < 3) return false;
    for (var i = 0; i + 3 <= needle.length; i++) {
      final h = _hash(
        needle.codeUnitAt(i),
        needle.codeUnitAt(i + 1),
        needle.codeUnitAt(i + 2),
      );
      if (f[h >> 3] & (1 << (h & 7)) == 0) return true;
    }
    return false;
  }

  int _hash(int a, int b, int c) =>
      ((a * 31 + b) * 31 + c) * 2654435761 & (_bits - 1);

  static String normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  Uint8List _filterFor(String text) {
    final t = normalize(text);
    if (t.isEmpty) return _noText;
    final f = Uint8List(_bits >> 3);
    for (var i = 0; i + 3 <= t.length; i++) {
      final h = _hash(
        t.codeUnitAt(i),
        t.codeUnitAt(i + 1),
        t.codeUnitAt(i + 2),
      );
      f[h >> 3] |= 1 << (h & 7);
    }
    return f;
  }

  void clear() {
    _generation++;
    _filters.clear();
    _complete = false;
  }

  /// Closes the private document (and stops indexing) so the file can be
  /// replaced; the next [document] / [build] reopens it.
  Future<void> release() async {
    _generation++;
    _filters.clear();
    _complete = false;
    final doc = _doc;
    _doc = null;
    _opening = null;
    await doc?.dispose();
  }

  /// Indexes every page, one at a time, waiting while the UI is busy.
  Future<void> build() async {
    final gen = ++_generation;
    _complete = false;
    try {
      final doc = await document();
      if (doc == null) return;
      // Measure all pages in small slices so renders interleave.
      unawaited(
        doc.loadPagesProgressively(
          loadUnitDuration: const Duration(milliseconds: 40),
          onPageLoadProgress: (loaded, total, _) async {
            while (isBusy?.call() == true && !_disposed) {
              await Future<void>.delayed(const Duration(milliseconds: 120));
            }
            await Future<void>.delayed(const Duration(milliseconds: 4));
            return !_disposed && gen == _generation;
          },
        ),
      );
      final total = doc.pages.length;
      _bits = total <= 5000 ? 8192 : (total <= 20000 ? 4096 : 2048);
      for (var n = 1; n <= total; n++) {
        if (gen != _generation || _disposed) return;
        if (_filters.containsKey(n)) continue;
        while (isBusy?.call() == true && !_disposed) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
        final page = await doc.pages[n - 1].waitForLoaded(
          timeout: const Duration(seconds: 30),
        );
        if (gen != _generation || _disposed) return;
        if (page == null) continue;
        String? text;
        try {
          text = (await page.loadText())?.fullText;
        } catch (_) {}
        _filters[n] = _filterFor(text ?? '');
        if (n % 3 == 0)
          await Future<void>.delayed(const Duration(milliseconds: 3));
      }
      if (gen == _generation) _complete = true;
    } catch (_) {
      // A partial index still works; unindexed pages are always searched.
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _generation++;
    _filters.clear();
    final doc = _doc;
    _doc = null;
    await doc?.dispose();
  }
}
