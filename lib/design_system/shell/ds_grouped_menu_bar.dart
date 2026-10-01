import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:flutter/material.dart';

/// One entry in a [DsGroupedMenuButton] dropdown.
class DsGroupedMenuItem {
  const DsGroupedMenuItem({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.dividerBefore = false,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;
  final bool dividerBefore;
  final bool enabled;
}

/// Compact group trigger (Edit / Pages / Protect / Tools) with a readable menu.
///
/// Touch target is ~[DsSpacing.compactTouchTarget] so phone chrome stays usable
/// without a long row of individual icon buttons.
class DsGroupedMenuButton extends StatelessWidget {
  const DsGroupedMenuButton({
    super.key,
    required this.label,
    required this.icon,
    required this.items,
    this.enabled = true,
    this.iconOnly = false,
    this.emphasize = false,
  });

  final String label;
  final IconData icon;
  final List<DsGroupedMenuItem> items;
  final bool enabled;
  final bool iconOnly;

  /// Stronger fill for the always-visible Tools control.
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final minSide = DsSpacing.compactTouchTarget;

    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 6),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      menuChildren: [
        for (final item in items) ...[
          if (item.dividerBefore) const Divider(height: 9),
          MenuItemButton(
            leadingIcon: Icon(item.icon, size: 20),
            style: ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(0, minSide)),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              ),
            ),
            onPressed: item.enabled ? item.onSelected : null,
            child: Text(
              item.label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ],
      builder: (context, menu, _) {
        void toggle() => menu.isOpen ? menu.close() : menu.open();
        final open = menu.isOpen;
        final bg = open
            ? theme.colorScheme.primary.withValues(alpha: 0.14)
            : (emphasize
                ? theme.colorScheme.primary.withValues(alpha: 0.10)
                : null);
        final fg = emphasize || open
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface;

        if (iconOnly) {
          return Semantics(
            button: true,
            label: label,
            child: Tooltip(
              message: label,
              child: IconButton(
                onPressed: enabled ? toggle : null,
                icon: Icon(icon, size: 20),
                tooltip: label,
                style: IconButton.styleFrom(
                  foregroundColor: fg,
                  backgroundColor: bg,
                  minimumSize: Size(minSide, minSide),
                  maximumSize: Size(minSide + 4, minSide),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: TextButton(
            onPressed: enabled ? toggle : null,
            style: TextButton.styleFrom(
              foregroundColor: fg,
              backgroundColor: bg,
              minimumSize: Size(0, minSide),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 1),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: const Icon(Icons.expand_more_rounded, size: 16),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Horizontal strip of grouped menu buttons (no individual tool icons).
class DsGroupedMenuBar extends StatelessWidget {
  const DsGroupedMenuBar({
    super.key,
    required this.children,
    this.leading,
    this.trailing,
    this.scrollable = true,
  });

  final List<Widget> children;
  final Widget? leading;
  final Widget? trailing;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(width: DsSpacing.xs),
        ],
        ...children,
        if (trailing != null) ...[
          const SizedBox(width: DsSpacing.xs),
          trailing!,
        ],
      ],
    );

    if (!scrollable) return row;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: row,
    );
  }
}
