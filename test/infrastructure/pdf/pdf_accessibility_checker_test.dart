import 'dart:convert';
import 'dart:typed_data';

import 'package:document_studio/infrastructure/pdf/pdf_accessibility_checker.dart';
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


A11ySeverity sev(List<A11yFinding> l, String title) =>
    l.firstWhere((f) => f.title == title).severity;

void main() {
  test('a bare file fails title, language and tags', () {
    final r = checkPdfAccessibility(_pdf(2));
    expect(sev(r, 'Document title'), A11ySeverity.fail);
    expect(sev(r, 'Language'), A11ySeverity.fail);
    expect(sev(r, 'Tagged PDF'), A11ySeverity.fail);
  });

  test('fixing title and language turns them green', () {
    var b = _pdf(2);
    b = fixPdfAccessibility(b, fixId: 'title', title: 'Report')!;
    b = fixPdfAccessibility(b, fixId: 'lang', language: 'en-GB')!;
    final r = checkPdfAccessibility(b);
    expect(sev(r, 'Document title'), A11ySeverity.pass);
    expect(sev(r, 'Language'), A11ySeverity.pass);
  });
}
