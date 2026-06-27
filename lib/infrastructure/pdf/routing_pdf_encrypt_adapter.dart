import 'dart:io';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/infrastructure/pdf/dart_pdf_security_service.dart';
import 'package:document_studio/infrastructure/pdf/qpdf_encrypt_adapter.dart';
import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:path/path.dart' as p;

/// Prefers qpdf when the CLI exists; otherwise uses PDFium + pure-Dart AES-128.
class RoutingPdfEncryptAdapter implements PdfEncryptPort {
  RoutingPdfEncryptAdapter({
    QpdfEncryptAdapter? qpdf,
    DartPdfSecurityService? dart,
  })  : _qpdf = qpdf ?? QpdfEncryptAdapter(),
        _dart = dart ?? const DartPdfSecurityService();

  final QpdfEncryptAdapter _qpdf;
  final DartPdfSecurityService _dart;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<LocalFileRef> encryptWithPassword({
    required LocalFileRef input,
    required String outputPath,
    required String userPassword,
    String ownerPassword = '',
    String? inputPassword,
    PdfEncryptPermissions permissions = const PdfEncryptPermissions(),
  }) async {
    if (await isQpdfCliAvailable()) {
      return _qpdf.encryptWithPassword(
        input: input,
        outputPath: outputPath,
        userPassword: userPassword,
        ownerPassword: ownerPassword,
        inputPassword: inputPassword,
        permissions: permissions,
      );
    }
    try {
      await _dart.encryptToFile(
        inputPath: input.path,
        outputPath: outputPath,
        userPassword: userPassword,
        ownerPassword: ownerPassword,
        inputPassword: inputPassword,
        allowPrinting: permissions.allowPrinting,
        allowModify: permissions.allowModify,
        allowExtract: permissions.allowExtract,
        allowAnnotate: permissions.allowAnnotate,
      );
    } on DocumentStudioError {
      rethrow;
    } catch (e) {
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.nativeEngineError,
        message: 'Encryption failed.',
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
  Future<LocalFileRef> decryptToFile({
    required LocalFileRef input,
    required String outputPath,
    required String password,
  }) async {
    if (await isQpdfCliAvailable()) {
      return _qpdf.decryptToFile(
        input: input,
        outputPath: outputPath,
        password: password,
      );
    }
    try {
      await _dart.decryptToFile(
        inputPath: input.path,
        outputPath: outputPath,
        password: password,
      );
    } on DocumentStudioError {
      rethrow;
    } catch (e) {
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.nativeEngineError,
        message: 'Decrypt failed.',
        cause: e,
      );
    }
    return LocalFileRef(
      path: outputPath,
      displayName: p.basename(outputPath),
      sizeBytes: await File(outputPath).length(),
    );
  }
}

/// Probes encryption with qpdf when present, otherwise PDFium.
Future<PdfProtectionState> probePdfProtectionRouted(
  String path, {
  QpdfCliRunner? cli,
  DartPdfSecurityService? dart,
}) async {
  if (await isQpdfCliAvailable()) {
    return probePdfProtection(path, cli: cli);
  }
  final probe =
      await (dart ?? const DartPdfSecurityService()).probeProtection(path);
  return switch (probe) {
    PdfProtectionProbe.none => PdfProtectionState.none,
    PdfProtectionProbe.restrictionsOnly => PdfProtectionState.restrictionsOnly,
    PdfProtectionProbe.openPassword => PdfProtectionState.openPassword,
    PdfProtectionProbe.unknown => PdfProtectionState.unknown,
  };
}
