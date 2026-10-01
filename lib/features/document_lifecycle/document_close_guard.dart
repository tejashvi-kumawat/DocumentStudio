import 'package:document_studio/app/providers.dart';
import 'package:document_studio/app/router/app_router.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/design_system/adaptive/ds_adaptive.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/features/document_lifecycle/document_session.dart';
import 'package:document_studio/features/pdf_viewer/document_tabs_controller.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// User choice when closing a dirty document.
enum DirtyCloseChoice { save, discard, cancel }

/// Asks whether to save unsaved Apply changes before closing.
Future<DirtyCloseChoice> promptDirtyDocumentClose(
  BuildContext context, {
  required String documentName,
}) async {
  if (context.dsIsApple) {
    final result = await showCupertinoDialog<DirtyCloseChoice>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Save changes?'),
        content: Text(
          '“$documentName” has unsaved changes. Save before closing?',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(DirtyCloseChoice.cancel),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(DirtyCloseChoice.discard),
            child: const Text('Don\'t Save'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(DirtyCloseChoice.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return result ?? DirtyCloseChoice.cancel;
  }

  final result = await showGeneralDialog<DirtyCloseChoice>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Save changes?',
    transitionDuration: DsMotion.dialogDuration,
    transitionBuilder: (ctx, a, _, child) =>
        DsMotion.fadeScaleTransition(a, child),
    pageBuilder: (ctx, _, _) => AlertDialog(
      title: const Text('Save changes?'),
      content: Text(
        '“$documentName” has unsaved changes. Save before closing?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(DirtyCloseChoice.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(DirtyCloseChoice.discard),
          child: const Text('Don\'t Save'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(DirtyCloseChoice.save),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  return result ?? DirtyCloseChoice.cancel;
}

/// Saves [session] in place or via Save As. Returns false if the user cancelled.
Future<bool> saveDocumentSessionExplicitly({
  required BuildContext context,
  required FileStoragePort storage,
  required DocumentTabsController tabs,
  required DocumentSession session,
}) async {
  final outcome = await session.save();
  if (outcome == DocumentSaveOutcome.needsSaveAs) {
    if (!context.mounted) return false;
    final saved = await session.saveAs(storage);
    if (saved == null) return false;
    tabs.syncActiveTabFromSession();
    return true;
  }
  tabs.syncActiveTabFromSession();
  return true;
}

/// Confirms (and optionally saves) before closing a dirty tab. Returns whether
/// the tab may be closed.
Future<bool> confirmCloseDocumentTab({
  required BuildContext context,
  required WidgetRef ref,
  required DocumentTabsController tabs,
  required int index,
}) async {
  if (index < 0 || index >= tabs.tabs.length) return false;
  final session = tabs.tabs[index].session;
  if (!session.isDirty) return true;

  final choice = await promptDirtyDocumentClose(
    context,
    documentName: session.file.displayName,
  );
  if (!context.mounted) return false;
  switch (choice) {
    case DirtyCloseChoice.cancel:
      return false;
    case DirtyCloseChoice.discard:
      return true;
    case DirtyCloseChoice.save:
      return saveDocumentSessionExplicitly(
        context: context,
        storage: ref.read(fileStorageProvider),
        tabs: tabs,
        session: session,
      );
  }
}

/// Prompts for every dirty open document before quitting. Returns whether the
/// app may exit.
Future<bool> confirmCloseAllDirtyDocuments({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final tabs = ref.read(documentTabsControllerProvider);
  final dirty = [
    for (var i = 0; i < tabs.tabs.length; i++)
      if (tabs.tabs[i].session.isDirty) i,
  ];
  if (dirty.isEmpty) return true;

  for (final index in dirty) {
    if (!context.mounted) return false;
    // Activate so Save As / messages refer to the right document.
    tabs.activateTab(index);
    final ok = await confirmCloseDocumentTab(
      context: context,
      ref: ref,
      tabs: tabs,
      index: index,
    );
    if (!ok) return false;
  }
  return true;
}

/// Convenience when only a [BuildContext] + [WidgetRef] are available.
Future<bool> requestCloseDocumentTab(
  BuildContext context,
  WidgetRef ref,
  int index,
) {
  final tabs = ref.read(documentTabsControllerProvider);
  return confirmCloseDocumentTab(
    context: context,
    ref: ref,
    tabs: tabs,
    index: index,
  );
}

/// Root-navigator helper for window-close / quit flows.
Future<bool> requestQuitWithDirtyPrompt(WidgetRef ref) async {
  final ctx = rootNavigatorKey.currentContext;
  if (ctx == null || !ctx.mounted) return true;
  return confirmCloseAllDirtyDocuments(context: ctx, ref: ref);
}
