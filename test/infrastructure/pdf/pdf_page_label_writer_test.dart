import 'dart:io';

import 'package:document_studio/features/pdf_viewer/pdf_page_labels.dart';
import 'package:document_studio/infrastructure/conversion/blank_pdf_service.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/infrastructure/pdf/pdf_page_label_writer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ds_page_labels_');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('dart writer stores decimal and roman PageLabels', () async {
    final input = p.join(dir.path, 'in.pdf');
    await BlankPdfService().create(outputPath: input, pageCount: 4);
    final opened = PdfEditDocument.open(await File(input).readAsBytes());
    expect(opened.pageDict(1).containsKey('MediaBox'), isTrue);

    final first = writePdfPageLabelsOnDocument(
      doc: opened,
      pageCount: 4,
      edit: const PdfPageLabelEdit(
        allPages: false,
        fromPage1: 1,
        toPage1: 2,
        beginNewSection: true,
        style: 'r',
        prefix: 'A-',
        startAt: 4,
      ),
    );
    final mid = PdfEditDocument.open(first.bytes);
    expect(mid.pageCount, 4);
    final roman = readPdfPageLabelRanges(mid);
    expect(resolvePdfPageLabel(page1Based: 1, ranges: roman), 'A-iv');
    expect(resolvePdfPageLabel(page1Based: 2, ranges: roman), 'A-v');
    expect(resolvePdfPageLabel(page1Based: 3, ranges: roman), '3');

    final second = writePdfPageLabelsOnDocument(
      doc: mid,
      pageCount: 4,
      edit: const PdfPageLabelEdit(
        allPages: true,
        fromPage1: 1,
        toPage1: 4,
        beginNewSection: true,
        style: 'D',
        prefix: 'P',
        startAt: 10,
      ),
    );
    final done = PdfEditDocument.open(second.bytes);
    final labels = readPdfPageLabelRanges(done);
    expect(resolvePdfPageLabel(page1Based: 1, ranges: labels), 'P10');
    expect(resolvePdfPageLabel(page1Based: 4, ranges: labels), 'P13');
    expect(done.pageCount, 4);
  });
}
