import 'dart:async';
import 'dart:collection';

import 'package:document_studio/core/search/page_text_index.dart';
import 'package:pdfrx/pdfrx.dart';

/// [PdfTextSearcher] that searches every page of the document.
///
/// The viewer's own document only "loads" pages as they are scrolled to
/// (`loadPageDimensionsOnDemand`), and its text calls either return an empty
/// text or wait forever for pages never visited — so the stock searcher only
/// covered visited pages. Here all text comes from a private, fully loaded
/// copy owned by [PageTextIndex]; a background trigram index lets a search
/// skip pages that cannot match; and only a small window of structured text
/// is kept (pages with matches stay alive through the matches).
class DsTextSearcher extends PdfTextSearcher {
  DsTextSearcher(
    PdfViewerController controller, {
    required String path,
    String? password,
    bool Function()? isBusy,
  })  : index = PageTextIndex(path: path, password: password, isBusy: isBusy),
        super(controller) {
    addListener(_guardRestart);
  }

  // pdfrx restarts a search when a page with matches finishes loading, but
  // its restart compares the pattern with the one it just kept and skips the
  // search — every match vanished ("No searchable text…") as soon as the
  // viewer (or OCR) loaded such a page. Re-run the query ourselves then.
  Pattern? _lastPattern;
  bool _lastCaseInsensitive = true;
  bool _hadMatches = false;
  Timer? _rerun;

  @override
  void startTextSearch(
    Pattern pattern, {
    bool caseInsensitive = true,
    bool goToFirstMatch = true,
    bool searchImmediately = false,
  }) {
    _lastPattern = pattern;
    _lastCaseInsensitive = caseInsensitive;
    _hadMatches = false;
    super.startTextSearch(
      pattern,
      caseInsensitive: caseInsensitive,
      goToFirstMatch: goToFirstMatch,
      searchImmediately: searchImmediately,
    );
  }

  @override
  void resetTextSearch() {
    _lastPattern = null;
    _hadMatches = false;
    super.resetTextSearch();
  }

  void _guardRestart() {
    if (matches.isNotEmpty) {
      _hadMatches = true;
      return;
    }
    final p = _lastPattern;
    if (p == null || !_hadMatches || isSearching) return;
    _hadMatches = false;
    _rerun?.cancel();
    _rerun = Timer(const Duration(milliseconds: 250), () {
      final again = _lastPattern;
      if (again == null || matches.isNotEmpty) return;
      final ci = _lastCaseInsensitive;
      super.resetTextSearch();
      startTextSearch(
        again,
        caseInsensitive: ci,
        goToFirstMatch: false,
        searchImmediately: true,
      );
    });
  }

  final PageTextIndex index;

  static const _window = 48;
  final LinkedHashMap<int, PdfPageText> _recent = LinkedHashMap();

  /// Plain text of the current query for the index pre-filter; null when the
  /// filter cannot judge it.
  String? prefilterNeedle;

  /// Starts background indexing (never runs OCR).
  void startIndexing() => index.build();

  PdfPageText _empty(int n) => PdfPageText(
        pageNumber: n,
        fullText: '',
        charRects: const [],
        fragments: const [],
      );

  @override
  Future<PdfPageText?> loadText({required int pageNumber}) async {
    final needle = prefilterNeedle;
    if (needle != null && index.excludes(pageNumber, needle)) {
      return _empty(pageNumber);
    }
    final hit = _recent.remove(pageNumber);
    if (hit != null) {
      _recent[pageNumber] = hit;
      return hit;
    }
    final page = await index.pageLoaded(pageNumber);
    if (page == null) return _empty(pageNumber);
    final text = await page.loadStructuredText();
    _recent[pageNumber] = text;
    while (_recent.length > _window) {
      _recent.remove(_recent.keys.first);
    }
    return text;
  }

  /// Drops caches and re-indexes (call after the content changed).
  void clearCache() {
    _recent.clear();
    index.clear();
    index.build();
  }

  @override
  void dispose() {
    _rerun?.cancel();
    _recent.clear();
    index.dispose();
    super.dispose();
  }
}
