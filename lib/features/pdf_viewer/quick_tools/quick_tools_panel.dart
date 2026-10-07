import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/features/annotations/markup/markup_tool_icon.dart';
import 'package:document_studio/features/pdf_viewer/quick_tools/quick_tools.dart';
import 'package:flutter/material.dart';

/// The blue "…" panel: every tool by section (click to use it), a pin on
/// each to put it on the bar, and the bar's own order (drag to rearrange).
Future<void> showQuickToolsPanel(
  BuildContext context, {
  required Rect anchor,
  required bool enabled,
  required bool Function(QuickToolDef) isOn,
  required void Function(QuickToolDef) onRun,
  required VoidCallback onHide,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close quick tools',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (ctx, _, _) {
      final size = MediaQuery.sizeOf(ctx);
      final maxH = (size.height - 32).clamp(240.0, 600.0);
      return CustomSingleChildLayout(
        delegate: _PanelPlacement(anchor),
        child: SizedBox(
          width: 348,
          child: _QuickToolsPanel(
            maxHeight: maxH,
            enabled: enabled,
            isOn: isOn,
            onRun: (t) {
              Navigator.of(ctx).pop();
              onRun(t);
            },
            onHide: () {
              Navigator.of(ctx).pop();
              onHide();
            },
          ),
        ),
      );
    },
    transitionBuilder: (ctx, a, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween(
          begin: 0.96,
          end: 1.0,
        ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        alignment: Alignment.bottomRight,
        child: child,
      ),
    ),
  );
}

/// Left of the rail with the bottom edges level, moved so the whole panel
/// stays on screen.
class _PanelPlacement extends SingleChildLayoutDelegate {
  _PanelPlacement(this.anchor);
  final Rect anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) =>
      BoxConstraints.loose(c.biggest);

  @override
  Offset getPositionForChild(Size size, Size child) {
    final left = (anchor.left - child.width - 10).clamp(
      8.0,
      (size.width - child.width - 8).clamp(8.0, double.infinity),
    );
    final top = (anchor.bottom - child.height).clamp(
      8.0,
      (size.height - child.height - 8).clamp(8.0, double.infinity),
    );
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_PanelPlacement old) => old.anchor != anchor;
}

class _QuickToolsPanel extends StatelessWidget {
  const _QuickToolsPanel({
    required this.maxHeight,
    required this.enabled,
    required this.isOn,
    required this.onRun,
    required this.onHide,
  });

