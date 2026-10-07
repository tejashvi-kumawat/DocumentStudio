/// Source languages the on-device composer understands.
enum ComposeLanguage {
  markdown('Markdown', 'md'),
  html('HTML', 'html'),
  latex('LaTeX', 'tex');

  const ComposeLanguage(this.label, this.extension);
  final String label;
  final String extension;
}

/// A typeset document: what every parser produces and the PDF renderer
/// draws. Small on purpose — it covers what people write in Markdown,
/// HTML and everyday LaTeX.
class ComposeDoc {
  ComposeDoc({
    required this.blocks,
    this.title,
    this.author,
    this.date,
    this.serif = false,
    this.baseFontSize = 11,
    this.pageSize = 'A4',
    this.footnotes = const [],
    this.warnings = const [],
    this.marginPt,
    this.pageHeader,
    this.pageFooter,
    this.headerAlign = CAlign.center,
    this.footerAlign = CAlign.center,
  });

  /// Running header / footer text; `{PAGE}` and `{PAGES}` are page fields.
  /// A null footer prints the page number; an empty one prints nothing.
  final String? pageHeader, pageFooter;
  final CAlign headerAlign, footerAlign;

  /// Page margin in points (null = 1 inch for serif, 0.8 inch otherwise).
  final double? marginPt;

  ComposeDoc copyWith({
    bool? serif,
    double? baseFontSize,
    String? pageSize,
    double? marginPt,
  }) => ComposeDoc(
    blocks: blocks,
    title: title,
    author: author,
    date: date,
    serif: serif ?? this.serif,
    baseFontSize: baseFontSize ?? this.baseFontSize,
    pageSize: pageSize ?? this.pageSize,
    footnotes: footnotes,
    warnings: warnings,
    marginPt: marginPt ?? this.marginPt,
    pageHeader: pageHeader,
    pageFooter: pageFooter,
    headerAlign: headerAlign,
    footerAlign: footerAlign,
  );

  final List<CBlock> blocks;
  final String? title;
  final String? author;
  final String? date;

  /// Body face: serif (LaTeX look) or sans (Markdown / HTML look).
  final bool serif;
  final double baseFontSize;

  /// `A4`, `Letter`, `A5`, `Legal`.
  final String pageSize;
  final List<List<CInline>> footnotes;

  /// Unsupported commands / tags met while parsing (shown, never fatal).
  final List<String> warnings;
}

enum CAlign { left, center, right, justify }

sealed class CBlock {
  const CBlock();
}

class CHeading extends CBlock {
  const CHeading(this.level, this.inlines, {this.number});
  final int level; // 1..6
  final List<CInline> inlines;
  final String? number; // "1.2" (LaTeX numbering)
}

class CPara extends CBlock {
  const CPara(this.inlines, {this.align = CAlign.left, this.indent = false});
  final List<CInline> inlines;
  final CAlign align;
  final bool indent;
}

class CList extends CBlock {
  const CList(this.items, {this.ordered = false, this.start = 1, this.labels});
  final List<List<CBlock>> items;
  final bool ordered;
  final int start;

  /// Explicit item labels (LaTeX `description`, task lists ☐ / ☑).
  final List<List<CInline>?>? labels;
}

class CCode extends CBlock {
  const CCode(this.text, {this.language});
  final String text;
  final String? language;
}

class CQuote extends CBlock {
  const CQuote(this.blocks);
  final List<CBlock> blocks;
}

class CTable extends CBlock {
  const CTable(this.rows, {this.header = true, this.aligns, this.caption});
  final List<List<List<CInline>>> rows;
  final bool header;
  final List<CAlign>? aligns;
  final List<CInline>? caption;
}

class CImage extends CBlock {
  const CImage(
    this.src, {
    this.widthFraction,
    this.caption,
    this.align = CAlign.center,
  });
  final String src;
  final double? widthFraction; // of the text width
  final List<CInline>? caption;
  final CAlign align;
}

class CMath extends CBlock {
  const CMath(this.tex, {this.number});
  final String tex;
  final String? number; // "(1)"
}

class CRule extends CBlock {
  const CRule();
}

class CPageBreak extends CBlock {
  const CPageBreak();
}

class CSpace extends CBlock {
  const CSpace(this.points);
  final double points;
}

class CTitleBlock extends CBlock {
  const CTitleBlock();
}

class CToc extends CBlock {
  const CToc();
}

class CAbstract extends CBlock {
  const CAbstract(this.blocks);
  final List<CBlock> blocks;
}

/// Framed callout (question / answer / tcolorbox-style).
class CBox extends CBlock {
  const CBox(this.blocks, {this.title, this.borderColor, this.fillColor});

  final List<CBlock> blocks;
  final String? title;

  /// ARGB colours; null = renderer defaults.
  final int? borderColor;
  final int? fillColor;
}

/// Vector drawing from a TikZ subset (coordinates in PDF points).
class CDrawing extends CBlock {
  const CDrawing(this.ops, {required this.width, required this.height});

  final List<CDrawOp> ops;
  final double width;
  final double height;
}

