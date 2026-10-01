/// One OCR word with a pixel bounding box (image top-left origin).
class HocrWord {
  const HocrWord({
    required this.text,
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
  });

  final String text;
  final int x0;
  final int y0;
  final int x1;
  final int y1;

  int get widthPx => (x1 - x0).clamp(1, 1 << 20);
  int get heightPx => (y1 - y0).clamp(1, 1 << 20);
}

final _wordRe = RegExp(
  "class=['\"]ocrx_word['\"][^>]*title=['\"]([^'\"]*)['\"][^>]*>([^<]*)<",
  caseSensitive: false,
);
final _bboxRe = RegExp(r'bbox\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)');

/// Parses Tesseract hOCR for word boxes. Empty / whitespace-only words are skipped.
List<HocrWord> parseHocrWords(String hocr) {
  final out = <HocrWord>[];
  for (final m in _wordRe.allMatches(hocr)) {
    final title = m.group(1)!;
    final raw = _decodeXmlEntities(m.group(2) ?? '').trim();
    if (raw.isEmpty) continue;
    final box = _bboxRe.firstMatch(title);
    if (box == null) continue;
    out.add(
      HocrWord(
        text: raw,
        x0: int.parse(box.group(1)!),
        y0: int.parse(box.group(2)!),
        x1: int.parse(box.group(3)!),
        y1: int.parse(box.group(4)!),
      ),
    );
  }
  return out;
}

/// Plain text from hOCR when word boxes are missing.
String hocrPlainText(String hocr) {
  final words = parseHocrWords(hocr);
  if (words.isNotEmpty) {
    return words.map((w) => w.text).join(' ');
  }
  return hocr
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _decodeXmlEntities(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'");
