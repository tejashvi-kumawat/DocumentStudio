import 'package:document_studio/domain/pdf_markup/header_footer/hf_spec.dart';
import 'package:document_studio/domain/pdf_markup/markup_fonts.dart';
import 'package:flutter/material.dart';

/// Bundled DS font that is metric-compatible with [font]'s standard-14 face.
MarkupFontFamily markupFamilyFor(HfFont font) => switch (font.family) {
      HfFontFamily.sans => MarkupFontFamily.sans,
      HfFontFamily.serif => MarkupFontFamily.serif,
      HfFontFamily.mono => MarkupFontFamily.mono,
    };

/// On-screen style for text the PDF writer sets in [font].
TextStyle stampPreviewTextStyle(HfFont font, double sizePx, Color color) {
  return TextStyle(
    fontFamily: markupFamilyFor(font).flutterFamily,
    fontWeight: font.bold ? FontWeight.w700 : FontWeight.w400,
    fontSize: sizePx,
    color: color,
    height: 1,
    letterSpacing: 0,
  );
}

TextPainter stampTextPainter(
  String text,
  HfFont font,
  double sizePx,
  Color color,
) {
  return TextPainter(
    text: TextSpan(text: text, style: stampPreviewTextStyle(font, sizePx, color)),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
}

/// Paints [tp] with its baseline start at ([startXPx], [baselineYPx]) and its
/// advance stretched to exactly [targetWidthPx] (the AFM width the PDF uses),
/// so the preview and the saved page line up glyph run for glyph run.
void paintStampTextRun(
  Canvas canvas,
  TextPainter tp, {
  required double startXPx,
  required double baselineYPx,
  required double targetWidthPx,
}) {
  final baseline = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  final sx = tp.width > 0.01 ? targetWidthPx / tp.width : 1.0;
  canvas.save();
  canvas.translate(startXPx, baselineYPx);
  canvas.scale(sx, 1);
  tp.paint(canvas, Offset(0, -baseline));
  canvas.restore();
}
