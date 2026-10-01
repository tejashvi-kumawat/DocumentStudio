import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_scaffold.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_tool_panel_scope.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:flutter/material.dart';

/// One open session cannot hold two documents to move pages between.
///
/// Insert and replace already bring pages from another file into this PDF.
class ViewerMoveBetweenPanel extends StatelessWidget {
  const ViewerMoveBetweenPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ViewerToolFormScaffold(
      primaryKey: const Key('viewer_move_between_insert'),
      primaryLabel: 'Insert pages',
      primaryIcon: Icons.note_add_outlined,
      onPrimary: () =>
          openViewerToolPanel(context, ViewerToolId.workspaceInsert),
      children: [
        Text(
          'This viewer keeps one open document, so pages cannot be moved '
          'between two open documents. Insert pages from another PDF into '
          'this document, or replace pages here from another PDF.',
          style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () =>
                openViewerToolPanel(context, ViewerToolId.workspaceReplace),
            icon: const Icon(Icons.find_replace_outlined, size: 18),
            label: const Text('Replace pages'),
          ),
        ),
      ],
    );
  }
}
