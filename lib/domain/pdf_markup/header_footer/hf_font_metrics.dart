import 'package:document_studio/domain/pdf_markup/header_footer/hf_spec.dart';
import 'package:document_studio/infrastructure/pdf/pdf_helvetica_metrics.dart';

// Times-Roman / Times-Bold AFM advance widths for ASCII 32..126 (1/1000 em).
const List<int> _timesRegular = <int>[
  250, 333, 408, 500, 500, 833, 778, 180, 333, 333, 500, 564, 250, 333, 250, 278, //
  500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 278, 278, 564, 564, 564, 444, //
  921, 722, 667, 667, 722, 611, 556, 722, 722, 333, 389, 722, 611, 889, 722, 722, //
  556, 722, 667, 556, 611, 722, 722, 944, 722, 722, 611, 333, 278, 333, 469, 500, //
  333, 444, 500, 444, 500, 444, 333, 500, 500, 278, 278, 500, 278, 778, 500, 500, //
  500, 500, 333, 389, 278, 500, 500, 722, 500, 500, 444, 480, 200, 480, 541,
];

const List<int> _timesBold = <int>[
  250, 333, 555, 500, 500, 1000, 833, 278, 333, 333, 500, 570, 250, 333, 250, 278, //
  500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 333, 333, 570, 570, 570, 500, //
  930, 722, 667, 722, 722, 667, 611, 778, 778, 389, 500, 778, 667, 944, 722, 778, //
  611, 778, 722, 556, 667, 722, 722, 1000, 722, 722, 667, 333, 278, 333, 581, 500, //
  333, 500, 556, 444, 556, 444, 333, 500, 556, 278, 333, 556, 278, 833, 556, 500, //
  556, 556, 444, 389, 333, 556, 500, 722, 500, 500, 444, 394, 220, 394, 520,
];

/// Code points (besides ASCII and Latin-1) that WinAnsiEncoding can show.
const Set<int> hfWinAnsiExtras = {
  0x20AC, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030,
  0x0160, 0x2039, 0x0152, 0x017D, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022,
  0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x017E, 0x0178,
};

/// Replaces characters the standard-14 fonts cannot show with `?` so the
/// preview measures and draws exactly what the PDF writer outputs.
String hfSanitize(String text) {
  final sb = StringBuffer();
  for (final cp in text.runes) {
    if (cp == 0x09) {
      sb.write(' ');
    } else if ((cp >= 0x20 && cp <= 0x7E) ||
        (cp >= 0xA0 && cp <= 0xFF) ||
        hfWinAnsiExtras.contains(cp)) {
      sb.writeCharCode(cp);
    } else {
      sb.write('?');
    }
  }
  return sb.toString();
}

int _timesWidth(int cp, bool bold) {
  final table = bold ? _timesBold : _timesRegular;
  if (cp == 0xA0) return 250;
  if (cp >= 32 && cp <= 126) return table[cp - 32];
  return switch (cp) {
    0x2013 => 500,
    0x2014 => 1000,
    0x2022 => 350,
    0x2026 => 1000,
    0x2018 || 0x2019 => 333,
    0x201C || 0x201D => bold ? 500 : 444,
    0x20AC => 500,
    0x00A9 || 0x00AE => bold ? 747 : 760,
    _ => 500,
  };
}

/// Advance width of [text] (already sanitized) in points.
double hfTextWidthPt(String text, HfFont font, double sizePt) {
  switch (font.family) {
    case HfFontFamily.mono:
      return text.runes.length * 600 * sizePt / 1000;
    case HfFontFamily.sans:
      return helveticaTextWidthPt(text, sizePt, bold: font.bold);
    case HfFontFamily.serif:
      var units = 0;
      for (final r in text.runes) {
        units += _timesWidth(r, font.bold);
      }
      return units * sizePt / 1000;
  }
}

/// Ascender / descender (em) used to place baselines inside margins.
const double hfAscentEm = 0.75;
const double hfDescentEm = 0.22;
const double hfLineHeightEm = 1.2;
