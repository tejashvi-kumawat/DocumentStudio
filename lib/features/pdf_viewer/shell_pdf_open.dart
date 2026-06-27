import 'package:document_studio/core/storage/linux_document_portal.dart';
import 'package:document_studio/features/pdf_viewer/document_tabs_controller.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Opens [file] in the shell document tab strip and shows the viewer on Home branch.
///
/// Portal paths are resolved to the host file first so one document is one tab
/// and the viewer never scans the slow xdg-document-portal FUSE mount.
Future<void> openPdfInDocumentTabs(
  WidgetRef ref,
  LocalFileRef file, {
  String? password,
  ViewerToolId? openToolPanel,
}) async {
  // Always await host resolve BEFORE openDocument so DocumentSession /
  // PdfDocumentRefKey / hardlink never see `/run/user/…/doc/…`.
  final host = await LinuxDocumentPortal.resolve(file.path);
  final resolved =
      host == file.path ? file : file.copyWithPath(host);
  final tabs = ref.read(documentTabsControllerProvider);
  await tabs.openDocument(
    resolved,
    password: password,
    openToolPanel: openToolPanel,
  );
}

/// Ensures the app is on Home branch (`/`) after tab changes.
void goToShellHomeBranch(BuildContext context) {
  final path = GoRouterState.of(context).uri.path;
  if (path == '/' || path.startsWith('/viewer')) {
    if (path.startsWith('/viewer')) {
      context.go('/');
    }
    return;
  }
  context.go('/');
}

/// Opens a PDF in tabs and navigates to the shell home branch viewer.
Future<void> openPdfInShellViewer(
  BuildContext context,
  WidgetRef ref,
  LocalFileRef file, {
  String? password,
  ViewerToolId? openToolPanel,
}) async {
  await openPdfInDocumentTabs(
    ref,
    file,
    password: password,
    openToolPanel: openToolPanel,
  );
  if (!context.mounted) return;
  goToShellHomeBranch(context);
}

extension DocumentTabsOpenTool on DocumentTabsController {
  /// Activates the document viewer and queues [tool] for the embedded panel.
  void showDocumentWithTool(ViewerToolId tool) {
    if (!hasTabs) return;
    showDocument();
    queueViewerToolPanel(tool);
  }
}
