import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:document_studio/core/desktop/desktop_engine_resolver.dart';
import 'package:document_studio/infrastructure/ocr/ocr_engine_environment.dart';
import 'package:document_studio/infrastructure/ocr/ocr_port.dart';
import 'package:document_studio/infrastructure/ocr/ocr_preprocess.dart';
import 'package:path/path.dart' as p;

/// Desktop [OcrPort] that resolves the bundled Tesseract CLI, applies
/// deskew/denoise preprocess on a background isolate, then runs recognition
/// against the tessdata folder that holds the requested language(s).
class DesktopTesseractOcrPort implements OcrPort {
  DesktopTesseractOcrPort({DesktopEngineResolver? resolver})
      : _resolver = resolver ?? desktopEngineResolver;

  final DesktopEngineResolver _resolver;

  @override
  Future<OcrTextResult> recognizeText(
    Uint8List imageBytes, {
    OcrOptions options = const OcrOptions(),
    OcrCancelToken? cancelToken,
  }) async {
    final env = await loadOcrEngineEnvironment(resolver: _resolver);
    final problem = env.readinessError(options.language);
    if (problem != null) throw OcrEngineBlockedException(problem);

    final prepared = (options.deskew || options.denoise)
        ? await Isolate.run(
            () => preprocessOcrImageBytes(imageBytes, options: options),
          )
        : imageBytes;
    cancelToken?.throwIfCancelled();

    final dir = await Directory.systemTemp.createTemp('ds_ocr_');
    try {
      final input = p.join(dir.path, 'input.${_suffixFor(prepared)}');
      await File(input).writeAsBytes(prepared, flush: true);
      final text = await runTesseractProcess(
        executable: env.tesseractPath!,
        args: [input, 'stdout', '-l', options.language, '--dpi', '${options.dpi}'],
        tessdataDir: env.tessdataDirFor(options.languageCodes),
        cancelToken: cancelToken,
      );
      return OcrTextResult(text: text.trimRight(), language: options.language);
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  static String _suffixFor(Uint8List b) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'jpg';
    }
    if (b.length >= 4 && b[0] == 0x49 && b[1] == 0x49 && b[2] == 0x2A) {
      return 'tif';
    }
    if (b.length >= 4 && b[0] == 0x4D && b[1] == 0x4D && b[3] == 0x2A) {
      return 'tif';
    }
    if (b.length >= 12 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42) {
      return 'webp';
    }
    if (b.length >= 2 && b[0] == 0x42 && b[1] == 0x4D) return 'bmp';
    if (b.length >= 2 && b[0] == 0x50 && b[1] == 0x35) return 'pgm';
    return 'png';
  }
}
