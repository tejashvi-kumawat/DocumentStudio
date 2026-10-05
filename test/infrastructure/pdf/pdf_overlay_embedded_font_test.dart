import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_text_builder.dart';
import 'package:document_studio/infrastructure/pdf/ttf_font.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('embedded TrueType font produces a parseable file with FontFile2', () {
    final ttf = TtfFont.parse(
      File('assets/fonts/text/LiberationSerif-Regular.ttf').readAsBytesSync(),
    )!;
    final bytes = PdfOverlayTextBuilder().build(
      pageCount: 1,
      linesForPage: (_) => [
        PdfOverlayTextLine(text: 'Hello', xPt: 50, yPt: 700, ttf: ttf),
        const PdfOverlayTextLine(text: 'Std', xPt: 50, yPt: 650),
      ],
    );
    final doc = PdfEditDocument.open(Uint8List.fromList(bytes));
    expect(doc.pageCount, 1);
    final text = String.fromCharCodes(bytes);
    expect(text.contains('/FontFile2'), isTrue);
    expect(text.contains('/Subtype /TrueType'), isTrue);
    expect(text.contains('/BaseFont /Helvetica'), isTrue);
  });
}
