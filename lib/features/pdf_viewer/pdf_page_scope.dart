/// Page targeting for viewer-embedded tools (this page, selection, all, range).
enum PdfPageScopeKind {
  thisPage,
  selectedPages,
  allPages,
  range,
}

/// Parses expressions like `1-3,5` into 1-based page numbers within [totalPages].
///
/// Tolerant of spaces/semicolons as separators, en/em dashes, and open ends:
/// `8-` means 8 to the last page, `-3` means 1 to 3.
PdfPageScopeParseResult parsePdfPageRangeExpression(
  String input,
  int totalPages,
) {
  final trimmed = input
      .trim()
      .replaceAll(RegExp('[\u2012\u2013\u2014\u2212]'), '-')
      .replaceAll(RegExp(r'\s*-\s*'), '-');
  if (trimmed.isEmpty) {
    return const PdfPageScopeParseResult.error('Enter a page range (e.g. 1-3,5).');
  }
  if (totalPages < 1) {
    return const PdfPageScopeParseResult.error('Document has no pages.');
  }

  final pages = <int>{};
  // `odd` / `even` filter the other segments (or all pages when alone).
  final segments = trimmed
      .toLowerCase()
      .split(RegExp(r'[,;\s]+'))
      .where((s) => s.isNotEmpty)
      .toList();
  int? parity;
  segments.removeWhere((s) {
    if (s == 'odd' || s == 'even') {
      parity = s == 'odd' ? 1 : 0;
      return true;
    }
    return false;
  });
  if (parity != null && segments.isEmpty) {
    for (var p = 1; p <= totalPages; p++) {
      if (p % 2 == parity) pages.add(p);
    }
    return pages.isEmpty
        ? const PdfPageScopeParseResult.error('No pages in range.')
        : PdfPageScopeParseResult.ok(pages);
  }
  for (final segment in segments) {
    final part = segment.trim();
    if (part.isEmpty) continue;
    final dash = part.indexOf('-');
    if (dash >= 0) {
      final startRaw = part.substring(0, dash).trim();
      final endRaw = part.substring(dash + 1).trim();
      final start = startRaw.isEmpty ? 1 : int.tryParse(startRaw);
      final end = endRaw.isEmpty ? totalPages : int.tryParse(endRaw);
      if (start == null || end == null) {
        return PdfPageScopeParseResult.error('Invalid range segment: $part');
      }
      if (start < 1 || end < 1 || start > end) {
        return PdfPageScopeParseResult.error('Invalid range: $part');
      }
      for (var p = start; p <= end; p++) {
        if (p > totalPages) {
          return PdfPageScopeParseResult.error(
            'Page $p is out of range (document has $totalPages pages).',
          );
        }
        pages.add(p);
      }
    } else {
      final page = int.tryParse(part);
      if (page == null || page < 1) {
        return PdfPageScopeParseResult.error('Invalid page number: $part');
      }
      if (page > totalPages) {
        return PdfPageScopeParseResult.error(
          'Page $page is out of range (document has $totalPages pages).',
        );
      }
      pages.add(page);
    }
  }
  if (parity != null) pages.removeWhere((p) => p % 2 != parity);

  if (pages.isEmpty) {
    return const PdfPageScopeParseResult.error('No pages in range.');
  }
  return PdfPageScopeParseResult.ok(pages);
}

/// Compact expression for [pages], e.g. `{1,2,3,5}` → `1-3, 5`.
String formatPdfPageRange(Iterable<int> pages) {
  final sorted = pages.toSet().toList()..sort();
  final parts = <String>[];
  var i = 0;
  while (i < sorted.length) {
    var j = i;
    while (j + 1 < sorted.length && sorted[j + 1] == sorted[j] + 1) {
      j++;
    }
    parts.add(j == i ? '${sorted[i]}' : '${sorted[i]}-${sorted[j]}');
    i = j + 1;
  }
  return parts.join(', ');
}

class PdfPageScopeParseResult {
  const PdfPageScopeParseResult._({this.pages, this.error});

  const PdfPageScopeParseResult.ok(Set<int> pages)
      : this._(pages: pages, error: null);

  const PdfPageScopeParseResult.error(String message)
      : this._(pages: null, error: message);

  final Set<int>? pages;
  final String? error;

  bool get isOk => error == null && pages != null;
}

/// Resolves concrete 1-based page numbers for a scope selection.
PdfPageScopeResolveResult resolvePdfPageScope({
  required PdfPageScopeKind kind,
  required int currentPage1,
  required Set<int> selectedPages1Based,
  required int totalPages,
  required String rangeExpression,
}) {
  if (totalPages < 1) {
    return const PdfPageScopeResolveResult.error('Document has no pages.');
  }

  switch (kind) {
    case PdfPageScopeKind.thisPage:
      final page = currentPage1.clamp(1, totalPages);
      return PdfPageScopeResolveResult.ok({page});
    case PdfPageScopeKind.selectedPages:
      if (selectedPages1Based.isEmpty) {
        return const PdfPageScopeResolveResult.error(
          'No pages selected. Use This page or Range, or pick pages in the thumbnail sidebar (Shift/Ctrl).',
        );
      }
      final clamped = {
        for (final p in selectedPages1Based)
          if (p >= 1 && p <= totalPages) p,
      };
      if (clamped.isEmpty) {
        return const PdfPageScopeResolveResult.error(
          'Selected pages are out of document range.',
        );
      }
      return PdfPageScopeResolveResult.ok(clamped);
    case PdfPageScopeKind.allPages:
      return PdfPageScopeResolveResult.ok({
        for (var p = 1; p <= totalPages; p++) p,
      });
    case PdfPageScopeKind.range:
      final parsed = parsePdfPageRangeExpression(rangeExpression, totalPages);
      if (!parsed.isOk) {
        return PdfPageScopeResolveResult.error(parsed.error!);
      }
      return PdfPageScopeResolveResult.ok(parsed.pages!);
  }
}

class PdfPageScopeResolveResult {
  const PdfPageScopeResolveResult._({this.pages, this.error});

  const PdfPageScopeResolveResult.ok(Set<int> pages)
      : this._(pages: pages, error: null);

  const PdfPageScopeResolveResult.error(String message)
      : this._(pages: null, error: message);

  final Set<int>? pages;
  final String? error;

  bool get isOk => error == null && pages != null;
}
