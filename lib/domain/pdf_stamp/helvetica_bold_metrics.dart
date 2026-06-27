/// Font metrics for the PDF standard-14 font Helvetica-Bold (WinAnsiEncoding).
///
/// Both the on-screen watermark/stamp preview and the PDF writer measure text
/// with these numbers, so the burned glyph run has exactly the extents the
/// preview shows. Units are 1/1000 em.
abstract final class HelveticaBoldMetrics {
  static const double ascentEm = 0.718;
  static const double descentEm = 0.207;

  /// Text box height (ascender + descender) per 1pt of font size.
  static const double boxHeightEm = ascentEm + descentEm;

  /// Baseline offset below the vertical box center, per 1pt of font size.
  static const double baselineBelowCenterEm = (ascentEm - descentEm) / 2;

  // Advance widths for codes 32..126 (Helvetica-Bold.afm, WinAnsi).
  static const List<int> _ascii = [
    278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, //
    278, 278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 333, 333, //
    584, 584, 584, 611, 975, 722, 722, 722, 722, 667, 611, 778, 722, 278, //
    556, 722, 611, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944, //
    667, 667, 611, 333, 278, 333, 584, 556, 333, 556, 611, 556, 611, 556, //
    333, 611, 611, 278, 278, 556, 278, 889, 611, 611, 611, 611, 389, 556, //
    333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584,
  ];

  /// Characters Helvetica can encode in WinAnsi; others become `?` so the
  /// preview never shows glyphs the PDF cannot draw.
  static String sanitize(String text) {
    final out = StringBuffer();
    for (final rune in text.runes) {
      if (rune == 0x0A || rune == 0x0D || rune == 0x09) {
        out.write(' ');
      } else if ((rune >= 32 && rune <= 126) || (rune >= 160 && rune <= 255)) {
        out.writeCharCode(rune);
      } else {
        out.write('?');
      }
    }
    return out.toString();
  }

  static int _widthOf(int code) {
    if (code >= 32 && code <= 126) return _ascii[code - 32];
    if (code >= 192 && code <= 255) {
      // Accented Latin-1 letters share their base glyph's advance.
      return code < 224 ? 722 : 556;
    }
    return 556;
  }

  /// Advance width of already-[sanitize]d [text] in em units.
  static double widthEm(String text) {
    var total = 0;
    for (final code in text.codeUnits) {
      total += _widthOf(code);
    }
    return total / 1000.0;
  }
}
