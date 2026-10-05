import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/features/document_workspace/workspace_inspector_panel.dart';
import 'package:flutter/material.dart';

/// Action ribbon for the Workspace page grid: select, rotate, duplicate,
/// delete, blank page, reorder, reverse, undo / redo, and Save.
class WorkspaceToolbar extends StatelessWidget {
  const WorkspaceToolbar({
    super.key,
    required this.pageCount,
    required this.selectedCount,
    required this.busy,
    required this.canUndo,
    required this.canRedo,
    required this.onAddPdf,
    required this.onSelectAll,
    required this.onClearSelection,
    required this.onRotateLeft,
    required this.onRotateRight,
    required this.onDuplicate,
    required this.onDelete,
    required this.onBlank,
    required this.onMoveEarlier,
    required this.onMoveLater,
    required this.onReverse,
    required this.onUndo,
    required this.onRedo,
    required this.onSave,
    required this.onSaveSelection,
    this.documentTools = const [],
  });

  /// Whole-document tools (Edit, Sign, OCR, Compress…) in a "Tools" menu.
  final List<WorkspaceDocumentToolItem> documentTools;

  final int pageCount;
  final int selectedCount;
  final bool busy;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onAddPdf;
  final VoidCallback onSelectAll;
  final VoidCallback onClearSelection;
  final VoidCallback onRotateLeft;
  final VoidCallback onRotateRight;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onBlank;
  final VoidCallback onMoveEarlier;
  final VoidCallback onMoveLater;
  final VoidCallback onReverse;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onSave;
  final VoidCallback onSaveSelection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final sel = selectedCount > 0 && !busy;
    final any = pageCount > 0 && !busy;

    Widget btn(
      IconData icon,
      String label,
      VoidCallback? onTap, {
      String? tip,
      bool primary = false,
    }) {
      final enabled = onTap != null;
      final color = !enabled
          ? theme.disabledColor
          : primary
          ? DsColors.primary
          : theme.colorScheme.onSurface;
      return Tooltip(
        message: tip ?? label,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 19, color: color),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(fontSize: 10.5, color: color, height: 1.1),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Ribbon group: buttons over a small caption, Acrobat / Office style.
    Widget group(String caption, List<Widget> children) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: children),
          Text(
            caption.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );

    Widget sep() => Container(
      width: 1,
      height: 44,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: DsColors.border(theme.brightness),
    );

    final tools = documentTools;
    return Material(
      color: dark
          ? DsColors.surfaceContainerDark
          : DsColors.surfaceContainerLight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: DsColors.border(theme.brightness)),
          ),
        ),
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    group('Pages', [
                      btn(
                        Icons.note_add_outlined,
                        'Add PDF',
                        busy ? null : onAddPdf,
                        tip: 'Add another PDF to this workspace',
                      ),
                      btn(
                        Icons.insert_page_break_outlined,
                        'Blank',
                        any ? onBlank : null,
                        tip: 'Insert a blank page after the selection',
                      ),
                      btn(
                        Icons.copy_all_outlined,
                        'Duplicate',
                        sel ? onDuplicate : null,
                      ),
                      btn(
                        Icons.delete_outline,
                        'Delete',
                        sel ? onDelete : null,
                        tip: 'Remove the selected pages (Del)',
                      ),
                    ]),
                    sep(),
                    group('Arrange', [
                      btn(
                        Icons.rotate_left,
                        'Left',
                        sel ? onRotateLeft : null,
                        tip: 'Rotate left',
                      ),
                      btn(
                        Icons.rotate_right,
                        'Right',
                        sel ? onRotateRight : null,
                        tip: 'Rotate right',
                      ),
                      btn(
                        Icons.arrow_back,
                        'Earlier',
                        sel ? onMoveEarlier : null,
                        tip: 'Move the selected page earlier',
                      ),
                      btn(
                        Icons.arrow_forward,
                        'Later',
                        sel ? onMoveLater : null,
                        tip: 'Move the selected page later',
                      ),
                      btn(
                        Icons.swap_horiz,
                        'Reverse',
                        any ? onReverse : null,
                        tip: 'Reverse the page order',
                      ),
                    ]),
                    sep(),
                    group('Select', [
                      btn(
                        Icons.select_all,
                        'All',
                        any ? onSelectAll : null,
                        tip: 'Select every page (Ctrl+A)',
                      ),
                      btn(
                        Icons.deselect,
                        'None',
                        selectedCount > 0 ? onClearSelection : null,
                        tip: 'Clear the selection (Esc)',
                      ),
                    ]),
                    sep(),
                    group('History', [
                      btn(
                        Icons.undo,
                        'Undo',
                        canUndo && !busy ? onUndo : null,
                        tip: 'Undo (Ctrl+Z)',
                      ),
                      btn(
                        Icons.redo,
                        'Redo',
                        canRedo && !busy ? onRedo : null,
                        tip: 'Redo (Ctrl+Y)',
                      ),
                    ]),
                    if (tools.isNotEmpty) ...[
                      sep(),
                      group('Document', [
                        MenuAnchor(
                          menuChildren: [
                            for (final t in tools)
                              MenuItemButton(
                                leadingIcon: Icon(t.icon, size: 18),
                                onPressed: busy ? null : t.onPressed,
                                child: Text(t.label),
                              ),
                          ],
                          builder: (context, menu, _) => btn(
                            Icons.handyman_outlined,
                            'Tools ▾',
                            busy
                                ? null
                                : () =>
                                      menu.isOpen ? menu.close() : menu.open(),
                            tip: 'Edit, sign, OCR, compress, protect, convert…',
                          ),
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
              if (selectedCount > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('$selectedCount of $pageCount selected'),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 12, left: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: sel ? onSaveSelection : null,
                      icon: const Icon(Icons.file_download_outlined, size: 18),
                      label: const Text('Save selection'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: any ? onSave : null,
                      icon: const Icon(Icons.save_alt, size: 18),
                      label: const Text('Save PDF'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
