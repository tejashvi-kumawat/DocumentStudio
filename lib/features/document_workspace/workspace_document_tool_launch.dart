import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/organize/organize_page_ref.dart';
import 'package:document_studio/features/page_management/organize_workspace_notifier.dart';
import 'package:document_studio/features/pdf_viewer/shell_pdf_open.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Resolves which imported PDF a workspace document-level tool should run on.
///
/// Preference: highlighted source → first selected page's source → primary import.
LocalFileRef? resolveWorkspaceTargetDocument({
  required List<LocalFileRef> importedFiles,
  required List<OrganizePageRef> pages,
  required Set<String> selectedIds,
  String? highlightSourcePath,
}) {
  if (importedFiles.isEmpty) return null;

  final highlight = highlightSourcePath;
  if (highlight != null && highlight.isNotEmpty) {
    for (final f in importedFiles) {
      if (f.path == highlight) return f;
    }
  }

  if (selectedIds.isNotEmpty) {
    for (final page in pages) {
      if (selectedIds.contains(page.id)) return page.file;
    }
  }

  return importedFiles.first;
}

/// Opens [file] in the shell viewer and queues [tool] (same path as Tools/viewer).
Future<void> launchWorkspaceDocumentTool({
  required BuildContext context,
  required WidgetRef ref,
  required LocalFileRef file,
  required ViewerToolId tool,
  String? password,
}) async {
  await openPdfInShellViewer(
    context,
    ref,
    file,
    password: password,
    openToolPanel: tool,
  );
}

/// Convenience: resolve target from [state] then open viewer with [tool].
/// Returns false when no document is available.
bool launchWorkspaceToolOnSelection({
  required BuildContext context,
  required WidgetRef ref,
  required OrganizeWorkspaceState state,
  required ViewerToolId tool,
  Map<String, String> passwordsByPath = const {},
}) {
  final file = resolveWorkspaceTargetDocument(
    importedFiles: state.importedFiles,
    pages: state.pages,
    selectedIds: state.selectedIds,
    highlightSourcePath: state.highlightSourcePath,
  );
  if (file == null) return false;
  launchWorkspaceDocumentTool(
    context: context,
    ref: ref,
    file: file,
    tool: tool,
    password: passwordsByPath[file.path],
  );
  return true;
}
