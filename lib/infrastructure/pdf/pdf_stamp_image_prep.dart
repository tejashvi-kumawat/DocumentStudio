import 'dart:io' show zlib;
import 'dart:typed_data';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/domain/pdf_stamp/pdf_page_stamp_models.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_image_builder.dart';
import 'package:image/image.dart' as img;

/// Builds [PdfOverlayImageLine] from raster bytes and target [rect] on the page.
///
/// Images with real transparency are written losslessly (Flate RGB + `/SMask`);
/// opaque images are re-encoded as JPEG.
PdfOverlayImageLine buildImageStampOverlayLine({
  required Uint8List sourceBytes,
  required PdfStampRect rect,
  double opacity = 1,
  double rotationDegrees = 0,
}) {
  final decoded = img.decodeImage(sourceBytes);
  if (decoded == null) {
    throw const DocumentStudioError(
      code: DocumentStudioErrorCode.invalidFile,
      message: 'Unsupported or corrupt image',
    );
  }
  final transparent = _transparentPlanes(decoded);
  if (transparent != null) {
    return PdfOverlayImageLine(
      jpegBytes: transparent.rgbFlate,
      rgbIsFlate: true,
      smaskBytes: transparent.alphaFlate,
      imageWidthPx: decoded.width,
      imageHeightPx: decoded.height,
      xPt: rect.xPt,
      yPt: rect.yPt,
      widthPt: rect.widthPt,
      heightPt: rect.heightPt,
      opacity: opacity.clamp(0.05, 1.0),
      rotationDegrees: rotationDegrees,
    );
  }
  final jpeg = Uint8List.fromList(img.encodeJpg(decoded, quality: 92));
  return PdfOverlayImageLine(
    jpegBytes: jpeg,
    imageWidthPx: decoded.width,
    imageHeightPx: decoded.height,
    xPt: rect.xPt,
    yPt: rect.yPt,
    widthPt: rect.widthPt,
    heightPt: rect.heightPt,
    opacity: opacity.clamp(0.05, 1.0),
    rotationDegrees: rotationDegrees,
  );
}

/// Zlib-compressed RGB and alpha planes when [decoded] has any alpha < 255,
/// otherwise null.
({Uint8List rgbFlate, Uint8List alphaFlate})? _transparentPlanes(
  img.Image decoded,
) {
  if (!decoded.hasAlpha) return null;
  final rgba = decoded.convert(numChannels: 4, format: img.Format.uint8);
  final w = rgba.width;
  final h = rgba.height;
  final rgb = Uint8List(w * h * 3);
  final alpha = Uint8List(w * h);
  var anyTransparent = false;
  var i = 0;
  for (final p in rgba) {
    final a = p.a.toInt();
    alpha[i] = a;
    if (a == 0) {
      // Fully transparent: white avoids dark fringes when viewers interpolate.
      rgb[i * 3] = 255;
      rgb[i * 3 + 1] = 255;
      rgb[i * 3 + 2] = 255;
    } else {
      rgb[i * 3] = p.r.toInt();
      rgb[i * 3 + 1] = p.g.toInt();
      rgb[i * 3 + 2] = p.b.toInt();
    }
    if (a < 255) anyTransparent = true;
    i++;
  }
  if (!anyTransparent) return null;
  return (
    rgbFlate: Uint8List.fromList(zlib.encode(rgb)),
    alphaFlate: Uint8List.fromList(zlib.encode(alpha)),
  );
}

PdfStampRect defaultImageStampRect({
  required double pageWidthPt,
  required double pageHeightPt,
  required int imageWidthPx,
  required int imageHeightPx,
  PdfPageStampLayout layout = const PdfPageStampLayout(),
}) {
  final aspect = imageWidthPx / imageHeightPx;
  return computeImageStampRect(
    pageWidthPt: pageWidthPt,
    pageHeightPt: pageHeightPt,
    imageAspectWidthOverHeight: aspect,
    layout: layout,
  );
}
