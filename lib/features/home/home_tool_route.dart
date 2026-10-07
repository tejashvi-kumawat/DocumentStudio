import 'package:document_studio/app/providers.dart';
import 'package:document_studio/app/shell/shell_navigation_context.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/errors/document_studio_error_ui.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/home/home_tool.dart';
import 'package:document_studio/features/conversion/conversion_route.dart';
import 'package:document_studio/features/pdf_viewer/pdf_document_route_args.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/features/pdf_viewer/shell_pdf_open.dart';
import 'package:document_studio/features/pdf_viewer/viewer_route_args.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Opens a tool route, attaching [PdfDocumentRouteArgs] when the shell still
/// holds an open-document handoff (viewer tabs or recent viewer launch).
Future<void> pushHomeToolRoute(
  BuildContext context,
  WidgetRef ref,
  String path, {
  required HomeToolDocumentEntry documentEntry,
}) async {
  if (documentEntry == HomeToolDocumentEntry.requiresOpenPdf) {
    await openHomeToolOnOpenDocument(context, ref, path);
    return;
  }

  Object? extra;
  if (documentEntry != HomeToolDocumentEntry.standalone) {
    extra = ref.read(shellNavigationContextProvider).activeDocument;
  }
  if (!context.mounted) return;
  context.push(path, extra: extra);
}

/// Picks or reuses an open PDF, lands on the shell viewer, and opens the tool panel when supported.
Future<void> openHomeToolOnOpenDocument(
  BuildContext context,
  WidgetRef ref,
  String toolRoutePath,
) async {
  final panelTool = viewerToolIdFromToolRoutePath(toolRoutePath);
  final tabs = ref.read(documentTabsControllerProvider);
  LocalFileRef? file = tabs.hasTabs ? tabs.activeTab?.file : null;
  file ??= ref.read(shellNavigationContextProvider).activeDocument?.file;

  if (file == null) {
    final storage = ref.read(fileStorageProvider);
    try {
      final picked = await storage.pickOpenFile(allowedExtensions: ['pdf']);
      if (picked == null || !context.mounted) return;
      file = picked;
    } on DocumentStudioError catch (e) {
      if (!context.mounted) return;
      showDocumentStudioErrorSnackBar(context, e);
      return;
    }
  }

  if (!context.mounted) return;

  await openPdfInShellViewer(context, ref, file, openToolPanel: panelTool);
}

/// Call before pushing a tool from the PDF viewer so Cancel returns to viewer.
void rememberViewerToolReturnFromContext(BuildContext context, Object args) {
  final LocalFileRef file;
  final String? password;
  if (args is PdfDocumentRouteArgs) {
    file = args.file;
    password = args.password;
  } else if (args is PdfToImagesRouteArgs) {
    file = args.file;
    password = args.password;
  } else if (args is ViewerRouteArgs) {
    file = args.file;
    password = args.password;
  } else {
    return;
  }
  ProviderScope.containerOf(context)
      .read(shellNavigationContextProvider.notifier)
      .rememberToolReturnFromViewer(
        ViewerRouteArgs(file: file, password: password),
      );
}
