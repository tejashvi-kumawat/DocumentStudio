import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/infrastructure/pdf/pdf_render_port.dart';

bool isOrganizeImportPasswordError(DocumentStudioError error) {
  return error.code == DocumentStudioErrorCode.passwordRequired ||
      error.code == DocumentStudioErrorCode.wrongPassword;
}

String organizeImportPasswordFailureMessage(DocumentStudioError error) {
  final hint = error.recoveryHint;
  if (hint != null && hint.isNotEmpty) return hint;
  if (error.code == DocumentStudioErrorCode.wrongPassword) {
    return error.code.userMessage;
  }
  if (error.message.isNotEmpty &&
      error.code != DocumentStudioErrorCode.passwordRequired) {
    return error.message;
  }
  return error.code.userMessage;
}

typedef OrganizeImportLoadInfo = Future<PdfDocumentInfo> Function(
  LocalFileRef file, {
  String? password,
});

/// Loads page count for organize/workspace import, prompting for a PDF password
/// when needed (same retry loop as merge [`_loadPageCount`]).
Future<int?> loadOrganizeImportPageCount({
  required LocalFileRef file,
  required OrganizeImportLoadInfo loadInfo,
  required Map<String, String> passwordsByPath,
  required Future<String?> Function() promptPassword,
  void Function(String message)? onPasswordRejected,
}) async {
  try {
    final info = await loadInfo(
      file,
      password: passwordsByPath[file.path],
    );
    return info.pageCount;
  } on DocumentStudioError catch (e) {
    if (!isOrganizeImportPasswordError(e)) rethrow;
    final rejected = passwordsByPath.containsKey(file.path) ? e : null;
    return _promptPasswordAndRetryOrganizeImport(
      file: file,
      loadInfo: loadInfo,
      passwordsByPath: passwordsByPath,
      promptPassword: promptPassword,
      onPasswordRejected: onPasswordRejected,
      rejected: rejected,
    );
  }
}

Future<int?> _promptPasswordAndRetryOrganizeImport({
  required LocalFileRef file,
  required OrganizeImportLoadInfo loadInfo,
  required Map<String, String> passwordsByPath,
  required Future<String?> Function() promptPassword,
  void Function(String message)? onPasswordRejected,
  DocumentStudioError? rejected,
}) async {
  if (rejected != null) {
    onPasswordRejected?.call(organizeImportPasswordFailureMessage(rejected));
    passwordsByPath.remove(file.path);
  }

  final password = await promptPassword();
  if (password == null || password.isEmpty) {
    passwordsByPath.remove(file.path);
    return null;
  }
  passwordsByPath[file.path] = password;

  try {
    final info = await loadInfo(file, password: password);
    return info.pageCount;
  } on DocumentStudioError catch (e) {
    if (!isOrganizeImportPasswordError(e)) rethrow;
    return _promptPasswordAndRetryOrganizeImport(
      file: file,
      loadInfo: loadInfo,
      passwordsByPath: passwordsByPath,
      promptPassword: promptPassword,
      onPasswordRejected: onPasswordRejected,
      rejected: e,
    );
  }
}
