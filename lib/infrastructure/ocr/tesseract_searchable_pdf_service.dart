import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:document_studio/core/desktop/desktop_engine_resolver.dart';
import 'package:document_studio/core/pdf/pdf_document_cache.dart';
import 'package:document_studio/core/storage/disk_lru_cache.dart';
import 'package:document_studio/core/storage/storage_cache_manager.dart';
import 'package:document_studio/core/storage/storage_paths.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/infrastructure/ocr/ocr_engine_environment.dart';
import 'package:document_studio_ocr/document_studio_ocr.dart';
import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

/// Describes which OCR binaries/data are missing for searchable PDF.
class SearchablePdfEngineStatus {
  const SearchablePdfEngineStatus({
    required this.tesseractPath,
    required this.tessdataPrefix,
    required this.missingMessage,
    this.installedLanguages = const [],
  });

  final String? tesseractPath;
  final String? tessdataPrefix;

  /// Null when ready; otherwise exact missing binary / data message for UI.
  final String? missingMessage;

  /// traineddata ids found on this machine (e.g. `eng`, `deu`).
  final List<String> installedLanguages;

  bool get isReady => missingMessage == null;
}

/// Live progress for a searchable-PDF job.
class SearchablePdfProgress {
  const SearchablePdfProgress({
    required this.fraction,
    required this.message,
    required this.pagesDone,
    required this.pagesTotal,
  });

  final double fraction;
  final String message;
  final int pagesDone;
  final int pagesTotal;
}

/// Outcome of a searchable-PDF job.
class SearchablePdfResult {
  const SearchablePdfResult({
    required this.bytes,
    required this.recognizedPages,
    required this.skippedPages,
    required this.elapsed,
    this.rotatedPages = const {},
  });

  final Uint8List bytes;

  /// 1-based pages that received a new text layer.
  final List<int> recognizedPages;

  /// 1-based pages skipped because they already contained text.
  final List<int> skippedPages;

  final Duration elapsed;

  /// 1-based page → clockwise degrees applied to turn sideways or
  /// upside-down scans upright (auto-rotate).
  final Map<int, int> rotatedPages;

  bool get unchanged => recognizedPages.isEmpty;
}

/// Builds a searchable PDF: each page is rasterized, OCR'd by Tesseract into a
/// text-only PDF page (invisible glyphs, Unicode, per-word width scaling), then
/// overlaid on the original page with qpdf.
///
/// Page images are rendered in display orientation at `round(pt * dpi / 72)`
/// pixels and Tesseract is told the same DPI, so its page has the original
/// point size. qpdf's overlay counter-rotates for `/Rotate` and maps onto the
/// visible page box, keeping words aligned with the scan. Original page
/// content is never modified.
class TesseractSearchablePdfService implements SearchablePdfPort {
  TesseractSearchablePdfService({
    DesktopEngineResolver? resolver,
    QpdfCliRunner? qpdf,
  })  : _resolver = resolver ?? desktopEngineResolver,
        _qpdf = qpdf ?? QpdfCliRunner();

  final DesktopEngineResolver _resolver;
  final QpdfCliRunner _qpdf;

  /// Minimum extractable characters for a page to count as "has text".
  static const int existingTextMinChars = 16;

  /// Probe tesseract, qpdf, and traineddata for [language].
  Future<SearchablePdfEngineStatus> probeEngine({
    String language = 'eng',
    bool refresh = false,
  }) async {
    final env = await loadOcrEngineEnvironment(
      resolver: _resolver,
      refresh: refresh,
    );
    var missing = env.readinessError(language);
    if (missing == null && !await isQpdfCliAvailable()) {
      missing = 'PDF engine not found: qpdf is missing from engines/ and '
          'PATH. Run scripts/bundle_linux_engines.sh or install qpdf.';
    }
    final codes = [
      for (final part in language.split('+'))
        if (part.trim().isNotEmpty) part.trim(),
    ];
    return SearchablePdfEngineStatus(
      tesseractPath: env.tesseractPath,
      tessdataPrefix: env.tessdataDirFor(codes),
      missingMessage: missing,
      installedLanguages: env.installedLanguages,
    );
  }

