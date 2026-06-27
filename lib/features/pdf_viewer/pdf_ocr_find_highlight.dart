import 'package:document_studio/design_system/ds_colors.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Page wash for in-memory OCR find hits (no glyph boxes from CLI OCR).
///
/// Text-layer matches still use [PdfTextSearcher.pageTextMatchPaintCallback].
PdfViewerPagePaintCallback paintOcrFindPageHits({
  required List<int> hitPages1Based,
  required int? currentPage1Based,
}) {
  return (canvas, pageRect, page) {
    if (hitPages1Based.isEmpty) return;
    final page1 = page.pageNumber;
    if (!hitPages1Based.contains(page1)) return;
    final isCurrent = currentPage1Based == page1;
    final fill = Paint()
      ..color = DsColors.warning.withValues(alpha: isCurrent ? 0.22 : 0.10)
      ..style = PaintingStyle.fill;
    final inset = pageRect.deflate(pageRect.width * 0.02);
    canvas.drawRect(inset, fill);
    if (isCurrent) {
      final stroke = Paint()
        ..color = DsColors.primary.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRect(inset, stroke);
    }
  };
}
