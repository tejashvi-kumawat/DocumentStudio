import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:flutter/material.dart';

extension DocumentStudioErrorPresentation on DocumentStudioError {
  String get userFacingMessage {
    final base = code.userMessage;
    final hint = recoveryHint;
    if (hint == null || hint.isEmpty) {
      return base;
    }
    return '$base $hint';
  }

  /// Short headline for full-screen open failures (viewer route).
  String get openFailureTitle => switch (code) {
    DocumentStudioErrorCode.passwordRequired => 'Password required',
    DocumentStudioErrorCode.wrongPassword => 'Wrong password',
    DocumentStudioErrorCode.corruptedPdf ||
    DocumentStudioErrorCode.invalidPdf => 'Could not read PDF',
    DocumentStudioErrorCode.fileNotFound => 'File not found',
    DocumentStudioErrorCode.permissionDenied ||
    DocumentStudioErrorCode.fileNotAccessible => 'Cannot access file',
    _ => 'Could not open document',
  };
}

void showDocumentStudioErrorSnackBar(
  BuildContext context,
  DocumentStudioError error,
) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(error.userFacingMessage)));
}

/// Full-screen open failure for viewer and similar routes ([DS-EDGE-009]).
class DocumentOpenErrorPanel extends StatelessWidget {
  const DocumentOpenErrorPanel({
    super.key,
    required this.error,
    this.onBack,
    this.onRetry,
    this.onPickAnotherFile,
    this.onUnlock,
  });

  final DocumentStudioError error;
  final VoidCallback? onBack;
  final VoidCallback? onRetry;
  final VoidCallback? onPickAnotherFile;
  final VoidCallback? onUnlock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 40,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                error.openFailureTitle,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                error.userFacingMessage,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (onPickAnotherFile != null)
                    FilledButton.icon(
                      onPressed: onPickAnotherFile,
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: const Text('Try another file'),
                    ),
                  if (onUnlock != null)
                    FilledButton.icon(
                      onPressed: onUnlock,
                      icon: const Icon(Icons.lock_open, size: 18),
                      label: const Text('Unlock'),
                    ),
                  if (onBack != null)
                    OutlinedButton(
                      onPressed: onBack,
                      child: const Text('Go back'),
                    ),
                  if (onRetry != null)
                    OutlinedButton(
                      onPressed: onRetry,
                      child: const Text('Try again'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
