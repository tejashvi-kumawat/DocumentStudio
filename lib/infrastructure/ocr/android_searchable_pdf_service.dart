import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio/core/pdf/pdf_document_cache.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/infrastructure/ocr/android_tesseract_ocr_port.dart';
import 'package:document_studio/infrastructure/ocr/hocr_word_parser.dart';
import 'package:document_studio/infrastructure/ocr/ocr_engine_environment.dart';
import 'package:document_studio/infrastructure/ocr/searchable_pdf_text_layer.dart';
import 'package:document_studio/infrastructure/ocr/tesseract_searchable_pdf_service.dart';
import 'package:document_studio_ocr/document_studio_ocr.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

/// On-device searchable PDF for Android/iOS: Tesseract → invisible text stamp.
///
/// Does **not** use qpdf or the Tesseract PDF renderer. Pages are rasterized
/// one at a time (no `loadAllPages`), OCR'd via [AndroidTesseractOcrPort], then
/// an invisible Helvetica layer is stamped with pure-Dart [PdfEditDocument].
class AndroidSearchablePdfService implements SearchablePdfPort {
  AndroidSearchablePdfService({AndroidTesseractOcrPort? ocr})
    : _ocr = ocr ?? const AndroidTesseractOcrPort();

  final AndroidTesseractOcrPort _ocr;

  static const int existingTextMinChars =
      TesseractSearchablePdfService.existingTextMinChars;

  Future<SearchablePdfEngineStatus> probeEngine({
    String language = 'eng',
    bool refresh = false,
  }) async {
    final env = await loadOcrEngineEnvironment(refresh: refresh);
    return SearchablePdfEngineStatus(
      tesseractPath: env.tesseractPath,
      tessdataPrefix: env.tessdataDirFor(language.split('+')),
      missingMessage: env.readinessError(language),
      installedLanguages: env.installedLanguages,
    );
  }

  Future<Uint8List> makeSearchableFile({
    required LocalFileRef file,
    String? password,
    OcrOptions options = const OcrOptions(),
    Set<int>? pages1Based,
    void Function(double fraction, String message)? onProgress,
    OcrCancelToken? cancelToken,
  }) async {
    final result = await makeSearchable(
      file: file,
      password: password,
      options: options,
      pages1Based: pages1Based,
      cancelToken: cancelToken,
      onProgress: onProgress == null
          ? null
          : (p) => onProgress(p.fraction, p.message),
    );
    return result.bytes;
  }

