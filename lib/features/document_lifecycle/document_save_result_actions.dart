import 'dart:io';

import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/pdf_document_route_args.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

/// Desktop file-manager reveal (folder containing [file]).
Future<bool> revealFileInFolder(LocalFileRef file) async {
  if (kIsWeb) return false;
  final path = file.path;
  if (path.isEmpty) return false;
  try {
    if (Platform.isLinux) {
      final result = await Process.run('xdg-open', [p.dirname(path)]);
      return result.exitCode == 0;
    }
    if (Platform.isMacOS) {
      final result = await Process.run('open', ['-R', path]);
      return result.exitCode == 0;
    }
    if (Platform.isWindows) {
      final normalized = path.replaceAll('/', '\\');
      final result = await Process.run('explorer.exe', ['/select,', normalized]);
      return result.exitCode == 0;
    }
  } catch (_) {
    return false;
  }
  return false;
}

bool get documentSaveResultCanRevealInFolder {
  if (kIsWeb) return false;
  return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
}

/// Opens a tool's output PDF as a document tab in the shell viewer (closing
/// the full-screen tool route). Non-PDF outputs are revealed in their folder.
void openToolResult(
  BuildContext context,
  LocalFileRef file, {
  String? password,
}) {
  if (!file.isPdf) {
    revealFileInFolder(file);
    return;
  }
  ProviderScope.containerOf(context, listen: false)
      .read(documentTabsControllerProvider)
      .openDocument(file, password: password);
  GoRouter.of(context).go('/');
}

/// "Show in folder" with a snackbar when the file manager cannot be opened.
Future<void> revealToolResult(BuildContext context, LocalFileRef file) async {
  final ok = await revealFileInFolder(file);
  if (ok || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Could not open the folder for this file.')),
  );
}

/// Acrobat-style post-save actions: viewer, workspace, reveal in folder.
void showDocumentSaveResultActions(
  BuildContext context, {
  required LocalFileRef file,
  String? password,
  required String message,
  FileStoragePort? storage,
  bool showOpenInViewer = true,
  bool showEditInWorkspace = true,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: _DocumentSaveResultSnackContent(
        message: message,
        file: file,
        password: password,
        showOpenInViewer: showOpenInViewer,
        showEditInWorkspace: showEditInWorkspace,
      ),
      duration: const Duration(seconds: 12),
      behavior: SnackBarBehavior.floating,
      showCloseIcon: true,
    ),
  );
}

/// Alias used by protect/unlock flows.
void showSavedPdfWithViewerAction(
  BuildContext context, {
  required LocalFileRef file,
  String? password,
  required String message,
}) {
  showDocumentSaveResultActions(
    context,
    file: file,
    password: password,
    message: message,
  );
}

class _DocumentSaveResultSnackContent extends StatelessWidget {
  const _DocumentSaveResultSnackContent({
    required this.message,
    required this.file,
    this.password,
    this.showOpenInViewer = true,
    this.showEditInWorkspace = true,
  });

  final String message;
  final LocalFileRef file;
  final String? password;
  final bool showOpenInViewer;
  final bool showEditInWorkspace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showFolder = documentSaveResultCanRevealInFolder;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 0,
          children: [
            if (showOpenInViewer)
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  openToolResult(context, file, password: password);
                },
                child: const Text('Open in viewer'),
              ),
            if (showEditInWorkspace)
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  context.push(
                    '/workspace',
                    extra: PdfDocumentRouteArgs(file: file, password: password),
                  );
                },
                child: const Text('Edit in workspace'),
              ),
            if (showFolder)
              TextButton(
                onPressed: () async {
                  final ok = await revealFileInFolder(file);
                  if (!context.mounted) return;
                  if (!ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not open folder for this file.'),
                      ),
                    );
                  }
                },
                child: const Text('Show in folder'),
              ),
          ],
        ),
        Text(
          file.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
