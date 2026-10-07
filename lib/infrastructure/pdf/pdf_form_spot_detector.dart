import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Kind of fill-in region detected on a PDF page.
enum PdfFormSpotKind { text, checkbox, signature }

/// A fillable rectangle in PDF user space (bottom-left origin) plus UI norm.
class PdfFormSpot {
  const PdfFormSpot({
    required this.id,
    required this.name,
    required this.kind,
    required this.pdfRect,
    required this.normRect,
    this.pageIndex1Based = 1,
  });

  final String id;
  final String name;
  final PdfFormSpotKind kind;

  /// PDF user space: left, bottom, right, top (llx, lly, urx, ury).
  final Rect pdfRect;

  /// Normalized page space, top-left origin, 0–1 (for overlays).
  final Rect normRect;

  final int pageIndex1Based;
}

/// Detects AcroForm widget rectangles and likely blank fill-in lines/boxes.
class PdfFormSpotDetector {
  /// Scans raw PDF bytes for `/Subtype /Widget` annotations with `/Rect`.
  ///
  /// Page assignment is best-effort: when `/P` object refs are absent, spots
  /// are returned for [pageIndex1Based] only if their rect fits that page.
  List<PdfFormSpot> detectFromPdfBytes(
    Uint8List bytes, {
    required int pageIndex1Based,
    required double pageWidthPt,
    required double pageHeightPt,
  }) {
    final latin = String.fromCharCodes(
      bytes.take(math.min(bytes.length, 8 << 20)),
    );
    final widgets = <PdfFormSpot>[];
    // Prefer dict chunks that include Widget + Rect; /FT may appear anywhere
    // in the same object window.
    final widgetRe = RegExp(
      r'/Subtype\s*/Widget[\s\S]{0,1800}?/Rect\s*\[\s*'
      r'([+-]?\d*\.?\d+)\s+([+-]?\d*\.?\d+)\s+'
      r'([+-]?\d*\.?\d+)\s+([+-]?\d*\.?\d+)\s*\]'
      r'|'
      r'/Rect\s*\[\s*'
      r'([+-]?\d*\.?\d+)\s+([+-]?\d*\.?\d+)\s+'
      r'([+-]?\d*\.?\d+)\s+([+-]?\d*\.?\d+)\s*\]'
      r'[\s\S]{0,1800}?/Subtype\s*/Widget',
      multiLine: true,
    );
    var i = 0;
    for (final m in widgetRe.allMatches(latin)) {
      final llx = double.tryParse(m.group(1) ?? m.group(5) ?? '') ?? 0;
      final lly = double.tryParse(m.group(2) ?? m.group(6) ?? '') ?? 0;
      final urx = double.tryParse(m.group(3) ?? m.group(7) ?? '') ?? 0;
      final ury = double.tryParse(m.group(4) ?? m.group(8) ?? '') ?? 0;
      final chunk = m.group(0) ?? '';
      final nameMatch = RegExp(r'/T\s*\(([^)\\]*(?:\\.[^)\\]*)*)\)')
          .firstMatch(chunk);
      final rawName = nameMatch?.group(1);
      final name = rawName == null
          ? 'Field ${i + 1}'
          : rawName.replaceAll(r'\(', '(').replaceAll(r'\)', ')');
      final ft = RegExp(r'/FT\s*/(\w+)').firstMatch(chunk)?.group(1);
      // Require a field type when present in the neighborhood; still accept
      // Widget+/Rect without /FT as text (common for kids that inherit FT).
      final kind = switch (ft) {
        'Btn' => PdfFormSpotKind.checkbox,
        'Sig' => PdfFormSpotKind.signature,
        _ => PdfFormSpotKind.text,
      };
      final pdfRect = Rect.fromLTRB(
        math.min(llx, urx),
        math.min(lly, ury),
        math.max(llx, urx),
        math.max(lly, ury),
      );
      if (pdfRect.width < 2 || pdfRect.height < 2) continue;
      if (pdfRect.left > pageWidthPt + 2 || pdfRect.bottom > pageHeightPt + 2) {
        continue;
      }
      if (pdfRect.right < -2 || pdfRect.top < -2) continue;

      final norm = _pdfRectToNorm(
        pdfRect,
        pageWidthPt: pageWidthPt,
        pageHeightPt: pageHeightPt,
      );
      widgets.add(
        PdfFormSpot(
          id: 'acro_$i',
          name: name,
          kind: kind,
          pdfRect: pdfRect,
          normRect: norm,
          pageIndex1Based: pageIndex1Based,
        ),
      );
      i++;
    }
    if (widgets.isNotEmpty) return widgets;

    return detectBlankSpotsHeuristic(
      latin,
      pageIndex1Based: pageIndex1Based,
      pageWidthPt: pageWidthPt,
      pageHeightPt: pageHeightPt,
    );
  }

