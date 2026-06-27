import 'dart:typed_data';

import 'ocr_blocked_exception.dart';
import 'ocr_options.dart';
import 'ocr_port.dart';
import 'ocr_text_result.dart';

/// Placeholder until `libtesseract` FFI is integrated. Inventory status: `[B]`.
class BlockedOcrPort implements OcrPort {
  const BlockedOcrPort();

  static const String blockedReason =
      '[B] OCR requires Tesseract FFI integration (ADR-004).';

  @override
  Future<OcrTextResult> recognizeText(
    Uint8List imageBytes, {
    OcrOptions options = const OcrOptions(),
  }) {
    throw OcrEngineBlockedException(blockedReason);
  }
}
