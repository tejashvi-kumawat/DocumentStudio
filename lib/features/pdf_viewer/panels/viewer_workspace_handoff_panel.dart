import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_scaffold.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:flutter/material.dart';

/// Explains why a tool needs the full workspace grid and offers one handoff.
class ViewerWorkspaceHandoffPanel extends StatelessWidget {
  const ViewerWorkspaceHandoffPanel({
    super.key,
    required this.title,
    required this.reason,
    required this.handoff,
  });

  final String title;
  final String reason;
  final PdfViewerDocumentHandoff handoff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ViewerToolFormScaffold(
      primaryKey: const Key('viewer_workspace_handoff_open'),
      primaryLabel: 'Open workspace',
      primaryIcon: Icons.dashboard_customize_outlined,
      onPrimary: () =>
          PdfViewerDocumentActions.openDocumentWorkspace(context, handoff),
      children: [
        Text(title, style: theme.textTheme.labelLarge?.copyWith(fontSize: 13)),
        const SizedBox(height: 4),
        Text(reason, style: theme.textTheme.bodySmall?.copyWith(fontSize: 12)),
      ],
    );
  }
}
