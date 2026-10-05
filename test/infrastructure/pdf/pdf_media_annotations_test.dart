import 'dart:convert';
import 'dart:typed_data';

import 'package:document_studio/infrastructure/pdf/pdf_media_annotations.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _pdf() {
  final sb = StringBuffer('%PDF-1.7\n');
  final offsets = <int>[];
  void obj(String body) {
    offsets.add(sb.length);
    sb.write('${offsets.length} 0 obj\n$body\nendobj\n');
  }

  obj('<< /Type /Catalog /Pages 2 0 R >>');
  obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Annots [4 0 R 6 0 R] >>');
  obj('<< /Type /Annot /Subtype /Screen /Rect [100 400 300 600] '
      '/A << /S /Rendition /R << /C << /D << /Type /Filespec /F (clip.mp4) '
      '/EF << /F 5 0 R >> >> >> >> >> >>');
  obj('<< /Length 4 >>\nstream\nABCD\nendstream');
  obj('<< /Type /Annot /Subtype /Link /Rect [0 0 10 10] >>');
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
  test('finds an embedded video on its page and maps the rect', () {
    final found = readPdfMediaAnnotations(_pdf(), 1);
    expect(found, hasLength(1));
    final a = found.single;
    expect(a.kind, PdfMediaKind.video);
    expect(a.fileName, 'clip.mp4');
    expect(a.canPlay, isTrue);
    expect(a.extract(), Uint8List.fromList('ABCD'.codeUnits));
    // PDF y 400..600 on an 800 high page → top-left 200..400.
    expect(a.normRect.left, closeTo(100 / 600, 1e-6));
    expect(a.normRect.top, closeTo(200 / 800, 1e-6));
    expect(a.normRect.bottom, closeTo(400 / 800, 1e-6));
  });

  test('index strips embedded bytes but stays playable', () {
    final idx = indexPdfMedia(_pdf());
    expect(idx.keys, [1]);
    expect(idx[1]!.single.stream, isNull);
    expect(idx[1]!.single.canPlay, isTrue);
  });

  test('garbage input returns nothing', () {
    expect(readPdfMediaAnnotations(Uint8List(8), 1), isEmpty);
  });
}
