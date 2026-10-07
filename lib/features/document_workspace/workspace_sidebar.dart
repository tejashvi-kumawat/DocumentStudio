import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_shell_page.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/organize/organize_page_ref.dart';
import 'package:flutter/material.dart';

enum WorkspaceSidebarAction { addPdf }

/// Document list + document-level actions.
///
/// Desktop/tablet: fixed [railWidth] rail. Phone: [fullWidth] list with 16dp
/// padding and 44–48dp rows (no side-by-side squash).
class WorkspaceSidebar extends StatelessWidget {
  const WorkspaceSidebar({
    super.key,
    required this.onAction,
    required this.importedFiles,
    required this.pages,
    this.busy = false,
    this.highlightSourcePath,
    this.onDocumentTap,
    this.onOpenDocument,
    this.fullWidth = false,
    this.padding,
  });

  final void Function(WorkspaceSidebarAction action) onAction;
  final List<LocalFileRef> importedFiles;
  final List<OrganizePageRef> pages;
  final bool busy;
  final String? highlightSourcePath;
  final void Function(LocalFileRef file)? onDocumentTap;

  /// Optional secondary action (e.g. open PDF in viewer) on each row.
  final void Function(LocalFileRef file)? onOpenDocument;

  /// When true, fills the parent width (phone document-list pane).
  final bool fullWidth;

  /// Outer padding; defaults to 16dp when [fullWidth], else rail density.
  final EdgeInsetsGeometry? padding;

  int _pageCountFor(String path) =>
      pages.where((p) => p.file.path == path).length;

  /// Fixed rail width so the page grid is never squeezed by an unbounded side column.
  static const double railWidth = 220;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;
    final sizeClass = dsWindowSizeClassForWidth(
      MediaQuery.sizeOf(context).width,
    );
    final dense = sizeClass != DsWindowSizeClass.expanded;
    final pad = fullWidth
        ? DsSpacing.pagePaddingCompact
        : (dense ? DsSpacing.md : 12.0);
    final rowMin = fullWidth ? DsSpacing.compactTouchTarget : 36.0;

    const docActions = <_Item>[
      _Item('Add PDF', Icons.add, WorkspaceSidebarAction.addPdf),
    ];

    final body = ListView(
      padding:
          padding ??
          EdgeInsets.symmetric(
            vertical: fullWidth
                ? DsSpacing.md
                : (dense ? DsSpacing.sm : DsSpacing.md),
            horizontal: fullWidth ? 0 : 0,
          ),
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            pad,
            fullWidth ? DsSpacing.sm : (dense ? DsSpacing.sm : 12),
            pad,
            6,
          ),
          child: Text(
            'DOCUMENTS',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (importedFiles.isEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 4, pad, 8),
            child: Text(
              'No PDFs in this workspace yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final file in importedFiles)
            ListTile(
              dense: !fullWidth,
              visualDensity: fullWidth
                  ? VisualDensity.standard
                  : VisualDensity.compact,
              minVerticalPadding: fullWidth ? 10 : 0,
              contentPadding: EdgeInsets.symmetric(horizontal: pad),
              minTileHeight: rowMin,
              selected: highlightSourcePath == file.path,
              onTap: onDocumentTap == null || busy
                  ? null
                  : () => onDocumentTap!(file),
              leading: Icon(
                Icons.picture_as_pdf_outlined,
                size: fullWidth ? 24 : 20,
                color: theme.colorScheme.primary,
              ),
              title: Text(
                file.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: fullWidth
                    ? theme.textTheme.bodyLarge
                    : theme.textTheme.bodySmall,
              ),
              subtitle: Text(
                '${_pageCountFor(file.path)} page${_pageCountFor(file.path) == 1 ? '' : 's'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
              trailing: onOpenDocument == null
                  ? (fullWidth
                        ? Icon(
                            Icons.chevron_right,
                            color: theme.colorScheme.onSurfaceVariant,
                          )
                        : null)
                  : IconButton(
                      tooltip: 'Open PDF',
                      icon: const Icon(Icons.menu_book_outlined),
                      iconSize: 22,
                      constraints: BoxConstraints(
                        minWidth: rowMin,
                        minHeight: rowMin,
                      ),
                      onPressed: busy ? null : () => onOpenDocument!(file),
                    ),
            ),
        Divider(height: 1, color: border),
        for (final item in docActions)
          _SidebarTile(
            item: item,
            enabled: !busy,
            onTap: () => onAction(item.action),
            fullWidth: fullWidth,
            horizontalPad: pad,
            minHeight: rowMin,
          ),
      ],
    );

    final material = Material(
      color: isDark
          ? DsColors.surfaceContainerDark
          : DsColors.surfaceContainerLight,
      child: fullWidth
          ? body
          : DecoratedBox(
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: border)),
              ),
              child: SizedBox(width: railWidth, child: body),
            ),
    );

    return material;
  }
}

class _Item {
  const _Item(this.label, this.icon, this.action);

  final String label;
  final IconData icon;
  final WorkspaceSidebarAction action;
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.item,
    required this.enabled,
    required this.onTap,
    this.fullWidth = false,
    this.horizontalPad,
    this.minHeight,
  });

  final _Item item;
  final bool enabled;
  final VoidCallback onTap;
  final bool fullWidth;
  final double? horizontalPad;
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: !fullWidth,
      visualDensity: fullWidth ? VisualDensity.standard : VisualDensity.compact,
      enabled: enabled,
      contentPadding: horizontalPad == null
          ? null
          : EdgeInsets.symmetric(horizontal: horizontalPad!),
      minTileHeight: minHeight,
      leading: Icon(item.icon, size: fullWidth ? 22 : 20),
      title: Text(
        item.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: fullWidth
            ? Theme.of(context).textTheme.bodyLarge
            : Theme.of(context).textTheme.bodySmall,
      ),
      onTap: enabled ? onTap : null,
    );
  }
}

/// Compact toolbar menu for document-level workspace actions (narrow layouts).
class WorkspaceCompactMenu extends StatelessWidget {
  const WorkspaceCompactMenu({
    super.key,
    required this.onAction,
    this.busy = false,
  });

  final void Function(WorkspaceSidebarAction action) onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    const items = [_Item('Add PDF', Icons.add, WorkspaceSidebarAction.addPdf)];

    return PopupMenuButton<WorkspaceSidebarAction>(
      tooltip: 'Documents',
      icon: const Icon(Icons.folder_outlined),
      onSelected: onAction,
      itemBuilder: (ctx) => [
        for (final item in items)
          PopupMenuItem(
            value: item.action,
            enabled: !busy,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(item.icon, size: 20),
              title: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    );
  }
}
