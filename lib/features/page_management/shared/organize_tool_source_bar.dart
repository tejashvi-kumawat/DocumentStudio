import 'package:document_studio/design_system/ds_colors.dart';
import 'package:flutter/material.dart';

/// Compact file actions row above page grids in tool workspaces.
class OrganizeToolSourceBar extends StatelessWidget {
  const OrganizeToolSourceBar({
    super.key,
    required this.busy,
    this.onOpenPdf,
    this.onInsertFromPdf,
    this.onReverseAll,
    this.trailing,
  });

  final bool busy;
  final VoidCallback? onOpenPdf;
  final VoidCallback? onInsertFromPdf;
  final VoidCallback? onReverseAll;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;

    return Material(
      color: isDark ? DsColors.surfaceContainerDark : DsColors.surfaceContainerLight,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: border))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: [
              if (onOpenPdf != null)
                _Action(
                  icon: Icons.folder_open_outlined,
                  label: 'Open PDF',
                  busy: busy,
                  onPressed: onOpenPdf,
                ),
              if (onInsertFromPdf != null)
                _Action(
                  icon: Icons.playlist_add,
                  label: 'Insert from PDF',
                  busy: busy,
                  onPressed: onInsertFromPdf,
                ),
              if (onReverseAll != null)
                _Action(
                  icon: Icons.swap_vert,
                  label: 'Reverse all',
                  busy: busy,
                  onPressed: onReverseAll,
                ),
              if (trailing != null) ...[
                const Spacer(),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.busy,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: busy ? null : onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }
}
