import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:document_studio/features/pdf_viewer/live_text_edit_math.dart';
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/features/pdf_viewer/widgets/page_placement_math.dart';
import 'package:document_studio/infrastructure/pdf/pdf_helvetica_metrics.dart';
import 'package:flutter/material.dart';

/// Selection frame / handle color (neutral blue so it never reads as an error
/// against the red brand accent).
/// Acrobat selection blue (design standard).
const Color kLiveSelectionColor = Color(0xFF1473E6);

/// Display pixels per PDF point for a page painted at [pagePx].
double livePxPerPt(Size pagePx, double pageWidthPt) {
  final w = pageWidthPt.isFinite && pageWidthPt > 1 ? pageWidthPt : 612.0;
  return pagePx.width / w;
}

/// Text style whose advances / baseline match the Helvetica the writer uses.
TextStyle liveHelveticaStyle({
  required double fontPx,
  required Color color,
  bool bold = false,
  bool italic = false,
  String family = 'sans',
  double lineHeightEm = kTextLineHeightEm,
  String? customFamily,
}) {
  final flutterFamily = customFamily ?? switch (family) {
    'serif' => 'DS Serif',
    'mono' => 'DS Mono',
    _ => kHelveticaCompatibleFontFamily,
  };
  return TextStyle(
    fontFamily: flutterFamily,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    fontFamilyFallback: kHelveticaCompatibleFontFallback,
    fontSize: fontPx,
    height: lineHeightEm,
    leadingDistribution: TextLeadingDistribution.even,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
    color: color,
    letterSpacing: 0,
    wordSpacing: 0,
    fontFeatures: const [ui.FontFeature.disable('kern')],
    textBaseline: TextBaseline.alphabetic,
  );
}

TextPainter _layoutLine(String text, TextStyle style) {
  return TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
}

/// Paints one line with its alphabetic baseline at [leftBaseline] (px).
void paintHelveticaLine(
  Canvas canvas,
  String text, {
  required Offset leftBaseline,
  required double fontPx,
  required Color color,
  bool bold = false,
  bool italic = false,
  String family = 'sans',
  double lineHeightEm = kTextLineHeightEm,
  String? customFamily,
}) {
  if (text.isEmpty || fontPx <= 0.5) return;
  final tp = _layoutLine(
    text,
    liveHelveticaStyle(
      fontPx: fontPx,
      color: color,
      bold: bold,
      italic: italic,
      family: family,
      lineHeightEm: lineHeightEm,
      customFamily: customFamily,
    ),
  );
  final base = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  tp.paint(canvas, Offset(leftBaseline.dx, leftBaseline.dy - base));
  tp.dispose();
}

/// Paints pre-wrapped [lines] exactly where the writer burns them.
void paintLiveTextBox(
  Canvas canvas, {
  required Rect boxPx,
  required List<String> lines,
  required double fontSizePt,
  required double pxPerPt,
  required Color color,
  required bool bold,
  required LiveMarginAlign align,
  bool italic = false,
  String family = 'sans',
  double lineHeightEm = kTextLineHeightEm,
  String? customFamily,
}) {
  final fontPx = fontSizePt * pxPerPt;
  final leadingPx = fontSizePt * lineHeightEm * pxPerPt;
  final halfExtraPx = (lineHeightEm - kTextLineHeightEm) / 2 * fontPx;
  final boxWPt = boxPx.width / pxPerPt;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) continue;
    final dxPt = alignedLineOffsetPt(
      line: line,
      boxWidthPt: boxWPt,
      fontSizePt: fontSizePt,
      bold: bold,
      align: align,
    );
    paintHelveticaLine(
      canvas,
      line,
      leftBaseline: Offset(
        boxPx.left + dxPt * pxPerPt,
        boxPx.top + i * leadingPx + halfExtraPx + fontPx * kHelveticaBaselineFromLineTopEm,
      ),
      fontPx: fontPx,
      color: color,
      bold: bold,
      italic: italic,
      family: family,
      lineHeightEm: lineHeightEm,
      customFamily: customFamily,
    );
  }
}

/// Cursor for a resize handle (unrotated box).
MouseCursor cursorForPlacementHandle(PlacementHandle h) {
  return switch (h) {
    PlacementHandle.topLeft ||
    PlacementHandle.bottomRight =>
      SystemMouseCursors.resizeUpLeftDownRight,
    PlacementHandle.topRight ||
    PlacementHandle.bottomLeft =>
      SystemMouseCursors.resizeUpRightDownLeft,
    PlacementHandle.top || PlacementHandle.bottom => SystemMouseCursors.resizeUpDown,
    PlacementHandle.left || PlacementHandle.right => SystemMouseCursors.resizeLeftRight,
  };
}

