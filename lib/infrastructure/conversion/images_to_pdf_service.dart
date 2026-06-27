import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/jobs/job_models.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/infrastructure/conversion/images_to_pdf_page_size.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

/// Builds a multi-page PDF from raster images ([DS-CNV-001] minimal path).
class ImagesToPdfService {
  static const maxImageDimensionPx = 8000;

  static const supportedExtensions = [
    'jpg',
    'jpeg',
    'png',
    'webp',
    'tif',
    'tiff',
    'bmp',
  ];

  Future<LocalFileRef> fromImageFiles({
    required List<LocalFileRef> images,
    required String outputPath,
    ImagesToPdfPageSize pageSize = ImagesToPdfPageSize.fitImage,
    void Function(JobProgress progress)? onProgress,
    JobCancelToken? cancelToken,
  }) async {
    if (images.isEmpty) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.invalidFile,
        message: 'Pick at least one image',
      );
    }

    final pageDocs = <PdfDocument>[];
    try {
      final collectedPages = <PdfPage>[];
      final total = images.length;
      for (var i = 0; i < images.length; i++) {
        if (cancelToken?.isCancelled ?? false) {
          throw const DocumentStudioError(
            code: DocumentStudioErrorCode.processCancelled,
            message: 'Cancelled',
          );
        }
        onProgress?.call(
          JobProgress(
            fraction: total == 0 ? 0 : i / total,
            message: 'Page ${i + 1} of $total',
          ),
        );
        final ref = images[i];
        final bytes = await File(ref.path).readAsBytes();
        final preset = pageSize.pagePoints;
        final prepared = await Isolate.run(() => _preparePage(bytes, preset));
        if (prepared == null) {
          throw DocumentStudioError(
            code: DocumentStudioErrorCode.invalidFile,
            message: 'Unsupported or corrupt image: ${ref.displayName}',
          );
        }
        final doc = await PdfDocument.createFromJpegData(
          prepared.jpeg,
          width: prepared.widthPt,
          height: prepared.heightPt,
          sourceName: ref.path,
        );
        pageDocs.add(doc);
        if (doc.pages.isEmpty) {
          throw DocumentStudioError(
            code: DocumentStudioErrorCode.invalidFile,
            message: 'Could not add page for ${ref.displayName}',
          );
        }
        collectedPages.add(doc.pages.first);
      }
      onProgress?.call(
        JobProgress(fraction: 0.95, message: 'Assembling PDF…'),
      );

      final outDoc = await PdfDocument.createNew(
        sourceName:
            'document_studio://images-to-pdf/${DateTime.now().microsecondsSinceEpoch}',
      );
      try {
        outDoc.pages = collectedPages;
        await outDoc.assemble();
        final pdfBytes = await outDoc.encodePdf();
        await Directory(p.dirname(outputPath)).create(recursive: true);
        await File(outputPath).writeAsBytes(pdfBytes, flush: true);
        final stat = await File(outputPath).stat();
        return LocalFileRef(
          path: outputPath,
          displayName: p.basename(outputPath),
          sizeBytes: stat.size,
          lastModified: stat.modified,
        );
      } finally {
        await outDoc.dispose();
      }
    } finally {
      for (final d in pageDocs) {
        await d.dispose();
      }
    }
  }

}

/// Longest page side for "Fit image" pages (17 in); larger images are shown
/// smaller on the page but keep all their pixels.
const double _maxFitPagePt = 1224;

/// Upper bound for composed preset pages (300 dpi).
const double _maxPresetPxPerPt = 300 / 72;

class _PreparedPage {
  const _PreparedPage(this.jpeg, this.widthPt, this.heightPt);

  final Uint8List jpeg;
  final double widthPt;
  final double heightPt;
}

/// Decodes, applies EXIF orientation, flattens transparency onto white, and
/// encodes a page JPEG. Runs on a background isolate.
///
/// Preset pages are composed at the image's own resolution (capped at 300 dpi)
/// rather than 1 px per point, so photos stay sharp.
_PreparedPage? _preparePage(Uint8List bytes, (double, double)? preset) {
  final isJpeg = bytes.length > 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final orientation = decoded.exif.imageIfd.orientation ?? 1;
  var frame = orientation == 1 ? decoded : img.bakeOrientation(decoded);
  final longest = math.max(frame.width, frame.height);
  if (longest > ImagesToPdfService.maxImageDimensionPx) {
    final s = ImagesToPdfService.maxImageDimensionPx / longest;
    frame = img.copyResize(
      frame,
      width: math.max(1, (frame.width * s).round()),
      height: math.max(1, (frame.height * s).round()),
      interpolation: img.Interpolation.average,
    );
  }

  if (preset == null) {
    final fit = math.min(1.0, _maxFitPagePt / math.max(frame.width, frame.height));
    final widthPt = frame.width * fit;
    final heightPt = frame.height * fit;
    final unchanged = identical(frame, decoded);
    if (isJpeg && unchanged && decoded.numChannels == 3) {
      return _PreparedPage(bytes, widthPt, heightPt);
    }
    final flat = frame.hasAlpha ? _flattenOnWhite(frame) : frame;
    return _PreparedPage(
      Uint8List.fromList(img.encodeJpg(flat, quality: 92)),
      widthPt,
      heightPt,
    );
  }

  final (pageWPt, pageHPt) = preset;
  final pxPerPt = math
      .max(frame.width / pageWPt, frame.height / pageHPt)
      .clamp(1.0, _maxPresetPxPerPt);
  final canvasW = (pageWPt * pxPerPt).round();
  final canvasH = (pageHPt * pxPerPt).round();
  final composed = composeImageOnPage(
    source: frame,
    pageW: canvasW,
    pageH: canvasH,
  );
  return _PreparedPage(
    Uint8List.fromList(img.encodeJpg(composed, quality: 92)),
    pageWPt,
    pageHPt,
  );
}

img.Image _flattenOnWhite(img.Image src) {
  final canvas = img.Image(width: src.width, height: src.height);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(canvas, src);
  return canvas;
}
