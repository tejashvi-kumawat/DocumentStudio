import 'package:document_studio/domain/models/local_file_ref.dart';

class PdfDocumentInfo {
  const PdfDocumentInfo({
    required this.pageCount,
    this.title,
    this.author,
    this.subject,
    this.keywords,
    this.creator,
    this.producer,
    this.encrypted,
  });

  final int pageCount;
  final String? title;
  final String? author;
  final String? subject;
  final String? keywords;
  final String? creator;
  final String? producer;
  final bool? encrypted;
}

/// Abstraction over PDFium/pdfrx. Features depend on this, not on pdfrx directly.
abstract class PdfRenderPort {
  Future<PdfDocumentInfo> loadInfo(LocalFileRef file, {String? password});

  Future<bool> validateOpenable(LocalFileRef file, {String? password});

  /// Concatenated plain text across pages (best-effort; may be empty).
  Future<String> extractPlainText(LocalFileRef file, {String? password});
}
