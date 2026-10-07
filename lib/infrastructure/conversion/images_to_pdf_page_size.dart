import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Target page size when combining images into a PDF ([DS-CNV-001]).
enum ImagesToPdfPageSize { fitImage, a4, letter, legal }

extension ImagesToPdfPageSizeX on ImagesToPdfPageSize {
  String get label => switch (this) {
    ImagesToPdfPageSize.fitImage => 'Fit image',
    ImagesToPdfPageSize.a4 => 'A4',
    ImagesToPdfPageSize.letter => 'US Letter',
    ImagesToPdfPageSize.legal => 'US Legal',
  };

  /// MediaBox width/height in PDF points (72 pt = 1 in), or null for native image size.
  (double widthPt, double heightPt)? get pagePoints => switch (this) {
    ImagesToPdfPageSize.fitImage => null,
    ImagesToPdfPageSize.a4 => (595.0, 842.0),
    ImagesToPdfPageSize.letter => (612.0, 792.0),
    ImagesToPdfPageSize.legal => (612.0, 1008.0),
  };
}

/// Scales [source] to fit inside the page box and centers on white ([DS-CNV-001]).
img.Image composeImageOnPage({
  required img.Image source,
  required int pageW,
  required int pageH,
}) {
  final scale = math.min(pageW / source.width, pageH / source.height);
  final tw = (source.width * scale).round().clamp(1, pageW);
  final th = (source.height * scale).round().clamp(1, pageH);
  final resized = (tw == source.width && th == source.height)
      ? source
      : img.copyResize(
          source,
          width: tw,
          height: th,
          interpolation: tw < source.width
              ? img.Interpolation.average
              : img.Interpolation.linear,
        );
  final canvas = img.Image(width: pageW, height: pageH);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  final x = (pageW - tw) ~/ 2;
  final y = (pageH - th) ~/ 2;
  img.compositeImage(canvas, resized, dstX: x, dstY: y);
  return canvas;
}
