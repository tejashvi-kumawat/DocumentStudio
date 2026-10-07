import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:document_studio/core/isolate/run_isolated.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// One freehand stroke in pad-local logical pixels.
///
/// [widthFactors] scale the ink base width per point (velocity based, ~0.6–1.25).
class SignatureStroke {
  const SignatureStroke({required this.points, required this.widthFactors})
    : assert(points.length == widthFactors.length);

  final List<Offset> points;
  final List<double> widthFactors;

  bool get isEmpty => points.isEmpty;
}

/// Drawn signature: strokes in pad-local logical pixels plus the pad size.
class SignatureInk {
  const SignatureInk({
    required this.strokes,
    required this.padSize,
    this.color = const Color(0xFF1A1A1A),
    this.baseWidth = 2.6,
  });

  final List<SignatureStroke> strokes;
  final Size padSize;
  final Color color;
  final double baseWidth;

  bool get isEmpty => strokes.every((s) => s.isEmpty);

  /// Ink bounds including half the widest stroke.
  Rect? get bounds {
    double? l, t, r, b;
    var maxW = 0.0;
    for (final s in strokes) {
      for (var i = 0; i < s.points.length; i++) {
        final p = s.points[i];
        l = l == null ? p.dx : math.min(l, p.dx);
        t = t == null ? p.dy : math.min(t, p.dy);
        r = r == null ? p.dx : math.max(r, p.dx);
        b = b == null ? p.dy : math.max(b, p.dy);
        maxW = math.max(maxW, s.widthFactors[i]);
      }
    }
    if (l == null) return null;
    final half = maxW * baseWidth / 2;
    return Rect.fromLTRB(l - half, t! - half, r! + half, b! + half);
  }
}

/// Paints [strokes] with quadratic Bézier midpoint smoothing and per-segment
/// variable width. Shared by the live pad and the rasterizer.
void paintSignatureStrokes(
  Canvas canvas,
  Iterable<SignatureStroke> strokes, {
  required Color color,
  required double baseWidth,
}) {
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  for (final s in strokes) {
    paintSignatureStroke(canvas, s, paint: paint, baseWidth: baseWidth);
  }
}

void paintSignatureStroke(
  Canvas canvas,
  SignatureStroke stroke, {
  required Paint paint,
  required double baseWidth,
}) {
  final pts = stroke.points;
  final w = stroke.widthFactors;
  final n = pts.length;
  if (n == 0) return;
  if (n == 1) {
    final style = paint.style;
    canvas.drawCircle(
      pts.first,
      baseWidth * w.first / 2,
      paint..style = PaintingStyle.fill,
    );
    paint.style = style;
    return;
  }
  if (n == 2) {
    paint.strokeWidth = baseWidth * (w[0] + w[1]) / 2;
    canvas.drawLine(pts[0], pts[1], paint);
    return;
  }
  Offset mid(int i) =>
      Offset((pts[i].dx + pts[i + 1].dx) / 2, (pts[i].dy + pts[i + 1].dy) / 2);
  paint.strokeWidth = baseWidth * (w[0] + w[1]) / 2;
  canvas.drawLine(pts[0], mid(0), paint);
  for (var i = 1; i < n - 1; i++) {
    final a = mid(i - 1);
    final b = mid(i);
    paint.strokeWidth = baseWidth * w[i];
    canvas.drawPath(
      Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(pts[i].dx, pts[i].dy, b.dx, b.dy),
      paint,
    );
  }
  paint.strokeWidth = baseWidth * (w[n - 2] + w[n - 1]) / 2;
  canvas.drawLine(mid(n - 2), pts[n - 1], paint);
}

Future<Uint8List> _encodePng(ui.Image image, String what) async {
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (byteData == null) {
    throw StateError('Could not encode $what PNG');
  }
  return byteData.buffer.asUint8List();
}

