import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:path/path.dart' as p;

/// Standard PDF Info dictionary fields editable via qpdf.
class PdfDocumentInfoFields {
  const PdfDocumentInfoFields({
    this.title = '',
    this.author = '',
    this.subject = '',
    this.keywords = '',
    this.creator = '',
    this.producer = '',
  });

  final String title;
  final String author;
  final String subject;
  final String keywords;
  final String creator;
  final String producer;

  Map<String, String> toQpdfFieldMap() {
    return {
      'Title': title,
      'Author': author,
      'Subject': subject,
      'Keywords': keywords,
      'Creator': creator,
      'Producer': producer,
    };
  }
}

/// Metadata strip / rewrite via qpdf CLI.
abstract class PdfMetadataPort {
  Future<bool> isAvailable();

  Future<LocalFileRef> stripAllMetadata({
    required LocalFileRef input,
    required String outputPath,
    String? inputPassword,
  });

  Future<LocalFileRef> writeDocumentInfo({
    required LocalFileRef input,
    required String outputPath,
    required PdfDocumentInfoFields fields,
    String? inputPassword,
  });
}

class QpdfMetadataAdapter implements PdfMetadataPort {
  QpdfMetadataAdapter({QpdfCliRunner? cli}) : _cli = cli ?? QpdfCliRunner();

  final QpdfCliRunner _cli;

  @override
  Future<bool> isAvailable() => isQpdfCliAvailable();

  @override
  Future<LocalFileRef> stripAllMetadata({
    required LocalFileRef input,
    required String outputPath,
    String? inputPassword,
  }) async {
    await _ensureAvailable();
    try {
      await _cli.removeAllMetadata(
        inputPath: input.path,
        outputPath: outputPath,
        password: inputPassword,
      );
    } on QpdfCliException catch (e) {
      throw _mapCliError(e, failureMessage: 'qpdf could not remove metadata.');
    }
    return LocalFileRef(
      path: outputPath,
      displayName: p.basename(outputPath),
    );
  }

  @override
  Future<LocalFileRef> writeDocumentInfo({
    required LocalFileRef input,
    required String outputPath,
    required PdfDocumentInfoFields fields,
    String? inputPassword,
  }) async {
    await _ensureAvailable();
    try {
      await _cli.updateDocumentInfo(
        inputPath: input.path,
        outputPath: outputPath,
        fields: fields.toQpdfFieldMap(),
        password: inputPassword,
      );
    } on QpdfCliException catch (e) {
      throw _mapCliError(e, failureMessage: 'qpdf could not update metadata.');
    }
    return LocalFileRef(
      path: outputPath,
      displayName: p.basename(outputPath),
    );
  }

  Future<void> _ensureAvailable() async {
    if (!await isAvailable()) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.featureUnavailable,
        message: 'Metadata tools need the bundled qpdf engine.',
        recoveryHint:
            'On desktop, download qpdf once from Settings or reinstall '
            'Document Studio. Android and iOS use the built-in PDF engine '
            'and do not install qpdf.',
      );
    }
  }

  DocumentStudioError _mapCliError(
    QpdfCliException e, {
    required String failureMessage,
  }) {
    final text = '${e.stderr}${e.stdout}'.toLowerCase();
    if (text.contains('password') &&
        (text.contains('incorrect') || text.contains('invalid'))) {
      return DocumentStudioError(
        code: DocumentStudioErrorCode.wrongPassword,
        message: 'Incorrect password for the source PDF.',
        cause: e,
      );
    }
    return DocumentStudioError(
      code: DocumentStudioErrorCode.nativeEngineError,
      message: failureMessage,
      cause: e,
    );
  }
}
