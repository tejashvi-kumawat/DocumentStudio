import 'dart:typed_data';

import 'package:document_studio/domain/pdf_markup/pdf_page_geometry.dart';
import 'package:document_studio/infrastructure/ocr/hocr_word_parser.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_content_builder.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_page_stamper.dart';
import 'package:document_studio/infrastructure/pdf/pdf_helvetica_metrics.dart';

/// Stamp kind for OCR invisible text layers (removable via [PdfPageStamper]).
const kOcrTextStampKind = 'OcrText';

/// Invisible text for one PDF page, ready to stamp.
class PageOcrTextLayer {
  const PageOcrTextLayer({
    required this.page1Based,
    required this.words,
    this.fallbackLines = const [],
    required this.imageWidthPx,
    required this.imageHeightPx,
  });

  final int page1Based;
  final List<HocrWord> words;

  /// When hOCR had no boxes — plain lines laid out top-to-bottom.
  final List<String> fallbackLines;
  final int imageWidthPx;
  final int imageHeightPx;

  bool get isEmpty =>
      words.isEmpty && fallbackLines.every((l) => l.trim().isEmpty);
}

/// Burns OCR text as invisible Helvetica into [pdf] (pure Dart, no qpdf).
Uint8List stampOcrTextLayers(Uint8List pdf, List<PageOcrTextLayer> layers) {
  final usable = layers.where((l) => !l.isEmpty).toList();
  if (usable.isEmpty) return pdf;

  final doc = PdfEditDocument.open(pdf);
  final stamper = PdfPageStamper(doc);
  final fontRef = stamper.font(PdfStdFont.helvetica);

  for (final layer in usable) {
    if (layer.page1Based < 1 || layer.page1Based > doc.pageCount) continue;
    final geo = doc.pageGeometry(layer.page1Based);
    final content = _buildPageContent(layer, geo, fontRefName: 'F1');
    if (content.isEmpty) continue;
    final res = PdfStampResources()..fonts['F1'] = fontRef;
    stamper.stamp(
      layer.page1Based,
      kind: kOcrTextStampKind,
      content: content,
      resources: res,
    );
  }
  if (!doc.hasChanges) return pdf;
  return doc.save();
}

Uint8List _buildPageContent(
  PageOcrTextLayer layer,
  PdfPageGeometry geo, {
  required String fontRefName,
}) {
  final pageW = geo.displayWidth;
  final pageH = geo.displayHeight;
  final cb = PdfContentBuilder();
  var wrote = false;

  if (layer.words.isNotEmpty &&
      layer.imageWidthPx > 0 &&
      layer.imageHeightPx > 0) {
    final sx = pageW / layer.imageWidthPx;
    final sy = pageH / layer.imageHeightPx;
    for (final w in layer.words) {
      final text = sanitizeForStdFont(w.text);
      if (text.trim().isEmpty) continue;
      final boxW = w.widthPx * sx;
      final boxH = w.heightPx * sy;
      if (boxW < 0.5 || boxH < 0.5) continue;
      final left = w.x0 * sx;
      // Image y grows down; PDF display-up y grows up from page bottom.
      final bottom = pageH - w.y1 * sy;
      final fontSize = (boxH * 0.85).clamp(4.0, 72.0);
      final natural = helveticaTextWidthPt(text, fontSize);
      final horiz = natural > 0.01 ? boxW / natural : 1.0;
      // Tf size 1 + Tm scale ≈ fontSize with optional horizontal fit.
      cb.text(
        fontRefName,
        1,
        Affine2(fontSize * horiz, 0, 0, fontSize, left, bottom + boxH * 0.12),
        text,
        invisible: true,
      );
      wrote = true;
    }
  }

  if (!wrote && layer.fallbackLines.isNotEmpty) {
    const margin = 36.0;
    const size = 11.0;
    const leading = 14.0;
    var y = pageH - margin - size;
    for (final line in layer.fallbackLines) {
      final text = sanitizeForStdFont(line);
      if (text.trim().isEmpty) {
        y -= leading;
        continue;
      }
      if (y < margin) break;
      cb.text(
        fontRefName,
        size,
        Affine2.translate(margin, y),
        text,
        invisible: true,
      );
      wrote = true;
      y -= leading;
    }
  }

  return wrote ? cb.bytes() : Uint8List(0);
}
