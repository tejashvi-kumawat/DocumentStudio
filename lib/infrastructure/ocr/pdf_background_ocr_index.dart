import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:document_studio/core/desktop/desktop_engine_resolver.dart';
import 'package:document_studio/core/pdf/pdf_document_cache.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/infrastructure/ocr/ocr_engine_environment.dart';
import 'package:document_studio_ocr/document_studio_ocr.dart';
import 'package:path/path.dart' as p;

/// In-memory OCR word index for Find on image-only pages (no file rewrite).
class PdfBackgroundOcrHit {
  const PdfBackgroundOcrHit({
    required this.pageIndex1Based,
    required this.text,
  });

  final int pageIndex1Based;
  final String text;
}

/// Background OCR of image-only pages so Find can jump to them.
///
/// Pages are recognized in parallel; results are cached on disk per file
/// content hash + language, so reopening a scanned file is instant.
class PdfBackgroundOcrIndex {
  PdfBackgroundOcrIndex({DesktopEngineResolver? resolver, this._ocr})
    : _resolver = resolver ?? desktopEngineResolver;

  static const _ocrDpi = 200;
  static const _cacheVersion = 2;

  final DesktopEngineResolver _resolver;
  final OcrPort? _ocr;
  final Map<int, String> _pageText = {};
  bool _running = false;
  bool _cancelled = false;

  bool get isRunning => _running;
  bool get hasAnyText => _pageText.isNotEmpty;

  OcrCancelToken? _token;

  void cancel() {
    _cancelled = true;
    _token?.cancel();
  }

  void clear() {
    _cancelled = true;
    _token?.cancel();
    _pageText.clear();
    _running = false;
  }

  /// Searches indexed OCR text (case-insensitive substring).
  PdfBackgroundOcrHit? find(String query) {
    final hits = findAll(query);
    return hits.isEmpty ? null : hits.first;
  }

  /// All pages whose indexed text contains [query] (case-insensitive,
  /// whitespace-insensitive so line breaks inside a phrase still match).
  List<PdfBackgroundOcrHit> findAll(String query) {
    final needle = _normalize(query);
    if (needle.isEmpty) return const [];
    final out = <PdfBackgroundOcrHit>[];
    final pages = _pageText.keys.toList()..sort();
    for (final page1 in pages) {
      final text = _pageText[page1]!;
      if (_normalize(text).contains(needle)) {
        out.add(PdfBackgroundOcrHit(pageIndex1Based: page1, text: text));
      }
    }
    return out;
  }

  static String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  /// 1-based page numbers that match [query].
  List<int> findAllPageNumbers(String query) => [
    for (final hit in findAll(query)) hit.pageIndex1Based,
  ];

  String? textForPage(int pageIndex1Based) => _pageText[pageIndex1Based];

