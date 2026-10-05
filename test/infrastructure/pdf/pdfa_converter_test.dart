import 'dart:io';

import 'package:document_studio/infrastructure/pdf/pdf_archive_checker.dart';
import 'package:document_studio/infrastructure/pdf/pdf_accessibility_checker.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_text_builder.dart';
import 'package:document_studio/infrastructure/pdf/pdfa/pdfa_converter.dart';
import 'package:document_studio/infrastructure/pdf/pdfa/srgb_icc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sRGB profile has a valid header', () {
    final icc = buildSrgbIccProfile();
    expect(icc.length, greaterThan(2000));
    expect(String.fromCharCodes(icc.sublist(36, 40)), 'acsp');
    final out = Platform.environment['DS_ICC_OUT'];
    if (out != null) File(out).writeAsBytesSync(icc);
  });

  final hasGs = Process.runSync('which', ['gs']).exitCode == 0;
  test('converts a PDF with unembedded fonts to PDF/A-2b', () async {
    final dir = Directory.systemTemp.createTempSync('pdfa_t');
    final input = File('${dir.path}/in.pdf')
      ..writeAsBytesSync(
        PdfOverlayTextBuilder().build(
          pageCount: 1,
          linesForPage: (_) => [
            PdfOverlayTextLine(text: 'Archive me', xPt: 72, yPt: 700, fontSizePt: 20),
          ],
        ),
      );
    final out = '${dir.path}/out.pdf';
    final r = await convertToPdfA(inputPath: input.path, outputPath: out, title: 'Test');
    expect(r.error, isNull);
    final bytes = File(out).readAsBytesSync();
    final report = checkPdfArchiveReadiness(bytes);
    for (final f in report) {
      expect(f.severity, isNot(A11ySeverity.fail), reason: '${f.title}: ${f.detail}');
    }
    final copy = Platform.environment['DS_PDFA_OUT'];
    if (copy != null) File(copy).writeAsBytesSync(bytes);
    dir.deleteSync(recursive: true);
  }, skip: hasGs ? false : 'Ghostscript not installed');
}
