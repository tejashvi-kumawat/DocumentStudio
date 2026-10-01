/// Standard-14 Helvetica / Helvetica-Bold advance widths (AFM, 1/1000 em).
///
/// Used by both the on-canvas text preview (wrapping / alignment) and the PDF
/// writer so line breaks and positions agree. Liberation Sans / Arial share
/// these metrics, which is why the live editor renders with that family.
library;

/// Font family stack whose advance widths match Helvetica.
const String kHelveticaCompatibleFontFamily = 'Liberation Sans';
const List<String> kHelveticaCompatibleFontFallback = <String>[
  'Arimo',
  'Arial',
  'Helvetica',
  'Nimbus Sans',
];

/// Distance from the top of a 1.2-leading line box to the baseline, in em,
/// when the line uses [TextLeadingDistribution.even] with Arial metrics
/// (ascent 0.905, descent 0.212).
const double kHelveticaBaselineFromLineTopEm = 0.9465;

/// Line height multiplier shared by preview and writer.
const double kTextLineHeightEm = 1.2;

// ASCII 32..126, WinAnsi order (0x27 = quotesingle, 0x60 = grave).
const List<int> _regular = <int>[
  278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278, //
  556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556, //
  1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778, //
  667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556, //
  333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556, //
  556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584,
];

const List<int> _bold = <int>[
  278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, 278, 278, //
  556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 333, 333, 584, 584, 584, 611, //
  975, 722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778, //
  667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 333, 278, 333, 584, 556, //
  333, 556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889, 611, 611, //
  611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584,
];

/// Latin-1 letters map to their base letter's width (accents add no advance).
const Map<int, int> _latin1Base = <int, int>{
  0xC0: 0x41, 0xC1: 0x41, 0xC2: 0x41, 0xC3: 0x41, 0xC4: 0x41, 0xC5: 0x41,
  0xC7: 0x43, 0xC8: 0x45, 0xC9: 0x45, 0xCA: 0x45, 0xCB: 0x45,
  0xCC: 0x49, 0xCD: 0x49, 0xCE: 0x49, 0xCF: 0x49, 0xD1: 0x4E,
  0xD2: 0x4F, 0xD3: 0x4F, 0xD4: 0x4F, 0xD5: 0x4F, 0xD6: 0x4F, 0xD8: 0x4F,
  0xD9: 0x55, 0xDA: 0x55, 0xDB: 0x55, 0xDC: 0x55, 0xDD: 0x59,
  0xE0: 0x61, 0xE1: 0x61, 0xE2: 0x61, 0xE3: 0x61, 0xE4: 0x61, 0xE5: 0x61,
  0xE7: 0x63, 0xE8: 0x65, 0xE9: 0x65, 0xEA: 0x65, 0xEB: 0x65,
  0xEC: 0x69, 0xED: 0x69, 0xEE: 0x69, 0xEF: 0x69, 0xF1: 0x6E,
  0xF2: 0x6F, 0xF3: 0x6F, 0xF4: 0x6F, 0xF5: 0x6F, 0xF6: 0x6F, 0xF8: 0x6F,
  0xF9: 0x75, 0xFA: 0x75, 0xFB: 0x75, 0xFC: 0x75, 0xFD: 0x79, 0xFF: 0x79,
};

/// Advance width of one code point in 1/1000 em.
int helveticaGlyphWidth(int codePoint, {bool bold = false}) {
  final table = bold ? _bold : _regular;
  var cp = codePoint;
  if (cp == 0xA0) cp = 0x20;
  cp = _latin1Base[cp] ?? cp;
  if (cp >= 32 && cp <= 126) return table[cp - 32];
  switch (cp) {
    case 0xC6: // AE
      return 1000;
    case 0xE6: // ae
      return bold ? 889 : 889;
    case 0xDF: // germandbls
      return bold ? 611 : 611;
    case 0x2013: // endash
      return 556;
    case 0x2014: // emdash
      return 1000;
    case 0x2018:
    case 0x2019:
      return bold ? 278 : 222;
    case 0x201C:
    case 0x201D:
      return bold ? 500 : 333;
    case 0x2022: // bullet
      return 350;
    case 0x20AC: // Euro
      return 556;
    case 0x2026: // ellipsis
      return 1000;
  }
  return 556;
}

/// Width of [text] set in Helvetica at [fontSizePt], in points (no kerning).
double helveticaTextWidthPt(
  String text,
  double fontSizePt, {
  bool bold = false,
}) {
  var units = 0;
  for (final r in text.runes) {
    units += helveticaGlyphWidth(r, bold: bold);
  }
  return units * fontSizePt / 1000.0;
}
