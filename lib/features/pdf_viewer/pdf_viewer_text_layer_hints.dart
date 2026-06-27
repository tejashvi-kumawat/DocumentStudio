/// User-facing hints when a PDF has no extractable text layer (scan-only pages).
const kPdfScanOnlyCopyHint =
    'No selectable text on this page. Scanned PDFs need OCR (Tools → OCR) first.';

const kPdfScanOnlyFindHint =
    'No searchable text — this document may be scan-only. Try OCR for searchable text.';

/// Status line for find bar when a query returns no matches (not while searching).
String pdfViewerFindStatusLabel({
  required String query,
  required int matchCount,
  required bool isSearching,
  int? currentIndex,
  bool ocrIndexing = false,
  bool fromOcrIndex = false,
}) {
  if (ocrIndexing && matchCount == 0) {
    return 'Building OCR search index…';
  }
  if (fromOcrIndex && matchCount > 0) {
    final index = (currentIndex ?? 0) + 1;
    return '$index of $matchCount (OCR)';
  }
  if (isSearching && matchCount == 0) {
    return 'Searching…';
  }
  if (matchCount == 0) {
    if (query.trim().length >= 2) {
      return kPdfScanOnlyFindHint;
    }
    return 'No matches';
  }
  final index = (currentIndex ?? 0) + 1;
  return '$index of $matchCount';
}
