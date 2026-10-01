import 'dart:math' as math;
import 'dart:ui';

import 'package:document_studio/features/pdf_viewer/widgets/page_placement_canvas.dart';

/// Minimum fraction of the page for width/height so a box cannot collapse.
const double kPagePlacementMinFraction = 0.04;

/// Which edge/corner is being resized (normalized page space, top-left origin).
enum PlacementHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
}

/// Clamps a placement so it stays fully inside the page media box (0–1).
PagePlacementNorm clampPagePlacement(
  PagePlacementNorm next, {
  double minFraction = kPagePlacementMinFraction,
}) {
  var width = next.width.clamp(minFraction, 1.0);
  var height = next.height.clamp(minFraction, 1.0);
  var left = next.left.clamp(0.0, 1.0 - width);
  var top = next.top.clamp(0.0, 1.0 - height);
  if (left + width > 1.0) left = 1.0 - width;
  if (top + height > 1.0) top = 1.0 - height;
  return PagePlacementNorm(left: left, top: top, width: width, height: height);
}

/// Moves [base] by normalized [dx]/[dy], clamped to the page.
PagePlacementNorm movePagePlacement(
  PagePlacementNorm base, {
  required double dx,
  required double dy,
  double minFraction = kPagePlacementMinFraction,
}) {
  return clampPagePlacement(
    base.copyWith(left: base.left + dx, top: base.top + dy),
    minFraction: minFraction,
  );
}

/// Resizes [base] from [handle] by normalized pointer delta.
///
/// When [keepAspect] is true, opposite corners/edges preserve
/// [aspectWidthOverHeight] (width/height). Shift-free aspect uses free resize.
PagePlacementNorm resizePagePlacement(
  PagePlacementNorm base, {
  required PlacementHandle handle,
  required double dx,
  required double dy,
  bool keepAspect = false,
  double? aspectWidthOverHeight,
  double minFraction = kPagePlacementMinFraction,
}) {
  var left = base.left;
  var top = base.top;
  var right = base.left + base.width;
  var bottom = base.top + base.height;
  final aspect = aspectWidthOverHeight ??
      (base.height > 1e-9 ? base.width / base.height : 1.0);

  void applyFree() {
    switch (handle) {
      case PlacementHandle.topLeft:
        left += dx;
        top += dy;
      case PlacementHandle.top:
        top += dy;
      case PlacementHandle.topRight:
        right += dx;
        top += dy;
      case PlacementHandle.right:
        right += dx;
      case PlacementHandle.bottomRight:
        right += dx;
        bottom += dy;
      case PlacementHandle.bottom:
        bottom += dy;
      case PlacementHandle.bottomLeft:
        left += dx;
        bottom += dy;
      case PlacementHandle.left:
        left += dx;
    }
  }

  void applyAspect() {
    // Anchor opposite corner/edge; size from the dragged corner's diagonal intent.
    switch (handle) {
      case PlacementHandle.bottomRight:
        final w = math.max(minFraction, base.width + dx);
        final h = w / aspect;
        right = left + w;
        bottom = top + h;
      case PlacementHandle.topLeft:
        final w = math.max(minFraction, base.width - dx);
        final h = w / aspect;
        left = right - w;
        top = bottom - h;
      case PlacementHandle.topRight:
        final w = math.max(minFraction, base.width + dx);
        final h = w / aspect;
        right = left + w;
        top = bottom - h;
      case PlacementHandle.bottomLeft:
        final w = math.max(minFraction, base.width - dx);
        final h = w / aspect;
        left = right - w;
        bottom = top + h;
      case PlacementHandle.right:
      case PlacementHandle.left:
        final w = handle == PlacementHandle.right
            ? math.max(minFraction, base.width + dx)
            : math.max(minFraction, base.width - dx);
        final h = w / aspect;
        if (handle == PlacementHandle.right) {
          right = left + w;
        } else {
          left = right - w;
        }
        final cy = top + base.height / 2;
        top = cy - h / 2;
        bottom = cy + h / 2;
      case PlacementHandle.top:
      case PlacementHandle.bottom:
        final h = handle == PlacementHandle.bottom
            ? math.max(minFraction, base.height + dy)
            : math.max(minFraction, base.height - dy);
        final w = h * aspect;
        if (handle == PlacementHandle.bottom) {
          bottom = top + h;
        } else {
          top = bottom - h;
        }
        final cx = left + base.width / 2;
        left = cx - w / 2;
        right = cx + w / 2;
    }
  }

  if (keepAspect) {
    applyAspect();
  } else {
    applyFree();
  }

  // Normalize inverted edges before clamp.
  if (right < left) {
    final t = left;
    left = right;
    right = t;
  }
  if (bottom < top) {
    final t = top;
    top = bottom;
    bottom = t;
  }

  return clampPagePlacement(
    PagePlacementNorm(
      left: left,
      top: top,
      width: right - left,
      height: bottom - top,
    ),
    minFraction: minFraction,
  );
}

