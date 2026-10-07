import 'dart:math' as math;
import 'dart:ui';

import 'package:document_studio/features/pdf_viewer/widgets/page_placement_math.dart';

/// Four corners in normalized page space (top-left origin, 0–1).
class PageCropQuadNorm {
  const PageCropQuadNorm({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  final Offset topLeft;
  final Offset topRight;
  final Offset bottomRight;
  final Offset bottomLeft;

  List<Offset> get corners => [topLeft, topRight, bottomRight, bottomLeft];

  PageCropQuadNorm copyWith({
    Offset? topLeft,
    Offset? topRight,
    Offset? bottomRight,
    Offset? bottomLeft,
  }) {
    return PageCropQuadNorm(
      topLeft: topLeft ?? this.topLeft,
      topRight: topRight ?? this.topRight,
      bottomRight: bottomRight ?? this.bottomRight,
      bottomLeft: bottomLeft ?? this.bottomLeft,
    );
  }

  /// Axis-aligned bounding box of the quad, clamped to the page.
  Rect get boundingRect => clampNormRect(
    Rect.fromLTRB(
      math.min(
        math.min(topLeft.dx, topRight.dx),
        math.min(bottomLeft.dx, bottomRight.dx),
      ),
      math.min(
        math.min(topLeft.dy, topRight.dy),
        math.min(bottomLeft.dy, bottomRight.dy),
      ),
      math.max(
        math.max(topLeft.dx, topRight.dx),
        math.max(bottomLeft.dx, bottomRight.dx),
      ),
      math.max(
        math.max(topLeft.dy, topRight.dy),
        math.max(bottomLeft.dy, bottomRight.dy),
      ),
    ),
  );

  static PageCropQuadNorm fromRect(Rect r) {
    final c = clampNormRect(r);
    return PageCropQuadNorm(
      topLeft: Offset(c.left, c.top),
      topRight: Offset(c.right, c.top),
      bottomRight: Offset(c.right, c.bottom),
      bottomLeft: Offset(c.left, c.bottom),
    );
  }

  static const PageCropQuadNorm pageInset = PageCropQuadNorm(
    topLeft: Offset(0.08, 0.08),
    topRight: Offset(0.92, 0.08),
    bottomRight: Offset(0.92, 0.92),
    bottomLeft: Offset(0.08, 0.92),
  );
}

enum PageCropQuadCorner { topLeft, topRight, bottomRight, bottomLeft }

/// Clamps each corner onto the page (0–1).
PageCropQuadNorm clampPageCropQuad(PageCropQuadNorm q) {
  Offset c(Offset o) => Offset(o.dx.clamp(0.0, 1.0), o.dy.clamp(0.0, 1.0));
  return PageCropQuadNorm(
    topLeft: c(q.topLeft),
    topRight: c(q.topRight),
    bottomRight: c(q.bottomRight),
    bottomLeft: c(q.bottomLeft),
  );
}

/// Moves one corner by a normalized delta, clamped to the page.
PageCropQuadNorm movePageCropQuadCorner(
  PageCropQuadNorm base, {
  required PageCropQuadCorner corner,
  required double dx,
  required double dy,
}) {
  Offset next(Offset o) =>
      Offset((o.dx + dx).clamp(0.0, 1.0), (o.dy + dy).clamp(0.0, 1.0));
  return clampPageCropQuad(switch (corner) {
    PageCropQuadCorner.topLeft => base.copyWith(topLeft: next(base.topLeft)),
    PageCropQuadCorner.topRight => base.copyWith(topRight: next(base.topRight)),
    PageCropQuadCorner.bottomRight => base.copyWith(
      bottomRight: next(base.bottomRight),
    ),
    PageCropQuadCorner.bottomLeft => base.copyWith(
      bottomLeft: next(base.bottomLeft),
    ),
  });
}

/// Moves the whole quad by a normalized delta without leaving the page.
PageCropQuadNorm movePageCropQuad(
  PageCropQuadNorm base, {
  required double dx,
  required double dy,
}) {
  final r = base.boundingRect;
  final maxDx = (1.0 - r.right).clamp(0.0, 1.0);
  final minDx = (-r.left).clamp(-1.0, 0.0);
  final maxDy = (1.0 - r.bottom).clamp(0.0, 1.0);
  final minDy = (-r.top).clamp(-1.0, 0.0);
  final cdx = dx.clamp(minDx, maxDx);
  final cdy = dy.clamp(minDy, maxDy);
  Offset m(Offset o) => Offset(o.dx + cdx, o.dy + cdy);
  return clampPageCropQuad(
    PageCropQuadNorm(
      topLeft: m(base.topLeft),
      topRight: m(base.topRight),
      bottomRight: m(base.bottomRight),
      bottomLeft: m(base.bottomLeft),
    ),
  );
}

PageCropQuadCorner? hitTestCropQuadCorner({
  required PageCropQuadNorm quad,
  required Size pageSize,
  required Offset local,
  double hitSlop = 14,
}) {
  final w = math.max(pageSize.width, 1.0);
  final h = math.max(pageSize.height, 1.0);
  Offset px(Offset n) => Offset(n.dx * w, n.dy * h);
  final map = <PageCropQuadCorner, Offset>{
    PageCropQuadCorner.topLeft: px(quad.topLeft),
    PageCropQuadCorner.topRight: px(quad.topRight),
    PageCropQuadCorner.bottomRight: px(quad.bottomRight),
    PageCropQuadCorner.bottomLeft: px(quad.bottomLeft),
  };
  PageCropQuadCorner? best;
  var bestDist = hitSlop;
  for (final e in map.entries) {
    final d = (e.value - local).distance;
    if (d <= bestDist) {
      bestDist = d;
      best = e.key;
    }
  }
  return best;
}

/// Detect non-white content margins from RGBA/BGRA bytes (row-major).
///
/// Returns a normalized LTRB crop rect inset to content, or null if empty.
Rect? detectContentBoundsNorm({
  required int width,
  required int height,
  required List<int> bytes,
  required bool bgra,
  int whiteThreshold = 245,
  double paddingFraction = 0.02,
}) {
  if (width < 2 || height < 2 || bytes.length < width * height * 4) {
    return null;
  }
  bool isInk(int i) {
    final r = bgra ? bytes[i + 2] : bytes[i];
    final g = bytes[i + 1];
    final b = bgra ? bytes[i] : bytes[i + 2];
    return r < whiteThreshold || g < whiteThreshold || b < whiteThreshold;
  }

  var minX = width;
  var minY = height;
  var maxX = -1;
  var maxY = -1;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      if (!isInk(i)) continue;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX < minX || maxY < minY) return null;

  final padX = (width * paddingFraction).round().clamp(0, width);
  final padY = (height * paddingFraction).round().clamp(0, height);
  final left = ((minX - padX) / width).clamp(0.0, 1.0);
  final top = ((minY - padY) / height).clamp(0.0, 1.0);
  final right = ((maxX + padX + 1) / width).clamp(0.0, 1.0);
  final bottom = ((maxY + padY + 1) / height).clamp(0.0, 1.0);
  if (right - left < kPagePlacementMinFraction ||
      bottom - top < kPagePlacementMinFraction) {
    return null;
  }
  return clampNormRect(Rect.fromLTRB(left, top, right, bottom));
}