  Future<SearchablePdfResult> makeSearchable({
    required LocalFileRef file,
    String? password,
    OcrOptions options = const OcrOptions(),
    Set<int>? pages1Based,
    void Function(SearchablePdfProgress progress)? onProgress,
    OcrCancelToken? cancelToken,
  }) async {
    final stopwatch = Stopwatch()..start();
    final token = cancelToken ?? OcrCancelToken();
    void report(double f, String msg, int done, int total) => onProgress?.call(
      SearchablePdfProgress(
        fraction: f.clamp(0.0, 1.0),
        message: msg,
        pagesDone: done,
        pagesTotal: total,
      ),
    );

    report(0, 'Checking OCR engine…', 0, 0);
    final status = await probeEngine(language: options.language);
    if (!status.isReady) {
      throw OcrEngineBlockedException(status.missingMessage!);
    }
    token.throwIfCancelled();

    final tempDir = await Directory.systemTemp.createTemp('ds_a_searchable_');
    try {
      report(0.01, 'Opening PDF…', 0, 0);
      // Progressive open — never loadAllPages (huge scans must stay responsive).
      final lease = await PdfDocumentCache.instance.acquire(
        file.path,
        password: password,
      );
      final doc = lease.document;
      final layers = <PageOcrTextLayer>[];
      final recognized = <int>[];
      final skipped = <int>[];
      try {
        final pageCount = doc.pages.length;
        final requested = (pages1Based == null || pages1Based.isEmpty)
            ? [for (var i = 1; i <= pageCount; i++) i]
            : (pages1Based.where((n) => n >= 1 && n <= pageCount).toList()
                ..sort());
        if (requested.isEmpty) {
          throw OcrEngineBlockedException('No valid pages to recognize.');
        }

        final toOcr = <int>[];
        if (options.skipPagesWithText) {
          report(
            0.02,
            'Checking pages for existing text…',
            0,
            requested.length,
          );
          for (final n in requested) {
            token.throwIfCancelled();
            if (await _pageHasText(doc.pages[n - 1])) {
              skipped.add(n);
            } else {
              toOcr.add(n);
            }
          }
        } else {
          toOcr.addAll(requested);
        }

        final total = toOcr.length;
        if (total == 0) {
          report(1, 'All pages already contain text', 0, 0);
          return SearchablePdfResult(
            bytes: await File(file.path).readAsBytes(),
            recognizedPages: const [],
            skippedPages: skipped,
            elapsed: stopwatch.elapsed,
          );
        }

        report(0.04, 'Recognizing text · 0 of $total pages', 0, total);
        for (var i = 0; i < toOcr.length; i++) {
          token.throwIfCancelled();
          final n = toOcr[i];
          final layer = await _ocrPage(
            page: doc.pages[n - 1],
            pageNumber: n,
            tempDir: tempDir.path,
            options: options,
            token: token,
          );
          if (!layer.isEmpty) {
            layers.add(layer);
            recognized.add(n);
          } else {
            // Still count as attempted; empty OCR does not change the page.
            recognized.add(n);
          }
          final done = i + 1;
          report(
            0.04 + 0.88 * done / total,
            'Recognizing text · $done of $total pages',
            done,
            total,
          );
        }
      } finally {
        lease.release();
      }

      token.throwIfCancelled();
      report(
        0.94,
        'Adding invisible text layer…',
        recognized.length,
        recognized.length,
      );
      final inputBytes = await File(file.path).readAsBytes();
      final outBytes = stampOcrTextLayers(inputBytes, layers);
      report(1, 'Done', recognized.length, recognized.length);
      return SearchablePdfResult(
        bytes: outBytes,
        recognizedPages: recognized,
        skippedPages: skipped,
        elapsed: stopwatch.elapsed,
      );
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  @override
  Future<Uint8List> createSearchablePdf(
    Uint8List pdfBytes, {
    OcrOptions options = const OcrOptions(),
  }) async {
    final dir = await Directory.systemTemp.createTemp('ds_a_searchable_in_');
    try {
      final path = p.join(dir.path, 'input.pdf');
      await File(path).writeAsBytes(pdfBytes, flush: true);
      return await makeSearchableFile(
        file: LocalFileRef(path: path, displayName: 'input.pdf'),
        options: options,
      );
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<PageOcrTextLayer> _ocrPage({
    required PdfPage page,
    required int pageNumber,
    required String tempDir,
    required OcrOptions options,
    required OcrCancelToken token,
  }) async {
    final pgmPath = p.join(tempDir, 'page_$pageNumber.pgm');
    final pngPath = p.join(tempDir, 'page_$pageNumber.png');
    final raster = await renderPdfPageForOcr(
      page,
      dpi: options.dpi,
      path: pgmPath,
      enhance: options.denoise,
    );
    token.throwIfCancelled();
    // Android BitmapFactory cannot decode PGM — write a real PNG for Tesseract.
    await _pgmToPng(raster.path, pngPath, raster.width, raster.height);
    try {
      await File(raster.path).delete();
    } catch (_) {}
    token.throwIfCancelled();
    final hocr = await _ocr.recognizeHocrFile(
      pngPath,
      options: options.copyWith(dpi: raster.dpi),
    );
    token.throwIfCancelled();
    try {
      await File(pngPath).delete();
    } catch (_) {}

    final words = parseHocrWords(hocr);
    if (words.isNotEmpty) {
      return PageOcrTextLayer(
        page1Based: pageNumber,
        words: words,
        imageWidthPx: raster.width,
        imageHeightPx: raster.height,
      );
    }
    final plain = hocrPlainText(hocr);
    final lines = plain.isEmpty
        ? const <String>[]
        : plain
              .split(RegExp(r'\n+'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
    return PageOcrTextLayer(
      page1Based: pageNumber,
      words: const [],
      fallbackLines: lines,
      imageWidthPx: raster.width,
      imageHeightPx: raster.height,
    );
  }

  /// Converts an 8-bit PGM (from [renderPdfPageForOcr]) to PNG for Android OCR.
  static Future<void> _pgmToPng(
    String pgmPath,
    String pngPath,
    int width,
    int height,
  ) async {
    await Isolate.run(() {
      final raw = File(pgmPath).readAsBytesSync();
      // Skip "P5\nW H\n255\n" header.
      var i = 0;
      var newlines = 0;
      while (i < raw.length && newlines < 3) {
        if (raw[i] == 0x0A) newlines++;
        i++;
      }
      final gray = raw.sublist(i);
      final image = img.Image(width: width, height: height, numChannels: 1);
      final n = math.min(gray.length, width * height);
      for (var p = 0; p < n; p++) {
        image.setPixelRgb(p % width, p ~/ width, gray[p], gray[p], gray[p]);
      }
      File(pngPath).writeAsBytesSync(img.encodePng(image, level: 1));
    });
  }

  Future<bool> _pageHasText(PdfPage page) async {
    try {
      final text = await page.loadText();
      final chars = text?.fullText.replaceAll(RegExp(r'\s'), '').length ?? 0;
      return chars >= existingTextMinChars;
    } catch (_) {
      return false;
    }
  }
}
