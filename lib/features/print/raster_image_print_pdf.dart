import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio/features/print/print_exception.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

/// Max edge length when wrapping a raster for the OS print dialog; larger
/// images are downscaled rather than rejected.
const rasterPrintMaxDimensionPx = 8000;

/// Highest resolution sent to the printer when fitting onto paper.
const _maxPrintPxPerPt = 300 / 72;

/// Builds a one-page PDF suitable for [Printing.layoutPdf] from raster bytes.
///
/// When [pageWidthPt]/[pageHeightPt] are given (the paper chosen in the print
/// dialog), the image is auto-rotated to match the paper orientation and
/// fitted inside [marginPt]; otherwise the page takes the image's size.
Future<Uint8List> buildPrintPdfFromRasterBytes(
  Uint8List imageBytes, {
  double? pageWidthPt,
  double? pageHeightPt,
  double marginPt = 18,
}) async {
  final prepared = await Isolate.run(
    () => _prepareRaster(imageBytes, pageWidthPt, pageHeightPt, marginPt),
  );
  if (prepared == null) {
    throw PrintException('Unsupported or corrupt image.');
  }

  final doc = await PdfDocument.createFromJpegData(
    prepared.jpeg,
    width: prepared.widthPt,
    height: prepared.heightPt,
    sourceName: 'document_studio://print-raster',
  );
  try {
    await doc.assemble();
    final pdfBytes = await doc.encodePdf();
    if (pdfBytes.isEmpty) {
      throw PrintException('Could not prepare image for printing.');
    }
    return pdfBytes;
  } finally {
    await doc.dispose();
  }
}

class _PreparedRaster {
  const _PreparedRaster(this.jpeg, this.widthPt, this.heightPt);

  final Uint8List jpeg;
  final double widthPt;
  final double heightPt;
}

_PreparedRaster? _prepareRaster(
  Uint8List bytes,
  double? pageW,
  double? pageH,
  double margin,
) {
  var image = img.decodeImage(bytes);
  if (image == null) return null;
  image = img.bakeOrientation(image);
  if (image.hasAlpha) {
    final flat = img.Image(width: image.width, height: image.height);
    img.fill(flat, color: img.ColorRgb8(255, 255, 255));
    image = img.compositeImage(flat, image);
  }
  final longest = math.max(image.width, image.height);
  if (longest > rasterPrintMaxDimensionPx) {
    final s = rasterPrintMaxDimensionPx / longest;
    image = img.copyResize(
      image,
      width: math.max(1, (image.width * s).round()),
      height: math.max(1, (image.height * s).round()),
      interpolation: img.Interpolation.average,
    );
  }

  if (pageW == null || pageH == null || pageW <= 0 || pageH <= 0) {
    return _PreparedRaster(
      Uint8List.fromList(img.encodeJpg(image, quality: 92)),
      image.width.toDouble(),
      image.height.toDouble(),
    );
  }

  final imageLandscape = image.width > image.height;
  final pageLandscape = pageW > pageH;
  if (image.width != image.height && imageLandscape != pageLandscape) {
    image = img.copyRotate(image, angle: 90);
  }

  final m = math.min(margin, math.min(pageW, pageH) / 4);
  final availW = pageW - 2 * m;
  final availH = pageH - 2 * m;
  final ptPerPx = math.min(availW / image.width, availH / image.height);
  final pxPerPt = math.min(1 / ptPerPx, _maxPrintPxPerPt);

  final drawW = math.max(1, (image.width * ptPerPx * pxPerPt).round());
  final drawH = math.max(1, (image.height * ptPerPx * pxPerPt).round());
  if (drawW != image.width || drawH != image.height) {
    image = img.copyResize(
      image,
      width: drawW,
      height: drawH,
      interpolation: drawW < image.width
          ? img.Interpolation.average
          : img.Interpolation.cubic,
    );
  }

  final canvas = img.Image(
    width: math.max(drawW, (pageW * pxPerPt).round()),
    height: math.max(drawH, (pageH * pxPerPt).round()),
  );
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(
    canvas,
    image,
    dstX: (canvas.width - drawW) ~/ 2,
    dstY: (canvas.height - drawH) ~/ 2,
  );
  return _PreparedRaster(
    Uint8List.fromList(img.encodeJpg(canvas, quality: 90)),
    pageW,
    pageH,
  );
}
