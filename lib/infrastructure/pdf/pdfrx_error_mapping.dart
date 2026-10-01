import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:pdfrx/pdfrx.dart';

/// Maps pdfrx/PDFium failures to [DocumentStudioError] for user-facing flows
/// ([DS-EDGE-009] corrupted vs invalid PDF).
DocumentStudioError documentStudioErrorFromPdfrxOpen(
  Object error, {
  String? password,
}) {
  if (error is DocumentStudioError) {
    return error;
  }
  if (error is PdfPasswordException) {
    return DocumentStudioError(
      code: DocumentStudioErrorCode.passwordRequired,
      message: error.toString(),
      cause: error,
      recoveryHint: 'Enter the document password to continue.',
    );
  }
  if (error is PdfException) {
    final code = _pdfExceptionCode(error);
    return DocumentStudioError(
      code: code,
      message: error.toString(),
      cause: error,
      recoveryHint: code == DocumentStudioErrorCode.corruptedPdf
          ? 'Try opening a backup copy or re-downloading the file.'
          : null,
    );
  }
  return DocumentStudioError(
    code: DocumentStudioErrorCode.renderFailed,
    message: error.toString(),
    cause: error,
    recoveryHint: password != null
        ? 'Check the password or try opening the file without protection.'
        : null,
  );
}

DocumentStudioErrorCode _pdfExceptionCode(PdfException error) {
  final text = error.toString().toLowerCase();
  if (text.contains('corrupt') ||
      text.contains('damaged') ||
      text.contains('xref') ||
      text.contains('unexpected end') ||
      text.contains('invalid xref') ||
      text.contains('format error')) {
    return DocumentStudioErrorCode.corruptedPdf;
  }
  if (text.contains('not a pdf') ||
      text.contains('not pdf') ||
      text.contains('invalid pdf') ||
      text.contains('pdf format')) {
    return DocumentStudioErrorCode.invalidPdf;
  }
  return DocumentStudioErrorCode.invalidPdf;
}
