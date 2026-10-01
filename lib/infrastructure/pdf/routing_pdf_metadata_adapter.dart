import 'dart:io';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/infrastructure/pdf/dart_pdf_security_service.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_parser.dart';
import 'package:document_studio/infrastructure/pdf/qpdf_metadata_adapter.dart';
import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:path/path.dart' as p;

/// Prefers qpdf for metadata rewrite; falls back to pure-Dart Info updates.
class RoutingPdfMetadataAdapter implements PdfMetadataPort {
  RoutingPdfMetadataAdapter({
    QpdfMetadataAdapter? qpdf,
    DartPdfSecurityService? dart,
  })  : _qpdf = qpdf ?? QpdfMetadataAdapter(),
        _dart = dart ?? const DartPdfSecurityService();

  final QpdfMetadataAdapter _qpdf;
  final DartPdfSecurityService _dart;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<LocalFileRef> stripAllMetadata({
    required LocalFileRef input,
    required String outputPath,
    String? inputPassword,
  }) async {
    if (await isQpdfCliAvailable()) {
      return _qpdf.stripAllMetadata(
        input: input,
        outputPath: outputPath,
        inputPassword: inputPassword,
      );
    }
    try {
      final wasEncrypted = await _looksEncrypted(input.path);
      await _dart.stripAllMetadata(
        inputPath: input.path,
        outputPath: outputPath,
        inputPassword: inputPassword,
        reencryptUserPassword:
            wasEncrypted && inputPassword != null && inputPassword.isNotEmpty
                ? inputPassword
                : null,
      );
    } on DocumentStudioError {
      rethrow;
    } on PdfEditException catch (e) {
      throw DocumentStudioError(
        code: e.encrypted
            ? DocumentStudioErrorCode.passwordRequired
            : DocumentStudioErrorCode.nativeEngineError,
        message: e.encrypted
            ? 'This PDF is password protected.'
            : 'Could not remove metadata.',
        cause: e,
      );
    } catch (e) {
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.nativeEngineError,
        message: 'Could not remove metadata.',
        cause: e,
      );
    }
    return LocalFileRef(
      path: outputPath,
      displayName: p.basename(outputPath),
      sizeBytes: await File(outputPath).length(),
    );
  }

  @override
  Future<LocalFileRef> writeDocumentInfo({
    required LocalFileRef input,
    required String outputPath,
    required PdfDocumentInfoFields fields,
    String? inputPassword,
  }) async {
    if (await isQpdfCliAvailable()) {
      return _qpdf.writeDocumentInfo(
        input: input,
        outputPath: outputPath,
        fields: fields,
        inputPassword: inputPassword,
      );
    }
    try {
      final wasEncrypted = await _looksEncrypted(input.path);
      await _dart.writeDocumentInfo(
        inputPath: input.path,
        outputPath: outputPath,
        inputPassword: inputPassword,
        fields: {
          'Title': fields.title,
          'Author': fields.author,
          'Subject': fields.subject,
          'Keywords': fields.keywords,
          'Creator': fields.creator,
          'Producer': fields.producer,
        },
        reencryptUserPassword:
            wasEncrypted && inputPassword != null && inputPassword.isNotEmpty
                ? inputPassword
                : null,
      );
    } on DocumentStudioError {
      rethrow;
    } on PdfEditException catch (e) {
      throw DocumentStudioError(
        code: e.encrypted
            ? DocumentStudioErrorCode.passwordRequired
            : DocumentStudioErrorCode.nativeEngineError,
        message: e.encrypted
            ? 'This PDF is password protected.'
            : 'Could not update metadata.',
        cause: e,
      );
    } catch (e) {
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.nativeEngineError,
        message: 'Could not update metadata.',
        cause: e,
      );
    }
    return LocalFileRef(
      path: outputPath,
      displayName: p.basename(outputPath),
      sizeBytes: await File(outputPath).length(),
    );
  }

  Future<bool> _looksEncrypted(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      const key = [0x2F, 0x45, 0x6E, 0x63, 0x72, 0x79, 0x70, 0x74]; // /Encrypt
      final end = bytes.length - key.length;
      outer:
      for (var i = 0; i <= end; i++) {
        if (bytes[i] != 0x2F) continue;
        for (var k = 1; k < key.length; k++) {
          if (bytes[i + k] != key[k]) continue outer;
        }
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
