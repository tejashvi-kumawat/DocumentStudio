import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/annotations/markup/markup_editor_controller.dart';
import 'package:document_studio/features/document_lifecycle/document_session.dart';
import 'package:document_studio/features/annotations/markup/markup_tool.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_tool_panel_scope.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:flutter/material.dart';

/// Open-PDF tool row, Acrobat order.
///
/// Edit and Comment are toggles (click again to leave the mode). Related
/// tools share one dropdown: Organize (pages in, out and around), Convert,
/// Protect (encrypt / decrypt / redact), Sign. Everything else lives under
/// Tools. The row scrolls on a narrow window.
class PdfViewerToolRow extends StatelessWidget {
  const PdfViewerToolRow({
    super.key,
    required this.enabled,
    required this.markup,
    required this.onArmMarkup,
    required this.onAllTools,
    this.allToolsOpen = false,
    this.leading,
    this.activeTool,
    this.onToggleEdit,
    this.onToggleComment,
    this.onOpenImageConverter,
    this.history,
    this.onUndo,
    this.onRedo,
    this.onSave,
  });

  /// The open document: Undo / Redo / Save follow its state.
  final DocumentSession? history;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onSave;

  static const height = 48.0;

  final bool enabled;
  final MarkupEditorController markup;

  /// Single comment-bar button, docked to the left of this row.
  final Widget? leading;

  /// Arms select / edit on the open page without opening a side panel.
  final ValueChanged<MarkupTool> onArmMarkup;
  final VoidCallback onAllTools;
  final bool allToolsOpen;

  /// The open tool panel / live mode, so its button shows as on.
  final ViewerToolId? activeTool;

  /// Toggle the Edit PDF mode (click text or images on the page).
  final VoidCallback? onToggleEdit;

  /// Toggle the comment / markup bar.
  final VoidCallback? onToggleComment;

