import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/core/desktop/desktop_engine_resolver.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio_ocr/document_studio_ocr.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

/// Result of OCR find on a page (normalized match box top-left origin, 0–1).
class OcrPageSearchHit {
  const OcrPageSearchHit({
    required this.pageIndex1Based,
    required this.snippet,
  });

  final int pageIndex1Based;
  final String snippet;
}

/// When the text layer has no hits, OCR nearby pages with tesseract.
class PdfOcrPageSearcher {
  PdfOcrPageSearcher({DesktopEngineResolver? resolver, OcrPort? ocr})
      : _resolver = resolver ?? desktopEngineResolver,
        _ocr = ocr;

  final DesktopEngineResolver _resolver;
  final OcrPort? _ocr;

  Future<bool> isAvailable() async {
    final exe = await _resolver.resolveTesseract();
    return exe != null;
  }

  Future<String?> missingEngineMessage() async {
    if (await isAvailable()) return null;
    return 'OCR engine missing — rebuild so tesseract is bundled, or install '
        'tesseract-ocr and eng.traineddata.';
  }

  /// Searches [query] on [centerPage1] then neighbors within [radius].
  Future<OcrPageSearchHit?> findNearPage({
    required LocalFileRef file,
    required int centerPage1,
    required String query,
    String? password,
    int radius = 1,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;
    final available = await isAvailable();
    if (!available) return null;

    final doc = await PdfDocument.openFile(
      file.path,
      passwordProvider: password == null ? null : () async => password,
    );
    try {
      final total = doc.pages.length;
      final pages = <int>{
        for (var d = -radius; d <= radius; d++) centerPage1 + d,
      }.where((p) => p >= 1 && p <= total).toList()
        ..sort((a, b) {
          final da = (a - centerPage1).abs();
          final db = (b - centerPage1).abs();
          return da.compareTo(db);
        });

      final ocr = _ocr ??
          TesseractCliOcrPort(
            executable: await _resolver.resolveTesseract(),
          );
      final tessPrefix = _resolver.resolveTessdataPrefix();
      if (tessPrefix != null) {
        // Ensure child processes see tessdata.
        // ignore: avoid_print
      }

      for (final page1 in pages) {
        final page = doc.pages[page1 - 1];
        final pdfImage = await page.render(
          fullWidth: page.width * 2,
          fullHeight: page.height * 2,
        );
        if (pdfImage == null) continue;
        late final Uint8List png;
        try {
          final raster = img.Image.fromBytes(
            width: pdfImage.width,
            height: pdfImage.height,
            bytes: pdfImage.pixels.buffer,
            order: img.ChannelOrder.bgra,
          );
          png = Uint8List.fromList(img.encodePng(raster));
        } finally {
          pdfImage.dispose();
        }
        final result = await ocr.recognizeText(png);
        final lower = result.text.toLowerCase();
        final needle = trimmed.toLowerCase();
        if (lower.contains(needle)) {
          return OcrPageSearchHit(
            pageIndex1Based: page1,
            snippet: result.text.trim(),
          );
        }
      }
      return null;
    } finally {
      await doc.dispose();
    }
  }
}