/// Rasterizes a drawn signature to a tight, transparent, high-resolution PNG.
///
/// Prefer [ink] (keeps the true aspect ratio). [strokesNorm] (0–1 in a
/// [pixelWidth]×[pixelHeight] pad) is kept as a legacy fallback.
Future<Uint8List> rasterizeDrawnSignature({
  SignatureInk? ink,
  List<List<Offset>>? strokesNorm,
  int pixelWidth = 640,
  int pixelHeight = 240,
  Color color = const Color(0xFF1A1A1A),
  double strokeWidth = 3.5,
  double scale = 3,
  int maxSidePx = 2000,
}) async {
  final source =
      ink ??
      SignatureInk(
        padSize: Size(pixelWidth.toDouble(), pixelHeight.toDouble()),
        color: color,
        baseWidth: strokeWidth,
        strokes: [
          for (final s in strokesNorm ?? const <List<Offset>>[])
            SignatureStroke(
              points: [
                for (final p in s)
                  Offset(p.dx * pixelWidth, p.dy * pixelHeight),
              ],
              widthFactors: List.filled(s.length, 1.0),
            ),
        ],
      );
  final bounds = source.bounds;
  if (source.isEmpty || bounds == null) {
    throw ArgumentError('Draw a signature first');
  }
  final longest = math.max(bounds.width, bounds.height);
  final pad = math.max(longest * 0.04, source.baseWidth);
  final region = bounds.inflate(pad);
  final regionLongest = math.max(region.width, region.height);
  final s = math.min(scale, maxSidePx / regionLongest);
  final outW = math.max(1, (region.width * s).ceil());
  final outH = math.max(1, (region.height * s).ceil());

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(s);
  canvas.translate(-region.left, -region.top);
  paintSignatureStrokes(
    canvas,
    source.strokes,
    color: source.color,
    baseWidth: source.baseWidth,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(outW, outH);
  picture.dispose();
  return _encodePng(image, 'drawn signature');
}

/// A script typeface for typed signatures.
class SignatureTypeface {
  const SignatureTypeface({
    required this.id,
    required this.label,
    required this.families,
    this.italic = true,
    this.weight = FontWeight.w400,
  });

  final String id;
  final String label;

  /// Preferred family first, then fallbacks.
  final List<String> families;
  final bool italic;
  final FontWeight weight;

  TextStyle textStyle({required double fontSize, Color? color}) {
    return TextStyle(
      fontFamily: families.isEmpty ? null : families.first,
      fontFamilyFallback: families.length > 1 ? families.sublist(1) : null,
      fontSize: fontSize,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      fontWeight: weight,
      color: color,
      height: 1.2,
    );
  }
}

/// Script faces bundled under `assets/fonts/signature` (SIL OFL), so typed
/// signatures look identical on every platform.
const kSignatureTypefaces = <SignatureTypeface>[
  SignatureTypeface(
    id: 'great_vibes',
    label: 'Great Vibes',
    families: ['DS Great Vibes'],
    italic: false,
  ),
  SignatureTypeface(
    id: 'dancing',
    label: 'Dancing Script',
    families: ['DS Dancing Script'],
    italic: false,
    weight: FontWeight.w500,
  ),
  SignatureTypeface(
    id: 'allura',
    label: 'Allura',
    families: ['DS Allura'],
    italic: false,
  ),
  SignatureTypeface(
    id: 'sacramento',
    label: 'Sacramento',
    families: ['DS Sacramento'],
    italic: false,
  ),
  SignatureTypeface(
    id: 'alex_brush',
    label: 'Alex Brush',
    families: ['DS Alex Brush'],
    italic: false,
  ),
  SignatureTypeface(
    id: 'mr_dafoe',
    label: 'Mr Dafoe',
    families: ['DS Mr Dafoe'],
    italic: false,
  ),
  SignatureTypeface(
    id: 'herr_von_muellerhoff',
    label: 'Muellerhoff',
    families: ['DS Herr Von Muellerhoff'],
    italic: false,
  ),
  SignatureTypeface(
    id: 'caveat',
    label: 'Caveat',
    families: ['DS Caveat'],
    italic: false,
    weight: FontWeight.w500,
  ),
];

SignatureTypeface signatureTypefaceById(String? id) => kSignatureTypefaces
    .firstWhere((t) => t.id == id, orElse: () => kSignatureTypefaces.first);

/// Kept for callers that used to probe system fonts; the faces are bundled.
Future<List<SignatureTypeface>> loadAvailableSignatureTypefaces() async =>
    kSignatureTypefaces;

/// Rasterizes a typed name into a tight, transparent, high-resolution PNG.
Future<Uint8List> rasterizeTypedSignature({
  required String text,
  double fontSize = 160,
  Color color = const Color(0xFF1A1A1A),
  SignatureTypeface? typeface,
}) async {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError('Signature text is empty');
  }
  final style = (typeface ?? kSignatureTypefaces.first).textStyle(
    fontSize: fontSize,
    color: color,
  );
  final painter = TextPainter(
    text: TextSpan(text: trimmed, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 2,
  )..layout(maxWidth: fontSize * 24);
  // Script glyphs overhang their advance box; render with margin then crop.
  final margin = fontSize * 0.6;
  final width = (painter.width + margin * 2).ceil();
  final height = (painter.height + margin * 2).ceil();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, Offset(margin, margin));
  painter.dispose();
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  final cropped = await _cropToAlpha(image);
  return _encodePng(cropped, 'typed signature');
}

