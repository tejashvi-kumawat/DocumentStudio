import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

/// Page placement shared by every on-page preview and every PDF writer.
///
/// "Display space" is what the viewer shows: points, origin at the top-left
/// of the visible (crop box) page after `/Rotate`, y growing downwards. pdfrx
/// reports the same size via `PdfPage.width/height`, so a page overlay maps
/// display points to pixels with a single scale factor.
///
/// "User space" is the unrotated PDF coordinate system (y up) that
/// annotations and content streams are written in.
class PdfPageGeometry {
  const PdfPageGeometry({
    required this.cropLeft,
    required this.cropBottom,
    required this.cropWidth,
    required this.cropHeight,
    int rotate = 0,
  }) : rotate = ((((rotate % 360) + 360) % 360) + 45) ~/ 90 * 90 % 360;

  /// Geometry for a page known only by its displayed size (preview-only use).
  factory PdfPageGeometry.display(double widthPt, double heightPt) =>
      PdfPageGeometry(
        cropLeft: 0,
        cropBottom: 0,
        cropWidth: widthPt,
        cropHeight: heightPt,
      );

  factory PdfPageGeometry.fromJson(Map<String, dynamic> j) => PdfPageGeometry(
        cropLeft: (j['x'] as num).toDouble(),
        cropBottom: (j['y'] as num).toDouble(),
        cropWidth: (j['w'] as num).toDouble(),
        cropHeight: (j['h'] as num).toDouble(),
        rotate: (j['r'] as num).toInt(),
      );

  final double cropLeft;
  final double cropBottom;
  final double cropWidth;
  final double cropHeight;

  /// 0, 90, 180 or 270 (clockwise, as in `/Rotate`).
  final int rotate;

  bool get _swapped => rotate == 90 || rotate == 270;
  double get displayWidth => _swapped ? cropHeight : cropWidth;
  double get displayHeight => _swapped ? cropWidth : cropHeight;

  Map<String, dynamic> toJson() => {
        'x': cropLeft,
        'y': cropBottom,
        'w': cropWidth,
        'h': cropHeight,
        'r': rotate,
      };

  /// Display point (top-left origin, y down) → user space.
  Offset displayToUser(Offset d) {
    final (x, y) = switch (rotate) {
      90 => (d.dy, d.dx),
      180 => (cropWidth - d.dx, d.dy),
      270 => (cropWidth - d.dy, cropHeight - d.dx),
      _ => (d.dx, cropHeight - d.dy),
    };
    return Offset(x + cropLeft, y + cropBottom);
  }

  /// User space → display point.
  Offset userToDisplay(Offset u) {
    final lx = u.dx - cropLeft;
    final ly = u.dy - cropBottom;
    return switch (rotate) {
      90 => Offset(ly, lx),
      180 => Offset(cropWidth - lx, ly),
      270 => Offset(cropHeight - ly, cropWidth - lx),
      _ => Offset(lx, cropHeight - ly),
    };
  }

  /// Axis-aligned user-space rect `[llx, lly, urx, ury]` covering [display].
  List<double> displayRectToUser(Rect display) {
    final a = displayToUser(display.topLeft);
    final b = displayToUser(display.bottomRight);
    return [
      math.min(a.dx, b.dx),
      math.min(a.dy, b.dy),
      math.max(a.dx, b.dx),
      math.max(a.dy, b.dy),
    ];
  }

  Rect userRectToDisplay(List<double> r) {
    final a = userToDisplay(Offset(r[0], r[1]));
    final b = userToDisplay(Offset(r[2], r[3]));
    return Rect.fromPoints(a, b);
  }

  /// Matrix `[a b c d e f]` mapping "display-up" coordinates — display x,
  /// with y measured upwards from the display bottom — to user space.
  ///
  /// Form XObjects / appearance streams drawn in display-up coordinates with
  /// this `/Matrix` appear upright in the viewer for any `/Rotate`.
  List<double> get displayUpToUserMatrix {
    final x0 = cropLeft;
    final y0 = cropBottom;
    return switch (rotate) {
      90 => [0, 1, -1, 0, x0 + cropWidth, y0],
      180 => [-1, 0, 0, -1, x0 + cropWidth, y0 + cropHeight],
      270 => [0, -1, 1, 0, x0, y0 + cropHeight],
      _ => [1, 0, 0, 1, x0, y0],
    };
  }

  /// Display point → display-up point.
  Offset displayToUp(Offset d) => Offset(d.dx, displayHeight - d.dy);

