import 'dart:convert';
import 'dart:typed_data';

/// Metrics and character map read from a TrueType (glyf) font so it can be
/// embedded in a PDF and measured exactly. OpenType-CFF fonts are not
/// supported ([TtfFont.parse] returns null for them).
class TtfFont {
  TtfFont._({
    required this.bytes,
    required this.unitsPerEm,
    required this.ascent,
    required this.descent,
    required this.capHeight,
    required this.bbox,
    required this.italicAngle,
    required this.isFixedPitch,
    required this.bold,
    required this.italic,
    required this.family,
    required this.postScriptName,
    required Map<int, int> cmap,
    required List<int> advances,
    required int numHMetrics,
  })  : _cmap = cmap,
        _advances = advances,
        _numHMetrics = numHMetrics;

  final Uint8List bytes;
  final int unitsPerEm;

  /// All below in 1000-unit em (PDF glyph space).
  final int ascent;
  final int descent;
  final int capHeight;
  final List<int> bbox;
  final double italicAngle;
  final bool isFixedPitch;
  final bool bold;
  final bool italic;
  final String family;
  final String postScriptName;

  final Map<int, int> _cmap;
  final List<int> _advances;
  final int _numHMetrics;

  int _glyphFor(int codePoint) => _cmap[codePoint] ?? 0;

  /// Advance of [codePoint] in 1000-unit em (missing glyph → .notdef width).
  double advance1000(int codePoint) {
    final g = _glyphFor(codePoint);
    final i = g < _numHMetrics ? g : _numHMetrics - 1;
    return _advances[i] * 1000 / unitsPerEm;
  }

  /// Width of [text] in points at [fontSizePt].
  double textWidthPt(String text, double fontSizePt) {
    var w = 0.0;
    for (final r in text.runes) {
      w += advance1000(r);
    }
    return w * fontSizePt / 1000;
  }

  /// A copy of the font holding only the glyph outlines of [codePoints]
  /// (plus .notdef and composite parts). Glyph ids, metrics and the cmap stay
  /// as they are, so text written with the full font renders the same; only
  /// unused outlines are emptied and tables a PDF reader never needs (names,
  /// layout, kerning, signatures) are dropped. A 200 KB font typically
  /// shrinks to a few KB. Returns the full font when it cannot be subset.
  Uint8List subset(Iterable<int> codePoints) {
    try {
      return _subset(codePoints);
    } catch (_) {
      return bytes;
    }
  }

  static const _keepTables = {
    'head', 'hhea', 'maxp', 'hmtx', 'loca', 'glyf', 'cmap', 'cvt ', 'fpgm',
    'prep', 'OS/2', 'gasp',
  };

  Uint8List _subset(Iterable<int> codePoints) {
    final d = ByteData.sublistView(bytes);
    final n = d.getUint16(4);
    final tables = <String, (int, int)>{};
    for (var i = 0; i < n; i++) {
      final o = 12 + i * 16;
      tables[latin1.decode(bytes.sublist(o, o + 4))] =
          (d.getUint32(o + 8), d.getUint32(o + 12));
    }
    final head = tables['head']!;
    final maxp = tables['maxp']!;
    final loca = tables['loca']!;
    final glyf = tables['glyf']!;
    final numGlyphs = d.getUint16(maxp.$1 + 4);
    final longLoca = d.getInt16(head.$1 + 50) == 1;
    int off(int g) => longLoca
        ? d.getUint32(loca.$1 + g * 4)
        : d.getUint16(loca.$1 + g * 2) * 2;

    // Glyphs to keep, following composite references.
    final keep = <int>{0};
    final todo = <int>[
      for (final c in codePoints)
        if (_cmap[c] case final g?) g,
    ];
    while (todo.isNotEmpty) {
      final g = todo.removeLast();
      if (g >= numGlyphs || !keep.add(g) && g != 0) continue;
      final start = off(g), end = off(g + 1);
      if (end - start < 10) continue;
      final base = glyf.$1 + start;
      if (d.getInt16(base) >= 0) continue; // simple glyph
      var p = base + 10;
      while (true) {
        final flags = d.getUint16(p);
        todo.add(d.getUint16(p + 2));
        p += 4 + ((flags & 0x0001) != 0 ? 4 : 2);
        if ((flags & 0x0008) != 0) {
          p += 2;
        } else if ((flags & 0x0040) != 0) {
          p += 4;
        } else if ((flags & 0x0080) != 0) {
          p += 8;
        }
        if ((flags & 0x0020) == 0) break;
      }
    }

    // New glyf (kept outlines only) and long-format loca.
    final newGlyf = BytesBuilder(copy: false);
    final newLoca = ByteData((numGlyphs + 1) * 4);
    var pos = 0;
    for (var g = 0; g < numGlyphs; g++) {
      newLoca.setUint32(g * 4, pos);
      if (!keep.contains(g)) continue;
      final start = off(g), end = off(g + 1);
      if (end <= start) continue;
      newGlyf.add(bytes.sublist(glyf.$1 + start, glyf.$1 + end));
      pos += end - start;
      final pad = (4 - pos % 4) % 4;
      if (pad > 0) {
        newGlyf.add(Uint8List(pad));
        pos += pad;
      }
    }
    newLoca.setUint32(numGlyphs * 4, pos);

    final out = <String, Uint8List>{};
    for (final e in tables.entries) {
      if (!_keepTables.contains(e.key)) continue;
      out[e.key] = Uint8List.fromList(
        bytes.sublist(e.value.$1, e.value.$1 + e.value.$2),
      );
    }
    out['glyf'] = newGlyf.toBytes();
    out['loca'] = newLoca.buffer.asUint8List();
    final newHead = out['head']!;
    ByteData.sublistView(newHead)
      ..setInt16(50, 1) // indexToLocFormat: long
      ..setUint32(8, 0); // checkSumAdjustment, set below
    return _assemble(out);
  }

