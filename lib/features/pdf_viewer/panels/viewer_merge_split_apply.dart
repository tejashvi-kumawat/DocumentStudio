import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/document_lifecycle/document_session.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// Merges [inputs] into the open session working copy.
///
/// Does not write [DocumentSession.sourcePath]. Save / Ctrl+S does that.
Future<void> applyMergeIntoOpenSession({
  required WidgetRef ref,
  required BuildContext context,
  required PdfViewerDocumentHandoff handoff,
  required List<LocalFileRef> inputs,
  Map<String, String>? passwordsByPath,
}) async {
  if (inputs.length < 2) {
    throw StateError('Add at least one other PDF to merge.');
  }
  final tabs = ref.read(documentTabsControllerProvider);
  final session = tabs.activeSession;
  if (session == null || !session.sameDocumentPath(handoff.file.path)) {
    throw StateError('No open document to merge into.');
  }
  final bytes = await ref
      .read(pageOrganizeServiceProvider)
      .mergeToBytes(inputs: inputs, passwordsByPath: passwordsByPath);
  if (!context.mounted) return;
  final outcome = await session.commitBytes(Uint8List.fromList(bytes));
  if (outcome != DocumentSaveOutcome.savedInPlace) {
    throw const DocumentStudioError(
      code: DocumentStudioErrorCode.fileNotAccessible,
      message: 'Could not update the open document.',
      recoveryHint: 'Use Save as to write a new PDF.',
    );
  }
  tabs.syncActiveTabFromSession();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Merged into this document. Save or Ctrl+S writes the original file.',
      ),
    ),
  );
}

/// Default file name for merge Save as. Never the open document's own name.
String suggestedMergeSaveAsName(String displayName) {
  final stem = p.basenameWithoutExtension(displayName.trim());
  final base = stem.isEmpty ? 'merged' : stem;
  return '$base-merged.pdf';
}

/// Asks for a file name. Returns null when cancelled.
Future<String?> promptMergeSaveAsName(
  BuildContext context, {
  required String suggestedName,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _MergeSaveAsNameDialog(suggestedName: suggestedName),
  );
}

/// Writes the merge to a new PDF named by [fileName].
///
/// The open session is not updated and its source path is not changed.
/// Returns null when a fallback folder picker is cancelled.
Future<LocalFileRef?> saveMergedPdfAsNewFile({
  required WidgetRef ref,
  required BuildContext context,
  required PdfViewerDocumentHandoff handoff,
  required List<LocalFileRef> inputs,
  required String fileName,
  Map<String, String>? passwordsByPath,
}) async {
  if (inputs.length < 2) {
    throw StateError('Add at least one other PDF to merge.');
  }
  final tabs = ref.read(documentTabsControllerProvider);
  final session = tabs.activeSession;
  if (session == null || !session.sameDocumentPath(handoff.file.path)) {
    throw StateError('No open document to merge.');
  }
  if (!context.mounted) return null;

  final storage = ref.read(fileStorageProvider);
  var directory = splitOutputDirectoryForOpenDocument(
    session: session,
    handoffPath: handoff.file.path,
  );
  if (!await _directoryIsWritable(directory)) {
    final picked = await storage.pickOutputDirectory(
      dialogTitle: 'Save merged PDF to folder',
    );
    if (picked == null || !context.mounted) return null;
    directory = picked;
  }
  final dest = mergeSaveAsDestination(
    directory: directory,
    fileName: fileName,
    forbiddenPaths: splitForbiddenPaths(
      session: session,
      handoffPath: handoff.file.path,
    ),
  );
  final bytes = await ref
      .read(pageOrganizeServiceProvider)
      .mergeToBytes(inputs: inputs, passwordsByPath: passwordsByPath);
  if (!context.mounted) return null;
  await storage.writeAtomic(
    destinationPath: dest,
    writeToTemp: (temp) async {
      await File(temp).writeAsBytes(bytes, flush: true);
    },
  );
  final stat = await File(dest).stat();
  final out = LocalFileRef(
    path: dest,
    displayName: p.basename(dest),
    sizeBytes: stat.size,
    lastModified: stat.modified,
  );
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Saved ${out.displayName}. The open document was not changed.',
        ),
      ),
    );
  }
  return out;
}

/// Path for a merge Save as name in [directory].
///
/// Refuses the open document and its working copy. Does not invent a
/// replacement name — the caller must ask again.
String mergeSaveAsDestination({
  required String directory,
  required String fileName,
  required Set<String> forbiddenPaths,
}) {
  final name = normalizeMergeSaveAsFileName(fileName);
  final dest = p.normalize(p.join(directory, name));
  if (_pathConflicts(dest, forbiddenPaths)) {
    throw const DocumentStudioError(
      code: DocumentStudioErrorCode.invalidFile,
      message: 'That name is the open document. Save updates this copy. Ctrl+S writes the original file.',
    );
  }
  return dest;
}

/// File name only. Rejects empty names and folder paths.
String normalizeMergeSaveAsFileName(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed == '.' || trimmed == '..') {
    throw const DocumentStudioError(
      code: DocumentStudioErrorCode.invalidFile,
      message: 'Enter a file name.',
    );
  }
  if (trimmed.contains('/') || trimmed.contains('\\')) {
    throw const DocumentStudioError(
      code: DocumentStudioErrorCode.invalidFile,
      message: 'Enter a file name, not a folder path.',
    );
  }
  final cleaned = trimmed.replaceAll(RegExp(r'[\x00-\x1f]'), '');
  if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') {
    throw const DocumentStudioError(
      code: DocumentStudioErrorCode.invalidFile,
      message: 'Enter a file name.',
    );
  }
  return cleaned.toLowerCase().endsWith('.pdf') ? cleaned : '$cleaned.pdf';
}

