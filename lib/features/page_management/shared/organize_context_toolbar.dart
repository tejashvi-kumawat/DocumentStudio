import 'package:document_studio/design_system/ds_colors.dart';
import 'package:flutter/material.dart';

/// Contextual actions for page workspace — selection drives visible controls.
class OrganizeContextToolbar extends StatelessWidget {
  const OrganizeContextToolbar({
    super.key,
    required this.pageCount,
    required this.selectionCount,
    required this.busy,
    this.documentLabel,
    this.onSelectAll,
    this.onClearSelection,
    this.onRotateCw,
    this.onRotateCcw,
    this.onRotate180,
    this.onDuplicate,
    this.onDelete,
    this.onExtract,
    this.onInsertBlank,
    this.onReplace,
    this.primaryAction,
  });

  final int pageCount;
  final int selectionCount;
  final bool busy;
  final String? documentLabel;
  final VoidCallback? onSelectAll;
  final VoidCallback? onClearSelection;
  final VoidCallback? onRotateCw;
  final VoidCallback? onRotateCcw;
  final VoidCallback? onRotate180;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final VoidCallback? onExtract;
  final VoidCallback? onInsertBlank;
  final VoidCallback? onReplace;
  final Widget? primaryAction;

  bool get _hasSelection => selectionCount > 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;

    return Material(
      elevation: 0,
      color: isDark ? DsColors.surfaceContainerDark : DsColors.surfaceContainerLight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: border)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (documentLabel != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Text(
                            documentLabel!,
                            style: theme.textTheme.labelLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (_hasSelection)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            '$selectionCount selected',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        )
                      else if (pageCount > 0)
                        Text(
                          '$pageCount pages',
                          style: theme.textTheme.bodySmall,
                        ),
                      if (pageCount > 0) ...[
                        const SizedBox(width: 8),
                        _btn(
                          context,
                          'Select all',
                          onSelectAll,
                          tip: busy ? 'Wait for the current operation' : 'Select all (Ctrl+A)',
                        ),
                        if (_hasSelection)
                          _btn(context, 'Clear', onClearSelection, tip: 'Clear selection'),
                      ],
                      if (_hasSelection) ...[
                        if (onRotateCw != null)
                          _iconBtn(Icons.rotate_right, 'Rotate 90° clockwise', onRotateCw),
                        if (onRotateCcw != null)
                          _iconBtn(Icons.rotate_left, 'Rotate 90° counter-clockwise', onRotateCcw),
                        if (onRotate180 != null) _iconBtn(Icons.flip, 'Rotate 180°', onRotate180),
                        if (onDuplicate != null)
                          _iconBtn(Icons.copy_all_outlined, 'Duplicate selected pages', onDuplicate),
                        if (onExtract != null)
                          _iconBtn(Icons.content_cut, 'Extract selection to new PDF', onExtract),
                        if (onReplace != null)
                          _iconBtn(Icons.swap_horiz, 'Replace from another PDF…', onReplace),
                        if (onInsertBlank != null)
                          _iconBtn(Icons.note_add_outlined, 'Insert blank page after selection', onInsertBlank),
                        if (onDelete != null)
                          _iconBtn(Icons.delete_outline, 'Remove selected (Delete)', onDelete, destructive: true),
                      ] else if (pageCount > 0 && onDelete != null) ...[
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            'Select pages to edit',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isDark
                                  ? DsColors.textSecondaryDark
                                  : DsColors.textSecondaryLight,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (primaryAction != null) primaryAction!,
            ],
          ),
        ),
      ),
    );
  }

  Widget _btn(
    BuildContext context,
    String label,
    VoidCallback? onPressed, {
    String? tip,
  }) {
    final button = TextButton(
      onPressed: busy ? null : onPressed,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Text(label),
    );
    if (tip == null) return button;
    return Tooltip(message: tip, child: button);
  }

  Widget _iconBtn(
    IconData icon,
    String tip,
    VoidCallback? onPressed, {
    bool destructive = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: IconButton(
        visualDensity: VisualDensity.compact,
        iconSize: 20,
        tooltip: tip,
        onPressed: busy ? null : onPressed,
        color: destructive ? Colors.red.shade700 : null,
        icon: Icon(icon),
      ),
    );
  }
}
