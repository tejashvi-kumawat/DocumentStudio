import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/organize/organize_page_ref.dart';
import 'package:document_studio/infrastructure/conversion/images_to_pdf_service.dart';
import 'package:document_studio/infrastructure/organize/page_organize_service.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

/// Axis-aligned redaction rectangle in PDF user space (bottom-left origin).
class RedactRectPt {
  const RedactRectPt({
    required this.xPt,
    required this.yPt,
    required this.widthPt,
    required this.heightPt,
  });

  final double xPt;
  final double yPt;
  final double widthPt;
  final double heightPt;
}

/// Permanently removes page content under [rects] by rasterizing the page,
/// painting opaque black, and replacing that page with a flattened image page.
class PdfRedactService {
  PdfRedactService({required this._organize, ImagesToPdfService? imagesToPdf})
    : _imagesToPdf = imagesToPdf ?? ImagesToPdfService();

  final PageOrganizeService _organize;
  final ImagesToPdfService _imagesToPdf;

  /// Returns PDF bytes with redaction applied to [pageIndex1Based].
  Future<Uint8List> redactPageToBytes({
    required LocalFileRef input,
    required int pageIndex1Based,
    required List<RedactRectPt> rects,
    required int totalPages,
    String? password,
    int dpi = 150,
  }) async {
    if (rects.isEmpty) {
      throw ArgumentError('Draw at least one redaction rectangle');
    }
    if (pageIndex1Based < 1 || pageIndex1Based > totalPages) {
      throw ArgumentError('Invalid page');
    }

    final doc = await PdfDocument.openFile(
      input.path,
      passwordProvider: password == null ? null : () async => password,
    );
    try {
      final page = doc.pages[pageIndex1Based - 1];
      final scale = dpi / 72.0;
      final pdfImage = await page.render(
        fullWidth: page.width * scale,
        fullHeight: page.height * scale,
      );
      if (pdfImage == null) {
        throw const DocumentStudioError(
          code: DocumentStudioErrorCode.invalidFile,
          message: 'Could not render page for redaction',
        );
      }
      late final Uint8List pngBytes;
      try {
        final raster = img.Image.fromBytes(
          width: pdfImage.width,
          height: pdfImage.height,
          bytes: pdfImage.pixels.buffer,
          order: img.ChannelOrder.bgra,
        );
        final width = pdfImage.width;
        final height = pdfImage.height;
        for (final r in rects) {
          final left = (r.xPt / page.width * width).floor().clamp(0, width - 1);
          final top = ((1 - (r.yPt + r.heightPt) / page.height) * height)
              .floor()
              .clamp(0, height - 1);
          final rw = (r.widthPt / page.width * width).ceil().clamp(
            1,
            width - left,
          );
          final rh = (r.heightPt / page.height * height).ceil().clamp(
            1,
            height - top,
          );
          img.fillRect(
            raster,
            x1: left,
            y1: top,
            x2: left + rw - 1,
            y2: top + rh - 1,
            color: img.ColorRgba8(0, 0, 0, 255),
          );
        }
        pngBytes = Uint8List.fromList(img.encodePng(raster));
      } finally {
        pdfImage.dispose();
      }

      final tempDir = await Directory.systemTemp.createTemp('ds_redact_');
      try {
        final pngPath = p.join(tempDir.path, 'page.png');
        await File(pngPath).writeAsBytes(pngBytes, flush: true);
        final pagePdfPath = p.join(tempDir.path, 'page.pdf');
        final pagePdf = await _imagesToPdf.fromImageFiles(
          images: [LocalFileRef(path: pngPath, displayName: 'page.png')],
          outputPath: pagePdfPath,
        );

        final pages = <OrganizePageRef>[
          for (var n = 1; n <= totalPages; n++)
            if (n == pageIndex1Based)
              OrganizePageRef.fromFilePage(pagePdf, 1)
            else
              OrganizePageRef.fromFilePage(input, n),
        ];
        final assembled = await _organize.assembleWorkspaceExport(
          pages: pages,
          passwordsByPath: password == null || password.isEmpty
              ? null
              : {input.path: password},
        );
        return Uint8List.fromList(assembled.bytes);
      } finally {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    } finally {
      await doc.dispose();
    }
  }
}

/// Converts UI-normalized rects (top-left 0–1) on a page to PDF points.
List<RedactRectPt> redactRectsFromNorm({
  required List<ui.Rect> normRects,
  required double pageWidthPt,
  required double pageHeightPt,
}) {
  return [
    for (final r in normRects)
      RedactRectPt(
        xPt: r.left * pageWidthPt,
        yPt: (1 - r.bottom) * pageHeightPt,
        widthPt: r.width * pageWidthPt,
        heightPt: r.height * pageHeightPt,
      ),
  ];
}
