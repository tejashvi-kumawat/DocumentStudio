import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_acrobat_tool_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:flutter/material.dart';

/// Honest blocked-state body for viewer embedded tools.
class ViewerBlockedToolPanel extends StatelessWidget {
  const ViewerBlockedToolPanel({
    super.key,
    required this.title,
    required this.reason,
    required this.handoff,
    this.alternativeToolId,
    this.alternativeLabel,
  });

  final String title;
  final String reason;
  final PdfViewerDocumentHandoff handoff;
  final String? alternativeToolId;
  final String? alternativeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(DsSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: DsSpacing.sm),
          Text(
            reason,
            key: const Key('viewer_blocked_tool_reason'),
            style: theme.textTheme.bodyMedium,
          ),
          if (alternativeToolId != null && alternativeLabel != null) ...[
            const SizedBox(height: DsSpacing.md),
            FilledButton.tonal(
              key: const Key('viewer_blocked_tool_alternative'),
              onPressed: () {
                runPdfViewerAcrobatTool(
                  context: context,
                  handoff: handoff,
                  toolId: alternativeToolId!,
                );
              },
              child: Text(alternativeLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
