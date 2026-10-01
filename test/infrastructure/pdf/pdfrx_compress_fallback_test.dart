import 'dart:convert';
import 'dart:typed_data';

import 'package:document_studio/infrastructure/pdf/dart_pdf_compress.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_objects.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_parser.dart';
import 'package:document_studio/infrastructure/pdf/pdf_compress_options.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

/// Builds a tiny PDF with one DCTDecode image large enough to shrink.
Uint8List _pdfWithJpegImage() {
  final frame = img.Image(width: 400, height: 300, numChannels: 3);
  for (var y = 0; y < 300; y++) {
    for (var x = 0; x < 400; x++) {
      frame.setPixelRgb(x, y, (x * 3) & 0xff, (y * 5) & 0xff, 180);
    }
  }
  // High-quality JPEG so re-encode at q=50 + downsample clearly shrinks.
  final jpeg = Uint8List.fromList(img.encodeJpg(frame, quality: 95));
  final len = jpeg.length;

  final b = BytesBuilder();
  void w(String s) => b.add(s.codeUnits);
  final off = <int>[0];

  void mark() => off.add(b.length);

  w('%PDF-1.4\n');
  mark();
  w('1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj\n');
  mark();
  w('2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj\n');
  mark();
  w(
    '3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 300] '
    '/Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>endobj\n',
  );
  mark();
  w(
    '4 0 obj<< /Type /XObject /Subtype /Image /Width 400 /Height 300 '
    '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode '
    '/Length $len >>stream\n',
  );
  b.add(jpeg);
  w('\nendstream\nendobj\n');
  mark();
  w(
    '5 0 obj<< /Length 37 >>stream\n'
    'q 400 0 0 300 0 0 cm /Im0 Do Q\n'
    'endstream\nendobj\n',
  );
  final xref = b.length;
  w('xref\n0 6\n');
  w('0000000000 65535 f \n');
  for (var i = 1; i <= 5; i++) {
    w('${off[i].toString().padLeft(10, '0')} 00000 n \n');
  }
  w('trailer<< /Size 6 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return b.toBytes();
}

/// One-page PDF whose only content is selectable Helvetica text.
Uint8List _textOnlyPdf() {
  const content = 'BT /F1 24 Tf 72 720 Td (Hello selectable) Tj ET\n';
  final body = BytesBuilder();
  final off = <int>[0];
  void mark() => off.add(body.length);
  void w(String s) => body.add(s.codeUnits);

  w('%PDF-1.4\n');
  mark();
  w('1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj\n');
  mark();
  w('2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj\n');
  mark();
  w(
    '3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
    '/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>endobj\n',
  );
  mark();
  w('4 0 obj<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>endobj\n');
  mark();
  w('5 0 obj<< /Length ${content.length} >>stream\n');
  w(content);
  w('endstream\nendobj\n');
  final xref = body.length;
  w('xref\n0 6\n');
  w('0000000000 65535 f \n');
  for (var i = 1; i <= 5; i++) {
    w('${off[i].toString().padLeft(10, '0')} 00000 n \n');
  }
  w('trailer<< /Size 6 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return body.toBytes();
}

Uint8List _pdfWithSizedJpeg({required int side, required int quality}) {
  final raw = Uint8List(side * side * 3);
  for (var i = 0; i < raw.length; i++) {
    raw[i] = (i * 1103515245 + 12345) & 0xff;
  }
  final frame = img.Image.fromBytes(
    width: side,
    height: side,
    bytes: raw.buffer,
    numChannels: 3,
  );
  final jpeg = Uint8List.fromList(img.encodeJpg(frame, quality: quality));
  final len = jpeg.length;
  final b = BytesBuilder();
  final off = <int>[0];
  void mark() => off.add(b.length);
  void w(String s) => b.add(s.codeUnits);

  w('%PDF-1.4\n');
  mark();
  w('1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj\n');
  mark();
  w('2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj\n');
  mark();
  w(
    '3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $side $side] '
    '/Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>endobj\n',
  );
  mark();
  w(
    '4 0 obj<< /Type /XObject /Subtype /Image /Width $side /Height $side '
    '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode '
    '/Length $len >>stream\n',
  );
  b.add(jpeg);
  w('\nendstream\nendobj\n');
  mark();
  final content = 'q $side 0 0 $side 0 0 cm /Im0 Do Q\n';
  w(
    '5 0 obj<< /Length ${content.length} >>stream\n'
    '${content}endstream\nendobj\n',
  );
  final xref = b.length;
  w('xref\n0 6\n');
  w('0000000000 65535 f \n');
  for (var i = 1; i <= 5; i++) {
    w('${off[i].toString().padLeft(10, '0')} 00000 n \n');
  }
  w('trailer<< /Size 6 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return b.toBytes();
}

int? _imageWidth(Uint8List pdf) {
  final doc = PdfEditDocument.open(pdf);
  for (final n in doc.liveObjectNumbers) {
    final obj = doc.getObject(n);
    if (obj is PdfStream && obj.dict.nameOf('Subtype') == 'Image') {
      return (obj.dict['Width'] as PdfNum?)?.i;
    }
  }
  return null;
}

String _pageContentText(Uint8List pdf) {
  final doc = PdfEditDocument.open(pdf);
  final page = doc.pageDict(1);
  final raw = page['Contents'];
  final resolved = doc.resolve(raw);
  final items = resolved is PdfArray
      ? resolved.items
      : <PdfObj>[?raw];
  final buf = StringBuffer();
  for (final item in items) {
    final stream = doc.resolve(item);
    if (stream is! PdfStream) continue;
    final filter = stream.dict['Filter'];
    final data = filter == null
        ? stream.data
        : decodeStreamData(stream.dict, stream.data);
    buf.write(latin1.decode(data));
  }
  return buf.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('image pass count is 1, then 2 above 400 KB', () {
    expect(dartPdfImageCompressPasses(400 * 1024), 1);
    expect(dartPdfImageCompressPasses(400 * 1024 + 1), 2);
    expect(kDartPdfImageSecondPassBytes, 400 * 1024);
  });

  test('presets match the compress table', () {
    final smallest = PdfCompressOptions.fromProfile(CompressProfile.smallest);
    final extreme = PdfCompressOptions.fromProfile(CompressProfile.extreme);
    final recommended = PdfCompressOptions.fromProfile(CompressProfile.balanced);
    final lossless = PdfCompressOptions.fromProfile(CompressProfile.highQuality);
    expect(smallest.jpegQuality, 40);
    expect(smallest.downsampleMaxPx, 1000);
    expect(extreme.jpegQuality, 45);
    expect(extreme.downsampleMaxPx, 1200);
    expect(recommended.jpegQuality, 60);
    expect(recommended.downsampleMaxPx, 1600);
    expect(lossless.jpegQuality, isNull);
    expect(lossless.downsampleMaxPx, isNull);
    expect(lossless.lossyImages, isFalse);
    expect(smallest.userLabel, 'Smallest');
    expect(extreme.userLabel, 'Extreme');
    expect(recommended.userLabel, 'Recommended');
    expect(lossless.userLabel, 'Lossless');
    expect(dartPdfSecondPassQuality(40), 30);
    expect(dartPdfSecondPassMaxPx(1000), 800);
    expect(dartPdfSecondPassQuality(45), 35);
    expect(dartPdfSecondPassMaxPx(1200), 960);
    expect(dartPdfSecondPassQuality(60), 50);
    expect(dartPdfSecondPassMaxPx(1600), 1280);
  });

  test('DartPdfCompress shrinks a JPEG-heavy PDF without qpdf', () async {
    try {
      await pdfrxFlutterInitialize();
    } catch (_) {}

    final input = _pdfWithJpegImage();
    final out = await DartPdfCompress.compressBytes(
      input,
      options: PdfCompressOptions.fromProfile(CompressProfile.smallest),
    );

    expect(out.length, lessThan(input.length));
    expect(out.length, greaterThan(50));
    // Must not be an identical copy.
    expect(out, isNot(orderedEquals(input)));

    final doc = await PdfDocument.openData(out);
    try {
      expect(doc.pages.length, 1);
    } finally {
      await doc.dispose();
    }
  });

  test('lossy compress keeps selectable text on a text-only page', () async {
    final input = _textOnlyPdf();
    final out = await DartPdfCompress.compressBytes(
      input,
      options: PdfCompressOptions.fromProfile(CompressProfile.smallest),
    );
    final text = _pageContentText(out);
    expect(text, contains('Hello selectable'));
    expect(text, contains('Tj'));
    expect(_imageWidth(out), isNull);
  });

  test('Smallest downscales a photo so the longest edge is at most 1000px', () async {
    try {
      await pdfrxFlutterInitialize();
    } catch (_) {}
    final input = _pdfWithSizedJpeg(side: 1600, quality: 95);
    final out = await DartPdfCompress.compressBytes(
      input,
      options: PdfCompressOptions.fromProfile(CompressProfile.smallest),
    );
    expect(out.length, lessThan(input.length));
    final width = _imageWidth(out);
    expect(width, isNotNull);
    expect(width!, lessThanOrEqualTo(1000));
    expect(width, greaterThan(0));
    final doc = await PdfDocument.openData(out);
    try {
      expect(doc.pages.length, 1);
    } finally {
      await doc.dispose();
    }
  });

  test('DartPdfCompress lossless rewrite stays openable', () async {
    try {
      await pdfrxFlutterInitialize();
    } catch (_) {}

    const src = '%PDF-1.4\n'
        '1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj\n'
        '2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj\n'
        '3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] >>endobj\n'
        'xref\n0 4\n'
        '0000000000 65535 f \n'
        '0000000009 00000 n \n'
        '0000000058 00000 n \n'
        '0000000115 00000 n \n'
        'trailer<< /Size 4 /Root 1 0 R >>\n'
        'startxref\n190\n%%EOF\n';
    final input = Uint8List.fromList(src.codeUnits);
    final out = await DartPdfCompress.compressBytes(
      input,
      options: PdfCompressOptions.fromProfile(CompressProfile.highQuality),
    );
    final doc = await PdfDocument.openData(out);
    try {
      expect(doc.pages.length, 1);
    } finally {
      await doc.dispose();
    }
  });
}
