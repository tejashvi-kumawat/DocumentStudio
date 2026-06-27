import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

/// One searchable text match on a page (normalized top-left 0–1 rect).
class PdfPageTextMatch {
  const PdfPageTextMatch({
    required this.text,
    required this.normRect,
    required this.start,
    required this.end,
  });

  final String text;
  final ui.Rect normRect;
  final int start;
  final int end;
}

/// Converts a PDF-space [PdfRect] (bottom-left origin) to UI-normalized top-left.
ui.Rect pdfRectToNormTopLeft(PdfRect r, double pageWidthPt, double pageHeightPt) {
  final w = pageWidthPt <= 0 ? 1.0 : pageWidthPt;
  final h = pageHeightPt <= 0 ? 1.0 : pageHeightPt;
  final left = (r.left / w).clamp(0.0, 1.0);
  final right = (r.right / w).clamp(0.0, 1.0);
  final top = (1 - r.top / h).clamp(0.0, 1.0);
  final bottom = (1 - r.bottom / h).clamp(0.0, 1.0);
  return ui.Rect.fromLTRB(
    left,
    top < bottom ? top : bottom,
    right,
    top < bottom ? bottom : top,
  );
}

/// Finds case-insensitive substring matches on [pageText] with char-box bounds.
List<PdfPageTextMatch> findPageTextMatches({
  required Object pageText,
  required String query,
  required double pageWidthPt,
  required double pageHeightPt,
}) {
  final needle = query.trim();
  final String fullText;
  final List<PdfRect> charRects;
  if (pageText is PdfPageText) {
    fullText = pageText.fullText;
    charRects = pageText.charRects;
  } else if (pageText is PdfPageRawText) {
    fullText = pageText.fullText;
    charRects = pageText.charRects;
  } else {
    return const [];
  }
  if (needle.isEmpty || fullText.isEmpty || charRects.isEmpty) {
    return const [];
  }
  final hay = fullText.toLowerCase();
  final n = needle.toLowerCase();
  final out = <PdfPageTextMatch>[];
  var from = 0;
  while (true) {
    final idx = hay.indexOf(n, from);
    if (idx < 0) break;
    final end = idx + n.length;
    if (end > charRects.length) break;
    final bounds = charRects.boundingRect(start: idx, end: end);
    out.add(
      PdfPageTextMatch(
        text: fullText.substring(idx, end),
        normRect: pdfRectToNormTopLeft(bounds, pageWidthPt, pageHeightPt),
        start: idx,
        end: end,
      ),
    );
    from = idx + (n.isEmpty ? 1 : n.length);
  }
  return out;
}

/// True when [haystack] (OCR or plain) contains [query] case-insensitively.
bool pageTextContainsQuery(String? haystack, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return false;
  final hay = (haystack ?? '').toLowerCase();
  return hay.contains(needle);
}