  final double maxHeight;
  final bool enabled;
  final bool Function(QuickToolDef) isOn;
  final void Function(QuickToolDef) onRun;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = DsColors.textSecondary(theme.brightness);
    final cfg = QuickToolsConfig.instance;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DsColors.border(theme.brightness)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 28,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ListenableBuilder(
            listenable: cfg,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 2),
                  child: Row(
                    children: [
                      Text(
                        'Quick tools',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Close',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Pin the tools you use most to the bar. Drag the pinned ones to reorder.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
                _PinnedStrip(cfg: cfg),
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    shrinkWrap: true,
                    children: [
                      for (final section in kQuickSections) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                          child: Text(
                            section.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10.5,
                              letterSpacing: 0.6,
                              fontWeight: FontWeight.w700,
                              color: muted,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final t in kQuickTools.where(
                              (t) => t.section == section,
                            ))
                              _ToolTile(
                                def: t,
                                enabled: enabled,
                                selected: isOn(t),
                                pinned: cfg.isPinned(t.id),
                                onRun: () => onRun(t),
                                onTogglePin: () => cfg.toggle(t.id),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: cfg.reset,
                        icon: const Icon(Icons.restart_alt, size: 17),
                        label: const Text('Reset to default'),
                      ),
                      TextButton.icon(
                        onPressed: onHide,
                        icon: const Icon(
                          Icons.visibility_off_outlined,
                          size: 17,
                        ),
                        label: const Text('Hide bar'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The bar's tools in order; drag to rearrange, ✕ to take one off.
class _PinnedStrip extends StatelessWidget {
  const _PinnedStrip({required this.cfg});
  final QuickToolsConfig cfg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ids = cfg.pinned;
    if (ids.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Text(
          'Nothing pinned. Pick tools below.',
          style: TextStyle(
            fontSize: 12,
            color: DsColors.textSecondary(theme.brightness),
          ),
        ),
      );
    }
    return SizedBox(
      height: 54,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        buildDefaultDragHandles: true,
        itemCount: ids.length,
        onReorderItem: cfg.move,
        proxyDecorator: (child, _, anim) => Material(
          color: Colors.transparent,
          elevation: 4 * anim.value,
          borderRadius: BorderRadius.circular(10),
          child: child,
        ),
        itemBuilder: (context, i) {
          final t = quickToolById(ids[i])!;
          return Padding(
            key: ValueKey(t.id),
            padding: const EdgeInsets.only(right: 6),
            child: _PinnedChip(def: t, onRemove: () => cfg.unpin(t.id)),
          );
        },
      ),
    );
  }
}

class _PinnedChip extends StatefulWidget {
  const _PinnedChip({required this.def, required this.onRemove});
  final QuickToolDef def;
  final VoidCallback onRemove;

  @override
  State<_PinnedChip> createState() => _PinnedChipState();
}

class _PinnedChipState extends State<_PinnedChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = widget.def;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tooltip(
        message: d.title,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: DsColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: DsColors.primary.withValues(alpha: 0.25),
                ),
              ),
              alignment: Alignment.center,
              child: d.markup != null
                  ? MarkupToolIcon(
                      d.markup!,
                      size: 20,
                      color: theme.colorScheme.onSurface,
                    )
                  : Icon(d.icon, size: 20, color: theme.colorScheme.onSurface),
            ),
            Positioned(
              right: -5,
              top: -5,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 100),
                opacity: _hover ? 1 : 0,
                child: GestureDetector(
                  onTap: widget.onRemove,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.inverseSurface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close,
                      size: 11,
                      color: theme.colorScheme.onInverseSurface,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolTile extends StatefulWidget {
  const _ToolTile({
    required this.def,
    required this.enabled,
    required this.selected,
    required this.pinned,
    required this.onRun,
    required this.onTogglePin,
  });

  final QuickToolDef def;
  final bool enabled, selected, pinned;
  final VoidCallback onRun, onTogglePin;

  @override
  State<_ToolTile> createState() => _ToolTileState();
}

class _ToolTileState extends State<_ToolTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = widget.def;
    final fg = widget.enabled
        ? theme.colorScheme.onSurface
        : theme.disabledColor;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onRun : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          width: 100,
          height: 76,
          decoration: BoxDecoration(
            color: widget.selected
                ? DsColors.primary.withValues(alpha: 0.12)
                : (_hover
                      ? theme.colorScheme.onSurface.withValues(alpha: 0.06)
                      : theme.colorScheme.onSurface.withValues(alpha: 0.025)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.selected
                  ? DsColors.primary.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      d.markup != null
                          ? MarkupToolIcon(d.markup!, size: 22, color: fg)
                          : Icon(d.icon, size: 22, color: fg),
                      const SizedBox(height: 5),
                      Text(
                        d.title,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, height: 1.15, color: fg),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 1,
                right: 1,
                child: Tooltip(
                  message: widget.pinned
                      ? 'Remove from the bar'
                      : 'Pin to the bar',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: widget.onTogglePin,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 100),
                        opacity: widget.pinned || _hover ? 1 : 0.0,
                        child: Icon(
                          widget.pinned
                              ? Icons.push_pin
                              : Icons.push_pin_outlined,
                          size: 14,
                          color: widget.pinned
                              ? DsColors.primary
                              : theme.colorScheme.onSurface.withValues(
                                  alpha: 0.55,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