  static int _checksum(Uint8List t) {
    var sum = 0;
    final padded = t.length % 4 == 0
        ? t
        : (Uint8List(t.length + 4 - t.length % 4)..setAll(0, t));
    final d = ByteData.sublistView(padded);
    for (var i = 0; i < padded.length; i += 4) {
      sum = (sum + d.getUint32(i)) & 0xFFFFFFFF;
    }
    return sum;
  }

  static Uint8List _assemble(Map<String, Uint8List> tables) {
    final tags = tables.keys.toList()..sort();
    final n = tags.length;
    var pow2 = 1, log2 = 0;
    while (pow2 * 2 <= n) {
      pow2 *= 2;
      log2++;
    }
    final headerLen = 12 + 16 * n;
    var total = headerLen;
    for (final t in tags) {
      total += (tables[t]!.length + 3) & ~3;
    }
    final out = Uint8List(total);
    final d = ByteData.sublistView(out)
      ..setUint32(0, 0x00010000)
      ..setUint16(4, n)
      ..setUint16(6, pow2 * 16)
      ..setUint16(8, log2)
      ..setUint16(10, n * 16 - pow2 * 16);
    var pos = headerLen;
    var headPos = -1;
    for (var i = 0; i < n; i++) {
      final tag = tags[i];
      final data = tables[tag]!;
      final rec = 12 + i * 16;
      out.setAll(rec, latin1.encode(tag));
      d
        ..setUint32(rec + 4, _checksum(data))
        ..setUint32(rec + 8, pos)
        ..setUint32(rec + 12, data.length);
      out.setAll(pos, data);
      if (tag == 'head') headPos = pos;
      pos += (data.length + 3) & ~3;
    }
    if (headPos >= 0) {
      d.setUint32(headPos + 8, (0xB1B0AFBA - _checksum(out)) & 0xFFFFFFFF);
    }
    return out;
  }

  /// Widths for WinAnsi codes 32..255 (the PDF `/Widths` array).
  List<int> winAnsiWidths() => [
        for (var code = 32; code <= 255; code++)
          advance1000(_winAnsiToUnicode(code)).round(),
      ];

  static int _winAnsiToUnicode(int code) {
    if (code >= 128 && code <= 159) {
      return _cp1252[code - 128];
    }
    return code;
  }

  static const _cp1252 = <int>[
    0x20AC, 0x0020, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
    0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x0020, 0x017D, 0x0020,
    0x0020, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x0020, 0x017E, 0x0178,
  ];

