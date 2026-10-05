import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:document_studio/infrastructure/pdf/edit/pdf_content_stream.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_page_editor.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_parser.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _pdf(String content) {
  final sb = StringBuffer('%PDF-1.7\n');
  final offsets = <int>[];
  void obj(String body) {
    offsets.add(sb.length);
    sb.write('${offsets.length} 0 obj\n$body\nendobj\n');
  }

  obj('<< /Type /Catalog /Pages 2 0 R >>');
  obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Contents 4 0 R '
      '/Resources << /XObject << /Im0 5 0 R >> /Font << /F1 6 0 R >> >> >>');
  obj('<< /Length ${content.length} >>\nstream\n$content\nendstream');
  obj('<< /Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceGray '
      '/BitsPerComponent 8 /Length 1 >>\nstream\n\u0080\nendstream');
  obj('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  final xref = sb.length;
  sb.write('xref\n0 ${offsets.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    sb.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  sb.write('trailer\n<< /Size ${offsets.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(sb.toString()));
}

const _page = '''
1 0 0 rg 50 50 100 40 re f
q 200 0 0 100 100 500 cm /Im0 Do Q
BT /F1 12 Tf 100 300 Td (Hello) Tj 0 -20 Td (World) Tj ET
''';

Uint8List _formPdf() {
  const formContent = 'BT /F1 12 Tf 100 300 Td (Inside) Tj ET';
  const pageContent = 'q 1 0 0 1 0 0 cm /Fm0 Do Q';
  final sb = StringBuffer('%PDF-1.7\n');
  final offsets = <int>[];
  void obj(String body) {
    offsets.add(sb.length);
    sb.write('${offsets.length} 0 obj\n$body\nendobj\n');
  }

  obj('<< /Type /Catalog /Pages 2 0 R >>');
  obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Contents 4 0 R '
      '/Resources << /XObject << /Fm0 5 0 R >> >> >>');
  obj('<< /Length ${pageContent.length} >>\nstream\n$pageContent\nendstream');
  obj('<< /Type /XObject /Subtype /Form /BBox [0 0 600 800] '
      '/Resources << /Font << /F1 6 0 R >> >> /Length ${formContent.length} >>\n'
      'stream\n$formContent\nendstream');
  obj('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  final xref = sb.length;
  sb.write('xref\n0 ${offsets.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    sb.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  sb.write('trailer\n<< /Size ${offsets.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(sb.toString()));
}

void main() {
  test('vector shapes: find, recolor, move, delete', () {
    final bytes = _pdf(_page);
    final shapes = findPageShapes(bytes, 1);
    expect(shapes, hasLength(1));
    final sh = shapes.single;
    expect(sh.kind, EditableKind.shape);
    expect(sh.normRect.left, closeTo(50 / 600, 1e-6));
    final colored = recolorPageShape(bytes, 1, sh.opStart, 0, 0, 1)!;
    expect(latin1.decode(readPageContent(PdfEditDocument.open(colored), 1)!).contains('0 0 1 rg'), isTrue);
    final moved = transformPageShape(bytes, 1, sh.opStart, sh.normRect.shift(const Offset(0.1, 0)))!;
    expect(findPageShapes(moved, 1).single.normRect.left, closeTo(sh.normRect.left + 0.1, 1e-4));
    final gone = deletePageShape(bytes, 1, sh.opStart)!;
    expect(findPageShapes(gone, 1), isEmpty);
  });

  test('text inside a form XObject can be removed', () {
    final bytes = _formPdf();
    final out = removeTextInRects(
      bytes,
      1,
      [Rect.fromLTRB(90 / 600, 485 / 800, 160 / 600, 505 / 800)],
    );
    expect(out, isNotNull);
    final doc = PdfEditDocument.open(out!);
    final form = doc.getObject(5) as dynamic;
    final text = latin1.decode(
      decodeStreamData(form.dict, form.data),
    );
    expect(text.contains('Inside'), isFalse);
  });

  test('needed image pixels follow the drawn size and dpi', () {
    final doc = PdfEditDocument.open(_pdf(_page));
    // 200 pt wide at 144 dpi = 400 px.
    expect(imageNeededPixels(doc, 144).values.single, 400);
  });

  test('tokenizer keeps strings and inline images intact', () {
    final ops = parseContentOps(
      Uint8List.fromList(latin1.encode('BT (a (b) c) Tj ET BI /W 1 ID xx EI Q')),
    );
    expect(ops.map((o) => o.name), ['BT', 'Tj', 'ET', 'BI', 'Q']);
  });

  test('finds the image rectangle in display space', () {
    final imgs = findPageImages(_pdf(_page), 1);
    expect(imgs, hasLength(1));
    final r = imgs.single.normRect;
    expect(r.left, closeTo(100 / 600, 1e-6));
    expect(r.right, closeTo(300 / 600, 1e-6));
    // user y 500..600 → display top 200..300 on an 800pt page
    expect(r.top, closeTo(200 / 800, 1e-6));
    expect(r.bottom, closeTo(300 / 800, 1e-6));
  });

  test('delete removes the Do operator', () {
    final bytes = _pdf(_page);
    final img = findPageImages(bytes, 1).single;
    final out = deletePageImage(bytes, 1, img.opStart)!;
    expect(findPageImages(out, 1), isEmpty);
  });

  test('move keeps size, resize scales it', () {
    final bytes = _pdf(_page);
    final img = findPageImages(bytes, 1).single;
    final moved = transformPageImage(
      bytes,
      1,
      img.opStart,
      img.normRect.shift(const Offset(0.1, 0.1)),
    )!;
    final m = findPageImages(moved, 1).single.normRect;
    expect(m.left, closeTo(img.normRect.left + 0.1, 1e-4));
    expect(m.width, closeTo(img.normRect.width, 1e-4));
    final big = transformPageImage(
      moved,
      1,
      findPageImages(moved, 1).single.opStart,
      Rect.fromLTWH(0.1, 0.1, 0.6, 0.2),
    )!;
    final b = findPageImages(big, 1).single.normRect;
    expect(b.width, closeTo(0.6, 1e-4));
    expect(b.height, closeTo(0.2, 1e-4));
  });

  test('removeTextInRects deletes only the targeted line', () {
    final bytes = _pdf(_page);
    // "Hello" baseline y=300 → display y 500 → norm 0.625; box around it.
    final out = removeTextInRects(
      bytes,
      1,
      [Rect.fromLTRB(90 / 600, 485 / 800, 150 / 600, 505 / 800)],
    )!;
    final doc = PdfEditDocument.open(out);
    final content = latin1.decode(readPageContent(doc, 1)!);
    expect(content.contains('(Hello)'), isFalse);
    expect(content.contains('(World)'), isTrue);
  });

  test('vector redaction removes the text and keeps the rest', () {
    final bytes = _pdf(_page);
    final r = redactPageVector(
      bytes,
      1,
      [Rect.fromLTRB(90 / 600, 485 / 800, 150 / 600, 505 / 800)],
    )!;
    expect(r.imagesTouched, isFalse);
    final content = latin1.decode(
      readPageContent(PdfEditDocument.open(r.bytes), 1)!,
    );
    expect(content.contains('Hello'), isFalse);
    expect(content.contains('(World)'), isTrue);
    expect(content.contains('re f'), isTrue);
  });

  test('redaction over a picture asks for flattening', () {
    final bytes = _pdf(_page);
    final img = findPageImages(bytes, 1).single.normRect;
    final r = redactPageVector(bytes, 1, [img.deflate(0.01)])!;
    expect(r.imagesTouched, isTrue);
  });

  test('nothing to remove returns null', () {
    expect(
      removeTextInRects(_pdf(_page), 1, [const Rect.fromLTWH(0.9, 0.9, 0.05, 0.05)]),
      isNull,
    );
  });
}
