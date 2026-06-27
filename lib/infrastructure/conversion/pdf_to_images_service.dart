import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/jobs/job_models.dart';
import 'package:document_studio/core/pdf/pdf_document_cache.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/infrastructure/pdf/pdfrx_error_mapping.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Raster export format for [PdfToImagesService] ([DS-CNV-002] minimal path).
enum PdfToImageFormat {
  png,
  jpeg,
  webp,
  tiff,
}

extension PdfToImageFormatX on PdfToImageFormat {
  String get fileExtension => switch (this) {
        PdfToImageFormat.jpeg => 'jpg',
        PdfToImageFormat.png => 'png',
        PdfToImageFormat.webp => 'webp',
        PdfToImageFormat.tiff => 'tiff',
      };

  String get mimeType => switch (this) {
        PdfToImageFormat.jpeg => 'image/jpeg',
        PdfToImageFormat.png => 'image/png',
        PdfToImageFormat.webp => 'image/webp',
        PdfToImageFormat.tiff => 'image/tiff',
      };

  String get label => switch (this) {
        PdfToImageFormat.jpeg => 'JPEG',
        PdfToImageFormat.png => 'PNG',
        PdfToImageFormat.webp => 'WEBP',
        PdfToImageFormat.tiff => 'TIFF',
      };
}

/// Builds PNG/JPEG files from PDF pages via pdfrx render ([DS-CNV-002]).
class PdfToImagesService {
  static const defaultDpi = 150;
  static const maxDpi = 600;

  static double renderScaleForDpi(int dpi) {
    if (dpi < 36 || dpi > maxDpi) {
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.invalidFile,
        message: 'DPI must be between 36 and $maxDpi',
      );
    }
    return dpi / 72.0;
  }

  static Future<PdfDocumentLease> _open(
    LocalFileRef pdf,
    String? password, {
    bool allPages = false,
  }) async {
    try {
      return await PdfDocumentCache.instance.acquire(
        pdf.path,
        password: password,
        loadAllPages: allPages,
      );
    } catch (e) {
      final mapped = documentStudioErrorFromPdfrxOpen(e, password: password);
      if (password != null &&
          mapped.code == DocumentStudioErrorCode.passwordRequired) {
        throw DocumentStudioError(
          code: DocumentStudioErrorCode.wrongPassword,
          message: 'Incorrect password for this PDF.',
          cause: e,
        );
      }
      throw mapped;
    }
  }

  Future<int> pageCount({
    required LocalFileRef pdf,
    String? password,
  }) async {
    final lease = await _open(pdf, password);
    try {
      return lease.document.pages.length;
    } finally {
      lease.release();
    }
  }

  Future<List<LocalFileRef>> exportPages({
    required LocalFileRef pdf,
    required String outputDirectory,
    PdfToImageFormat format = PdfToImageFormat.png,
    int dpi = defaultDpi,
    int? firstPage1,
    int? lastPage1,
    String? password,
    void Function(JobProgress progress)? onProgress,
    JobCancelToken? cancelToken,
  }) async {
    final scale = renderScaleForDpi(dpi);
    await Directory(outputDirectory).create(recursive: true);

    // Render only the requested range. loadAllPages would walk the whole
    // open document, including pages the user did not export.
    final lease = await _open(pdf, password);
    final doc = lease.document;
    try {
      if (doc.pages.isEmpty) {
        throw const DocumentStudioError(
          code: DocumentStudioErrorCode.invalidFile,
          message: 'PDF has no pages',
        );
      }
      final start = (firstPage1 ?? 1).clamp(1, doc.pages.length);
      final end = (lastPage1 ?? doc.pages.length).clamp(start, doc.pages.length);
      final ext = format.fileExtension;
      final stem = p.basenameWithoutExtension(pdf.displayName);
      final outputs = <LocalFileRef>[];

      final exportCount = end - start + 1;
      var done = 0;
      for (var pageNum = start; pageNum <= end; pageNum++) {
        if (cancelToken?.isCancelled ?? false) {
          throw const DocumentStudioError(
            code: DocumentStudioErrorCode.processCancelled,
            message: 'Cancelled',
          );
        }
        onProgress?.call(
          JobProgress(
            fraction: exportCount == 0 ? 0 : done / exportCount,
            message: 'Rendering page $pageNum',
          ),
        );
        final page = doc.pages[pageNum - 1];
        final pdfImage = await page.render(
          fullWidth: page.width * scale,
          fullHeight: page.height * scale,
        );
        if (pdfImage == null) {
          throw DocumentStudioError(
            code: DocumentStudioErrorCode.conversionFailed,
            message: 'Could not render page $pageNum',
          );
        }
        try {
          final pixels = pdfImage.pixels;
          final w = pdfImage.width;
          final h = pdfImage.height;
          final name = '${stem}_p$pageNum.$ext';
          final outPath = p.join(outputDirectory, name);
          await Isolate.run(
            () => _encodeToFile(pixels, w, h, format, outPath),
          );
          final stat = await File(outPath).stat();
          outputs.add(
            LocalFileRef(
              path: outPath,
              displayName: name,
              sizeBytes: stat.size,
              lastModified: stat.modified,
            ),
          );
          done++;
        } finally {
          pdfImage.dispose();
        }
      }
      return outputs;
    } finally {
      lease.release();
    }
  }
}

/// Encodes BGRA [pixels] and writes [outPath]. Runs on a background isolate.
void _encodeToFile(
  Uint8List pixels,
  int width,
  int height,
  PdfToImageFormat format,
  String outPath,
) {
  final frame = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: pixels.buffer,
    bytesOffset: pixels.offsetInBytes,
    order: img.ChannelOrder.bgra,
    numChannels: 4,
  );
  final rgb = format == PdfToImageFormat.jpeg
      ? frame.convert(numChannels: 3)
      : frame;
  final Uint8List encoded = switch (format) {
    PdfToImageFormat.jpeg => img.encodeJpg(rgb, quality: 92),
    PdfToImageFormat.png => img.encodePng(rgb, level: 6),
    PdfToImageFormat.webp => img.encodeWebP(rgb, quality: 92),
    PdfToImageFormat.tiff => img.encodeTiff(rgb),
  };
  File(outPath).writeAsBytesSync(encoded, flush: true);
}
