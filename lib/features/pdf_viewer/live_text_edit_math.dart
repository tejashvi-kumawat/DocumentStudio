import 'dart:math' as math;
import 'dart:ui';

import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/features/pdf_viewer/widgets/page_placement_canvas.dart';
import 'package:document_studio/features/pdf_viewer/widgets/page_placement_math.dart';
import 'package:document_studio/infrastructure/pdf/pdf_helvetica_metrics.dart';
import 'package:document_studio/infrastructure/pdf/ttf_font.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_text_builder.dart';

/// Minimum normalized width when dragging a new text box on the page.
const double kLiveTextBoxMinWidthNorm = 0.04;

/// Line-box height of [lineCount] lines as a fraction of page height.
///
/// Uses the same 1.2 em leading as the on-page editor and the PDF writer.
double liveTextBoxHeightNorm({
  required double fontSizePt,
  required double pageHeightPt,
  int lineCount = 1,
  double lineHeightEm = kTextLineHeightEm,
}) {
  final h = pageHeightPt > 1 ? pageHeightPt : 792.0;
  final lines = math.max(1, lineCount);
  return ((fontSizePt * lineHeightEm * lines) / h).clamp(0.004, 1.0);
}

/// Drag-create a text box: [originNorm] is pointer-down, [currentNorm] is tip.
///
/// Width comes from the horizontal drag; height is one line until typing wraps.
PagePlacementNorm textBoxPlacementFromWidthDrag({
  required Offset originNorm,
  required Offset currentNorm,
  required double heightNorm,
  double minWidthNorm = kLiveTextBoxMinWidthNorm,
}) {
  final left = math.min(originNorm.dx, currentNorm.dx).clamp(0.0, 1.0);
  final right = math.max(originNorm.dx, currentNorm.dx).clamp(0.0, 1.0);
  final width = math.max(minWidthNorm, right - left);
  return clampPagePlacement(
    PagePlacementNorm(
      left: left,
      top: originNorm.dy.clamp(0.0, 1.0),
      width: width,
      height: heightNorm,
    ),
    minFraction: math.min(minWidthNorm, kPagePlacementMinFraction),
  );
}

/// Greedy word wrap with Helvetica metrics — the same breaks Flutter makes
/// for a metric-compatible font (Liberation Sans) with kerning off.
List<String> wrapPlainTextToWidth({
  required String text,
  required double maxWidthPt,
  required double fontSizePt,
  bool bold = false,
  double Function(String text)? measure,
}) {
  final cleaned = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (cleaned.isEmpty) return const [''];
  double w(String s) => measure != null
      ? measure(s)
      : helveticaTextWidthPt(s, fontSizePt, bold: bold);
  final maxW = math.max(1.0, maxWidthPt);
  final out = <String>[];
  for (final paragraph in cleaned.split('\n')) {
    if (paragraph.trim().isEmpty) {
      out.add('');
      continue;
    }
    final words = paragraph.split(' ');
    var line = '';
    for (final word in words) {
      final candidate = line.isEmpty ? word : '$line $word';
      if (w(candidate.trimRight()) <= maxW || line.isEmpty && word.isEmpty) {
        line = candidate;
        continue;
      }
      if (line.isNotEmpty) {
        out.add(line.trimRight());
        line = '';
      }
      // A single word wider than the box breaks at character boundaries.
      var rest = word;
      while (rest.isNotEmpty && w(rest) > maxW) {
        var n = rest.length - 1;
        while (n > 1 && w(rest.substring(0, n)) > maxW) {
          n--;
        }
        out.add(rest.substring(0, n));
        rest = rest.substring(n);
      }
      line = rest;
    }
    out.add(line.trimRight());
  }
  return out.isEmpty ? const [''] : out;
}

/// Sticky-note box layout shared by the live preview and the writer.
const double kLiveNoteFontPt = 9;
const double kLiveNotePadPt = 5;
const double kLiveNoteWidthPt = 170;

List<String> liveNoteLines(String text, {double widthPt = kLiveNoteWidthPt}) =>
    wrapPlainTextToWidth(
      text: text.trim().isEmpty ? 'Note' : text.trim(),
      maxWidthPt: widthPt - 2 * kLiveNotePadPt,
      fontSizePt: kLiveNoteFontPt,
    );

double liveNoteHeightPt(int lineCount) =>
    math.max(1, lineCount) * kLiveNoteFontPt * kTextLineHeightEm +
    2 * kLiveNotePadPt;

/// Form-field value layout shared by the on-page field editor and the writer.
const double kFormFieldPadPt = 2;