  /// Parses [data]; null when it is not a usable TrueType font.
  static TtfFont? parse(Uint8List data) {
    try {
      final d = ByteData.sublistView(data);
      if (data.length < 12) return null;
      final tag = d.getUint32(0);
      if (tag == 0x4F54544F /* OTTO */ || tag == 0x74746366 /* ttcf */) {
        return null;
      }
      final n = d.getUint16(4);
      final tables = <String, (int, int)>{};
      for (var i = 0; i < n; i++) {
        final o = 12 + i * 16;
        final name = latin1.decode(data.sublist(o, o + 4));
        tables[name] = (d.getUint32(o + 8), d.getUint32(o + 12));
      }
      if (!tables.containsKey('glyf') || !tables.containsKey('head')) {
        return null;
      }
      final head = tables['head']!.$1;
      final upm = d.getUint16(head + 18);
      final xMin = d.getInt16(head + 36);
      final yMin = d.getInt16(head + 38);
      final xMax = d.getInt16(head + 40);
      final yMax = d.getInt16(head + 42);
      final macStyle = d.getUint16(head + 44);
      int scale(num v) => (v * 1000 / upm).round();

      final hhea = tables['hhea']!.$1;
      var asc = d.getInt16(hhea + 4);
      var desc = d.getInt16(hhea + 6);
      final numH = d.getUint16(hhea + 34);
      final hmtx = tables['hmtx']!.$1;
      final adv = <int>[
        for (var i = 0; i < numH; i++) d.getUint16(hmtx + i * 4),
      ];

      var cap = (asc * 0.7).round();
      var weight = 400;
      final os2 = tables['OS/2'];
      if (os2 != null) {
        final o = os2.$1;
        weight = d.getUint16(o + 4);
        final version = d.getUint16(o);
        if (version >= 2 && os2.$2 >= 90) cap = d.getInt16(o + 88);
        final typoAsc = d.getInt16(o + 68);
        final typoDesc = d.getInt16(o + 70);
        if (typoAsc != 0) {
          asc = typoAsc;
          desc = typoDesc;
        }
      }

      var italicAngle = 0.0;
      var fixed = false;
      final post = tables['post'];
      if (post != null) {
        italicAngle = d.getInt32(post.$1 + 4) / 65536.0;
        fixed = d.getUint32(post.$1 + 12) != 0;
      }

      final cmap = _readCmap(d, tables['cmap']!.$1);
      if (cmap.isEmpty) return null;
      final names = _readNames(data, d, tables['name']);

      return TtfFont._(
        bytes: data,
        unitsPerEm: upm,
        ascent: scale(asc),
        descent: scale(desc),
        capHeight: scale(cap),
        bbox: [scale(xMin), scale(yMin), scale(xMax), scale(yMax)],
        italicAngle: italicAngle,
        isFixedPitch: fixed,
        bold: (macStyle & 1) != 0 || weight >= 600,
        italic: (macStyle & 2) != 0 || italicAngle != 0,
        family: names.$1,
        postScriptName: names.$2,
        cmap: cmap,
        advances: adv,
        numHMetrics: numH,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<int, int> _readCmap(ByteData d, int base) {
    final count = d.getUint16(base + 2);
    int? best;
    var bestRank = -1;
    for (var i = 0; i < count; i++) {
      final platform = d.getUint16(base + 4 + i * 8);
      final enc = d.getUint16(base + 6 + i * 8);
      final off = d.getUint32(base + 8 + i * 8);
      // Prefer Unicode full repertoire, then Unicode BMP / Windows Unicode.
      final rank = (platform == 3 && enc == 10)
          ? 4
          : (platform == 0 && enc >= 4)
              ? 4
              : (platform == 3 && enc == 1)
                  ? 3
                  : (platform == 0)
                      ? 2
                      : -1;
      if (rank > bestRank) {
        bestRank = rank;
        best = base + off;
      }
    }
    if (best == null) return {};
    final out = <int, int>{};
    final format = d.getUint16(best);
    if (format == 4) {
      final segX2 = d.getUint16(best + 6);
      final seg = segX2 ~/ 2;
      final endO = best + 14;
      final startO = endO + segX2 + 2;
      final deltaO = startO + segX2;
      final rangeO = deltaO + segX2;
      for (var s = 0; s < seg; s++) {
        final end = d.getUint16(endO + s * 2);
        final start = d.getUint16(startO + s * 2);
        final delta = d.getInt16(deltaO + s * 2);
        final range = d.getUint16(rangeO + s * 2);
        if (start == 0xFFFF) continue;
        for (var c = start; c <= end; c++) {
          int g;
          if (range == 0) {
            g = (c + delta) & 0xFFFF;
          } else {
            final gi = rangeO + s * 2 + range + (c - start) * 2;
            if (gi + 2 > d.lengthInBytes) continue;
            g = d.getUint16(gi);
            if (g != 0) g = (g + delta) & 0xFFFF;
          }
          if (g != 0) out[c] = g;
        }
      }
    } else if (format == 12) {
      final groups = d.getUint32(best + 12);
      for (var g = 0; g < groups; g++) {
        final o = best + 16 + g * 12;
        final start = d.getUint32(o);
        final end = d.getUint32(o + 4);
        final gl = d.getUint32(o + 8);
        for (var c = start; c <= end && c - start < 70000; c++) {
          out[c] = gl + (c - start);
        }
      }
    }
    return out;
  }

  static (String, String) _readNames(
    Uint8List data,
    ByteData d,
    (int, int)? t,
  ) {
    if (t == null) return ('Font', 'Font');
    final base = t.$1;
    final count = d.getUint16(base + 2);
    final strOff = base + d.getUint16(base + 4);
    String? family;
    String? ps;
    for (var i = 0; i < count; i++) {
      final o = base + 6 + i * 12;
      final platform = d.getUint16(o);
      final id = d.getUint16(o + 6);
      final len = d.getUint16(o + 8);
      final off = d.getUint16(o + 10);
      if (id != 1 && id != 6) continue;
      final raw = data.sublist(strOff + off, strOff + off + len);
      String s;
      if (platform == 3 || platform == 0) {
        final units = <int>[
          for (var k = 0; k + 1 < raw.length; k += 2) (raw[k] << 8) | raw[k + 1],
        ];
        s = String.fromCharCodes(units);
      } else {
        s = latin1.decode(raw);
      }
      if (id == 1) family ??= s;
      if (id == 6) ps ??= s;
    }
    final f = family ?? 'Font';
    return (f, (ps ?? f).replaceAll(RegExp(r'[^A-Za-z0-9\-]'), ''));
  }
}
