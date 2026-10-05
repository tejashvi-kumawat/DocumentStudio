import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_sidebar_content.dart';
import 'package:flutter/material.dart';

/// Compact tab strip for the left viewer rail (thumbnails / bookmarks / attachments).
class PdfViewerSidebarTabs extends StatelessWidget {
  const PdfViewerSidebarTabs({
    super.key,
    required this.content,
    required this.onContentChanged,
  });

  final PdfViewerSidebarContent content;
  final ValueChanged<PdfViewerSidebarContent> onContentChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;

    return Material(
      color: isDark
          ? DsColors.surfaceContainerDark
          : DsColors.surfaceContainerLight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _Tab(
                key: const Key('pdf_sidebar_tab_thumbnails'),
                tooltip: 'Page thumbnails',
                icon: Icons.view_agenda_outlined,
                selected: content == PdfViewerSidebarContent.thumbnails,
                onTap: () =>
                    onContentChanged(PdfViewerSidebarContent.thumbnails),
              ),
              _Tab(
                key: const Key('pdf_sidebar_tab_outline'),
                tooltip: 'Bookmarks',
                icon: Icons.bookmarks_outlined,
                selected: content == PdfViewerSidebarContent.outline,
                onTap: () => onContentChanged(PdfViewerSidebarContent.outline),
              ),
              _Tab(
                key: const Key('pdf_sidebar_tab_attachments'),
                tooltip: 'Attachments',
                icon: Icons.attach_file_outlined,
                selected: content == PdfViewerSidebarContent.attachments,
                onTap: () =>
                    onContentChanged(PdfViewerSidebarContent.attachments),
              ),
              _Tab(
                key: const Key('pdf_sidebar_tab_search'),
                tooltip: 'Search results',
                icon: Icons.manage_search,
                selected: content == PdfViewerSidebarContent.search,
                onTap: () => onContentChanged(PdfViewerSidebarContent.search),
              ),
            ],
          ),
          Divider(height: 1, color: border),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
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
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 36,
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}
