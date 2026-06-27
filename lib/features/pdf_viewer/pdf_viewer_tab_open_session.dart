import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/pdf/pdf_document_cache.dart';

/// Per-tab open validation state for [PdfViewerScreen] (password + errors).
class PdfViewerTabOpenSession {
  bool validating = false;
  bool validated = false;
  DocumentStudioError? error;
  String? resolvedPassword;

  /// Keeps the validated document in [PdfDocumentCache] until the viewer
  /// acquires its own lease, so open does not parse the file twice.
  PdfDocumentLease? warmLease;

  void releaseWarmLease() {
    warmLease?.release();
    warmLease = null;
  }
}
