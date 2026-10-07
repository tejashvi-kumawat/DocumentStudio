import 'dart:convert';
import 'dart:io';

import 'package:document_studio/core/fonts/font_identifier.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_font_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final metricsJson = File('assets/fonts/library/metrics.json').readAsStringSync();
  final metrics = (jsonDecode(metricsJson) as List).cast<Map<String, dynamic>>();
  Map<int, double> widthsOf(String family, {bool bold = false}) {
    final m = metrics.firstWhere((m) => m['family'] == family && m['bold'] == bold && m['italic'] == false);
    final w = (m['w'] as List).cast<int>();
    return {for (var c = 33; c < 127; c++) if (w[c - 32] > 0) c: w[c - 32].toDouble()};
  }

  String? names(String n) => switch (n.toLowerCase().replaceAll(' ', '')) {
        final s when s.startsWith('calibri') => 'Carlito',
        final s when s.startsWith('timesnewroman') => 'Tinos',
        _ => null,
      };
  final id = FontIdentifier(metricsJson, names);

  test('by name, with style from the name', () {
    final r = id.identify(const PdfFontEvidence(name: 'Calibri-BoldItalic'));
    expect([r.family, r.bold, r.italic, r.how], ['Carlito', true, true, 'name']);
  });

  test('by the embedded program name when the BaseFont is meaningless', () {
    final r = id.identify(const PdfFontEvidence(name: 'TT0', embeddedFamily: 'Times New Roman'));
    expect([r.family, r.how], ['Tinos', 'embedded']);
  });

  test('by glyph widths when no name helps (like Adobe)', () {
    final fira = id.identify(PdfFontEvidence(name: 'F1', widths: widthsOf('Fira Sans')));
    expect([fira.family, fira.bold, fira.how], ['Fira Sans', false, 'metrics']);
    final bold = id.identify(PdfFontEvidence(name: 'F2', widths: widthsOf('Lato', bold: true)));
    expect([bold.family, bold.bold], ['Lato', true]);
  });

  test('falls back to serif / sans / mono from the descriptor flags', () {
    expect(id.identify(const PdfFontEvidence(name: 'X', flags: 2)).family, 'Tinos');
    expect(id.identify(const PdfFontEvidence(name: 'X', flags: 1)).family, 'Cousine');
    expect(id.identify(const PdfFontEvidence(name: 'X', flags: 64, weight: 700)).bold, isTrue);
  });

  test('ToUnicode CMaps map codes to characters', () {
    final cmap = utf8.encode('''
1 beginbfchar
<0003> <0020>
endbfchar
2 beginbfrange
<0024> <0026> <0041>
<0044> <0045> [<0061> <0062>]
endbfrange''');
    final m = parseToUnicode(cmap);
    expect(m[3], 0x20);
    expect([m[0x24], m[0x25], m[0x26]], [0x41, 0x42, 0x43]);
    expect([m[0x44], m[0x45]], [0x61, 0x62]);
  });
}