/// Auto-sized font: ≤12 pt, fits the field height, shrinks to fit the width.
double formFieldFontSizePt(String text, double widthPt, double heightPt) {
  var fs = (heightPt * 0.66).clamp(6.0, 12.0);
  final avail = widthPt - 2 * kFormFieldPadPt;
  if (text.isNotEmpty && avail > 4) {
    final w1 = helveticaTextWidthPt(text, 1);
    if (w1 > 0 && w1 * fs > avail) fs = math.max(6.0, avail / w1);
  }
  return fs;
}

/// Line-top offset (pt, from the field top) that vertically centers one line.
double formFieldLineTopPt(double heightPt, double fontSizePt) =>
    (heightPt - fontSizePt * kTextLineHeightEm) / 2;

/// Check mark polyline in field-local normalized coordinates.
const List<Offset> kFormCheckMarkNorm = [
  Offset(0.2, 0.53),
  Offset(0.41, 0.74),
  Offset(0.8, 0.27),
];

double formCheckStrokePt(double widthPt, double heightPt) =>
    math.max(0.8, math.min(widthPt, heightPt) * 0.12);

/// Horizontal offset (pt) of a line inside a box of [boxWidthPt].
double alignedLineOffsetPt({
  required String line,
  required double boxWidthPt,
  required double fontSizePt,
  required bool bold,
  required LiveMarginAlign align,
  double Function(String text)? measure,
}) {
  final lineW = measure != null
      ? measure(line)
      : helveticaTextWidthPt(line, fontSizePt, bold: bold);
  return switch (align) {
    LiveMarginAlign.left => 0.0,
    LiveMarginAlign.center => (boxWidthPt - lineW) / 2,
    LiveMarginAlign.right => boxWidthPt - lineW,
  };
}

/// Burns pre-wrapped [lines] at the exact positions the editor shows them:
/// line i's baseline sits at `top + i·1.2·size + 0.9465·size`.
List<PdfOverlayTextLine> overlayTextLinesForBox({
  required List<String> lines,
  required Rect boxNorm,
  required double pageWidthPt,
  required double pageHeightPt,
  required double fontSizePt,
  required bool bold,
  required (double r, double g, double b) fillRgb,
  LiveMarginAlign align = LiveMarginAlign.left,
  String? fontBase,
  double lineHeightEm = kTextLineHeightEm,
  TtfFont? ttf,
}) {
  final boxW = boxNorm.width * pageWidthPt;
  final leftPt = boxNorm.left * pageWidthPt;
  final topPt = boxNorm.top * pageHeightPt;
  final leading = fontSizePt * lineHeightEm;
  // Extra leading is split above and below the line, as the editor draws it.
  final halfExtra = (lineHeightEm - kTextLineHeightEm) / 2 * fontSizePt;
  final result = <PdfOverlayTextLine>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) continue;
    final x =
        leftPt +
        alignedLineOffsetPt(
          line: line,
          boxWidthPt: boxW,
          fontSizePt: fontSizePt,
          bold: bold,
          align: align,
          measure: ttf == null ? null : (t) => ttf.textWidthPt(t, fontSizePt),
        );
    final baselineFromTop =
        topPt +
        i * leading +
        halfExtra +
        fontSizePt * kHelveticaBaselineFromLineTopEm;
    result.add(
      PdfOverlayTextLine(
        text: line,
        xPt: x,
        yPt: pageHeightPt - baselineFromTop,
        fontSizePt: fontSizePt,
        bold: bold,
        fontBase: fontBase,
        ttf: ttf,
        fillRgb: fillRgb,
      ),
    );
  }
  return result;
}

/// Wraps [text] to the box width and burns it WYSIWYG.
List<PdfOverlayTextLine> buildWrappedOverlayTextLines({
  required String text,
  required Rect boxNorm,
  required double pageWidthPt,
  required double pageHeightPt,
  required double fontSizePt,
  required bool bold,
  required (double r, double g, double b) fillRgb,
  LiveMarginAlign align = LiveMarginAlign.left,
}) {
  final boxW = (boxNorm.width * pageWidthPt).clamp(1.0, pageWidthPt);
  final lines = wrapPlainTextToWidth(
    text: text,
    maxWidthPt: boxW,
    fontSizePt: fontSizePt,
    bold: bold,
  );
  return overlayTextLinesForBox(
    lines: lines,
    boxNorm: boxNorm,
    pageWidthPt: pageWidthPt,
    pageHeightPt: pageHeightPt,
    fontSizePt: fontSizePt,
    bold: bold,
    fillRgb: fillRgb,
    align: align,
  );
}