/// Crops [image] to its non-transparent pixels plus [paddingFraction] of the
/// longest side. Disposes [image] when a new one is returned.
Future<ui.Image> _cropToAlpha(
  ui.Image image, {
  double paddingFraction = 0.04,
}) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return image;
  final px = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final w = image.width;
  final h = image.height;
  var minX = w, minY = h, maxX = -1, maxY = -1;
  for (var y = 0; y < h; y++) {
    final row = y * w * 4;
    for (var x = 0; x < w; x++) {
      if (px[row + x * 4 + 3] > 4) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) return image;
  final cw = maxX - minX + 1;
  final ch = maxY - minY + 1;
  final pad = (math.max(cw, ch) * paddingFraction).ceil();
  final outW = cw + pad * 2;
  final outH = ch + pad * 2;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(
      minX.toDouble(),
      minY.toDouble(),
      cw.toDouble(),
      ch.toDouble(),
    ),
    Rect.fromLTWH(pad.toDouble(), pad.toDouble(), cw.toDouble(), ch.toDouble()),
    Paint()..filterQuality = FilterQuality.none,
  );
  final picture = recorder.endRecording();
  final out = await picture.toImage(outW, outH);
  picture.dispose();
  image.dispose();
  return out;
}

/// Result of [prepareSignatureImage].
class PreparedSignatureImage {
  const PreparedSignatureImage({
    required this.png,
    required this.width,
    required this.height,
    required this.hasOpaqueLightBackground,
  });

  final Uint8List png;
  final int width;
  final int height;

  /// True when the source had an opaque near-white background (scan/photo).
  final bool hasOpaqueLightBackground;
}

/// Normalizes a PNG/JPG signature image off the UI isolate: downscales above
/// ~2 MP, optionally keys out a near-white background (soft edge), and crops
/// to content.
Future<PreparedSignatureImage> prepareSignatureImage(
  Uint8List bytes, {
  bool removeWhiteBackground = true,
}) {
  return runIsolated((a) => _prepareSignatureImageSync(a.$1, a.$2), (
    bytes,
    removeWhiteBackground,
  ));
}

PreparedSignatureImage _prepareSignatureImageSync(
  Uint8List bytes,
  bool removeWhite,
) {
  var decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw ArgumentError('Unsupported image — use PNG or JPG');
  }
  const maxPixels = 2000000;
  final pixels = decoded.width * decoded.height;
  if (pixels > maxPixels) {
    final f = math.sqrt(maxPixels / pixels);
    decoded = img.copyResize(
      decoded,
      width: math.max(1, (decoded.width * f).round()),
      height: math.max(1, (decoded.height * f).round()),
      interpolation: img.Interpolation.average,
    );
  }
  final rgba = Uint8List.fromList(
    decoded
        .convert(format: img.Format.uint8, numChannels: 4)
        .getBytes(order: img.ChannelOrder.rgba),
  );
  final w = decoded.width;
  final h = decoded.height;

  final lightBg = _hasOpaqueLightBorder(rgba, w, h);
  if (removeWhite && lightBg) {
    const lo = 170.0;
    const hi = 232.0;
    for (var i = 0; i < rgba.length; i += 4) {
      final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
      final lum = 0.299 * r + 0.587 * g + 0.114 * b;
      if (lum >= hi) {
        rgba[i + 3] = 0;
      } else if (lum > lo) {
        final t = (hi - lum) / (hi - lo);
        // Un-mix the white paper from anti-aliased edges to avoid a halo.
        rgba[i] = ((r - 255 * (1 - t)) / t).clamp(0, 255).round();
        rgba[i + 1] = ((g - 255 * (1 - t)) / t).clamp(0, 255).round();
        rgba[i + 2] = ((b - 255 * (1 - t)) / t).clamp(0, 255).round();
        rgba[i + 3] = (rgba[i + 3] * t).round();
      }
    }
  }

  var minX = w, minY = h, maxX = -1, maxY = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (rgba[(y * w + x) * 4 + 3] > 8) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  var out = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  if (maxX >= 0 && (minX > 0 || minY > 0 || maxX < w - 1 || maxY < h - 1)) {
    final cw = maxX - minX + 1;
    final ch = maxY - minY + 1;
    final pad = (math.max(cw, ch) * 0.04).ceil();
    final x0 = math.max(0, minX - pad);
    final y0 = math.max(0, minY - pad);
    final x1 = math.min(w - 1, maxX + pad);
    final y1 = math.min(h - 1, maxY + pad);
    out = img.copyCrop(
      out,
      x: x0,
      y: y0,
      width: x1 - x0 + 1,
      height: y1 - y0 + 1,
    );
  }
  return PreparedSignatureImage(
    png: Uint8List.fromList(img.encodePng(out)),
    width: out.width,
    height: out.height,
    hasOpaqueLightBackground: lightBg,
  );
}

bool _hasOpaqueLightBorder(Uint8List rgba, int w, int h) {
  var total = 0;
  var light = 0;
  void sample(int x, int y) {
    final i = (y * w + x) * 4;
    total++;
    final lum = 0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2];
    if (rgba[i + 3] > 245 && lum > 200) light++;
  }

  final stepX = math.max(1, w ~/ 200);
  final stepY = math.max(1, h ~/ 200);
  for (var x = 0; x < w; x += stepX) {
    sample(x, 0);
    sample(x, h - 1);
  }
  for (var y = 0; y < h; y += stepY) {
    sample(0, y);
    sample(w - 1, y);
  }
  return total > 0 && light / total >= 0.6;
}
