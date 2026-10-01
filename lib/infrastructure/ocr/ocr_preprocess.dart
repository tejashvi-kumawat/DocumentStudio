import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio_ocr/document_studio_ocr.dart';
import 'package:image/image.dart' as img;

/// Lightweight OCR preprocess via the `image` package (no OpenCV). Run it on
/// a background isolate.
///
/// - Always applies the EXIF orientation of camera photos (Tesseract ignores
///   it and would read the photo sideways).
/// - [OcrOptions.denoise]: grayscale + percentile contrast stretch (faded or
///   unevenly lit photos).
/// - [OcrOptions.deskew]: estimate skew from row projections and straighten
///   onto a white background.
///
/// Returns the input bytes untouched when nothing needs to change.
Uint8List preprocessOcrImageBytes(
  Uint8List bytes, {
  required OcrOptions options,
}) {
  final rotatedByExif = _exifOrientation(bytes) > 1;
  if (!options.deskew && !options.denoise && !rotatedByExif) return bytes;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  var frame = img.bakeOrientation(decoded);

  if (options.denoise || options.deskew) {
    frame = _stretchGray(img.grayscale(frame));
  }

  if (options.deskew) {
    final angle = _estimateSkewDegrees(frame);
    if (angle.abs() >= 0.3) {
      frame = _rotateOnWhite(frame, angle);
    }
  }

  return Uint8List.fromList(img.encodePng(frame, level: 1));
}

int _exifOrientation(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return 1;
  try {
    return img.decodeJpgExif(bytes)?.imageIfd.orientation ?? 1;
  } catch (_) {
    return 1;
  }
}

/// Maps the 1st/99th luminance percentiles to black/white.
img.Image _stretchGray(img.Image gray) {
  final hist = List<int>.filled(256, 0);
  for (final p in gray) {
    hist[p.r.toInt().clamp(0, 255)]++;
  }
  final count = gray.width * gray.height;
  var acc = 0;
  var lo = 0;
  var hi = 255;
  for (var v = 0; v < 256; v++) {
    acc += hist[v];
    if (acc <= count ~/ 100) lo = v;
    if (acc >= count - count ~/ 100) {
      hi = v;
      break;
    }
  }
  if (hi - lo < 32) return gray;
  final lut = List<int>.generate(
    256,
    (v) => ((v - lo) * 255 / (hi - lo)).round().clamp(0, 255),
  );
  for (final p in gray) {
    final v = lut[p.r.toInt().clamp(0, 255)];
    p
      ..r = v
      ..g = v
      ..b = v;
  }
  return gray;
}

img.Image _rotateOnWhite(img.Image src, double angle) {
  final withAlpha = src.numChannels == 4 ? src : src.convert(numChannels: 4);
  final rotated = img.copyRotate(
    withAlpha,
    angle: angle,
    interpolation: img.Interpolation.linear,
  );
  final canvas = img.Image(width: rotated.width, height: rotated.height);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  return img.compositeImage(canvas, rotated);
}

/// Angle (degrees, clockwise-positive as used by [img.copyRotate]) that makes
/// text rows horizontal, searched in ±8° by projection variance.
double _estimateSkewDegrees(img.Image src) {
  final sample = img.copyResize(
    src,
    width: 480,
    height: math.max(40, (480 * src.height / src.width).round()),
    interpolation: img.Interpolation.average,
  );
  final w = sample.width;
  final h = sample.height;
  final xs = <int>[];
  final ys = <int>[];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (sample.getPixel(x, y).r < 128) {
        xs.add(x);
        ys.add(y);
      }
    }
  }
  if (xs.length < 50) return 0;

  double score(double deg) {
    final t = deg * math.pi / 180;
    final c = math.cos(t);
    final s = math.sin(t);
    final bins = List<int>.filled(h * 2 + w, 0);
    final offset = w;
    for (var i = 0; i < xs.length; i++) {
      final dx = xs[i] - w / 2;
      final dy = ys[i] - h / 2;
      final ry = (dx * s + dy * c + h / 2).round() + offset;
      if (ry >= 0 && ry < bins.length) bins[ry]++;
    }
    var sum = 0.0;
    for (final b in bins) {
      sum += b * b;
    }
    return sum;
  }

  var best = 0.0;
  var bestScore = score(0);
  for (var a = -8.0; a <= 8.0; a += 0.5) {
    final sc = score(a);
    if (sc > bestScore) {
      bestScore = sc;
      best = a;
    }
  }
  for (var a = best - 0.4; a <= best + 0.4; a += 0.1) {
    final sc = score(a);
    if (sc > bestScore) {
      bestScore = sc;
      best = a;
    }
  }
  return best;
}
