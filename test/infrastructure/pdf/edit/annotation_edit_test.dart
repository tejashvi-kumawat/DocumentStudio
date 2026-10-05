import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_objects.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_page_editor.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _pdf() {
  const objs = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] '
        '/Annots [4 0 R 5 0 R 6 0 R] >>',
    '<< /Type /Annot /Subtype /Ink /Rect [10 10 50 50] '
        '/InkList [[10 10 50 50]] >>',
    '<< /Type /Annot /Subtype /Link /Rect [0 0 5 5] >>',
    '<< /Type /Annot /Subtype /Square /Rect [100 100 150 120] >>',
  ];
  final b = StringBuffer('%PDF-1.7\n');
  final offs = <int>[];
  for (var i = 0; i < objs.length; i++) {
    offs.add(b.length);
    b.write('${i + 1} 0 obj\n${objs[i]}\nendobj\n');
  }
  final x = b.length;
  b.write('xref\n0 ${objs.length + 1}\n0000000000 65535 f \n');
  for (final o in offs) {
    b.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  b.write('trailer << /Size ${objs.length + 1} /Root 1 0 R >>\n'
      'startxref\n$x\n%%EOF\n');
  return Uint8List.fromList(b.toString().codeUnits);
}

void main() {
  test('finds drawings and shapes, not links', () {
    final found = findPageAnnotations(_pdf(), 1);
    expect(found.map((a) => a.name), ['Ink', 'Square']);
    expect(found.first.label, 'Drawing');
    // Ink rect 10..50 on a 200 pt page, top-left origin.
    expect(found.first.normRect.left, closeTo(0.05, 1e-6));
    expect(found.first.normRect.top, closeTo(0.75, 1e-6));
  });

  test('moves an ink drawing with its points', () {
    final ink = findPageAnnotations(_pdf(), 1).first;
    final out = transformPageAnnotation(
      _pdf(),
      1,
      ink.opStart,
      'Ink',
      ink.normRect.shift(const Offset(0.5, 0)),
    )!;
    final doc = PdfEditDocument.open(out);
    final d = doc.dictOf(doc.pageAnnotItems(1).first)!;
    final rect = (d['Rect']! as PdfArray).items.map((n) => doc.numOf(n)).toList();
    expect(rect[0], closeTo(110, 1e-6));
    final pts = ((d['InkList']! as PdfArray).items.first as PdfArray).items;
    expect(doc.numOf(pts[0]), closeTo(110, 1e-6));
    expect(doc.numOf(pts[1]), closeTo(10, 1e-6));
  });

  test('deletes one annotation and keeps the link', () {
    final sq = findPageAnnotations(_pdf(), 1).last;
    final out = deletePageAnnotation(_pdf(), 1, sq.opStart, 'Square')!;
    final left = findPageAnnotations(out, 1);
    expect(left.map((a) => a.name), ['Ink']);
    expect(PdfEditDocument.open(out).pageAnnotItems(1).length, 2);
  });

  test('refuses a stale index', () {
    expect(deletePageAnnotation(_pdf(), 1, 0, 'Square'), isNull);
  });

  test('pictures inside form XObjects can be moved and deleted', () {
    const objs = [
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] '
          '/Resources << /XObject << /Fx 5 0 R >> >> /Contents 4 0 R >>',
      null, // page content
      null, // form
      '<< /Type /XObject /Subtype /Image /Width 1 /Height 1 '
          '/ColorSpace /DeviceGray /BitsPerComponent 8 /Length 1 >>',
    ];
    final b = StringBuffer('%PDF-1.7\n');
    final offs = <int>[];
    void obj(int n, String body) {
      offs.add(b.length);
      b.write('$n 0 obj\n$body\nendobj\n');
    }
    obj(1, objs[0]!);
    obj(2, objs[1]!);
    obj(3, objs[2]!);
    const page = 'q 1 0 0 1 20 20 cm /Fx Do Q';
    obj(4, '<< /Length ${page.length} >>\nstream\n$page\nendstream');
    const form = 'q 50 0 0 40 10 10 cm /Im0 Do Q';
    obj(5, '<< /Type /XObject /Subtype /Form /BBox [0 0 200 200] '
        '/Resources << /XObject << /Im0 6 0 R >> >> /Length ${form.length} >>'
        '\nstream\n$form\nendstream');
    obj(6, '${objs[5]}\nstream\n\u0080\nendstream');
    final x = b.length;
    b.write('xref\n0 7\n0000000000 65535 f \n');
    for (final o in offs) {
      b.write('${o.toString().padLeft(10, '0')} 00000 n \n');
    }
    b.write('trailer << /Size 7 /Root 1 0 R >>\nstartxref\n$x\n%%EOF\n');
    final pdf = Uint8List.fromList(latin1.encode(b.toString()));

    final found = findPageImages(pdf, 1);
    expect(found, hasLength(1));
    final img = found.single;
    expect(img.form, 5);
    // Image at user (30,30)-(80,70) on a 200 pt page.
    expect(img.normRect.left, closeTo(0.15, 1e-6));
    final moved = transformPageImage(
      pdf, 1, img.opStart, img.normRect.shift(const Offset(0.25, 0)),
      form: img.form,
    )!;
    expect(findPageImages(moved, 1).single.normRect.left, closeTo(0.40, 1e-6));
    final gone = deletePageImage(pdf, 1, img.opStart, form: img.form)!;
    expect(findPageImages(gone, 1), isEmpty);
  });
}