bool _pathConflicts(String dest, Set<String> forbiddenPaths) {
  final candidates = <String>{p.normalize(dest), _canonicalPath(dest)};
  final forbidden = <String>{};
  for (final path in forbiddenPaths) {
    forbidden
      ..add(p.normalize(path))
      ..add(_canonicalPath(path));
  }
  return candidates.any(forbidden.contains);
}

class _MergeSaveAsNameDialog extends StatefulWidget {
  const _MergeSaveAsNameDialog({required this.suggestedName});

  final String suggestedName;

  @override
  State<_MergeSaveAsNameDialog> createState() => _MergeSaveAsNameDialogState();
}

class _MergeSaveAsNameDialogState extends State<_MergeSaveAsNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.suggestedName,
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final normalized = normalizeMergeSaveAsFileName(_name.text);
      Navigator.of(context).pop(normalized);
    } on DocumentStudioError catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save as'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Writes a new PDF next to the original. This document stays unchanged.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('viewer_merge_save_as_name'),
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'File name',
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

/// Directory beside the user's original file, not the session temp copy.
String splitOutputDirectoryForOpenDocument({
  required DocumentSession? session,
  required String handoffPath,
}) {
  if (session != null && session.sameDocumentPath(handoffPath)) {
    return p.dirname(session.sourcePath);
  }
  return p.dirname(handoffPath);
}

/// Paths split output must not replace: the original and the working copy.
Set<String> splitForbiddenPaths({
  required DocumentSession? session,
  required String handoffPath,
}) {
  final paths = <String>{handoffPath};
  if (session != null) {
    paths
      ..add(session.sourcePath)
      ..add(session.file.path);
  }
  return paths;
}

/// Writes split parts as new files. Never replaces the open document or its source.
///
/// Uses the folder next to the original when that folder is writable. Otherwise
/// asks for a folder with the existing split directory picker. The session
/// working copy is left unchanged — a split is several files, and Save still
/// writes the source.
Future<List<LocalFileRef>> writeSplitPartsWithoutClobberingSource({
  required FileStoragePort storage,
  required List<LocalFileRef> tempParts,
  required String namePrefix,
  required String preferredDirectory,
  required Set<String> forbiddenPaths,
}) async {
  if (tempParts.isEmpty) {
    throw const DocumentStudioError(
      code: DocumentStudioErrorCode.invalidPdf,
      message: 'Nothing to split',
    );
  }
  var directory = preferredDirectory;
  if (!await _directoryIsWritable(directory)) {
    final picked = await storage.pickOutputDirectory(
      dialogTitle: 'Save split PDFs to folder',
    );
    if (picked == null) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.processCancelled,
        message: 'Folder selection cancelled',
      );
    }
    directory = picked;
  }

  final saved = <LocalFileRef>[];
  final used = <String>{};
  for (var i = 0; i < tempParts.length; i++) {
    final dest = allocateSplitOutputPath(
      directory: directory,
      namePrefix: namePrefix,
      partNumber: i + 1,
      forbiddenPaths: {...forbiddenPaths, ...used},
    );
    final bytes = await File(tempParts[i].path).readAsBytes();
    await storage.writeAtomic(
      destinationPath: dest,
      writeToTemp: (temp) async {
        await File(temp).writeAsBytes(bytes, flush: true);
      },
    );
    used.add(dest);
    final stat = await File(dest).stat();
    saved.add(
      LocalFileRef(
        path: dest,
        displayName: p.basename(dest),
        sizeBytes: stat.size,
        lastModified: stat.modified,
      ),
    );
  }
  return saved;
}

/// Next free `prefix-partN.pdf` in [directory] that is not a forbidden path.
String allocateSplitOutputPath({
  required String directory,
  required String namePrefix,
  required int partNumber,
  required Set<String> forbiddenPaths,
}) {
  final raw = namePrefix.trim();
  final prefix = raw.isEmpty ? 'split' : raw.replaceAll(RegExp(r'[\\/]+'), '_');
  final forbidden = forbiddenPaths.map(_canonicalPath).toSet();
  var n = partNumber < 1 ? 1 : partNumber;
  for (var attempt = 0; attempt < 1000; attempt++) {
    final dest = p.normalize(p.join(directory, '$prefix-part$n.pdf'));
    final canon = _canonicalPath(dest);
    final clashes = forbidden.contains(canon) || File(dest).existsSync();
    if (!clashes) return dest;
    n++;
  }
  throw StateError(
    'Could not name a split file without replacing the original.',
  );
}

String _canonicalPath(String path) {
  try {
    return p.normalize(File(path).resolveSymbolicLinksSync());
  } catch (_) {
    return p.normalize(path);
  }
}

Future<bool> _directoryIsWritable(String directory) async {
  final probe = File(
    p.join(
      directory,
      '.ds-split-probe-${DateTime.now().microsecondsSinceEpoch}',
    ),
  );
  try {
    await probe.writeAsString('ok', flush: true);
    await probe.delete();
    return true;
  } catch (_) {
    try {
      if (await probe.exists()) await probe.delete();
    } catch (_) {}
    return false;
  }
}
