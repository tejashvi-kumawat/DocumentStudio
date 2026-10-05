import 'dart:io';

import 'package:document_studio/infrastructure/pdf/pdf_overlay_text_builder.dart';
import 'package:document_studio/infrastructure/pdf/ttf_font.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final full = File('assets/fonts/text/LiberationSerif-Regular.ttf').readAsBytesSync();
  final font = TtfFont.parse(full)!;

  test('subset keeps metrics and shrinks the font', () {
    final sub = font.subset('Hello world'.runes);
    expect(sub.length, lessThan(full.length ~/ 5));
    final again = TtfFont.parse(sub)!;
    expect(again.textWidthPt('Hello world', 12), font.textWidthPt('Hello world', 12));
  });

  test('embedded subset renders in a PDF', () {
    final pdf = PdfOverlayTextBuilder().build(
      pageCount: 1,
      linesForPage: (_) => [
        PdfOverlayTextLine(
          text: 'Subset Quality',
          xPt: 72,
          yPt: 700,
          fontSizePt: 24,
          ttf: font,
        ),
      ],
    );
    expect(pdf.length, lessThan(40 * 1024));
    final out = Platform.environment['DS_SUBSET_OUT'];
    if (out != null) File(out).writeAsBytesSync(pdf);
  });
}