/// Rotates [p] around [c] by [radians].
Offset rotateAround(Offset p, Offset c, double radians) {
  if (radians == 0) return p;
  final s = math.sin(radians);
  final co = math.cos(radians);
  final d = p - c;
  return Offset(c.dx + d.dx * co - d.dy * s, c.dy + d.dx * s + d.dy * co);
}

/// Rotates a vector by [radians].
Offset rotateVector(Offset v, double radians) {
  if (radians == 0) return v;
  final s = math.sin(radians);
  final co = math.cos(radians);
  return Offset(v.dx * co - v.dy * s, v.dx * s + v.dy * co);
}

/// Hit-test pad for handles in logical px (mouse-friendly at any zoom).
const double kLiveHandleHitPad = 9;

/// Paints the Acrobat/Apple-style selection frame with 8 round handles.
class LiveSelectionPainter extends CustomPainter {
  LiveSelectionPainter({
    required this.boxPx,
    this.rotationRadians = 0,
    this.showHandles = true,
    this.showRotateHandle = false,
    this.edgeHandlesOnly = false,
    this.dashed = false,
    this.color = kLiveSelectionColor,
    this.fill,
  });

  final Rect boxPx;
  final double rotationRadians;
  final bool showHandles;
  final bool showRotateHandle;

  /// Only left/right handles (text boxes resize width only).
  final bool edgeHandlesOnly;
  final bool dashed;
  final Color color;
  final Color? fill;

  static const double rotateHandleOffset = 22;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (rotationRadians != 0) {
      final c = boxPx.center;
      canvas.translate(c.dx, c.dy);
      canvas.rotate(rotationRadians);
      canvas.translate(-c.dx, -c.dy);
    }
    if (fill != null) {
      canvas.drawRect(boxPx, Paint()..color = fill!);
    }
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25;
    if (dashed) {
      paintDashedRect(canvas, boxPx, stroke);
    } else {
      canvas.drawRect(boxPx, stroke);
    }
    if (showRotateHandle) {
      final top = Offset(boxPx.center.dx, boxPx.top);
      final knob = top.translate(0, -rotateHandleOffset);
      canvas.drawLine(top, knob, stroke);
      _knob(canvas, knob, radius: 5.5);
    }
    if (showHandles) {
      final pts = edgeHandlesOnly
          ? [boxPx.centerLeft, boxPx.centerRight]
          : [
              boxPx.topLeft,
              boxPx.topCenter,
              boxPx.topRight,
              boxPx.centerRight,
              boxPx.bottomRight,
              boxPx.bottomCenter,
              boxPx.bottomLeft,
              boxPx.centerLeft,
            ];
      for (final p in pts) {
        _knob(canvas, p);
      }
    }
    canvas.restore();
  }

  void _knob(Canvas canvas, Offset c, {double radius = 4.5}) {
    canvas.drawCircle(
      c.translate(0, 0.6),
      radius + 0.8,
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
    canvas.drawCircle(c, radius, Paint()..color = Colors.white);
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant LiveSelectionPainter old) =>
      old.boxPx != boxPx ||
      old.rotationRadians != rotationRadians ||
      old.showHandles != showHandles ||
      old.showRotateHandle != showRotateHandle ||
      old.edgeHandlesOnly != edgeHandlesOnly ||
      old.dashed != dashed ||
      old.color != color ||
      old.fill != fill;
}

void paintDashedRect(Canvas canvas, Rect r, Paint paint, {double dash = 5, double gap = 3}) {
  void seg(Offset a, Offset b) {
    final len = (b - a).distance;
    if (len <= 0) return;
    final dir = (b - a) / len;
    var t = 0.0;
    while (t < len) {
      final e = math.min(t + dash, len);
      canvas.drawLine(a + dir * t, a + dir * e, paint);
      t = e + gap;
    }
  }

  seg(r.topLeft, r.topRight);
  seg(r.topRight, r.bottomRight);
  seg(r.bottomRight, r.bottomLeft);
  seg(r.bottomLeft, r.topLeft);
}

/// Small floating hint chip (e.g. "Click to place signature").
class LiveHintChip extends StatelessWidget {
  const LiveHintChip({super.key, required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE6202124),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: Colors.white),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
