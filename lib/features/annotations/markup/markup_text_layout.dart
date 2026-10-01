import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:document_studio/domain/pdf_markup/markup_fonts.dart';
import 'package:document_studio/domain/pdf_markup/markup_objects.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_content_builder.dart';
import 'package:flutter/material.dart';

/// PDF `Tj` draws without kerning or ligatures; match that on screen so a
/// measured line is exactly as wide in the saved file.
const List<ui.FontFeature> _kPdfLikeFeatures = [
  ui.FontFeature.disable('kern'),
  ui.FontFeature.disable('liga'),
  ui.FontFeature.disable('clig'),
];

TextStyle markupTextStyle({
  required MarkupFontFamily family,
  required double fontSize,
  bool bold = false,
  bool italic = false,
  int color = 0xFF000000,
  double lineHeight = 1.2,
  double letterSpacing = 0,
}) {
  return TextStyle(
    fontFamily: family.flutterFamily,
    fontSize: fontSize,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    color: Color(color),
    height: lineHeight,
    leadingDistribution: TextLeadingDistribution.even,
    letterSpacing: letterSpacing,
    fontFeatures: _kPdfLikeFeatures,
  );
}

/// Text as the PDF standard fonts will show it (WinAnsi only; tabs become
/// spaces). The editor lays out and previews this, so nothing changes on save.
String markupPdfSafeText(String text) {
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\t', '    ');
  return normalized.split('\n').map(sanitizeForStdFont).join('\n');
}

/// Whether [text] contains characters the PDF standard fonts can't show.
bool markupHasUnsupportedChars(String text) => !isWinAnsiEncodable(
  text.replaceAll('\n', '').replaceAll('\r', '').replaceAll('\t', ' '),
);

StrutStyle markupStrutStyle({
  required MarkupFontFamily family,
  required double fontSize,
  double lineHeight = 1.2,
}) {
  return StrutStyle(
    fontFamily: family.flutterFamily,
    fontSize: fontSize,
    height: lineHeight,
    leadingDistribution: TextLeadingDistribution.even,
    forceStrutHeight: true,
  );
}

TextStyle markupTextStyleFor(TextBoxMarkup t) => markupTextStyle(
  family: t.fontFamily,
  fontSize: t.fontSize,
  bold: t.bold,
  italic: t.italic,
  color: t.textColor,
  lineHeight: t.lineHeight,
  letterSpacing: t.letterSpacing,
);

TextAlign markupTextAlign(MarkupTextAlign a) => switch (a) {
  MarkupTextAlign.left => TextAlign.left,
  MarkupTextAlign.center => TextAlign.center,
  MarkupTextAlign.right => TextAlign.right,
};

class MarkupTextLayout {
  const MarkupTextLayout(this.lines, this.contentWidth, this.contentHeight);

  /// Frame-local lines (padding included).
  final List<MarkupTextLine> lines;

  /// Widest line / total height, without padding.
  final double contentWidth;
  final double contentHeight;
}

/// Lays out [text] like the on-page editor; the result is stored in the
/// object so the PDF writer places identical baselines.
///
/// [innerWidth] null → no wrapping (auto-width box).
MarkupTextLayout layoutMarkupText({
  required String text,
  required MarkupFontFamily family,
  required double fontSize,
  bool bold = false,
  bool italic = false,
  double lineHeight = 1.2,
  MarkupTextAlign align = MarkupTextAlign.left,
  double padding = 2,
  double letterSpacing = 0,
  double? innerWidth,
}) {
  text = markupPdfSafeText(text);
  final style = markupTextStyle(
    family: family,
    fontSize: fontSize,
    bold: bold,
    italic: italic,
    lineHeight: lineHeight,
    letterSpacing: letterSpacing,
  );
  final tp = TextPainter(
    text: TextSpan(text: text.isEmpty ? ' ' : text, style: style),
    textAlign: markupTextAlign(align),
    textDirection: TextDirection.ltr,
    strutStyle: markupStrutStyle(
      family: family,
      fontSize: fontSize,
      lineHeight: lineHeight,
    ),
  );
  final maxW = innerWidth == null ? double.infinity : math.max(1.0, innerWidth);
  tp.layout(maxWidth: maxW);
  final metrics = tp.computeLineMetrics();
  final lines = <MarkupTextLine>[];
  var widest = 0.0;
  if (text.isNotEmpty) {
    var start = 0;
    for (final lm in metrics) {
      if (start > text.length) break;
      final b = tp.getLineBoundary(TextPosition(offset: start));
      final end = math.max(b.end, start);
      var s = text.substring(start, math.min(end, text.length));
      start = end;
      if (start < text.length && text[start] == '\n') start++;
      s = s.replaceAll('\n', '').trimRight();
      widest = math.max(widest, lm.width);
      lines.add(
        MarkupTextLine(
          text: s,
          left: padding + lm.left,
          baseline: padding + lm.baseline,
          width: lm.width,
        ),
      );
    }
  }
  final h = tp.height;
  tp.dispose();
  return MarkupTextLayout(lines, widest, h);
}

/// Re-lays out [t] for its current frame width and grows the frame height to
/// fit. [autoWidth] (or [TextBoxMarkup.autoWidth]) sizes the box to the
/// longest line instead.
TextBoxMarkup relayoutTextBox(TextBoxMarkup t, {bool autoWidth = false}) {
  autoWidth = autoWidth || (t.autoWidth && !t.isCallout);
  final pad = t.padding;
  final layout = layoutMarkupText(
    text: t.text,
    family: t.fontFamily,
    fontSize: t.fontSize,
    bold: t.bold,
    italic: t.italic,
    lineHeight: t.lineHeight,
    align: t.align,
    padding: pad,
    letterSpacing: t.letterSpacing,
    innerWidth: autoWidth ? null : t.frame.width - pad * 2,
  );
  final minW = t.fontSize * 1.5 + pad * 2;
  final w = autoWidth
      ? math.max(minW, layout.contentWidth + pad * 2 + 2)
      : t.frame.width;
  final h = math.max(
    t.fontSize * t.lineHeight + pad * 2,
    layout.contentHeight + pad * 2,
  );
  final frame = Rect.fromLTWH(t.frame.left, t.frame.top, w, h);
  if (autoWidth && t.align != MarkupTextAlign.left) {
    // Re-run with the final width so centered/right lines are placed right.
    return relayoutTextBox(t.copyWith(frame: frame, autoWidth: false))
        .copyWith(autoWidth: t.autoWidth);
  }
  return t.copyWith(frame: frame, lines: layout.lines);
}

final Expando<List<TextPainter>> _linePainters = Expando<List<TextPainter>>(
  'markupLinePainters',
);

/// Paints committed [t.lines] at their baselines in frame-local space.
void paintMarkupTextLines(Canvas canvas, TextBoxMarkup t) {
  final painters = _linePainters[t] ??= [
    for (final line in t.lines)
      TextPainter(
        text: TextSpan(text: line.text, style: markupTextStyleFor(t)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(),
  ];
  for (var i = 0; i < t.lines.length && i < painters.length; i++) {
    final line = t.lines[i];
    final tp = painters[i];
    final base = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    tp.paint(canvas, Offset(line.left, line.baseline - base));
  }
}