  /// Maps display points from this geometry to [other] through user space
  /// (used when a page's crop box or rotation changed after saving).
  Offset remapTo(PdfPageGeometry other, Offset d) =>
      other.userToDisplay(displayToUser(d));

  /// Clockwise rotation delta (degrees) from this geometry to [other].
  int rotationDeltaTo(PdfPageGeometry other) =>
      ((other.rotate - rotate) % 360 + 360) % 360;

  bool sameAs(PdfPageGeometry o) =>
      (o.cropLeft - cropLeft).abs() < 0.01 &&
      (o.cropBottom - cropBottom).abs() < 0.01 &&
      (o.cropWidth - cropWidth).abs() < 0.01 &&
      (o.cropHeight - cropHeight).abs() < 0.01 &&
      o.rotate == rotate;
}

/// 2D affine transform `[a b c d e f]` (x' = a x + c y + e, y' = b x + d y + f).
class Affine2 {
  const Affine2(this.a, this.b, this.c, this.d, this.e, this.f);
  const Affine2.identity() : this(1, 0, 0, 1, 0, 0);

  factory Affine2.translate(double x, double y) => Affine2(1, 0, 0, 1, x, y);
  factory Affine2.scale(double sx, double sy) => Affine2(sx, 0, 0, sy, 0, 0);

  /// Rotation by [radians]; clockwise on screen in y-down spaces.
  factory Affine2.rotate(double radians) {
    final c = math.cos(radians);
    final s = math.sin(radians);
    return Affine2(c, s, -s, c, 0, 0);
  }

  /// Affine mapping (0,0)→[o], (1,0)→[x1], (0,1)→[y1].
  factory Affine2.fromBasis(Offset o, Offset x1, Offset y1) => Affine2(
        x1.dx - o.dx,
        x1.dy - o.dy,
        y1.dx - o.dx,
        y1.dy - o.dy,
        o.dx,
        o.dy,
      );

  factory Affine2.fromList(List<double> m) =>
      Affine2(m[0], m[1], m[2], m[3], m[4], m[5]);

  final double a, b, c, d, e, f;

  Offset apply(Offset p) =>
      Offset(a * p.dx + c * p.dy + e, b * p.dx + d * p.dy + f);

  /// `this ∘ other` (apply [other] first).
  Affine2 multiply(Affine2 o) => Affine2(
        a * o.a + c * o.b,
        b * o.a + d * o.b,
        a * o.c + c * o.d,
        b * o.c + d * o.d,
        a * o.e + c * o.f + e,
        b * o.e + d * o.f + f,
      );

  Affine2 inverse() {
    final det = a * d - b * c;
    if (det.abs() < 1e-12) return const Affine2.identity();
    final ia = d / det;
    final ib = -b / det;
    final ic = -c / det;
    final id = a / det;
    return Affine2(ia, ib, ic, id, -(ia * e + ic * f), -(ib * e + id * f));
  }

  List<double> toList() => [a, b, c, d, e, f];
}

/// Transform from a frame-local space (origin = frame top-left, y down,
/// unrotated) to display space, rotating [rotationDeg] clockwise about the
/// frame center with optional flips. Shared by painters and PDF writers.
Affine2 frameToDisplay(
  Rect frame,
  double rotationDeg, {
  bool flipH = false,
  bool flipV = false,
}) {
  final center = frame.center;
  var m = Affine2.translate(center.dx, center.dy)
      .multiply(Affine2.rotate(rotationDeg * math.pi / 180));
  if (flipH || flipV) {
    m = m.multiply(Affine2.scale(flipH ? -1 : 1, flipV ? -1 : 1));
  }
  return m.multiply(Affine2.translate(-frame.width / 2, -frame.height / 2));
}

/// Corners of [frame] rotated [rotationDeg] clockwise about its center.
List<Offset> rotatedFrameCorners(Rect frame, double rotationDeg) {
  final m = frameToDisplay(frame, rotationDeg);
  return [
    m.apply(Offset.zero),
    m.apply(Offset(frame.width, 0)),
    m.apply(Offset(frame.width, frame.height)),
    m.apply(Offset(0, frame.height)),
  ];
}

Rect boundsOfPoints(Iterable<Offset> pts) {
  var l = double.infinity, t = double.infinity;
  var r = -double.infinity, b = -double.infinity;
  for (final p in pts) {
    l = math.min(l, p.dx);
    t = math.min(t, p.dy);
    r = math.max(r, p.dx);
    b = math.max(b, p.dy);
  }
  if (l == double.infinity) return Rect.zero;
  return Rect.fromLTRB(l, t, r, b);
}
