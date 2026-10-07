import 'dart:convert';
import 'dart:typed_data';

import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_objects.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_parser.dart';
import 'package:document_studio/infrastructure/pdf/ttf_font.dart';

/// What a PDF says about one of its fonts — everything font recognition
/// can use besides the name: the embedded program's own family name, the
/// descriptor's style flags and the glyph widths of printable ASCII.
/// Plain data, so it can cross isolates.
class PdfFontEvidence {
  const PdfFontEvidence({
    required this.name,
    this.embeddedFamily,
    this.flags = 0,
    this.italicAngle = 0,
    this.weight,
    this.stemV,
    this.widths = const {},
  });

  /// BaseFont without the subset tag, `,Bold` turned into `-Bold`.
  final String name;

  /// Family name inside the embedded font program (TrueType name table,
  /// Type 1 /FamilyName, CFF name), when there is one.
  final String? embeddedFamily;

  /// FontDescriptor /Flags (1 fixed pitch, 2 serif, 4 symbolic, 64 italic,
  /// 262144 force bold).
  final int flags;
  final double italicAngle;

  /// /FontWeight (100…900), when given.
  final double? weight;
  final double? stemV;

  /// Character (32…126) → advance in 1/1000 em, from /Widths or /W.
  final Map<int, double> widths;

  bool get fixedPitch => flags & 1 != 0;
  bool get serif => flags & 2 != 0;
  bool get symbolic => flags & 4 != 0 && flags & 32 == 0;
  bool get italic => flags & 64 != 0 || italicAngle.abs() > 1;
  bool get forceBold => flags & 262144 != 0;
}

/// Font resource name → evidence, for one resource dictionary. Never throws.
Map<String, PdfFontEvidence> readFontEvidence(
  PdfEditDocument doc,
  PdfDict? resources,
) {
  final fonts = doc.dictOf(resources?['Font']);
  if (fonts == null) return const {};
  final out = <String, PdfFontEvidence>{};
  for (final e in fonts.entries.entries) {
    try {
      final f = doc.dictOf(e.value);
      if (f == null) continue;
      final ev = _evidence(doc, f);
      if (ev != null) out[e.key] = ev;
    } catch (_) {
      // One odd font never hides the others.
    }
  }
  return out;
}

String cleanFontName(String base) {
  var n = base;
  final plus = n.indexOf('+');
  if (plus == 6) n = n.substring(7);
  return n.replaceAll(',', '-');
}

PdfFontEvidence? _evidence(PdfEditDocument doc, PdfDict f) {
  final base = f.nameOf('BaseFont');
  if (base == null) return null;
  final subtype = f.nameOf('Subtype');
  PdfDict? descFont;
  PdfDict? descriptor;
  if (subtype == 'Type0') {
    final d = doc.resolve(f['DescendantFonts']);
    if (d is PdfArray && d.items.isNotEmpty)
      descFont = doc.dictOf(d.items.first);
    descriptor = doc.dictOf(descFont?['FontDescriptor']);
  } else {
    descriptor = doc.dictOf(f['FontDescriptor']);
  }
  final widths = <int, double>{};
  if (subtype == 'Type0') {
    _cidWidths(doc, f, descFont, widths);
  } else {
    final first = doc.numOf(f['FirstChar'])?.round();
    final w = doc.resolve(f['Widths']);
    if (first != null && w is PdfArray) {
      for (var i = 0; i < w.items.length; i++) {
        final code = first + i;
        if (code < 32 || code > 126) continue;
        final v = doc.numOf(w.items[i]);
        if (v != null && v > 0) widths[code] = v;
      }
    }
  }
  return PdfFontEvidence(
    name: cleanFontName(base),
    embeddedFamily: _embeddedFamily(doc, descriptor),
    flags: doc.numOf(descriptor?['Flags'])?.round() ?? 0,
    italicAngle: doc.numOf(descriptor?['ItalicAngle']) ?? 0,
    weight: doc.numOf(descriptor?['FontWeight']),
    stemV: doc.numOf(descriptor?['StemV']),
    widths: widths,
  );
}

