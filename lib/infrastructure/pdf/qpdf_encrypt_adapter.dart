import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:path/path.dart' as p;

/// Permission flags applied when writing encryption (qpdf restriction model).
class PdfEncryptPermissions {
  const PdfEncryptPermissions({
    this.allowPrinting = true,
    this.allowModify = false,
    this.allowExtract = false,
    this.allowAnnotate = false,
  });

  final bool allowPrinting;
  final bool allowModify;
  final bool allowExtract;
  final bool allowAnnotate;
}

/// Password protection via qpdf (CLI today; FFI later).
abstract class PdfEncryptPort {
  Future<bool> isAvailable();

  Future<LocalFileRef> encryptWithPassword({
    required LocalFileRef input,
    required String outputPath,
    required String userPassword,
    String ownerPassword = '',
    String? inputPassword,
    PdfEncryptPermissions permissions = const PdfEncryptPermissions(),
  });

  /// DS-SEC-003 — save an unencrypted copy (password required when encrypted).
  Future<LocalFileRef> decryptToFile({
    required LocalFileRef input,
    required String outputPath,
    required String password,
  });
}

/// How a PDF is protected (drives the Unlock flow).
enum PdfProtectionState { none, restrictionsOnly, openPassword, unknown }

/// Probes encryption with qpdf; [PdfProtectionState.unknown] if qpdf fails.
Future<PdfProtectionState> probePdfProtection(
  String path, {
  QpdfCliRunner? cli,
}) async {
  try {
    final code = await (cli ?? QpdfCliRunner()).requiresPasswordStatus(path);
    return switch (code) {
      0 => PdfProtectionState.openPassword,
      2 => PdfProtectionState.none,
      3 => PdfProtectionState.restrictionsOnly,
      _ => PdfProtectionState.unknown,
    };
  } catch (_) {
    return PdfProtectionState.unknown;
  }
}

String _qpdfDetail(QpdfCliException e) {
  final stderr = e.stderr.trim();
  if (stderr.isNotEmpty) return stderr;
  return e.stdout.trim();
}

class QpdfEncryptAdapter implements PdfEncryptPort {
  QpdfEncryptAdapter({QpdfCliRunner? cli}) : _cli = cli ?? QpdfCliRunner();

  final QpdfCliRunner _cli;

  @override
  Future<bool> isAvailable() => isQpdfCliAvailable();

  @override
  Future<LocalFileRef> encryptWithPassword({
    required LocalFileRef input,
    required String outputPath,
    required String userPassword,
    String ownerPassword = '',
    String? inputPassword,
    PdfEncryptPermissions permissions = const PdfEncryptPermissions(),
  }) async {
    if (!await isAvailable()) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.featureUnavailable,
        message: 'Bundled qpdf engine unavailable.',
      );
    }
    if (userPassword.isEmpty) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.invalidFile,
        message: 'Enter a password to encrypt the PDF.',
      );
    }
    try {
      await _cli.encrypt(
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
    } on QpdfCliException catch (e) {
      final detail = _qpdfDetail(e);
      final text = detail.toLowerCase();
      if (text.contains('password') && text.contains('incorrect')) {
        throw DocumentStudioError(
          code: DocumentStudioErrorCode.wrongPassword,
          message: 'Incorrect password for the source PDF.',
          cause: e,
          recoveryHint: detail.isEmpty ? null : detail,
        );
      }
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.nativeEngineError,
        message: detail.isEmpty ? 'Encryption failed.' : detail,
        cause: e,
        recoveryHint: detail.isEmpty ? null : detail,
      );
    }
    return LocalFileRef(
      path: outputPath,
      displayName: p.basename(outputPath),
    );
  }

  @override
  Future<LocalFileRef> decryptToFile({
    required LocalFileRef input,
    required String outputPath,
    required String password,
  }) async {
    if (!await isAvailable()) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.featureUnavailable,
        message: 'Bundled qpdf engine unavailable.',
      );
    }
    try {
      await _cli.decryptPdf(
        inputPath: input.path,
        outputPath: outputPath,
        password: password,
      );
    } on QpdfCliException catch (e) {
      final detail = _qpdfDetail(e);
      final text = detail.toLowerCase();
      if (text.contains('password') &&
          (text.contains('incorrect') || text.contains('invalid'))) {
        throw DocumentStudioError(
          code: DocumentStudioErrorCode.wrongPassword,
          message: 'Incorrect password for this PDF.',
          cause: e,
          recoveryHint: detail.isEmpty ? null : detail,
        );
      }
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.nativeEngineError,
        message: detail.isEmpty ? 'Decrypt failed.' : detail,
        cause: e,
        recoveryHint: detail.isEmpty ? null : detail,
      );
    }
    return LocalFileRef(
      path: outputPath,
      displayName: p.basename(outputPath),
    );
  }
}
