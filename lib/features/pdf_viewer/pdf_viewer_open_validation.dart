import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/pdf/pdf_open_limits.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/infrastructure/pdf/pdf_render_port.dart';

/// Result of [validatePdfViewerDocumentOpen] ([DS-READ-001-E] / [DS-READ-015]).
class PdfViewerOpenValidationResult {
  const PdfViewerOpenValidationResult({
    required this.success,
    this.password,
    this.error,
  });

  final bool success;
  final String? password;
  final DocumentStudioError? error;
}

/// Validates that [file] can open, prompting for a password when required.
Future<PdfViewerOpenValidationResult> validatePdfViewerDocumentOpen({
  required PdfRenderPort pdf,
  required LocalFileRef file,
  String? password,
  required Future<String?> Function() promptPassword,
  int maxOpenBytes = kPdfMaxOpenFileBytes,
}) async {
  final tooLarge = pdfOpenLimitErrorForFile(file, maxBytes: maxOpenBytes);
  if (tooLarge != null) {
    return PdfViewerOpenValidationResult(success: false, error: tooLarge);
  }
  var resolved = password;
  while (true) {
    try {
      await pdf.validateOpenable(file, password: resolved);
      return PdfViewerOpenValidationResult(success: true, password: resolved);
    } on DocumentStudioError catch (e) {
      if (e.code == DocumentStudioErrorCode.passwordRequired) {
        final entered = await promptPassword();
        if (entered == null || entered.isEmpty) {
          return PdfViewerOpenValidationResult(success: false, error: e);
        }
        resolved = entered;
        continue;
      }
      return PdfViewerOpenValidationResult(success: false, error: e);
    }
  }
}
