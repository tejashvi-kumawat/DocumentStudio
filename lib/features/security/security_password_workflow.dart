import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/errors/document_studio_error_ui.dart';
import 'package:document_studio/features/page_management/organize_pdf_import.dart';
import 'package:document_studio/features/page_management/pdf_password_prompt.dart';
import 'package:flutter/material.dart';

/// Prompts for a PDF password after optional rejection feedback (unlock/metadata).
Future<String?> promptPdfPasswordAfterRejection(
  BuildContext context, {
  DocumentStudioError? rejected,
}) async {
  if (rejected != null && context.mounted) {
    final message = isOrganizeImportPasswordError(rejected)
        ? organizeImportPasswordFailureMessage(rejected)
        : rejected.userFacingMessage;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
  if (!context.mounted) return null;
  return promptPdfPassword(context);
}
