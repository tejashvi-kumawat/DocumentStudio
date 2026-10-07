import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/pdf_markup/pdf_markup_models.dart';
import 'package:document_studio/infrastructure/pdf/composite_structure_adapter.dart';
import 'package:document_studio/infrastructure/pdf/pdf_link_annotation_service.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_service.dart';
import 'dart:ui' show Rect;
import 'package:document_studio/infrastructure/pdf/pdfrx_render_adapter.dart';
import 'package:document_studio/infrastructure/pdf/routing_pdf_encrypt_adapter.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/infrastructure/pdf/pdf_compress_options.dart';
import 'package:document_studio/infrastructure/pdf/pdf_page_box_options.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

/// Every structural PDF tool, run end to end on a generated document, with
/// each output opened again by PDFium and by our own parser.
void main() {
  late Directory dir;
  late LocalFileRef src;
  final tools = CompositePdfStructureAdapter();

  Future<Uint8List> makePdf(int pages, String label) async {
    final doc = pw.Document();
    for (var i = 1; i <= pages; i++) {
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Center(child: pw.Text('$label page $i', style: const pw.TextStyle(fontSize: 32))),
      ));
    }
    return doc.save();
  }

  Future<String> textOf(String path, int page) async {
    final d = await PdfDocument.openFile(path);
    try {
      return (await d.pages[page - 1].loadText())?.fullText ?? '';
    } finally {
      await d.dispose();
    }
  }

  Future<int> pagesOf(String path) async {
    // Both readers must accept the file.
    expect(PdfEditDocument.open(File(path).readAsBytesSync()).pageCount, greaterThan(0));
    final d = await PdfDocument.openFile(path);
    try {
      return d.pages.length;
    } finally {
      await d.dispose();
    }
  }

  LocalFileRef ref(String path) => LocalFileRef(path: path, displayName: p.basename(path));
  String out(String name) => p.join(dir.path, name);

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    dir = await Directory.systemTemp.createTemp('ds_tools_');
    Pdfrx.cacheDirectoryPath = dir.path; // no path_provider in tests
    await pdfrxFlutterInitialize();
    final path = out('src.pdf');
    await File(path).writeAsBytes(await makePdf(6, 'Source'));
    src = ref(path);
  });

  tearDownAll(() async {
    await dir.delete(recursive: true);
  });

  test('merge', () async {
    final second = out('second.pdf');
    await File(second).writeAsBytes(await makePdf(2, 'Second'));
    final r = await tools.merge(inputs: [src, ref(second)], outputPath: out('merged.pdf'));
    expect(await pagesOf(r.path), 8);
    expect(await textOf(r.path, 7), contains('Second page 1'));
  });

  test('extract pages', () async {
    final r = await tools.extractPages(input: src, pageNumbers1Based: [2, 5], outputPath: out('extract.pdf'));
    expect(await pagesOf(r.path), 2);
    expect(await textOf(r.path, 2), contains('Source page 5'));
  });

  test('split every N pages and by ranges', () async {
    final parts = await tools.splitEveryNPages(input: src, pagesPerFile: 4, outputDirectory: dir.path, namePrefix: 'part');
    expect([for (final f in parts) await pagesOf(f.path)], [4, 2]);
    final ranges = await tools.splitByRanges(
      input: src,
      rangesPages1Based: [
        [1, 2],
        [6],
      ],
      outputDirectory: dir.path,
      namePrefix: 'range',
    );
    expect([for (final f in ranges) await pagesOf(f.path)], [2, 1]);
  });

  test('delete, reorder, reverse', () async {
    final del = await tools.deletePages(input: src, deletePages1Based: {1, 6}, outputPath: out('del.pdf'));
    expect(await pagesOf(del.path), 4);
    expect(await textOf(del.path, 1), contains('Source page 2'));
    final re = await tools.reorderPages(input: src, newOrder1Based: [3, 1, 2, 4, 5, 6], outputPath: out('reorder.pdf'));
    expect(await textOf(re.path, 1), contains('Source page 3'));
    final rev = await tools.reversePages(input: src, outputPath: out('rev.pdf'));
    expect(await textOf(rev.path, 1), contains('Source page 6'));
  });

  test('rotate', () async {
    final r = await tools.rotatePages(input: src, pageRotationsDegrees: {1: 90}, outputPath: out('rot.pdf'));
    final d = await PdfDocument.openFile(r.path);
    try {
      expect(d.pages.first.rotation, PdfPageRotation.clockwise90);
      expect(d.pages[1].rotation, PdfPageRotation.none);
    } finally {
      await d.dispose();
    }
  });

  test('compress keeps every page and the text', () async {
    final r = await tools.compressPdf(input: src, outputPath: out('small.pdf'), options: const PdfCompressOptions());
    expect(await pagesOf(r.path), 6);
    expect(await textOf(r.path, 4), contains('Source page 4'));
  });

  test('crop and page size', () async {
    if (!await tools.supportsPageBoxEditing()) return;
    final c = await tools.cropPages(input: src, pageNumbers1Based: {1}, margin: PdfCropMarginPreset.medium, outputPath: out('crop.pdf'));
    expect(await pagesOf(c.path), 6);
    final s = await tools.setPageSize(input: src, pageNumbers1Based: {1, 2}, paperSize: PdfPaperSize.letter, outputPath: out('letter.pdf'));
    final d = await PdfDocument.openFile(s.path);
    try {
      expect(d.pages.first.width, closeTo(612, 1));
      expect(d.pages[2].width, closeTo(595, 1));
    } finally {
      await d.dispose();
    }
  });

  test('header & footer, page numbers, text watermark', () async {
    final overlay = PdfOverlayService(render: PdfrxRenderAdapter());
    final hf = await overlay.applyHeaderFooter(
      input: src,
      outputPath: out('hf.pdf'),
      options: const HeaderFooterOptions(headerTemplate: 'Quarterly report', footerTemplate: 'Confidential'),
    );
    expect(await pagesOf(hf.path), 6);
    expect(await textOf(hf.path, 3), allOf(contains('Quarterly report'), contains('Confidential'), contains('Source page 3')));
    final nums = await overlay.applyPageNumbers(input: src, outputPath: out('nums.pdf'), options: const PageNumberOptions());
    expect(await textOf(nums.path, 4), contains('4'));
    final wm = await overlay.applyTextWatermark(
      input: src,
      outputPath: out('wm.pdf'),
      options: const WatermarkOptions(textTemplate: 'DRAFT COPY'),
    );
    expect(await pagesOf(wm.path), 6);
    expect(await textOf(wm.path, 2), contains('DRAFT COPY'));
  });

  test('password protect and unlock', () async {
    final sec = RoutingPdfEncryptAdapter();
    final locked = await sec.encryptWithPassword(input: src, outputPath: out('locked.pdf'), userPassword: 's3cret');
    // Without the password PDFium refuses; with it the text is back.
    await expectLater(PdfDocument.openFile(locked.path, firstAttemptByEmptyPassword: true), throwsA(anything));
    final d = await PdfDocument.openFile(locked.path, passwordProvider: () => 's3cret');
    expect(d.pages.length, 6);
    await d.dispose();
    final open = await sec.decryptToFile(input: locked, outputPath: out('unlocked.pdf'), password: 's3cret');
    expect(await textOf(open.path, 1), contains('Source page 1'));
  });

  test('add, replace and remove a link without qpdf', () async {
    const box = Rect.fromLTWH(0.2, 0.3, 0.3, 0.05);
    final added = await PdfLinkAnnotationService().addLinkToBytes(
      input: src,
      link: const PdfLinkAnnotationSpec.uriDisplayNorm(pageIndex1Based: 2, displayNormRect: box, uri: 'example.org'),
    );
    final withLink = out('linked.pdf');
    await File(withLink).writeAsBytes(added);
    var d = await PdfDocument.openFile(withLink);
    var links = await d.pages[1].loadLinks();
    expect(links, hasLength(1));
    expect(links.single.url.toString(), 'https://example.org');
    expect((await d.pages[0].loadLinks()), isEmpty);
    await d.dispose();
    // Replace it with another address in the same place.
    final replaced = await PdfLinkAnnotationService().addLinkToBytes(
      input: ref(withLink),
      link: const PdfLinkAnnotationSpec.uriDisplayNorm(pageIndex1Based: 2, displayNormRect: box, uri: 'https://dart.dev'),
      replaceDisplayNormRect: box,
    );
    await File(withLink).writeAsBytes(replaced);
    d = await PdfDocument.openFile(withLink);
    links = await d.pages[1].loadLinks();
    expect(links.map((l) => l.url.toString()), ['https://dart.dev']);
    await d.dispose();
    final removed = await PdfLinkAnnotationService().removeLinksToBytes(input: ref(withLink), pageIndex1Based: 2, displayNormRect: box);
    await File(withLink).writeAsBytes(removed);
    d = await PdfDocument.openFile(withLink);
    expect(await d.pages[1].loadLinks(), isEmpty);
    await d.dispose();
  });
}
