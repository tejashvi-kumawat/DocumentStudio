import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'ocr_options.dart';

/// Lightweight OCR preprocess via the `image` package (no OpenCV).
///
/// - [OcrOptions.denoise]: grayscale + mild contrast boost
/// - [OcrOptions.deskew]: estimate skew from horizontal projection and rotate
Uint8List preprocessOcrImageBytes(
  Uint8List bytes, {
  required OcrOptions options,
}) {
  if (!options.deskew && !options.denoise) return bytes;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  var frame = decoded;

  if (options.denoise) {
    frame = img.grayscale(frame);
    frame = img.contrast(frame, contrast: 15);
  }

  if (options.deskew) {
    final angle = _estimateSkewDegrees(frame);
    if (angle.abs() >= 0.3 && angle.abs() <= 15) {
      frame = img.copyRotate(frame, angle: -angle);
    }
  }

  return Uint8List.fromList(img.encodePng(frame));
}

/// Rough deskew: compare horizontal projection energy across small angles.
double _estimateSkewDegrees(img.Image src) {
  final sample = img.copyResize(
    src,
    width: 320,
    height: (320 * src.height / src.width).round().clamp(40, 480),
  );
  var bestAngle = 0.0;
  var bestScore = -1.0;
  for (var a = -8.0; a <= 8.0; a += 0.5) {
    final rotated = a.abs() < 0.01 ? sample : img.copyRotate(sample, angle: a);
    final score = _projectionVariance(rotated);
    if (score > bestScore) {
      bestScore = score;
      bestAngle = a;
    }
  }
  return bestAngle;
}

double _projectionVariance(img.Image frame) {
  final h = frame.height;
  final w = frame.width;
  if (h < 2 || w < 2) return 0;
  final rowSums = List<double>.filled(h, 0);
  var mean = 0.0;
  for (var y = 0; y < h; y++) {
    var sum = 0.0;
    for (var x = 0; x < w; x++) {
      final p = frame.getPixel(x, y);
      final lum = (p.r + p.g + p.b) / 3.0;
      if (lum < 180) sum += 1;
    }
    rowSums[y] = sum;
    mean += sum;
  }
  mean /= h;
  var varSum = 0.0;
  for (final v in rowSums) {
    final d = v - mean;
    varSum += d * d;
  }
  return varSum / h;
}