enum CDrawKind { line, polyline, rect, ellipse, text }

/// One path / node in a [CDrawing].
///
/// Geometry conventions (points in pt, Y up):
/// - [line]: two points
/// - [polyline]: two or more points
/// - [rect]: opposite corners (two points)
/// - [ellipse]: center + (rx, ry) as the second "point" offsets
/// - [text]: one anchor point + [text]
class CDrawOp {
  const CDrawOp({
    required this.kind,
    this.points = const [],
    this.text,
    this.strokeColor,
    this.fillColor,
    this.strokeWidth = 1,
    this.dashed = false,
  });

  final CDrawKind kind;
  final List<(double x, double y)> points;
  final String? text;
  final int? strokeColor;
  final int? fillColor;
  final double strokeWidth;
  final bool dashed;
}

/// A run of inline text with its styling.
class CInline {
  const CInline(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.code = false,
    this.smallCaps = false,
    this.link,
    this.color,
    this.scale = 1,
    this.math,
    this.superscript = false,
    this.subscript = false,
    this.lineBreak = false,
  });

  final String text;
  final bool bold, italic, underline, strike, code, smallCaps;
  final String? link;
  final int? color; // ARGB
  final double scale;

  /// Inline math (TeX source); [text] is ignored.
  final String? math;
  final bool superscript, subscript;
  final bool lineBreak;

  CInline copyWith({
    String? text,
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strike,
    bool? code,
    bool? smallCaps,
    String? link,
    int? color,
    double? scale,
    bool? superscript,
    bool? subscript,
  }) => CInline(
    text ?? this.text,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    underline: underline ?? this.underline,
    strike: strike ?? this.strike,
    code: code ?? this.code,
    smallCaps: smallCaps ?? this.smallCaps,
    link: link ?? this.link,
    color: color ?? this.color,
    scale: scale ?? this.scale,
    math: math,
    superscript: superscript ?? this.superscript,
    subscript: subscript ?? this.subscript,
    lineBreak: lineBreak,
  );
}

/// Style state while walking a source tree.
class CStyle {
  const CStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.code = false,
    this.smallCaps = false,
    this.link,
    this.color,
    this.scale = 1,
    this.superscript = false,
    this.subscript = false,
  });

  final bool bold, italic, underline, strike, code, smallCaps;
  final String? link;
  final int? color;
  final double scale;
  final bool superscript, subscript;

  CStyle copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strike,
    bool? code,
    bool? smallCaps,
    String? link,
    int? color,
    double? scale,
    bool? superscript,
    bool? subscript,
  }) => CStyle(
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    underline: underline ?? this.underline,
    strike: strike ?? this.strike,
    code: code ?? this.code,
    smallCaps: smallCaps ?? this.smallCaps,
    link: link ?? this.link,
    color: color ?? this.color,
    scale: scale ?? this.scale,
    superscript: superscript ?? this.superscript,
    subscript: subscript ?? this.subscript,
  );

  CInline run(String text) => CInline(
    text,
    bold: bold,
    italic: italic,
    underline: underline,
    strike: strike,
    code: code,
    smallCaps: smallCaps,
    link: link,
    color: color,
    scale: scale,
    superscript: superscript,
    subscript: subscript,
  );
}

/// Named CSS / LaTeX colours → ARGB.
const kComposeColors = <String, int>{
  'black': 0xFF000000,
  'white': 0xFFFFFFFF,
  'red': 0xFFD32F2F,
  'green': 0xFF2E7D32,
  'blue': 0xFF1565C0,
  'cyan': 0xFF00838F,
  'magenta': 0xFFAD1457,
  'yellow': 0xFFF9A825,
  'orange': 0xFFEF6C00,
  'purple': 0xFF6A1B9A,
  'violet': 0xFF7B1FA2,
  'brown': 0xFF6D4C41,
  'gray': 0xFF757575,
  'grey': 0xFF757575,
  'darkgray': 0xFF424242,
  'lightgray': 0xFFBDBDBD,
  'teal': 0xFF00796B,
  'olive': 0xFF827717,
  'lime': 0xFF9E9D24,
  'pink': 0xFFE91E63,
  'navy': 0xFF1A237E,
  'maroon': 0xFF880E4F,
};

/// `#rgb`, `#rrggbb`, `rgb(r,g,b)` or a colour name → ARGB.
int? parseComposeColor(String v) {
  final s = v.trim().toLowerCase();
  if (kComposeColors.containsKey(s)) return kComposeColors[s];
  final hex = RegExp(r'^#?([0-9a-f]{3}|[0-9a-f]{6})$').firstMatch(s);
  if (hex != null) {
    var h = hex.group(1)!;
    if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
    return 0xFF000000 | int.parse(h, radix: 16);
  }
  final rgb = RegExp(r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)').firstMatch(s);
  if (rgb != null) {
    int c(int i) => int.parse(rgb.group(i)!).clamp(0, 255);
    return 0xFF000000 | (c(1) << 16) | (c(2) << 8) | c(3);
  }
  return null;
}