  /// OCR pages that have little/no text layer. Does not block; call unawaited.
  Future<void> indexFile({
    required LocalFileRef file,
    String? password,
    void Function(String status)? onStatus,
    void Function()? onDone,
    int minTextChars = 12,
  }) async {
    if (_running) return;
    _running = true;
    _cancelled = false;
    _pageText.clear();
    final token = OcrCancelToken();
    _token = token;
    Directory? tempDir;
    try {
      // Let the viewer render the first pages before competing for PDFium.
      await Future<void>.delayed(const Duration(seconds: 3));
      if (_cancelled) return;
      final env = await loadOcrEngineEnvironment(resolver: _resolver);
      final language = _indexLanguage(env);
      // Quiet: bundled engine missing — do not show install/rebuild copy.
      if (_ocr == null &&
          (language == null || env.readinessError(language) != null)) {
        return;
      }
      final options = OcrOptions(language: language ?? 'eng', dpi: _ocrDpi);
      final cacheFile = await _cacheFileFor(file, options.language);
      final cached = await _readCache(cacheFile);

      // Only pages already measured for painting. Never walk pageCount on a
      // 50k-page file (and never delay on unloaded slots).
      final lease = await PdfDocumentCache.instance.acquire(
        file.path,
        password: password,
      );
      final doc = lease.document;
      try {
        final toOcr = <int>[];
        for (var i = 0; i < doc.pages.length; i++) {
          if (_cancelled) return;
          if (!doc.pages[i].isLoaded) continue;
          final page1 = i + 1;
          try {
            final loaded = await doc.pages[i].loadText();
            final existing = loaded?.fullText.trim() ?? '';
            if (existing.length >= minTextChars) {
              _pageText[page1] = existing;
              continue;
            }
          } catch (_) {}
          final hit = cached?[page1];
          if (hit != null) {
            if (hit.isNotEmpty) _pageText[page1] = hit;
          } else {
            toOcr.add(page1);
          }
        }
        if (toOcr.isEmpty) return;

        onStatus?.call('Reading text in images…');
        tempDir = await Directory.systemTemp.createTemp('ds_bg_ocr_');
        final tessdata = env.tessdataDirFor(
          options.languageCodes,
          withOsd: env.useOsd(options),
        );
        final recognized = <int, String>{...?cached};
        final queue = List<int>.of(toOcr);
        final workers = toOcr.length == 1 ? 1 : ocrParallelism();

        Future<void> worker(int id) async {
          while (queue.isNotEmpty && !_cancelled) {
            final page1 = queue.removeAt(0);
            final raster = await renderPdfPageForOcr(
              doc.pages[page1 - 1],
              dpi: _ocrDpi,
              path: p.join(tempDir!.path, 'page_$id.pgm'),
            );
            if (_cancelled) return;
            final String text;
            if (_ocr != null) {
              final bytes = await File(raster.path).readAsBytes();
              text = (await _ocr.recognizeText(
                bytes,
                options: options,
              )).text.trim();
            } else {
              text = (await runTesseractProcess(
                executable: env.tesseractPath!,
                args: [
                  raster.path,
                  'stdout',
                  '-l',
                  options.language,
                  '--dpi',
                  '${raster.dpi}',
                  ...env.layoutArgs(options),
                ],
                tessdataDir: tessdata,
                cancelToken: token,
                singleThread: workers > 1,
              )).trim();
            }
            recognized[page1] = text;
            if (text.isNotEmpty) _pageText[page1] = text;
          }
        }

        try {
          await Future.wait([for (var i = 0; i < workers; i++) worker(i)]);
        } on OcrCancelledException {
          return;
        }
        if (!_cancelled) await _writeCache(cacheFile, recognized);
      } finally {
        lease.release();
      }
    } catch (_) {
      // Quiet failure — Find still works on the native text layer.
    } finally {
      if (identical(_token, token)) _token = null;
      try {
        await tempDir?.delete(recursive: true);
      } catch (_) {}
      _running = false;
      onStatus?.call('');
      onDone?.call();
    }
  }

  /// Preferred OCR language when installed, otherwise English or the first
  /// installed language.
  String? _indexLanguage(OcrEngineEnvironment env) {
    final preferred = ocrPreferredLanguage;
    if (env
        .missingLanguages(OcrOptions(language: preferred).languageCodes)
        .isEmpty) {
      return preferred;
    }
    final installed = env.installedLanguages;
    if (installed.contains('eng')) return 'eng';
    return installed.isEmpty ? null : installed.first;
  }

  static Future<File?> _cacheFileFor(LocalFileRef file, String language) async {
    try {
      final path = file.path;
      final digest = await Isolate.run(() async {
        final bytes = await File(path).readAsBytes();
        return sha1.convert(bytes).toString();
      });
      return File(p.join(ocrCacheDir(), 'index', '$digest-$language.json'));
    } catch (_) {
      return null;
    }
  }

  static Future<Map<int, String>?> _readCache(File? file) async {
    if (file == null || !await file.exists()) return null;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (json['v'] != _cacheVersion) return null;
      final pages = json['pages'] as Map<String, dynamic>;
      return {
        for (final e in pages.entries) int.parse(e.key): e.value as String,
      };
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(File? file, Map<int, String> pages) async {
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'v': _cacheVersion,
          'pages': {for (final e in pages.entries) '${e.key}': e.value},
        }),
      );
    } catch (_) {}
  }
}