  /// Finds underline / empty rectangle patterns that look like fill-in blanks.
  List<PdfFormSpot> detectBlankSpotsHeuristic(
    String pdfLatin, {
    required int pageIndex1Based,
    required double pageWidthPt,
    required double pageHeightPt,
  }) {
    final spots = <PdfFormSpot>[];
    // Horizontal line: x1 y1 m x2 y1 l S  (same y) spanning a useful width.
    final lineRe = RegExp(
      r'([+-]?\d*\.?\d+)\s+([+-]?\d*\.?\d+)\s+m\s+'
      r'([+-]?\d*\.?\d+)\s+([+-]?\d*\.?\d+)\s+l\s+[Ss]',
    );
    var i = 0;
    for (final m in lineRe.allMatches(pdfLatin)) {
      final x1 = double.tryParse(m.group(1) ?? '') ?? 0;
      final y1 = double.tryParse(m.group(2) ?? '') ?? 0;
      final x2 = double.tryParse(m.group(3) ?? '') ?? 0;
      final y2 = double.tryParse(m.group(4) ?? '') ?? 0;
      if ((y1 - y2).abs() > 1.5) continue;
      final width = (x2 - x1).abs();
      if (width < 40 || width > pageWidthPt * 0.95) continue;
      final left = math.min(x1, x2);
      final bottom = y1 - 2;
      final top = y1 + 14;
      final pdfRect = Rect.fromLTRB(left, bottom, left + width, top);
      if (pdfRect.left < 0 || pdfRect.right > pageWidthPt + 4) continue;
      if (pdfRect.bottom < 0 || pdfRect.top > pageHeightPt + 4) continue;
      spots.add(
        PdfFormSpot(
          id: 'blank_line_$i',
          name: 'Blank ${i + 1}',
          kind: PdfFormSpotKind.text,
          pdfRect: pdfRect,
          normRect: _pdfRectToNorm(
            pdfRect,
            pageWidthPt: pageWidthPt,
            pageHeightPt: pageHeightPt,
          ),
          pageIndex1Based: pageIndex1Based,
        ),
      );
      i++;
      if (spots.length >= 24) break;
    }

    // Empty rectangles via re + S (stroke only) sized like form fields.
    if (spots.isEmpty) {
      final reRe = RegExp(
        r'([+-]?\d*\.?\d+)\s+([+-]?\d*\.?\d+)\s+'
        r'([+-]?\d*\.?\d+)\s+([+-]?\d*\.?\d+)\s+re\s+[Ss]',
      );
      for (final m in reRe.allMatches(pdfLatin)) {
        final x = double.tryParse(m.group(1) ?? '') ?? 0;
        final y = double.tryParse(m.group(2) ?? '') ?? 0;
        final w = double.tryParse(m.group(3) ?? '') ?? 0;
        final h = double.tryParse(m.group(4) ?? '') ?? 0;
        if (w < 30 || w > pageWidthPt * 0.9) continue;
        if (h < 10 || h > 48) continue;
        final pdfRect = Rect.fromLTWH(x, y, w, h);
        spots.add(
          PdfFormSpot(
            id: 'blank_box_$i',
            name: 'Box ${i + 1}',
            kind: h <= 18 && w <= 18
                ? PdfFormSpotKind.checkbox
                : PdfFormSpotKind.text,
            pdfRect: pdfRect,
            normRect: _pdfRectToNorm(
              pdfRect,
              pageWidthPt: pageWidthPt,
              pageHeightPt: pageHeightPt,
            ),
            pageIndex1Based: pageIndex1Based,
          ),
        );
        i++;
        if (spots.length >= 24) break;
      }
    }

    return _dedupeOverlapping(spots);
  }

  Rect _pdfRectToNorm(
    Rect pdf, {
    required double pageWidthPt,
    required double pageHeightPt,
  }) {
    final w = math.max(pageWidthPt, 1);
    final h = math.max(pageHeightPt, 1);
    final left = (pdf.left / w).clamp(0.0, 1.0);
    final right = (pdf.right / w).clamp(0.0, 1.0);
    final top = (1 - pdf.top / h).clamp(0.0, 1.0);
    final bottom = (1 - pdf.bottom / h).clamp(0.0, 1.0);
    return Rect.fromLTRB(
      math.min(left, right),
      math.min(top, bottom),
      math.max(left, right),
      math.max(top, bottom),
    );
  }

  List<PdfFormSpot> _dedupeOverlapping(List<PdfFormSpot> input) {
    final out = <PdfFormSpot>[];
    for (final s in input) {
      final overlaps = out.any(
        (o) =>
            o.normRect.overlaps(s.normRect) &&
            _overlapRatio(o.normRect, s.normRect) > 0.55,
      );
      if (!overlaps) out.add(s);
    }
    return out;
  }

  double _overlapRatio(Rect a, Rect b) {
    final i = a.intersect(b);
    if (i.isEmpty) return 0;
    final area = a.width * a.height;
    if (area < 1e-9) return 0;
    return (i.width * i.height) / area;
  }
}
