import 'package:document_studio/domain/models/local_file_ref.dart';

/// Password for qpdf page-box export (single source file per crop/resize job).
String? pageBoxExportPassword({
  required Map<String, String>? passwordsByPath,
  required LocalFileRef input,
}) {
  return pageBoxPasswordForExportPath(
    passwordsByPath: passwordsByPath,
    filePath: input.path,
  );
}

String? pageBoxPasswordForExportPath({
  required Map<String, String>? passwordsByPath,
  required String filePath,
}) {
  final pw = passwordsByPath?[filePath];
  if (pw != null && pw.isNotEmpty) return pw;
  return null;
}
