import 'dart:io';
import 'dart:ui';

import 'package:document_studio/infrastructure/pdf/edit/pdf_page_stamp.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_text_builder.dart';
import 'package:document_studio/infrastructure/pdf/ttf_font.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stamps text (std and embedded font) and covers onto a page', () {
    final base = PdfOverlayTextBuilder().build(
      pageCount: 2,
      linesForPage: (p) => [
        PdfOverlayTextLine(text: 'Original $p', xPt: 72, yPt: 700, fontSizePt: 14),
      ],
    );
    final ttf = TtfFont.parse(
      File('assets/fonts/text/LiberationSerif-Regular.ttf').readAsBytesSync(),
    )!;
    final overlay = PdfOverlayTextBuilder().build(
      pageCount: 1,
      pageWidthPt: (_) => 612,
      pageHeightPt: (_) => 792,
      linesForPage: (_) => [
        PdfOverlayTextLine(text: 'Stamped Std', xPt: 72, yPt: 400, fontSizePt: 18),
        PdfOverlayTextLine(text: 'Stamped Ttf', xPt: 72, yPt: 300, fontSizePt: 18, ttf: ttf),
      ],
    );
    final out = stampOverlayOnPage(
      base,
      2,
      overlay,
      covers: const [Rect.fromLTRB(0.1, 0.1, 0.4, 0.13)],
    )!;
    expect(out.length, greaterThan(base.length));
    final path = Platform.environment['DS_STAMP_OUT'];
    if (path != null) File(path).writeAsBytesSync(out);
  });
}
