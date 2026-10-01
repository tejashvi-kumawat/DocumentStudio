import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/annotations/markup/markup_editor_controller.dart';
import 'package:document_studio/features/annotations/markup/markup_tool.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_tool_panel_scope.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:flutter/material.dart';

/// Open-PDF tool row, most-used actions first.
///
/// Order: Organize, Crop, Rotate, Edit, Convert, Encrypt, Decrypt, Tools.
/// Drawing tools live in the left comment bar, not a Pencil menu. The row
/// scrolls on a narrow window or phone. There is no More menu.
class PdfViewerToolRow extends StatelessWidget {
  const PdfViewerToolRow({
    super.key,
    required this.enabled,
    required this.markup,
    required this.onArmMarkup,
    required this.onAllTools,
    this.allToolsOpen = false,
    this.leading,
  });

  static const height = 48.0;

  final bool enabled;
  final MarkupEditorController markup;

  /// Single comment-bar button, docked to the left of this row.
  final Widget? leading;

  /// Arms select / edit on the open page without opening a side panel.
  final ValueChanged<MarkupTool> onArmMarkup;
  final VoidCallback onAllTools;
  final bool allToolsOpen;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark
            ? DsColors.surfaceContainerDark
            : DsColors.surfaceContainerLight,
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: SizedBox(
        height: height,
        child: ListenableBuilder(
          listenable: markup,
          builder: (context, _) {
            final editArmed =
                markup.editMode && markup.tool == MarkupTool.select;
            return Row(
              children: [
                ?leading,
                Expanded(
                  child: ListView(
                    key: const Key('pdf_viewer_tool_row'),
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: DsSpacing.xs,
                    ),
                    children: [
                      _DirectButton(
                        buttonKey: const Key('pdf_viewer_tool_organize'),
                        label: 'Organize',
                        icon: Icons.grid_view_outlined,
                        enabled: enabled,
                        onPressed: () => openViewerToolPanel(
                          context,
                          ViewerToolId.workspaceReorder,
                        ),
                      ),
                      _DirectButton(
                        buttonKey: const Key('pdf_viewer_tool_crop'),
                        label: 'Crop',
                        icon: Icons.crop,
                        enabled: enabled,
                        onPressed: () =>
                            openViewerToolPanel(context, ViewerToolId.crop),
                      ),
                      _DirectButton(
                        buttonKey: const Key('pdf_viewer_tool_rotate'),
                        label: 'Rotate',
                        icon: Icons.rotate_90_degrees_ccw_outlined,
                        enabled: enabled,
                        onPressed: () =>
                            openViewerToolPanel(context, ViewerToolId.rotate),
                      ),
                      _DirectButton(
                        buttonKey: const Key('pdf_viewer_tool_edit'),
                        label: 'Edit',
                        icon: Icons.edit_outlined,
                        enabled: enabled,
                        selected: editArmed,
                        onPressed: () => onArmMarkup(MarkupTool.select),
                      ),
                      _MenuButton(
                        buttonKey: const Key('pdf_viewer_tool_convert'),
                        label: 'Convert',
                        icon: Icons.swap_horiz,
                        enabled: enabled,
                        entries: [
                          _Entry(
                            'Convert to Office',
                            Icons.description_outlined,
                            () {
                              openViewerToolPanel(
                                context,
                                ViewerToolId.officeConvert,
                              );
                            },
                          ),
                          _Entry('Export to images', Icons.image_outlined, () {
                            openViewerToolPanel(
                              context,
                              ViewerToolId.exportImages,
                            );
                          }),
                          _Entry('Export to JPG', Icons.photo_outlined, () {
                            openViewerToolPanel(
                              context,
                              ViewerToolId.exportJpg,
                            );
                          }),
                          _Entry('Export to PNG', Icons.image_outlined, () {
                            openViewerToolPanel(
                              context,
                              ViewerToolId.exportPng,
                            );
                          }),
                        ],
                      ),
                      _DirectButton(
                        buttonKey: const Key('pdf_viewer_tool_encrypt'),
                        label: 'Encrypt',
                        icon: Icons.lock_outline,
                        enabled: enabled,
                        onPressed: () =>
                            openViewerToolPanel(context, ViewerToolId.protect),
                      ),
                      _DirectButton(
                        buttonKey: const Key('pdf_viewer_tool_decrypt'),
                        label: 'Decrypt',
                        icon: Icons.lock_open_outlined,
                        enabled: enabled,
                        onPressed: () =>
                            openViewerToolPanel(context, ViewerToolId.unlock),
                      ),
                      _DirectButton(
                        buttonKey: const Key('pdf_viewer_tool_all'),
                        label: 'Tools',
                        icon: Icons.apps_outlined,
                        enabled: true,
                        selected: allToolsOpen,
                        emphasize: true,
                        onPressed: onAllTools,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Entry {
  const _Entry(this.label, this.icon, this.onSelected);

  final String label;
  final IconData icon;
  final VoidCallback onSelected;
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.buttonKey,
    required this.label,
    required this.icon,
    required this.entries,
    required this.enabled,
  });

  final Key buttonKey;
  final String label;
  final IconData icon;
  final List<_Entry> entries;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        for (final entry in entries)
          MenuItemButton(
            leadingIcon: Icon(entry.icon, size: 18),
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(0, 40)),
            ),
            onPressed: enabled ? entry.onSelected : null,
            child: Text(entry.label),
          ),
      ],
      builder: (context, menu, _) {
        final open = menu.isOpen;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: TextButton(
            key: buttonKey,
            onPressed: enabled ? () => open ? menu.close() : menu.open() : null,
            style: TextButton.styleFrom(
              minimumSize: const Size(40, 40),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              foregroundColor: open
                  ? DsColors.primary
                  : theme.colorScheme.onSurface,
              backgroundColor: open
                  ? DsColors.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(open ? Icons.expand_less : Icons.expand_more, size: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DirectButton extends StatelessWidget {
  const _DirectButton({
    required this.buttonKey,
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
    this.selected = false,
    this.emphasize = false,
  });

  final Key buttonKey;
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;
  final bool selected;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = selected || emphasize;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: TextButton(
        key: buttonKey,
        onPressed: enabled ? onPressed : null,
        style: TextButton.styleFrom(
          minimumSize: const Size(40, 40),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          foregroundColor: active
              ? DsColors.primary
              : theme.colorScheme.onSurface,
          backgroundColor: active
              ? DsColors.primary.withValues(alpha: emphasize ? 0.10 : 0.12)
              : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
