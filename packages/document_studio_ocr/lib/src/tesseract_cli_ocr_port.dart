import 'dart:io';
import 'dart:typed_data';

import 'ocr_blocked_exception.dart';
import 'ocr_options.dart';
import 'ocr_port.dart';
import 'ocr_text_result.dart';
import 'tesseract_cli_availability.dart';

/// Desktop OCR via the bundled (or PATH) `tesseract` CLI.
///
/// Mobile/web builds still use [BlockedOcrPort].
class TesseractCliOcrPort implements OcrPort {
  const TesseractCliOcrPort({this.executable, this.tessdataPrefix});

  /// Absolute path or `tesseract`; null resolves via bundled/PATH lookup.
  final String? executable;

  /// Directory containing `eng.traineddata` (sets TESSDATA_PREFIX / --tessdata-dir).
  final String? tessdataPrefix;

  @override
  Future<OcrTextResult> recognizeText(
    Uint8List imageBytes, {
    OcrOptions options = const OcrOptions(),
  }) async {
    final exe = executable ?? await resolvedTesseractExecutable();
    // Trust an explicit absolute path from DesktopEngineResolver; only probe
    // availability when falling back to name lookup.
    if (executable == null && !await isTesseractCliAvailable()) {
      final searched = tesseractBundledCandidatePaths().join(', ');
      throw OcrEngineBlockedException(
        'Missing OCR binary: tesseract (searched: $searched).',
      );
    }
    if (executable != null && !File(executable!).existsSync()) {
      throw OcrEngineBlockedException(
        'Missing OCR binary: tesseract at $executable.',
      );
    }

    final suffix = _suffixForImageBytes(imageBytes);
    final dir = await Directory.systemTemp.createTemp('ds_ocr_');
    final imageFile = File('${dir.path}/input.$suffix');
    try {
      await imageFile.writeAsBytes(imageBytes, flush: true);
      final env = Map<String, String>.from(Platform.environment);
      final tessdata = tessdataPrefix ?? resolvedTessdataPrefix();
      final args = <String>[
        imageFile.path,
        'stdout',
        '-l',
        options.language,
        '--dpi',
        '${options.dpi}',
      ];
      if (tessdata != null) {
        // This tesseract build treats TESSDATA_PREFIX as the tessdata directory
        // itself (where eng.traineddata lives), not the parent of tessdata/.
        env['TESSDATA_PREFIX'] = tessdata;
        args.addAll(['--tessdata-dir', tessdata]);
      }
      final result = await Process.run(
        exe,
        args,
        environment: env,
      );
      if (result.exitCode != 0) {
        final err = result.stderr.toString().trim();
        throw StateError(
          err.isEmpty ? 'Tesseract failed (exit ${result.exitCode}).' : err,
        );
      }
      final text = result.stdout.toString().trimRight();
      return OcrTextResult(text: text, language: options.language);
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }
}

String _suffixForImageBytes(Uint8List b) {
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
