/// Layout options for plain-text PDF creation ([DS-CREATE-002]).
class TextToPdfLayout {
  const TextToPdfLayout({
    this.pageWidthPt = 612,
    this.pageHeightPt = 792,
    this.fontSizePt = 12,
    this.marginPt = 72,
    this.maxLines = 40,
  });

  final double pageWidthPt;
  final double pageHeightPt;
  final double fontSizePt;
  final double marginPt;
  final int maxLines;

  static const a4 = TextToPdfLayout(
    pageWidthPt: 595,
    pageHeightPt: 842,
  );

  static const letter = TextToPdfLayout(
    pageWidthPt: 612,
    pageHeightPt: 792,
  );

  double get lineLeadingPt => fontSizePt * 1.25;
}

enum TextToPdfPagePreset {
  letter,
  a4,
}

extension TextToPdfPagePresetX on TextToPdfPagePreset {
  String get label => switch (this) {
        TextToPdfPagePreset.letter => 'US Letter',
        TextToPdfPagePreset.a4 => 'A4',
      };

  TextToPdfLayout get layout => switch (this) {
        TextToPdfPagePreset.letter => TextToPdfLayout.letter,
        TextToPdfPagePreset.a4 => TextToPdfLayout.a4,
      };
}
