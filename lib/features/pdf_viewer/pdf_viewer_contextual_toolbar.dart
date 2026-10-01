import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_tool_panel_scope.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:flutter/material.dart';

/// Secondary toolbar shown while a viewer tool panel is active (Acrobat-style).
class PdfViewerContextualToolBar extends StatelessWidget {
  const PdfViewerContextualToolBar({
    super.key,
    required this.activeTool,
    required this.onClose,
  });

  final ViewerToolId activeTool;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark
        ? DsColors.surfaceContainerDark
        : DsColors.surfaceContainerLight;
    final borderColor = isDark ? DsColors.borderDark : DsColors.borderLight;

    return Material(
      key: const Key('pdf_viewer_contextual_toolbar'),
      color: bg,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: DsSpacing.sm),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: borderColor)),
        ),
        child: Row(
          children: [
            Text(
              activeTool.panelTitle,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(width: DsSpacing.md),
            ..._quickActions(context, activeTool),
            const Spacer(),
            OutlinedButton(
              key: const Key('pdf_viewer_contextual_toolbar_close'),
              onPressed: onClose,
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _quickActions(BuildContext context, ViewerToolId tool) {
    final related = _relatedTools(tool);
    if (related.isEmpty) return const [];
    return [
      for (final id in related)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: TextButton(
            onPressed: () => openViewerToolPanel(context, id),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(id.panelTitle),
          ),
        ),
    ];
  }

  List<ViewerToolId> _relatedTools(ViewerToolId tool) {
    return switch (tool) {
      ViewerToolId.crop => const [
          ViewerToolId.headersFooters,
          ViewerToolId.watermark,
        ],
      ViewerToolId.watermark => const [
          ViewerToolId.headersFooters,
          ViewerToolId.pageNumbers,
        ],
      ViewerToolId.headersFooters => const [
          ViewerToolId.watermark,
          ViewerToolId.pageNumbers,
        ],
      ViewerToolId.pageNumbers => const [
          ViewerToolId.headersFooters,
          ViewerToolId.watermark,
        ],
      ViewerToolId.exportImages ||
      ViewerToolId.exportJpg ||
      ViewerToolId.exportPng =>
        const [ViewerToolId.exportJpg, ViewerToolId.exportPng],
      _ => const [],
    };
  }
}
