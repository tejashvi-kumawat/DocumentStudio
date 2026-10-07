import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_sidebar_content.dart';
import 'package:flutter/material.dart';

/// Narrow Acrobat-style left icon rail (thumbnails, bookmarks, attachments).
class PdfViewerLeftIconRail extends StatelessWidget {
  const PdfViewerLeftIconRail({
    super.key,
    required this.content,
    required this.onContentChanged,
    this.onToggleExpanded,
    this.expanded = true,
    this.controls,
  });

  /// Page / zoom / view controls shown under the panel icons.
  final Widget? controls;

  final PdfViewerSidebarContent content;
  final ValueChanged<PdfViewerSidebarContent> onContentChanged;
  final VoidCallback? onToggleExpanded;
  final bool expanded;

  @visibleForTesting
  static const railWidth = 48.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark
        ? DsColors.surfaceContainerDark
        : DsColors.surfaceContainerLight;
    final borderColor = isDark ? DsColors.borderDark : DsColors.borderLight;

    return Material(
      color: bg,
      child: SizedBox(
        width: railWidth,
        child: Column(
          children: [
            _Icon(
              key: const Key('left_rail_thumbnails'),
              tooltip: 'Page thumbnails',
              icon: Icons.view_agenda_outlined,
              selected: content == PdfViewerSidebarContent.thumbnails,
              onTap: () => onContentChanged(PdfViewerSidebarContent.thumbnails),
            ),
            _Icon(
              key: const Key('left_rail_bookmarks'),
              tooltip: 'Bookmarks',
              icon: Icons.bookmarks_outlined,
              selected: content == PdfViewerSidebarContent.outline,
              onTap: () => onContentChanged(PdfViewerSidebarContent.outline),
            ),
            _Icon(
              key: const Key('left_rail_layers'),
              tooltip: 'Layers (objects on this page)',
              icon: Icons.layers_outlined,
              selected: content == PdfViewerSidebarContent.layers,
              onTap: () => onContentChanged(PdfViewerSidebarContent.layers),
            ),
            _Icon(
              key: const Key('left_rail_attachments'),
              tooltip: 'Attachments',
              icon: Icons.attach_file_outlined,
              selected: content == PdfViewerSidebarContent.attachments,
              onTap: () =>
                  onContentChanged(PdfViewerSidebarContent.attachments),
            ),
            _Icon(
              key: const Key('left_rail_search'),
              tooltip: 'Search results',
              icon: Icons.manage_search,
              selected: content == PdfViewerSidebarContent.search,
              onTap: () => onContentChanged(PdfViewerSidebarContent.search),
            ),
            if (controls case final c?) ...[
              Divider(height: 12, indent: 8, endIndent: 8, color: borderColor),
              Expanded(child: SingleChildScrollView(primary: false, child: c)),
            ] else
              const Spacer(),
            if (onToggleExpanded != null)
              IconButton(
                key: const Key('left_rail_toggle'),
                tooltip: expanded ? 'Hide panel' : 'Show panel',
                icon: Icon(
                  expanded ? Icons.chevron_left : Icons.chevron_right,
                  size: 18,
                ),
                onPressed: onToggleExpanded,
              ),
            Divider(height: 1, color: borderColor),
          ],
        ),
      ),
    );
  }
}

class _Icon extends StatelessWidget {
  const _Icon({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(height: 40, child: Icon(icon, size: 20, color: color)),
      ),
    );
  }
}
