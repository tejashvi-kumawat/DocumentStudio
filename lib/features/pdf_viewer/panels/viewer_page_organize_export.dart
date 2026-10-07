import 'package:document_studio/features/pdf_viewer/viewer_pending_page.dart';

import 'dart:typed_data';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/domain/organize/organize_page_ref.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Map<String, String>? passwordsMapForHandoff(PdfViewerDocumentHandoff handoff) {
  final pw = handoff.password;
  if (pw == null || pw.isEmpty) return null;
  return {handoff.file.path: pw};
}

/// Writes [pages] into the open session working copy.
///
/// Does not save the original file and does not remount the viewer.
Future<void> commitOrganizePagesInSession({
  required WidgetRef ref,
  required BuildContext context,
  required PdfViewerDocumentHandoff handoff,
  required List<OrganizePageRef> pages,
  required String successMessage,
  Map<String, String>? passwordsByPath,
  bool unlockMismatchedPasswords = false,

  /// Page to show afterwards (e.g. first inserted page). Default: wherever the
  /// current page moved to.
  int? focusPage1Based,
}) async {
  if (pages.isEmpty) {
    throw StateError('No pages to update');
  }
  final tabs = ref.read(documentTabsControllerProvider);
  final session = tabs.activeSession;
  if (session == null) {
    throw StateError('No open document to update.');
  }
  final openPassword = session.password ?? handoff.password;
  final passwords = <String, String>{
    ...?passwordsMapForHandoff(handoff),
    if (openPassword != null && openPassword.isNotEmpty)
      session.file.path: openPassword,
    ...?passwordsByPath,
  };
  final organize = ref.read(pageOrganizeServiceProvider);
  final assembled = await organize.assembleWorkspaceExport(
    pages: pages,
    passwordsByPath: passwords.isEmpty ? null : passwords,
    unlockMismatchedPasswords: unlockMismatchedPasswords,
  );
  if (!context.mounted) return;
  ViewerPendingPage.set(
    focusPage1Based ??
        remapPageAfterOrganize(
          pages: pages,
          sourcePath: session.file.path,
          oldPage: handoff.currentPage1,
        ),
  );
  await commitBytesToSession(
    context: context,
    storage: ref.read(fileStorageProvider),
    tabs: tabs,
    session: session,
    bytes: Uint8List.fromList(assembled.bytes),
    successMessage: successMessage,
  );
}

/// Exports organize pages into the open document session (in-place) when possible.
Future<void> exportOrganizePagesAndPromptSave({
  required WidgetRef ref,
  required BuildContext context,
  required PdfViewerDocumentHandoff handoff,
  required List<OrganizePageRef> pages,
  required String suggestedName,
  required String successMessage,
}) async {
  if (pages.isEmpty) {
    throw StateError('No pages to export');
  }
  final organize = ref.read(pageOrganizeServiceProvider);
  final assembled = await organize.assembleWorkspaceExport(
    pages: pages,
    passwordsByPath: passwordsMapForHandoff(handoff),
  );
  if (!context.mounted) return;

  final tabs = ref.read(documentTabsControllerProvider);
  final session = tabs.activeSession;
  // Prefer in-place when the open tab is this file.
  final sameOpen =
      session != null && session.sameDocumentPath(handoff.file.path);

  await commitOrganizeExport(
    ref: ref,
    context: context,
    bytes: assembled.bytes,
    successMessage: successMessage,
    suggestedName: suggestedName,
    session: sameOpen ? session : null,
  );
}

/// Batch/organize panels: export [pages] with optional password map.
Future<void> exportViewerOrganizePages({
  required WidgetRef ref,
  required BuildContext context,
  required PdfViewerDocumentHandoff handoff,
  required List<OrganizePageRef> pages,
  required String suggestedName,
  required String successMessage,
  Map<String, String>? passwordsByPath,
}) {
  return exportOrganizePagesAndPromptSave(
    ref: ref,
    context: context,
    handoff: handoff,
    pages: pages,
    suggestedName: suggestedName,
    successMessage: successMessage,
  );
}
