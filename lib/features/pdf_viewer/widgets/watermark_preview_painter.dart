import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:document_studio/domain/pdf_markup/header_footer/hf_spec.dart';
import 'package:document_studio/domain/pdf_stamp/helvetica_bold_metrics.dart';
import 'package:document_studio/domain/pdf_stamp/stamp_label_layout.dart';
import 'package:document_studio/domain/pdf_stamp/watermark_layout.dart';
import 'package:document_studio/features/pdf_markup/stamp_preview_text.dart';
import 'package:flutter/material.dart';

/// Live watermark preview shared by the options panel, the viewer page
/// overlays and the page-scope thumbnails.
class WatermarkPreviewState {
  const WatermarkPreviewState({
    required this.spec,
    this.pages1Based,
    this.image,
    this.visible = true,
    this.resolveText,
  });

  final WatermarkSpec spec;

  /// Pages that receive the watermark; `null` means every page.
  final Set<int>? pages1Based;

  /// Decoded image for image watermarks.
  final ui.Image? image;
  final bool visible;

  /// Resolves template tokens (`{page}`, `{date}` …) for a 1-based page.
  final String Function(String template, int page1Based)? resolveText;

  bool appliesTo(int page1Based) {
    if (!visible) return false;
    final pages = pages1Based;
    return pages == null || pages.contains(page1Based);
  }

  String textFor(int page1Based) =>
      resolveText?.call(spec.text, page1Based) ?? spec.text;
}

/// Paints the marks of [layoutWatermark] — the function the PDF writer uses —
/// for one page. Repaints from [repaint] (e.g. a preview ValueNotifier).
class WatermarkPreviewPainter extends CustomPainter {
  WatermarkPreviewPainter({
    required this.spec,
    required this.pageWidthPt,
    required this.pageHeightPt,
    required this.text,
    this.image,
    super.repaint,
  });

  final WatermarkSpec spec;
  final double pageWidthPt;
  final double pageHeightPt;
  final String text;
  final ui.Image? image;

  @override
  void paint(Canvas canvas, Size size) {
    paintWatermarkMarks(
      canvas,
      size,
      spec: spec,
      pageWidthPt: pageWidthPt,
      pageHeightPt: pageHeightPt,
      text: text,
      image: image,
    );
  }

  @override
  bool shouldRepaint(covariant WatermarkPreviewPainter old) =>
      old.spec != spec ||
      old.text != text ||
      old.image != image ||
      old.pageWidthPt != pageWidthPt ||
      old.pageHeightPt != pageHeightPt;
}

/// Draws exactly one glyph run / image per laid-out mark.
void paintWatermarkMarks(
  Canvas canvas,
  Size size, {
  required WatermarkSpec spec,
  required double pageWidthPt,
  required double pageHeightPt,
  required String text,
  ui.Image? image,
}) {
  if (!(size.width > 1 && size.height > 1)) return;
  if (spec.isImage && image == null) return;
  final marks = layoutWatermark(
    spec: spec,
    pageWidthPt: pageWidthPt,
    pageHeightPt: pageHeightPt,
    resolvedText: text,
  );
  if (marks.isEmpty) return;
  final scale = size.width / math.max(pageWidthPt, 1);
  final opacity = spec.clampedOpacity;
  final (r, g, b) = spec.colorRgb;
  final color = Color.from(alpha: opacity, red: r, green: g, blue: b);

  canvas.save();
  canvas.clipRect(Offset.zero & size);
  TextPainter? tp;
  for (final m in marks) {
    canvas.save();
    canvas.translate(m.centerXNorm * size.width, m.centerYNorm * size.height);
    // Spec angles are counter-clockwise; Flutter's y-down canvas rotates
    // clockwise for positive angles.
    canvas.rotate(-m.rotationDegrees * math.pi / 180);
    if (image != null && spec.isImage) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromCenter(
          center: Offset.zero,
          width: m.widthPt * scale,
          height: m.heightPt * scale,
        ),
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, opacity)
          ..filterQuality = FilterQuality.medium,
      );
    } else {
      tp ??= stampTextPainter(m.text, m.font, m.fontSizePt * scale, color);
      paintStampTextRun(
        canvas,
        tp,
        startXPx: m.baselineStartXPt * scale,
        baselineYPx: m.baselineYDownPt * scale,
        targetWidthPx: m.widthPt * scale,
      );
    }
    canvas.restore();
  }
  canvas.restore();
  tp?.dispose();
}

/// Paints a rubber-stamp label exactly as [layoutStampLabel] lays it out for
/// the PDF writer.
void paintStampLabel(
  Canvas canvas,
  Size size, {
  required Rect boxNorm,
  required String label,
  required Color color,
  required double pageWidthPt,
  required double pageHeightPt,
}) {
  final layout = layoutStampLabel(
    leftNorm: boxNorm.left,
    topNorm: boxNorm.top,
    rightNorm: boxNorm.right,
    bottomNorm: boxNorm.bottom,
    pageWidthPt: pageWidthPt,
    pageHeightPt: pageHeightPt,
    label: label,
  );
  final scale = size.width / math.max(pageWidthPt, 1);
  final box = Rect.fromLTWH(
    layout.leftNorm * size.width,
    layout.topNorm * size.height,
    layout.widthNorm * size.width,
    layout.heightNorm * size.height,
  );
  final solid = color.withValues(alpha: 1);
  canvas.drawRect(
    box,
    Paint()..color = solid.withValues(alpha: StampLabelLayout.fillOpacity),
  );
  canvas.drawRect(
    box,
    Paint()
      ..color = solid
      ..style = PaintingStyle.stroke
      ..strokeWidth = StampLabelLayout.strokeWidthPt * scale,
  );
  final tp = stampTextPainter(
    layout.text,
    HfFont.helveticaBold,
    layout.fontSizePt * scale,
    solid,
  );
  paintStampTextRun(
    canvas,
    tp,
    startXPx: box.center.dx - layout.textWidthPt * scale / 2,
    baselineYPx: box.center.dy + layout.baselineBelowCenterPt * scale,
    targetWidthPx: layout.textWidthPt * scale,
  );
  tp.dispose();
}

/// Width of [text] in Helvetica-Bold at [fontSizePt] (for UI hints).
double helveticaBoldWidthPt(String text, double fontSizePt) =>
    HelveticaBoldMetrics.widthEm(HelveticaBoldMetrics.sanitize(text)) *
    fontSizePt;
