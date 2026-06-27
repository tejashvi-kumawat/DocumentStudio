/// Font families available for on-page text, watermarks and headers/footers.
///
/// Each pairs a bundled, metric-compatible Flutter font (Liberation) with a
/// PDF standard-14 font, so a line measured on screen has the same width in
/// the saved PDF.
enum MarkupFontFamily {
  sans('DS Sans', 'Helvetica', 'Sans'),
  serif('DS Serif', 'Times', 'Serif'),
  mono('DS Mono', 'Courier', 'Mono');

  const MarkupFontFamily(this.flutterFamily, this.pdfFamily, this.label);

  final String flutterFamily;
  final String pdfFamily;
  final String label;

  /// Standard-14 BaseFont name for the style.
  String pdfBaseFont({bool bold = false, bool italic = false}) {
    switch (this) {
      case MarkupFontFamily.sans:
        if (bold && italic) return 'Helvetica-BoldOblique';
        if (bold) return 'Helvetica-Bold';
        if (italic) return 'Helvetica-Oblique';
        return 'Helvetica';
      case MarkupFontFamily.serif:
        if (bold && italic) return 'Times-BoldItalic';
        if (bold) return 'Times-Bold';
        if (italic) return 'Times-Italic';
        return 'Times-Roman';
      case MarkupFontFamily.mono:
        if (bold && italic) return 'Courier-BoldOblique';
        if (bold) return 'Courier-Bold';
        if (italic) return 'Courier-Oblique';
        return 'Courier';
    }
  }

  static MarkupFontFamily byName(String? name) => MarkupFontFamily.values
      .firstWhere((f) => f.name == name, orElse: () => MarkupFontFamily.sans);
}
