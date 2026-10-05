import 'dart:convert';
import 'dart:typed_data';

import 'package:document_studio/infrastructure/pdf/edit/pdf_outline_writer.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _pdf(int pages) {
  final sb = StringBuffer('%PDF-1.7\n');
  final offsets = <int>[];
  void obj(String body) {
    offsets.add(sb.length);
    sb.write('${offsets.length} 0 obj\n$body\nendobj\n');
  }

  obj('<< /Type /Catalog /Pages 2 0 R >>');
  final kids = [for (var i = 0; i < pages; i++) '${3 + i} 0 R'].join(' ');
  obj('<< /Type /Pages /Kids [$kids] /Count $pages >>');
  for (var i = 0; i < pages; i++) {
    obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>');
  }
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
  test('bookmarks round-trip with nesting and pages', () {
    final out = writePdfOutline(_pdf(4), [
      OutlineEntry(title: 'Intro', page: 1),
      OutlineEntry(
        title: 'Part 2',
        page: 3,
        children: [OutlineEntry(title: 'Detail', page: 4)],
      ),
    ])!;
    final back = readPdfOutline(out);
    expect(back.map((e) => e.title), ['Intro', 'Part 2']);
    expect(back[1].page, 3);
    expect(back[1].children.single.title, 'Detail');
    expect(back[1].children.single.page, 4);
  });

  test('empty list removes the outline', () {
    final withOutline =
        writePdfOutline(_pdf(2), [OutlineEntry(title: 'A', page: 2)])!;
    final cleared = writePdfOutline(withOutline, const [])!;
    expect(readPdfOutline(cleared), isEmpty);
  });
}
