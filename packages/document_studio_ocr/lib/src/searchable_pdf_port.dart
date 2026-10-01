import 'dart:typed_data';

import 'ocr_blocked_exception.dart';
import 'ocr_options.dart';

/// Scanned PDF → searchable PDF (sandwich PDF). Inventory status: `[B]` until Tesseract FFI.
abstract class SearchablePdfPort {
  /// Returns PDF bytes with an invisible text layer over the original scan.
  Future<Uint8List> createSearchablePdf(
    Uint8List pdfBytes, {
    OcrOptions options = const OcrOptions(),
  });
}

/// Stub implementation; always fails with [OcrEngineBlockedException].
class BlockedSearchablePdfPort implements SearchablePdfPort {
  const BlockedSearchablePdfPort({this.reason = blockedReason});

  static const String blockedReason =
      '[B] Searchable PDF requires Tesseract FFI + PDF merge (ADR-004).';

  /// User-facing explanation (defaults to [blockedReason]).
  final String reason;

  @override
  Future<Uint8List> createSearchablePdf(
    Uint8List pdfBytes, {
    OcrOptions options = const OcrOptions(),
  }) {
    throw OcrEngineBlockedException(reason);
  }
}
