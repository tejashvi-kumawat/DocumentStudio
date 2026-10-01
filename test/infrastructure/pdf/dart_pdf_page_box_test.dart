import 'dart:io';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/infrastructure/conversion/blank_pdf_service.dart';
import 'package:document_studio/infrastructure/pdf/dart_pdf_page_box.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_objects.dart';
import 'package:document_studio/infrastructure/pdf/pdf_page_box_options.dart';
import 'package:document_studio/infrastructure/pdf/pdfrx_structure_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ds_page_box_');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('cropPagesToBox sets CropBox and leaves other pages', () async {
    final input = p.join(dir.path, 'in.pdf');
    final output = p.join(dir.path, 'out.pdf');
    await BlankPdfService().create(outputPath: input, pageCount: 2);

    await PdfrxStructureAdapter().cropPagesToBox(
      input: LocalFileRef(path: input, displayName: 'in.pdf'),
      pageNumbers1Based: {2},
      box: const PdfCropRectPt(llx: 10, lly: 20, urx: 110, ury: 220),
      outputPath: output,
    );

    final doc = PdfEditDocument.open(await File(output).readAsBytes());
    expect(doc.pageCount, 2);
    expect(doc.pageDict(1).containsKey('CropBox'), isFalse);
    expect(_box(doc.pageDict(1)['MediaBox']), [0, 0, 612, 792]);
    expect(_box(doc.pageDict(2)['CropBox']), [10, 20, 110, 220]);
    expect(_box(doc.pageDict(2)['MediaBox']), [0, 0, 612, 792]);
  });

  test('margin crop insets an inherited MediaBox', () async {
    final input = p.join(dir.path, 'inherited.pdf');
    final output = p.join(dir.path, 'cropped.pdf');
    await File(input).writeAsBytes(await _inheritedMediaPdf());

    await DartPdfPageBox.cropPages(
      input: LocalFileRef(path: input, displayName: 'inherited.pdf'),
      pageNumbers1Based: {1},
      margin: PdfCropMarginPreset.small,
      outputPath: output,
    );

    final doc = PdfEditDocument.open(await File(output).readAsBytes());
    final marginPt = 5 * 72 / 25.4;
    final geo = doc.pageGeometry(1);
    expect(geo.cropLeft, closeTo(marginPt, 0.02));
    expect(geo.cropBottom, closeTo(marginPt, 0.02));
    expect(geo.cropWidth, closeTo(200 - 2 * marginPt, 0.02));
    expect(geo.cropHeight, closeTo(400 - 2 * marginPt, 0.02));
  });

  test('setPageSize writes MediaBox and CropBox without qpdf', () async {
    final input = p.join(dir.path, 'in.pdf');
    final output = p.join(dir.path, 'resized.pdf');
    await BlankPdfService().create(outputPath: input, pageCount: 1);

    await DartPdfPageBox.setPageSize(
      input: LocalFileRef(path: input, displayName: 'in.pdf'),
      pageNumbers1Based: {1},
      paperSize: PdfPaperSize.a4,
      outputPath: output,
    );

    final doc = PdfEditDocument.open(await File(output).readAsBytes());
    const a4 = [0.0, 0.0, 595.28, 841.89];
    expect(_box(doc.pageDict(1)['MediaBox']), a4);
    expect(_box(doc.pageDict(1)['CropBox']), a4);
  });

  test('unknown page is rejected', () async {
    final input = p.join(dir.path, 'in.pdf');
    await BlankPdfService().create(outputPath: input, pageCount: 1);
    expect(
      () => DartPdfPageBox.cropPagesToBox(
        input: LocalFileRef(path: input, displayName: 'in.pdf'),
        pageNumbers1Based: {3},
        box: const PdfCropRectPt(llx: 0, lly: 0, urx: 100, ury: 100),
        outputPath: p.join(dir.path, 'nope.pdf'),
      ),
      throwsA(
        isA<DocumentStudioError>().having(
          (e) => e.message,
          'message',
          contains('outside'),
        ),
      ),
    );
  });
}

List<double> _box(PdfObj? raw) {
  final arr = raw! as PdfArray;
  return [for (final e in arr.items) (e as PdfNum).d];
}

/// One page whose MediaBox lives on the parent Pages node.
Future<List<int>> _inheritedMediaPdf() async {
  final scratch = await Directory.systemTemp.createTemp('ds_page_box_src_');
  try {
    final path = p.join(scratch.path, 'blank.pdf');
    await BlankPdfService().create(outputPath: path, pageCount: 1);
    final doc = PdfEditDocument.open(await File(path).readAsBytes());
    final page = doc.pageDict(1).clone();
    page.remove('MediaBox');
    doc.setObject(doc.pageRef(1), page);
    final pagesRef = doc.catalog['Pages']! as PdfRef;
    final pages = doc.dictOf(pagesRef)!.clone();
    pages['MediaBox'] = PdfArray.nums([0, 0, 200, 400]);
    doc.setObject(pagesRef, pages);
    return doc.save();
  } finally {
    await scratch.delete(recursive: true);
  }
}
