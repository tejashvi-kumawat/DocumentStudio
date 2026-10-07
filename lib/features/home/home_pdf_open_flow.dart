import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/errors/document_studio_error_ui.dart';
import 'package:document_studio/core/storage/home_pdf_open_mode_repository.dart';
import 'package:document_studio/core/storage/linux_document_portal.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/home/home_pdf_open_chooser.dart';
import 'package:document_studio/features/home/home_pdf_open_mode.dart';
import 'package:document_studio/features/page_management/pdf_password_prompt.dart';
import 'package:document_studio/features/pdf_viewer/shell_pdf_open.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Opens the chooser after the user supplies a file (picker or drop).
Future<void> homeShowPdfOpenChooserAndNavigate(
  BuildContext context,
  WidgetRef ref,
  LocalFileRef file,
) async {
  final mode = await showHomePdfOpenChooser(context, file: file);
  if (mode == null || !context.mounted) return;
  await homeOpenPdfWithMode(context, ref, file, mode);
}

Future<HomePdfOpenMode> homeLastOpenModeFor(WidgetRef ref, String path) async {
  final repo = await ref.read(homePdfOpenModeRepositoryProvider.future);
  return repo.modeForPath(path);
}

Future<void> homeOpenPdfWithMode(
  BuildContext context,
  WidgetRef ref,
  LocalFileRef file,
  HomePdfOpenMode mode, {
  String? password,
}) async {
  final modeRepo = await ref.read(homePdfOpenModeRepositoryProvider.future);
  await modeRepo.setMode(file.path, mode);
  if (!context.mounted) return;

  switch (mode) {
    case HomePdfOpenMode.read:
      await _openRead(context, ref, file, password: password);
    case HomePdfOpenMode.editPages:
      await _openEditPages(context, ref, file, password: password);
    case HomePdfOpenMode.compress:
      await ref.read(recentsProvider.notifier).addRecent(file);
      if (!context.mounted) return;
      await openPdfInShellViewer(
        context,
        ref,
        file,
        password: password,
        openToolPanel: ViewerToolId.compress,
      );
    case HomePdfOpenMode.protect:
      await ref.read(recentsProvider.notifier).addRecent(file);
      if (!context.mounted) return;
      await openPdfInShellViewer(
        context,
        ref,
        file,
        password: password,
        openToolPanel: ViewerToolId.protect,
      );
  }
}

Future<void> _openEditPages(
  BuildContext context,
  WidgetRef ref,
  LocalFileRef file, {
  String? password,
}) async {
  // Resolve portal → host before workspace/validate so we never open FUSE.
  final host = await LinuxDocumentPortal.resolve(file.path);
  final resolved = host == file.path ? file : file.copyWithPath(host);
  final pdf = ref.read(pdfRenderPortProvider);
  try {
    await pdf.validateOpenable(resolved, password: password);
    await ref.read(recentsProvider.notifier).addRecent(resolved);
    if (!context.mounted) return;
    context.push('/workspace', extra: resolved);
  } on DocumentStudioError catch (e) {
    if (e.code == DocumentStudioErrorCode.passwordRequired) {
      if (!context.mounted) return;
      final pwd = await promptPdfPassword(context);
      if (pwd == null || !context.mounted) return;
      await _openEditPages(context, ref, resolved, password: pwd);
      return;
    }
    if (!context.mounted) return;
    showDocumentStudioErrorSnackBar(context, e);
  }
}

Future<void> _openRead(
  BuildContext context,
  WidgetRef ref,
  LocalFileRef file, {
  String? password,
}) async {
  // Do NOT validateOpenable here — that opened the portal FUSE path (and
  // sometimes loadAllPages) before shell resolve, producing a second cache
  // entry. Viewer warm-lease is the single open.
  await ref.read(recentsProvider.notifier).addRecent(file);
  if (!context.mounted) return;
  await openPdfInShellViewer(context, ref, file, password: password);
}

final homePdfOpenModeRepositoryProvider =
    FutureProvider<HomePdfOpenModeRepository>((ref) async {
      return HomePdfOpenModeRepository.create();
    });