/// Clamps a LTRB normalized rect (crop/redact) to the page with min size.
Rect clampNormRect(
  Rect rect, {
  double minFraction = kPagePlacementMinFraction,
}) {
  var left = rect.left.clamp(0.0, 1.0);
  var top = rect.top.clamp(0.0, 1.0);
  var right = rect.right.clamp(0.0, 1.0);
  var bottom = rect.bottom.clamp(0.0, 1.0);
  if (right < left) {
    final t = left;
    left = right;
    right = t;
  }
  if (bottom < top) {
    final t = top;
    top = bottom;
    bottom = t;
  }
  if (right - left < minFraction) {
    right = (left + minFraction).clamp(0.0, 1.0);
    left = (right - minFraction).clamp(0.0, 1.0);
  }
  if (bottom - top < minFraction) {
    bottom = (top + minFraction).clamp(0.0, 1.0);
    top = (bottom - minFraction).clamp(0.0, 1.0);
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

/// Converts a crop [Rect] to placement and back for shared resize math.
PagePlacementNorm normRectToPlacement(Rect r) => PagePlacementNorm(
      left: r.left,
      top: r.top,
      width: r.width,
      height: r.height,
    );

Rect placementToNormRect(PagePlacementNorm p) =>
    Rect.fromLTWH(p.left, p.top, p.width, p.height);

/// Resizes a crop/redact rect from [handle].
Rect resizeNormRect(
  Rect base, {
  required PlacementHandle handle,
  required double dx,
  required double dy,
  bool keepAspect = false,
  double? aspectWidthOverHeight,
  double minFraction = kPagePlacementMinFraction,
}) {
  final next = resizePagePlacement(
    normRectToPlacement(base),
    handle: handle,
    dx: dx,
    dy: dy,
    keepAspect: keepAspect,
    aspectWidthOverHeight: aspectWidthOverHeight,
    minFraction: minFraction,
  );
  return clampNormRect(placementToNormRect(next), minFraction: minFraction);
}

/// Reshapes [base] to [aspectWidthOverHeight] (norm width/height), keeping
/// center when possible and clamping to the page.
Rect applyNormAspectRatio(
  Rect base, {
  required double aspectWidthOverHeight,
  double minFraction = kPagePlacementMinFraction,
}) {
  final aspect = aspectWidthOverHeight <= 0 ? 1.0 : aspectWidthOverHeight;
  final cx = (base.left + base.right) / 2;
  final cy = (base.top + base.bottom) / 2;
  var w = base.width.clamp(minFraction, 1.0);
  var h = w / aspect;
  if (h > 1.0) {
    h = 1.0;
    w = h * aspect;
  }
  if (w > 1.0) {
    w = 1.0;
    h = w / aspect;
  }
  if (h < minFraction) {
    h = minFraction;
    w = (h * aspect).clamp(minFraction, 1.0);
  }
  return clampNormRect(
    Rect.fromCenter(center: Offset(cx, cy), width: w, height: h),
    minFraction: minFraction,
  );
}

/// Moves a crop/redact rect by normalized delta.
Rect moveNormRect(
  Rect base, {
  required double dx,
  required double dy,
  double minFraction = kPagePlacementMinFraction,
}) {
  final next = movePagePlacement(
    normRectToPlacement(base),
    dx: dx,
    dy: dy,
    minFraction: minFraction,
  );
  return clampNormRect(placementToNormRect(next), minFraction: minFraction);
}

/// Hit-test which handle (if any) is under [local] in a page-sized box.
PlacementHandle? hitTestPlacementHandle({
  required Rect boxPx,
  required Offset local,
  double handleHitPad = 10,
}) {
  bool near(Offset c) => (local - c).distance <= handleHitPad;
  final corners = <PlacementHandle, Offset>{
    PlacementHandle.topLeft: boxPx.topLeft,
    PlacementHandle.topRight: boxPx.topRight,
    PlacementHandle.bottomLeft: boxPx.bottomLeft,
    PlacementHandle.bottomRight: boxPx.bottomRight,
    PlacementHandle.top: Offset(boxPx.center.dx, boxPx.top),
    PlacementHandle.bottom: Offset(boxPx.center.dx, boxPx.bottom),
    PlacementHandle.left: Offset(boxPx.left, boxPx.center.dy),
    PlacementHandle.right: Offset(boxPx.right, boxPx.center.dy),
  };
  for (final e in corners.entries) {
    if (near(e.value)) return e.key;
  }
  return null;
}
