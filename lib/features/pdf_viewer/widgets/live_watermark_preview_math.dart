import 'dart:math' as math;
import 'dart:ui';

/// Pure layout for the live-page watermark preview (not a click-to-type box).
class LiveWatermarkPreviewMath {
  LiveWatermarkPreviewMath._();

  static const double defaultOpacity = 0.2;
  static const double defaultAngleDegrees = -45;
  static const double defaultFontSizePt = 48;

  /// Image stamp height as a fraction of page height (default ~18%).
  static const double defaultImageHeightFrac = 0.18;

  /// Centered normalized rect for a single diagonal watermark mark.
  static Rect centeredNormRect({
    double widthFrac = 0.72,
    double heightFrac = 0.14,
  }) {
    final w = widthFrac.clamp(0.05, 1.0);
    final h = heightFrac.clamp(0.04, 1.0);
    return Rect.fromCenter(center: const Offset(0.5, 0.5), width: w, height: h);
  }

  /// Tiled watermarks across the page (normalized top-left origin).
  static List<Rect> tiledNormRects({
    int cols = 2,
    int rows = 3,
    double widthFrac = 0.38,
    double heightFrac = 0.1,
  }) {
    final rects = <Rect>[];
    final c = math.max(1, cols);
    final r = math.max(1, rows);
    final cellW = 1.0 / c;
    final cellH = 1.0 / r;
    final w = widthFrac.clamp(0.05, cellW);
    final h = heightFrac.clamp(0.04, cellH);
    for (var row = 0; row < r; row++) {
      for (var col = 0; col < c; col++) {
        final cx = (col + 0.5) * cellW;
        final cy = (row + 0.5) * cellH;
        rects.add(Rect.fromCenter(center: Offset(cx, cy), width: w, height: h));
      }
    }
    return rects;
  }

  /// Preview marks for the current options (centered or tiled).
  static List<Rect> previewRects({
    required bool tiled,
    double? widthFrac,
    double? heightFrac,
  }) {
    if (tiled) {
      return tiledNormRects(
        widthFrac: widthFrac ?? 0.38,
        heightFrac: heightFrac ?? 0.1,
      );
    }
    return [
      centeredNormRect(
        widthFrac: widthFrac ?? 0.72,
        heightFrac: heightFrac ?? 0.14,
      ),
    ];
  }

  /// PDF-space stamp boxes (bottom-left origin) matching [previewRects].
  static List<({double xPt, double yPt, double widthPt, double heightPt})>
  stampRectsPt({
    required double pageWidthPt,
    required double pageHeightPt,
    required double stampWidthPt,
    required double stampHeightPt,
    required bool tiled,
  }) {
    final norms = previewRects(
      tiled: tiled,
      widthFrac: stampWidthPt / math.max(pageWidthPt, 1),
      heightFrac: stampHeightPt / math.max(pageHeightPt, 1),
    );
    return [
      for (final n in norms)
        (
          xPt: n.left * pageWidthPt,
          // Norm top-left → PDF bottom-left.
          yPt: (1.0 - n.bottom) * pageHeightPt,
          widthPt: n.width * pageWidthPt,
          heightPt: n.height * pageHeightPt,
        ),
    ];
  }

  /// True when [rect] is page-centered (norm space).
  static bool isCentered(Rect rect, {double epsilon = 1e-9}) {
    return (rect.center.dx - 0.5).abs() <= epsilon &&
        (rect.center.dy - 0.5).abs() <= epsilon;
  }

  /// Watermark preview is always a rotated mark — never a click caret.
  static bool get usesClickCaret => false;
}
