import 'dart:typed_data';

import 'ocr_options.dart';
import 'ocr_text_result.dart';

/// Image → text OCR. Canonical engine: Tesseract 5 behind this port.
abstract class OcrPort {
  /// Runs OCR on encoded image bytes (PNG, JPEG, etc.).
  Future<OcrTextResult> recognizeText(
    Uint8List imageBytes, {
    OcrOptions options = const OcrOptions(),
  });
}