  /// Opens the standalone image converter.
  final VoidCallback? onOpenImageConverter;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;
    void tool(ViewerToolId id) => openViewerToolPanel(context, id);

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
            final commentOn = markup.editMode;
            final editOn = activeTool == ViewerToolId.editText;
            bool on(List<ViewerToolId> ids) => ids.contains(activeTool);
            return Row(
              children: [
                ?leading,
                Expanded(
                  child: ListView(
                    key: const Key('pdf_viewer_tool_row'),
                    scrollDirection: Axis.horizontal,
                    primary: false,
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: DsSpacing.xs,
                    ),
                    children: [
                      _DirectButton(
                        buttonKey: const Key('pdf_viewer_tool_edit'),
                        tooltip: 'Edit PDF — click any text or image (Ctrl+E)',
                        label: 'Edit',
                        icon: Icons.edit_document,
                        enabled: enabled,
                        selected: editOn,
                        onPressed:
                            onToggleEdit ?? () => tool(ViewerToolId.editText),
                      ),
                      _DirectButton(
                        buttonKey: const Key('pdf_viewer_tool_comment'),
                        tooltip: 'Comment — highlight, notes, drawing (Ctrl+Shift+C)',
                        label: 'Comment',
                        icon: Icons.add_comment_outlined,
                        enabled: enabled,
                        selected: commentOn,
                        onPressed:
                            onToggleComment ??
                            () => onArmMarkup(MarkupTool.select),
                      ),
                      _MenuButton(
                        buttonKey: const Key('pdf_viewer_tool_organize'),
                        tooltip: 'Organize pages, insert, split, merge',
                        label: 'Organize',
                        icon: Icons.auto_awesome_mosaic_outlined,
                        enabled: enabled,
                        selected: on(const [
                          ViewerToolId.workspaceReorder,
                          ViewerToolId.workspaceInsert,
                          ViewerToolId.workspaceReplace,
                          ViewerToolId.workspaceMerge,
                          ViewerToolId.extract,
                          ViewerToolId.split,
                          ViewerToolId.deletePages,
                          ViewerToolId.placeImage,
                        ]),
                        entries: [
                          _Entry(
                            'Organize pages',
                            Icons.auto_awesome_mosaic_outlined,
                            () => tool(ViewerToolId.workspaceReorder),
                          ),
                          const _Entry.divider(),
                          _Entry(
                            'Insert pages from file',
                            Icons.note_add_outlined,
                            () => tool(ViewerToolId.workspaceInsert),
                          ),
                          _Entry(
                            'Insert blank page',
                            Icons.insert_page_break_outlined,
                            () => tool(ViewerToolId.insertBlank),
                          ),
                          _Entry(
                            'Insert from scanner / camera',
                            Icons.document_scanner_outlined,
                            () => tool(ViewerToolId.insertScan),
                          ),
                          _Entry(
                            'Add image',
                            Icons.add_photo_alternate_outlined,
                            () => tool(ViewerToolId.placeImage),
                          ),
                          _Entry(
                            'Replace pages',
                            Icons.find_replace,
                            () => tool(ViewerToolId.workspaceReplace),
                          ),
                          const _Entry.divider(),
                          _Entry(
                            'Combine files',
                            Icons.file_copy_outlined,
                            () => tool(ViewerToolId.workspaceMerge),
                          ),
                          _Entry(
                            'Split document',
                            Icons.call_split,
                            () => tool(ViewerToolId.split),
                          ),
                          _Entry(
                            'Extract pages',
                            Icons.content_cut,
                            () => tool(ViewerToolId.extract),
                          ),
                          _Entry(
                            'Delete pages',
                            Icons.delete_outline,
                            () => tool(ViewerToolId.deletePages),
                          ),
                          _Entry(
                            'Duplicate pages',
                            Icons.control_point_duplicate,
                            () => tool(ViewerToolId.duplicate),
                          ),
                          _Entry(
                            'Reverse order',
                            Icons.swap_vert,
                            () => tool(ViewerToolId.reverse),
                          ),
                          const _Entry.divider(),
                          _Entry(
                            'Header & footer',
                            Icons.vertical_align_center,
                            () => tool(ViewerToolId.headersFooters),
                          ),
                          _Entry(
                            'Page numbers',
                            Icons.format_list_numbered,
                            () => tool(ViewerToolId.pageNumbers),
                          ),
                          _Entry(
                            'Watermark',
                            Icons.branding_watermark_outlined,
                            () => tool(ViewerToolId.watermark),
                          ),
                        ],
                      ),
                      _DirectButton(
                        buttonKey: const Key('pdf_viewer_tool_crop'),
                        tooltip: 'Crop pages (Alt+Shift+C)',
                        label: 'Crop',
                        icon: Icons.crop,
                        enabled: enabled,
                        selected: activeTool == ViewerToolId.crop,
                        onPressed: () => tool(ViewerToolId.crop),
                      ),
                      _DirectButton(
                        buttonKey: const Key('pdf_viewer_tool_rotate'),
                        tooltip: 'Rotate pages (Ctrl+Shift++ / −)',
                        label: 'Rotate',
                        icon: Icons.rotate_90_degrees_cw_outlined,
                        enabled: enabled,
                        selected: activeTool == ViewerToolId.rotate,
                        onPressed: () => tool(ViewerToolId.rotate),
                      ),
                      _MenuButton(
                        buttonKey: const Key('pdf_viewer_tool_convert'),
                        tooltip: 'Export and convert',
                        label: 'Convert',
                        icon: Icons.ios_share,
                        enabled: enabled,
                        selected: on(const [
                          ViewerToolId.officeConvert,
                          ViewerToolId.exportImages,
                          ViewerToolId.exportJpg,
                          ViewerToolId.exportPng,
                        ]),
                        entries: [
                          _Entry(
                            'Export to images',
                            Icons.photo_library_outlined,
                            () => tool(ViewerToolId.exportImages),
                          ),
                          _Entry(
                            'Export to JPG',
                            Icons.photo_outlined,
                            () => tool(ViewerToolId.exportJpg),
                          ),
                          _Entry(
                            'Export to PNG',
                            Icons.image_outlined,
                            () => tool(ViewerToolId.exportPng),
                          ),
                          _Entry(
                            'Convert to Word / Excel / PowerPoint',
                            Icons.description_outlined,
                            () => tool(ViewerToolId.officeConvert),
                          ),
                          const _Entry.divider(),
                          _Entry(
                            'Make searchable (OCR)',
                            Icons.text_snippet_outlined,
                            () => tool(ViewerToolId.searchablePdf),
                          ),
                          if (onOpenImageConverter != null) ...[
                            const _Entry.divider(),
                            _Entry(
                              'Image converter (JPG, PNG, WebP…)',
                              Icons.transform,
                              onOpenImageConverter!,
                            ),
                          ],
                        ],
                      ),
                      _MenuButton(
                        buttonKey: const Key('pdf_viewer_tool_protect'),
                        tooltip: 'Protect — encrypt, redact, sanitize',
                        label: 'Protect',
                        icon: Icons.shield_outlined,
                        enabled: enabled,
                        selected: on(const [
                          ViewerToolId.protect,
                          ViewerToolId.unlock,
                          ViewerToolId.redact,
                          ViewerToolId.metadata,
                          ViewerToolId.removeMetadata,
                        ]),
                        entries: [
                          _Entry(
                            'Encrypt with password',
                            Icons.lock_outline,
                            () => tool(ViewerToolId.protect),
                          ),
                          _Entry(
                            'Remove password (decrypt)',
                            Icons.lock_open_outlined,
                            () => tool(ViewerToolId.unlock),
                          ),
                          const _Entry.divider(),
                          _Entry(
                            'Redact content',
                            Icons.hide_source,
                            () => tool(ViewerToolId.redact),
                          ),
                          _Entry(
                            'Document properties',
                            Icons.info_outline,
                            () => tool(ViewerToolId.metadata),
                          ),
                          _Entry(
                            'Remove hidden information',
                            Icons.cleaning_services_outlined,
                            () => tool(ViewerToolId.removeMetadata),
                          ),
                        ],
                      ),
                      _MenuButton(
                        buttonKey: const Key('pdf_viewer_tool_sign'),
                        tooltip: 'Sign and fill forms (Alt+Shift+S)',
                        label: 'Sign',
                        icon: Icons.history_edu_outlined,
                        enabled: enabled,
                        selected: on(const [
                          ViewerToolId.visualSign,
                          ViewerToolId.fillForm,
                        ]),
                        entries: [
                          _Entry(
                            'Sign yourself',
                            Icons.draw_outlined,
                            () => tool(ViewerToolId.visualSign),
                          ),
                          _Entry(
                            'Fill a form',
                            Icons.checklist_rtl,
                            () => tool(ViewerToolId.fillForm),
                          ),
                        ],
                      ),
                      _DirectButton(
                        buttonKey: const Key('pdf_viewer_tool_all'),
                        tooltip: 'All tools',
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
                if (history case final h?)
                  ListenableBuilder(
                    listenable: h,
                    builder: (context, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const VerticalDivider(
                          width: 12,
                          indent: 12,
                          endIndent: 12,
                        ),
                        IconButton(
                          key: const Key('pdf_viewer_undo'),
                          tooltip: 'Undo (Ctrl+Z)',
                          icon: const Icon(Icons.undo_rounded, size: 20),
                          onPressed: h.canUndo ? onUndo : null,
                        ),
                        IconButton(
                          key: const Key('pdf_viewer_redo'),
                          tooltip: 'Redo (Ctrl+Y)',
                          icon: const Icon(Icons.redo_rounded, size: 20),
                          onPressed: h.canRedo ? onRedo : null,
                        ),
                        IconButton(
                          key: const Key('pdf_viewer_save'),
                          tooltip: h.isDirty
                              ? 'Save changes (Ctrl+S)'
                              : 'Saved',
                          icon: Icon(
                            h.isDirty
                                ? Icons.save_rounded
                                : Icons.save_outlined,
                            size: 20,
                            color: h.isDirty ? DsColors.primary : null,
                          ),
                          onPressed: h.isDirty ? onSave : null,
                        ),
                        const SizedBox(width: DsSpacing.xs),
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
  const _Entry(this.label, this.icon, this.onSelected) : isDivider = false;
  const _Entry.divider()
    : label = '',
      icon = Icons.circle,
      onSelected = _noop,
      isDivider = true;

  static void _noop() {}

  final String label;
  final IconData icon;
  final VoidCallback onSelected;
  final bool isDivider;
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.buttonKey,
    required this.label,
    required this.icon,
    required this.entries,
    required this.enabled,
    this.selected = false,
    this.tooltip,
  });

  final Key buttonKey;
  final String label;
  final IconData icon;
  final List<_Entry> entries;
  final bool enabled;
  final bool selected;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        for (final entry in entries)
          if (entry.isDivider)
            const Divider(height: 9)
          else
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
        final open = menu.isOpen || selected;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Tooltip(
            message: tooltip ?? label,
            waitDuration: const Duration(milliseconds: 400),
            child: TextButton(
              key: buttonKey,
              onPressed: enabled
                  ? () => open ? menu.close() : menu.open()
                  : null,
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
    this.tooltip,
  });

  final Key buttonKey;
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;
  final bool selected;
  final bool emphasize;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = selected || emphasize;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Tooltip(
        message: tooltip ?? label,
        waitDuration: const Duration(milliseconds: 400),
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
            ],
          ),
        ),
      ),
    );
  }
}
