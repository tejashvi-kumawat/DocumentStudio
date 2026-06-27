import 'dart:io';

import 'package:document_studio/infrastructure/ocr/ocr_port.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// On-device [OcrPort] for Android (and iOS) via Tesseract4Android /
/// SwiftyTesseract through [flutter_tesseract_ocr].
///
/// Requires bundled `assets/tessdata/eng.traineddata` plus
/// `assets/tessdata_config.json` (see package README). Extra languages use the
/// same free GitHub tessdata_fast download as desktop ([downloadOcrLanguageData]).
class AndroidTesseractOcrPort implements OcrPort {
  const AndroidTesseractOcrPort();

  static Future<void>? _languageSync;

  @override
  Future<OcrTextResult> recognizeText(
    Uint8List imageBytes, {
    OcrOptions options = const OcrOptions(),
  }) async {
    if (kIsWeb) {
      throw OcrEngineBlockedException(
        'On-device OCR is not available in the web build.',
      );
    }
    await _ensureDownloadedLanguagesVisible();
    final dir = await Directory.systemTemp.createTemp('ds_aocr_');
    try {
      final input = await _writeTempImage(dir, imageBytes);
      final text = await FlutterTesseractOcr.extractText(
        input.path,
        language: options.language,
        args: _tessArgs(options),
      );
      return OcrTextResult(text: text.trimRight(), language: options.language);
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// hOCR (HTML with word boxes) for searchable-PDF text layers.
  Future<String> recognizeHocr(
    Uint8List imageBytes, {
    OcrOptions options = const OcrOptions(),
  }) async {
    if (kIsWeb) {
      throw OcrEngineBlockedException(
        'On-device OCR is not available in the web build.',
      );
    }
    await _ensureDownloadedLanguagesVisible();
    final dir = await Directory.systemTemp.createTemp('ds_aocr_h_');
    try {
      final input = await _writeTempImage(dir, imageBytes);
      return await FlutterTesseractOcr.extractHocr(
        input.path,
        language: options.language,
        args: _tessArgs(options),
      );
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// OCR an image already on disk (avoids a second write for searchable PDF).
  Future<String> recognizeHocrFile(
    String imagePath, {
    OcrOptions options = const OcrOptions(),
  }) async {
    await _ensureDownloadedLanguagesVisible();
    return FlutterTesseractOcr.extractHocr(
      imagePath,
      language: options.language,
      args: _tessArgs(options),
    );
  }

  static Map<String, String> _tessArgs(OcrOptions options) => {
        'preserve_interword_spaces': '1',
        if (options.dpi > 0) 'user_defined_dpi': '${options.dpi}',
      };

  static Future<File> _writeTempImage(Directory dir, Uint8List imageBytes) async {
    final suffix = _suffixFor(imageBytes);
    final input = File(p.join(dir.path, 'input.$suffix'));
    await input.writeAsBytes(imageBytes, flush: true);
    return input;
  }

  /// Copies user-downloaded traineddata into the plugin's expected folder
  /// under application documents (`tessdata/`), so "Add languages" works
  /// the same way as on desktop.
  static Future<void> _ensureDownloadedLanguagesVisible() {
    return _languageSync ??= () async {
      try {
        final docs = await getApplicationDocumentsDirectory();
        final pluginTess = Directory(p.join(docs.path, 'tessdata'));
        await pluginTess.create(recursive: true);
        // Bundled eng is installed by the plugin from assets; also link any
        // packs the user downloaded into app support `ocr-languages/`.
        final support = await getApplicationSupportDirectory();
        final downloaded = Directory(p.join(support.path, 'ocr-languages'));
        if (!await downloaded.exists()) return;
        await for (final entity in downloaded.list()) {
          if (entity is! File) continue;
          final name = p.basename(entity.path);
          if (!name.endsWith('.traineddata')) continue;
          final dest = File(p.join(pluginTess.path, name));
          if (await dest.exists()) continue;
          try {
            await entity.copy(dest.path);
          } catch (_) {}
        }
      } catch (_) {
        // Recognition may still work with bundled eng only.
      }
    }();
  }

  static void invalidateLanguageSync() => _languageSync = null;

  static String _suffixFor(Uint8List b) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'jpg';
    }
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47) {
      return 'png';
    }
    if (b.length >= 2 && b[0] == 0x42 && b[1] == 0x4D) return 'bmp';
    if (b.length >= 12 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42) {
      return 'webp';
    }
    return 'png';
  }
}
