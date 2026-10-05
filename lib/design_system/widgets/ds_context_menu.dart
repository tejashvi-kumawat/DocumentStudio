import 'package:flutter/material.dart';

/// One row of a [DsContextMenuPanel].
sealed class DsMenuEntry {
  const DsMenuEntry();
}

class DsMenuItem extends DsMenuEntry {
  const DsMenuItem({
    required this.label,
    this.icon,
    this.shortcut,
    this.onTap,
    this.children,
    this.checked = false,
    this.destructive = false,
  });

  final String label;
  final IconData? icon;

  /// Accelerator text, right-aligned (e.g. `Ctrl+C`).
  final String? shortcut;

  /// Null disables the row (greyed, never hidden — Acrobat behaviour).
  final VoidCallback? onTap;

  /// Non-null makes this a submenu.
  final List<DsMenuEntry>? children;
  final bool checked;
  final bool destructive;
}

class DsMenuDivider extends DsMenuEntry {
  const DsMenuDivider();
}

/// Compact desktop context menu: 28 px rows, icon column, right-aligned
/// accelerators, hover submenus. Calls [onDismiss] after an item runs.
class DsContextMenuPanel extends StatelessWidget {
  const DsContextMenuPanel({
    super.key,
    required this.entries,
    required this.onDismiss,
    this.width = 248,
  });

  final List<DsMenuEntry> entries;
  final VoidCallback onDismiss;
  final double width;

  /// Rough height, used to keep the menu on screen.
  static double estimateHeight(List<DsMenuEntry> entries) {
    var h = 8.0;
    for (final e in entries) {
      h += e is DsMenuDivider ? 9 : 28;
    }
    return h;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Material(
      color: dark ? const Color(0xFF2B2B2B) : Colors.white,
      elevation: 8,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(
          color: dark ? const Color(0xFF444444) : const Color(0xFFD3D3D3),
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints.tightFor(width: width),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final e in entries)
                switch (e) {
                  DsMenuDivider() => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Divider(
                        height: 1,
                        thickness: 1,
                        color:
                            dark ? const Color(0xFF444444) : const Color(0xFFE4E4E4),
                      ),
                    ),
                  DsMenuItem() => _Row(item: e, onDismiss: onDismiss),
                },
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item, required this.onDismiss});

  final DsMenuItem item;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final enabled = item.onTap != null || item.children != null;
    final base = dark ? const Color(0xFFF1F1F1) : const Color(0xFF222222);
    final color = !enabled
        ? base.withValues(alpha: 0.38)
        : item.destructive
            ? const Color(0xFFD7373F)
            : base;
    final style = TextStyle(fontSize: 12.5, color: color, height: 1.1);
    final row = SizedBox(
      height: 28,
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: item.checked
                ? Icon(Icons.check, size: 15, color: color)
                : item.icon == null
                    ? null
                    : Icon(item.icon, size: 16, color: color),
          ),
          Expanded(
            child: Text(item.label, style: style, overflow: TextOverflow.ellipsis),
          ),
          if (item.shortcut != null)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                item.shortcut!,
                style: style.copyWith(color: color.withValues(alpha: 0.6)),
              ),
            ),
          if (item.children != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(Icons.chevron_right, size: 16, color: color),
            ),
          const SizedBox(width: 8),
        ],
      ),
    );
    final hover = dark ? const Color(0xFF3C3C3C) : const Color(0xFFEDEDED);
    final sub = item.children;
    if (sub != null) {
      return MenuAnchor(
        alignmentOffset: const Offset(-2, -4),
        style: const MenuStyle(
          padding: WidgetStatePropertyAll(EdgeInsets.zero),
          backgroundColor: WidgetStatePropertyAll(Colors.transparent),
          elevation: WidgetStatePropertyAll(0),
          shadowColor: WidgetStatePropertyAll(Colors.transparent),
        ),
        menuChildren: [
          DsContextMenuPanel(entries: sub, onDismiss: onDismiss, width: 220),
        ],
        builder: (context, controller, _) => MouseRegion(
          onEnter: (_) => enabled ? controller.open() : null,
          child: InkWell(
            hoverColor: hover,
            onTap: () => controller.isOpen ? controller.close() : controller.open(),
            child: row,
          ),
        ),
      );
    }
    return InkWell(
      hoverColor: hover,
      onTap: item.onTap == null
          ? null
          : () {
              onDismiss();
              item.onTap!();
            },
      child: row,
    );
  }
}

/// Shows [entries] as a context menu at [globalPosition] (desktop right-click
/// outside the PDF canvas: sidebars, tabs, lists).
Future<void> showDsContextMenu(
  BuildContext context,
  Offset globalPosition,
  List<DsMenuEntry> entries,
) {
  final size = MediaQuery.sizeOf(context);
  final h = DsContextMenuPanel.estimateHeight(entries);
  final left = globalPosition.dx.clamp(8.0, (size.width - 260).clamp(8.0, 4000));
  final top = globalPosition.dy.clamp(8.0, (size.height - h - 16).clamp(8.0, 4000));
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close menu',
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (ctx, _, _) => Stack(
      children: [
        Positioned(
          left: left.toDouble(),
          top: top.toDouble(),
          child: DsContextMenuPanel(
            entries: entries,
            onDismiss: () => Navigator.of(ctx).maybePop(),
          ),
        ),
      ],
    ),
  );
}