/// CID font widths, mapped to characters through /ToUnicode.
void _cidWidths(
  PdfEditDocument doc,
  PdfDict font,
  PdfDict? cid,
  Map<int, double> out,
) {
  if (cid == null) return;
  final toUni = doc.resolve(font['ToUnicode']);
  if (toUni is! PdfStream) return;
  final map = parseToUnicode(decodeStreamData(toUni.dict, toUni.data));
  if (map.isEmpty) return;
  final dw = doc.numOf(cid['DW']) ?? 1000;
  final byCid = <int, double>{};
  final w = doc.resolve(cid['W']);
  if (w is PdfArray) {
    var i = 0;
    final items = w.items.map(doc.resolve).toList();
    while (i < items.length) {
      final c = doc.numOf(items[i])?.round();
      if (c == null) break;
      final next = i + 1 < items.length ? items[i + 1] : null;
      if (next is PdfArray) {
        for (var k = 0; k < next.items.length; k++) {
          byCid[c + k] = doc.numOf(next.items[k]) ?? dw;
        }
        i += 2;
      } else if (i + 2 < items.length) {
        final last = doc.numOf(next)?.round() ?? c;
        final v = doc.numOf(items[i + 2]) ?? dw;
        for (var k = c; k <= last && k - c < 65536; k++) {
          byCid[k] = v;
        }
        i += 3;
      } else {
        break;
      }
    }
  }
  // Identity encodings: code = CID.
  map.forEach((code, uni) {
    if (uni < 32 || uni > 126) return;
    out[uni] = byCid[code] ?? dw;
  });
}

/// Code → first Unicode scalar, from a ToUnicode CMap (bfchar / bfrange).
Map<int, int> parseToUnicode(Uint8List data) {
  final s = latin1.decode(data, allowInvalid: true);
  final out = <int, int>{};
  int hex(String h) => int.tryParse(h, radix: 16) ?? -1;
  int firstChar(String h) {
    if (h.length >= 4) {
      final hi = hex(h.substring(0, 4));
      if (hi >= 0xD800 && hi <= 0xDBFF && h.length >= 8) {
        final lo = hex(h.substring(4, 8));
        return 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00);
      }
      return hi;
    }
    return hex(h);
  }

  final bfchar = RegExp(r'beginbfchar(.*?)endbfchar', dotAll: true);
  final pair = RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>');
  for (final m in bfchar.allMatches(s)) {
    for (final p in pair.allMatches(m.group(1)!)) {
      out[hex(p.group(1)!)] = firstChar(p.group(2)!);
    }
  }
  final bfrange = RegExp(r'beginbfrange(.*?)endbfrange', dotAll: true);
  final range = RegExp(
    r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*(<([0-9A-Fa-f]+)>|\[([^\]]*)\])',
  );
  for (final m in bfrange.allMatches(s)) {
    for (final r in range.allMatches(m.group(1)!)) {
      final a = hex(r.group(1)!), b = hex(r.group(2)!);
      if (a < 0 || b < a || b - a > 65535) continue;
      if (r.group(4) != null) {
        final start = firstChar(r.group(4)!);
        for (var c = a; c <= b; c++) {
          out[c] = start + (c - a);
        }
      } else {
        final list = RegExp(r'<([0-9A-Fa-f]+)>')
            .allMatches(r.group(5)!)
            .toList();
        for (var k = 0; k < list.length && a + k <= b; k++) {
          out[a + k] = firstChar(list[k].group(1)!);
        }
      }
    }
  }
  return out;
}

String? _embeddedFamily(PdfEditDocument doc, PdfDict? descriptor) {
  if (descriptor == null) return null;
  try {
    final ff2 = doc.resolve(descriptor['FontFile2']);
    if (ff2 is PdfStream) {
      final ttf = TtfFont.parse(decodeStreamData(ff2.dict, ff2.data));
      final fam = ttf?.family.trim();
      if (fam != null && fam.isNotEmpty) return cleanFontName(fam);
    }
    final ff = doc.resolve(descriptor['FontFile']);
    if (ff is PdfStream) {
      final head = latin1.decode(
        decodeStreamData(ff.dict, ff.data).take(4096).toList(),
        allowInvalid: true,
      );
      final m =
          RegExp(r'/FamilyName\s*\(([^)]*)\)').firstMatch(head) ??
          RegExp(r'/FontName\s*/(\S+)').firstMatch(head);
      if (m != null) return cleanFontName(m.group(1)!);
    }
    final ff3 = doc.resolve(descriptor['FontFile3']);
    if (ff3 is PdfStream) return _cffName(decodeStreamData(ff3.dict, ff3.data));
  } catch (_) {}
  return null;
}

/// First name in a CFF font's Name INDEX.
String? _cffName(Uint8List d) {
  if (d.length < 8 || d[0] != 1) return null;
  final hdr = d[2];
  var p = hdr;
  final count = (d[p] << 8) | d[p + 1];
  if (count == 0) return null;
  final offSize = d[p + 2];
  int off(int i) {
    var v = 0;
    for (var k = 0; k < offSize; k++) {
      v = (v << 8) | d[p + 3 + i * offSize + k];
    }
    return v;
  }

  final dataStart = p + 3 + (count + 1) * offSize - 1;
  final a = dataStart + off(0), b = dataStart + off(1);
  if (a < 0 || b > d.length || b <= a) return null;
  return cleanFontName(latin1.decode(d.sublist(a, b)));
}