  /// Creates searchable PDF bytes for [file], optionally limiting pages.
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

  /// Full searchable-PDF pipeline with per-page progress and cancellation.
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
    final env = await loadOcrEngineEnvironment(resolver: _resolver);
    final tessExe = status.tesseractPath!;
    final tessdata = env.tessdataDirFor(
          options.languageCodes,
          withOsd: env.useOsd(options),
        ) ??
        status.tessdataPrefix;
    final layoutArgs = env.layoutArgs(options);
    token.throwIfCancelled();

    report(0.005, 'Checking for earlier results…', 0, 0);
    final cacheKey = await _resultCacheKey(file, options, pages1Based);
    if (cacheKey != null) {
      final cached = await _readCachedResult(cacheKey, stopwatch);
      if (cached != null) {
        report(1, 'Done (from cache)', cached.recognizedPages.length,
            cached.recognizedPages.length);
        return cached;
      }
    }

    final tempDir = await Directory.systemTemp.createTemp('ds_searchable_');
    try {
      report(0.01, 'Opening PDF…', 0, 0);
      // Do not loadAllPages: the open viewer shares this cache, and only
      // the requested pages are read below.
      final lease = await PdfDocumentCache.instance.acquire(
        file.path,
        password: password,
      );
      final doc = lease.document;
      final List<int> recognized;
      final List<int> skipped;
      final rotations = <int, int>{};
      try {
        final pageCount = doc.pages.length;
        final requested = (pages1Based == null || pages1Based.isEmpty)
            ? [for (var i = 1; i <= pageCount; i++) i]
            : (pages1Based.where((n) => n >= 1 && n <= pageCount).toList()
              ..sort());
        if (requested.isEmpty) {
          throw OcrEngineBlockedException('No valid pages to recognize.');
        }

        skipped = <int>[];
        final toOcr = <int>[];
        if (options.skipPagesWithText) {
          report(0.02, 'Checking pages for existing text…', 0, requested.length);
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

        recognized = <int>[];
        final total = toOcr.length;
        if (total > 0) {
          var done = 0;
          report(0.04, 'Recognizing text · 0 of $total pages', 0, total);
          final queue = List<int>.of(toOcr);
          final parallel = total == 1 ? 1 : ocrParallelism();

          Future<void> worker() async {
            while (queue.isNotEmpty) {
              token.throwIfCancelled();
              final n = queue.removeAt(0);
              final turn = await _ocrPageToTextPdf(
                page: doc.pages[n - 1],
                pageNumber: n,
                tempDir: tempDir.path,
                options: options,
                executable: tessExe,
                tessdata: tessdata,
                layoutArgs: layoutArgs,
                token: token,
                singleThread: parallel > 1,
              );
              if (turn != 0) rotations[n] = turn;
              done++;
              report(
                0.04 + 0.88 * done / total,
                'Recognizing text · $done of $total pages',
                done,
                total,
              );
            }
          }

          try {
            await Future.wait(
              [for (var i = 0; i < parallel; i++) worker()],
              eagerError: true,
            );
          } catch (_) {
            token.cancel();
            rethrow;
          }
          recognized.addAll(toOcr);
        }
      } finally {
        lease.release();
      }

      if (recognized.isEmpty) {
        report(1, 'All pages already contain text', 0, 0);
        return SearchablePdfResult(
          bytes: await File(file.path).readAsBytes(),
          recognizedPages: const [],
          skippedPages: skipped,
          elapsed: stopwatch.elapsed,
        );
      }

      token.throwIfCancelled();
      report(0.94, 'Adding invisible text layer…', recognized.length,
          recognized.length);
      final layerPath = p.join(tempDir.path, 'text_layer.pdf');
      final pagePdfs = [for (final n in recognized) _pagePdfPath(tempDir.path, n)];
      if (pagePdfs.length == 1) {
        await File(pagePdfs.single).copy(layerPath);
      } else {
        await _qpdf.mergeFiles(inputPaths: pagePdfs, outputPath: layerPath);
      }
      token.throwIfCancelled();

      final outPath = p.join(tempDir.path, 'searchable.pdf');
      await _qpdf.runRaw([
        if (password != null && password.isNotEmpty) '--password=$password',
        file.path,
        '--overlay',
        layerPath,
        '--to=${recognized.join(',')}',
        '--from=1-${recognized.length}',
        '--',
        outPath,
      ]);
      var finalPath = outPath;
      if (rotations.isNotEmpty) {
        // Separate pass: rotating before the overlay would change how qpdf
        // maps the text layer onto the page.
        report(0.97, 'Straightening rotated pages…', recognized.length,
            recognized.length);
        final byAngle = <int, List<int>>{};
        for (final e in rotations.entries) {
          (byAngle[e.value] ??= []).add(e.key);
        }
        finalPath = p.join(tempDir.path, 'searchable_upright.pdf');
        await _qpdf.runRaw([
          if (password != null && password.isNotEmpty) '--password=$password',
          outPath,
          for (final e in byAngle.entries)
            '--rotate=+${e.key}:${(e.value..sort()).join(',')}',
          '--',
          finalPath,
        ]);
      }
      report(1, 'Done', recognized.length, recognized.length);
      final result = SearchablePdfResult(
        bytes: await File(finalPath).readAsBytes(),
        recognizedPages: recognized,
        skippedPages: skipped,
        elapsed: stopwatch.elapsed,
        rotatedPages: Map.unmodifiable(rotations),
      );
      if (cacheKey != null) unawaited(_writeCachedResult(cacheKey, result));
      return result;
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
    final dir = await Directory.systemTemp.createTemp('ds_searchable_in_');
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

  static final DiskLruCache _resultPdfs = DiskLruCache(
    StorageArea.ocr,
    maxBytes: StorageCacheManager.limits[StorageArea.ocr]!,
    extension: 'pdf',
  );
  static final DiskLruCache _resultMeta = DiskLruCache(
    StorageArea.ocr,
    maxBytes: StorageCacheManager.limits[StorageArea.ocr]!,
    extension: 'json',
  );

  /// Content hash + every option that changes the output, so re-running the
  /// same job on the same bytes (even renamed / copied) is instant.
  static Future<String?> _resultCacheKey(
    LocalFileRef file,
    OcrOptions options,
    Set<int>? pages,
  ) async {
    try {
      final path = file.path;
      final digest = await Isolate.run(() async {
        final bytes = await File(path).readAsBytes();
        return sha1.convert(bytes).toString();
      });
      final pageSpec =
          pages == null || pages.isEmpty ? 'all' : (pages.toList()..sort()).join(',');
      return 'searchable-v1|$digest|${options.language}|${options.dpi}|'
          '${options.autoRotate}|${options.denoise}|'
          '${options.skipPagesWithText}|$pageSpec';
    } catch (_) {
      return null;
    }
  }

  static Future<SearchablePdfResult?> _readCachedResult(
    String key,
    Stopwatch stopwatch,
  ) async {
    final meta = await _resultMeta.read(key);
    if (meta == null) return null;
    try {
      final json = jsonDecode(utf8.decode(meta)) as Map<String, dynamic>;
      final recognized = (json['recognized'] as List).cast<int>();
      final skipped = (json['skipped'] as List).cast<int>();
      final rotated = {
        for (final e in (json['rotated'] as Map<String, dynamic>).entries)
          int.parse(e.key): e.value as int,
      };
      final bytes = await _resultPdfs.read(key);
      if (bytes == null) return null;
      return SearchablePdfResult(
        bytes: bytes,
        recognizedPages: recognized,
        skippedPages: skipped,
        elapsed: stopwatch.elapsed,
        rotatedPages: rotated,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCachedResult(
    String key,
    SearchablePdfResult result,
  ) async {
    await _resultPdfs.write(key, result.bytes);
    await _resultMeta.write(
      key,
      Uint8List.fromList(utf8.encode(jsonEncode({
        'recognized': result.recognizedPages,
        'skipped': result.skippedPages,
        'rotated': {
          for (final e in result.rotatedPages.entries) '${e.key}': e.value,
        },
      }))),
    );
  }

  static String _pagePdfPath(String dir, int page1) =>
      p.join(dir, 'page_${page1.toString().padLeft(5, '0')}.pdf');

  Future<bool> _pageHasText(PdfPage page) async {
    try {
      final text = await page.loadText();
      final chars = text?.fullText.replaceAll(RegExp(r'\s'), '').length ?? 0;
      return chars >= existingTextMinChars;
    } catch (_) {
      return false;
    }
  }

  /// Returns the clockwise rotation that would make the page upright.
  Future<int> _ocrPageToTextPdf({
    required PdfPage page,
    required int pageNumber,
    required String tempDir,
    required OcrOptions options,
    required String executable,
    required String? tessdata,
    required List<String> layoutArgs,
    required OcrCancelToken token,
    required bool singleThread,
  }) async {
    final imagePath = p.join(tempDir, 'page_$pageNumber.pgm');
    final raster = await renderPdfPageForOcr(
      page,
      dpi: options.dpi,
      path: imagePath,
      enhance: options.denoise,
    );
    token.throwIfCancelled();
    final outBase = p.withoutExtension(_pagePdfPath(tempDir, pageNumber));
    final detectOrientation = layoutArgs.isNotEmpty;
    try {
      await runTesseractProcess(
        executable: executable,
        args: [
          raster.path,
          outBase,
          '-l',
          options.language,
          '--dpi',
          '${raster.dpi}',
          ...layoutArgs,
          if (options.denoise) ...['-c', 'thresholding_method=2'],
          '-c',
          'tessedit_create_pdf=1',
          '-c',
          'textonly_pdf=1',
          '-c',
          'tessedit_create_txt=0',
          if (detectOrientation) ...['-c', 'tessedit_create_hocr=1'],
        ],
        tessdataDir: tessdata,
        cancelToken: token,
        singleThread: singleThread,
      );
    } finally {
      try {
        await File(imagePath).delete();
      } catch (_) {}
    }
    if (!File('$outBase.pdf').existsSync()) {
      throw OcrEngineBlockedException(
        'OCR engine did not produce a text layer for page $pageNumber.',
      );
    }
    if (!detectOrientation) return 0;
    final hocr = File('$outBase.hocr');
    try {
      return hocrPageOrientation(await hocr.readAsString());
    } catch (_) {
      return 0;
    } finally {
      try {
        await hocr.delete();
      } catch (_) {}
    }
  }
}

/// Clockwise rotation (0/90/180/270) that makes most text lines in a
/// Tesseract hOCR page upright, from each line's `textangle`, weighted by
/// line length. Returns 0 unless at least 3 lines were found and a clear
/// majority agrees.
///
/// A 90°/270° vote only counts when the line box is taller than wide: with
/// some script mixes (e.g. `eng+hin`) Tesseract reports `textangle 90` for
/// ordinary horizontal lines.
int hocrPageOrientation(String hocr) {
  final line = RegExp(
    "class=['\"]ocr_(?:line|header|caption|textfloat)['\"][^>]*"
    "title=['\"]([^'\"]*)['\"]",
  );
  final angle = RegExp(r'textangle (\d+)');
  final bbox = RegExp(r'bbox (\d+) (\d+) (\d+) (\d+)');
  final votes = <int, double>{};
  var total = 0.0;
  var lines = 0;
  for (final m in line.allMatches(hocr)) {
    final title = m.group(1)!;
    final box = bbox.firstMatch(title);
    if (box == null) continue;
    final w = int.parse(box.group(3)!) - int.parse(box.group(1)!);
    final h = int.parse(box.group(4)!) - int.parse(box.group(2)!);
    final a = int.tryParse(angle.firstMatch(title)?.group(1) ?? '0') ?? 0;
    var norm = ((a % 360) + 360) % 360;
    if (norm % 90 != 0) continue;
    final tall = h > w * 1.5;
    if ((norm == 90 || norm == 270) && !tall) norm = 0;
    final length = (tall ? h : w).toDouble();
    votes[norm] = (votes[norm] ?? 0) + length;
    total += length;
    lines++;
  }
  if (lines < 3 || total <= 0) return 0;
  final best = votes.entries.reduce((a, b) => a.value >= b.value ? a : b);
  return best.value >= total * 0.7 ? best.key : 0;
}
