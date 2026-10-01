import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/infrastructure/ocr/ocr_port.dart';

DocumentStudioError mapOcrException(Object error) {
  if (error is DocumentStudioError) return error;
  if (error is OcrEngineBlockedException) {
    return DocumentStudioError(
      code: DocumentStudioErrorCode.featureUnavailable,
      message: error.message,
      cause: error,
      recoveryHint:
          'Desktop OCR uses the bundled Tesseract CLI under engines/tesseract '
          '(with engines/tessdata). Rebuild so the Linux hook can copy it, or '
          'install tesseract-ocr + eng.traineddata.',
    );
  }
  return DocumentStudioError(
    code: DocumentStudioErrorCode.ocrFailed,
    message: error.toString(),
    cause: error,
  );
}

bool isOcrEngineBlocked(OcrPort port) => port is BlockedOcrPort;

bool isSearchablePdfEngineBlocked(SearchablePdfPort port) =>
    port is BlockedSearchablePdfPort;
