import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/organize/organize_page_ref.dart';
import 'package:document_studio/features/pdf_viewer/widgets/page_crop_quad_math.dart';
import 'package:document_studio/infrastructure/conversion/images_to_pdf_service.dart';
import 'package:document_studio/infrastructure/organize/page_organize_service.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

/// Perspective-warps the page to [quad] and replaces that page in the PDF.
Future<Uint8List> perspectiveCropPageToBytes({
  required LocalFileRef input,
  required int pageIndex1Based,
  required int totalPages,
  required PageCropQuadNorm quad,
  required PageOrganizeService organize,
  ImagesToPdfService? imagesToPdf,
  String? password,
  int dpi = 150,
}) async {
  final images = imagesToPdf ?? ImagesToPdfService();
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
      throw StateError('Could not render page for perspective crop');
    }
    late final Uint8List pngBytes;
    try {
      final raster = img.Image.fromBytes(
        width: pdfImage.width,
        height: pdfImage.height,
        bytes: pdfImage.pixels.buffer,
        order: img.ChannelOrder.bgra,
      );
      final w = pdfImage.width.toDouble();
      final h = pdfImage.height.toDouble();
      img.Point px(Offset n) => img.Point(n.dx * (w - 1), n.dy * (h - 1));
      double dist(img.Point a, img.Point b) =>
          Offset((a.x - b.x).toDouble(), (a.y - b.y).toDouble()).distance;

      final tl = px(quad.topLeft);
      final tr = px(quad.topRight);
      final br = px(quad.bottomRight);
      final bl = px(quad.bottomLeft);

      final outW = math
          .max(
            dist(tr, tl),
            dist(br, bl),
          )
          .round()
          .clamp(32, 4096);
      final outH = math
          .max(
            dist(bl, tl),
            dist(br, tr),
          )
          .round()
          .clamp(32, 4096);

      final warped = img.copyRectify(
        raster,
        topLeft: tl,
        topRight: tr,
        bottomLeft: bl,
        bottomRight: br,
        interpolation: img.Interpolation.linear,
        toImage: img.Image(width: outW, height: outH),
      );
      pngBytes = Uint8List.fromList(img.encodePng(warped));
    } finally {
      pdfImage.dispose();
    }

    final tempDir = await Directory.systemTemp.createTemp('ds_quad_crop_');
    try {
      final pngPath = p.join(tempDir.path, 'page.png');
      await File(pngPath).writeAsBytes(pngBytes, flush: true);
      final pagePdfPath = p.join(tempDir.path, 'page.pdf');
      final pagePdf = await images.fromImageFiles(
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
      final assembled = await organize.assembleWorkspaceExport(
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

/// Renders the page and returns auto-detected content bounds (normalized).
Future<Rect?> detectPageContentBoundsNorm({
  required LocalFileRef input,
  required int pageIndex1Based,
  String? password,
  int dpi = 72,
}) async {
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
    if (pdfImage == null) return null;
    try {
      return detectContentBoundsNorm(
        width: pdfImage.width,
        height: pdfImage.height,
        bytes: pdfImage.pixels.buffer.asUint8List(),
        bgra: true,
      );
    } finally {
      pdfImage.dispose();
    }
  } finally {
    await doc.dispose();
  }
}
