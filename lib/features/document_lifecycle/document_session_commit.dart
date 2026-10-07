import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/document_lifecycle/document_save_result_actions.dart';
import 'package:document_studio/features/document_lifecycle/document_session.dart';
import 'package:document_studio/features/document_lifecycle/document_session_autosave.dart';
import 'package:document_studio/features/pdf_viewer/document_tabs_controller.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// Commits [bytes] into [session]'s dirty working copy (undoable).
///
/// Does **not** write the user's original file — use explicit Save for that.
/// Does not remount the viewer: callers soft-reload via documentRef when needed.
/// [quiet] shows a short snackbar instead of the full result sheet.
///
/// When [debounce] is true, waits [kViewerAutosaveDebounce] after the last call
/// before writing once (latest bytes win). Explicit Apply should pass
/// `debounce: false` (the default).
Future<LocalFileRef?> commitBytesToSession({
  required BuildContext context,
  required FileStoragePort storage,
  required DocumentTabsController tabs,
  required DocumentSession session,
  required Uint8List bytes,
  required String successMessage,
  String? saveAsReason,
  String? suggestedName,
  bool quiet = true,
  bool debounce = false,
  bool silent = false,
  void Function()? beforeTabSync,
}) async {
  if (debounce) {
    documentSessionAutosave.bindCommit(
      ({
        required BuildContext context,
        required FileStoragePort storage,
        required DocumentTabsController tabs,
        required DocumentSession session,
        required Uint8List bytes,
        required String successMessage,
        String? saveAsReason,
        String? suggestedName,
        bool quiet = true,
        bool silent = false,
      }) => commitBytesToSession(
        context: context,
        storage: storage,
        tabs: tabs,
        session: session,
        bytes: bytes,
        successMessage: successMessage,
        saveAsReason: saveAsReason,
        suggestedName: suggestedName,
        quiet: quiet,
        silent: silent,
      ),
    );
    final completer = _DebounceCompleter();
    documentSessionAutosave.schedule(
      context: context,
      storage: storage,
      tabs: tabs,
      session: session,
      bytes: bytes,
      successMessage: successMessage,
      saveAsReason: saveAsReason,
      suggestedName: suggestedName,
      quiet: quiet,
      onComplete: completer.complete,
    );
    return completer.future;
  }
  final outcome = await session.commitBytes(bytes);
  if (outcome == DocumentSaveOutcome.needsSaveAs) {
    // Working copy could not be written (extreme temp failure). Offer Save As
    // as a last resort so the edit is not lost — still not an Apply→disk path.
    if (!context.mounted) return null;
    final reason =
        saveAsReason ??
        'Could not update the working copy. Choose a location to keep your changes.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reason)));
    final saved = await session.saveAs(
      storage,
      suggestedName: suggestedName ?? session.file.displayName,
    );
    if (saved == null) return null;
    beforeTabSync?.call();
    tabs.syncActiveTabFromSession();
    if (context.mounted && !silent) {
      showDocumentSaveResultActions(
        context,
        file: saved,
        password: session.password,
        message: '$successMessage (saved as ${saved.displayName})',
        showOpenInViewer: false,
      );
    }
    return saved;
  }

  beforeTabSync?.call();
  tabs.syncActiveTabFromSession();
  if (context.mounted && !silent) {
    if (quiet) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage.isEmpty ? 'Applied' : successMessage),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      showDocumentSaveResultActions(
        context,
        file: session.file,
        password: session.password,
        message: successMessage,
        showOpenInViewer: false,
        showEditInWorkspace: false,
      );
    }
  }
  return session.file;
}

/// Commits a temp PDF into the active viewer session (working copy + undo).
Future<LocalFileRef?> commitTempPathToActiveSession({
  required WidgetRef ref,
  required BuildContext context,
  required String tempPath,
  required String successMessage,
  void Function(DocumentSession session)? configureSession,
}) async {
  final tabs = ref.read(documentTabsControllerProvider);
  final session = tabs.activeSession;
  if (session == null) return null;
  final outcome = await session.commitTempFile(tempPath);
  if (outcome == DocumentSaveOutcome.needsSaveAs) {
    final bytes = session.pendingReplaceBytes;
    if (bytes == null) return null;
    if (!context.mounted) return null;
    final saved = await commitBytesToSession(
      context: context,
      storage: ref.read(fileStorageProvider),
      tabs: tabs,
      session: session,
      bytes: bytes,
      successMessage: successMessage,
    );
    if (saved != null) configureSession?.call(session);
    return saved;
  }
  configureSession?.call(session);
  tabs.syncActiveTabFromSession();
  if (context.mounted) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(successMessage.isEmpty ? 'Applied' : successMessage),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
  return session.file;
}

/// Commits assembled organize export into the active session when present.
Future<LocalFileRef?> commitOrganizeExport({
  required WidgetRef ref,
  required BuildContext context,
  required List<int> bytes,
  required String successMessage,
  String? suggestedName,
  DocumentSession? session,
}) async {
  final tabs = ref.read(documentTabsControllerProvider);
  final active = session ?? tabs.activeSession;
  final storage = ref.read(fileStorageProvider);
  final data = Uint8List.fromList(bytes);

  if (active != null) {
    return commitBytesToSession(
      context: context,
      storage: storage,
      tabs: tabs,
      session: active,
      bytes: data,
      successMessage: successMessage,
      suggestedName: suggestedName,
    );
  }

  final path = await storage.pickSavePath(
    suggestedName: suggestedName ?? 'document.pdf',
    bytes: data,
    allowedExtensions: const ['pdf'],
    mimeType: 'application/pdf',
  );
  if (path == null) return null;
  await storage.writeAtomic(
    destinationPath: path,
    writeToTemp: (temp) async {
      await File(temp).writeAsBytes(data, flush: true);
    },
  );
  final out = LocalFileRef(path: path, displayName: p.basename(path));
  if (context.mounted) {
    showDocumentSaveResultActions(context, file: out, message: successMessage);
  }
  return out;
}

/// Completer used when [commitBytesToSession] schedules via autosave debounce.
class _DebounceCompleter {
  final _c = Completer<LocalFileRef?>();
  Future<LocalFileRef?> get future => _c.future;
  void complete(LocalFileRef? value) {
    if (!_c.isCompleted) _c.complete(value);
  }
}
