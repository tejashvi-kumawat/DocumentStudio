import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/document_lifecycle/document_save_result_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// Bytes assembled by [PageOrganizeService.assembleWorkspaceExport] plus a name.
class OrganizeAssembledExport {
  const OrganizeAssembledExport({
    required this.tempPath,
    required this.bytes,
    required this.suggestedName,
  });

  final String tempPath;
  final List<int> bytes;
  final String suggestedName;
}

/// Save-as prompt, recents, post-save actions, optional workspace replace.
Future<void> runOrganizeExportResultActions({
  required BuildContext context,
  required WidgetRef ref,
  required OrganizeAssembledExport assembled,
  required int pageCount,
  Map<String, String>? passwordsByPath,
  required Future<void> Function(LocalFileRef file, int pageCount)
  onReplaceInWorkspace,
}) async {
  final storage = ref.read(fileStorageProvider);
  final suggested = assembled.suggestedName.endsWith('.pdf')
      ? assembled.suggestedName
      : '${assembled.suggestedName}.pdf';
  final bytes = Uint8List.fromList(assembled.bytes);
  final savePath = await storage.pickSavePath(
    suggestedName: suggested,
    bytes: bytes,
    allowedExtensions: const ['pdf'],
    mimeType: 'application/pdf',
  );
  if (savePath == null) {
    try {
      await File(assembled.tempPath).delete();
    } catch (_) {}
    return;
  }

  await storage.writeAtomic(
    destinationPath: savePath,
    writeToTemp: (t) async {
      await File(t).writeAsBytes(bytes, flush: true);
    },
  );

  try {
    await File(assembled.tempPath).delete();
  } catch (_) {}

  final saved = LocalFileRef(path: savePath, displayName: p.basename(savePath));
  await ref.read(recentsProvider.notifier).addRecent(saved);
  if (!context.mounted) return;
  showDocumentSaveResultActions(
    context,
    file: saved,
    password: passwordsByPath?[saved.path],
    message: 'Saved ${saved.displayName}',
  );

  final replace = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Replace workspace?'),
      content: Text(
        'Load “${saved.displayName}” ($pageCount pages) into this workspace?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Keep current'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Replace'),
        ),
      ],
    ),
  );
  if (replace == true) {
    await onReplaceInWorkspace(saved, pageCount);
  }
}
