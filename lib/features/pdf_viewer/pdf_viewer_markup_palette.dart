import 'dart:math' as math;

import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/features/annotations/markup/markup_editor_controller.dart';
import 'package:document_studio/features/annotations/markup/markup_tool.dart';
import 'package:flutter/material.dart';

/// Shapes behind the one shapes button. Acrobat order, only tools that exist.
/// Connected lines is not a [MarkupTool].
const pdfViewerMarkupShapeTools = <MarkupTool>[
  MarkupTool.line,
  MarkupTool.arrow,
  MarkupTool.rectangle,
  MarkupTool.ellipse,
  MarkupTool.callout,
  MarkupTool.polygon,
  MarkupTool.cloud,
];

const _markTools = <MarkupTool>[
  MarkupTool.highlight,
  MarkupTool.underline,
  MarkupTool.strikeout,
];

String _shapeLabel(MarkupTool tool) => switch (tool) {
  MarkupTool.ellipse => 'Circle',
  MarkupTool.callout => 'Text callout',
  _ => tool.label,
};

/// Floating comment tools on the open PDF page.
///
/// Sits on the right of the page (the parent supplies how far the Tools
/// panel cuts in). Drag the grip to move it; it stays on the page. One
/// control collapses it to that same button and expands it again.
/// Collapsed and dragged position last for this process session.
/// Color, bold, size, and alignment stay on the floating format bar.
class PdfViewerMarkupPalette extends StatefulWidget {
  const PdfViewerMarkupPalette({
    super.key,
    required this.enabled,
    required this.markup,
    required this.onSelect,
    this.pageRightInset = 8,
    this.pageBottomInset = 8,
  });

  final bool enabled;
  final MarkupEditorController markup;
  final ValueChanged<MarkupTool> onSelect;

  /// Space on the right already taken by the Tools panel (and a gap).
  final double pageRightInset;

  /// Space at the bottom already taken by a phone tool sheet.
  final double pageBottomInset;

  static const railWidth = 44.0;
  static const dockTop = 12.0;

  /// Remembered for the app session. Not written to disk.
  /// Starts collapsed: one button, until the user expands it.
  static bool sessionCollapsed = true;

  static final ValueNotifier<bool> collapsed = ValueNotifier<bool>(true);

  /// Top-left of the bar after the user drags it. Null keeps the right dock.
  static Offset? sessionOrigin;

  static void setSessionCollapsed(bool value) {
    sessionCollapsed = value;
    if (collapsed.value != value) collapsed.value = value;
  }

  @override
  State<PdfViewerMarkupPalette> createState() => _PdfViewerMarkupPaletteState();
}

class _PdfViewerMarkupPaletteState extends State<PdfViewerMarkupPalette> {
  final _barKey = GlobalKey();
  Size? _stack;
  Offset? _pos;

  @override
  void initState() {
    super.initState();
    PdfViewerMarkupPalette.collapsed.addListener(_onSessionChanged);
    _scheduleClamp();
  }

  @override
  void didUpdateWidget(PdfViewerMarkupPalette oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageRightInset != widget.pageRightInset ||
        oldWidget.pageBottomInset != widget.pageBottomInset) {
      _scheduleClamp();
    }
  }

  @override
  void dispose() {
    PdfViewerMarkupPalette.collapsed.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
    _scheduleClamp();
  }

  void _scheduleClamp() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _clamp();
    });
  }

  double _bottomPad() =>
      widget.pageBottomInset + MediaQuery.paddingOf(context).bottom;

  void _dragBy(Offset delta) {
    final stack = _stack;
    if (stack == null) return;
    final current =
        _pos ??
        Offset(
          math.max(
            0,
            stack.width -
                widget.pageRightInset -
                PdfViewerMarkupPalette.railWidth,
          ),
          PdfViewerMarkupPalette.dockTop,
        );
    PdfViewerMarkupPalette.sessionOrigin = current + delta;
    _clamp();
  }

  void _clamp() {
    final stack = _stack;
    final barBox = _barKey.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null || barBox == null || !barBox.hasSize) return;
    final bar = barBox.size;
    final maxLeft = math.max(
      0.0,
      stack.width - widget.pageRightInset - bar.width,
    );
    final maxTop = math.max(0.0, stack.height - _bottomPad() - bar.height);
    final dock = Offset(
      maxLeft,
      math.min(PdfViewerMarkupPalette.dockTop, maxTop),
    );
    final raw = PdfViewerMarkupPalette.sessionOrigin ?? dock;
    final next = Offset(raw.dx.clamp(0.0, maxLeft), raw.dy.clamp(0.0, maxTop));
    if (PdfViewerMarkupPalette.sessionOrigin != null) {
      PdfViewerMarkupPalette.sessionOrigin = next;
    }
    if (_pos != next) setState(() => _pos = next);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.markup,
        PdfViewerMarkupPalette.collapsed,
      ]),
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final stack = constraints.biggest;
            if (_stack != stack) {
              final hadStack = _stack != null;
              _stack = stack;
              if (hadStack) _scheduleClamp();
            }
            final collapsed = PdfViewerMarkupPalette.collapsed.value;
            final parked = PdfViewerMarkupPalette.sessionOrigin;
            final left =
                _pos?.dx ??
                parked?.dx ??
                math.max(
                  0.0,
                  stack.width -
                      widget.pageRightInset -
                      PdfViewerMarkupPalette.railWidth,
                );
            final top =
                _pos?.dy ?? parked?.dy ?? PdfViewerMarkupPalette.dockTop;
            final maxHeight = math.max(64.0, stack.height - top - _bottomPad());
            final armed = widget.markup.editMode ? widget.markup.tool : null;
            return Stack(
              children: [
                Positioned(
                  left: left,
                  top: top,
                  child: NotificationListener<SizeChangedLayoutNotification>(
                    onNotification: (_) {
                      _scheduleClamp();
                      return true;
                    },
                    child: SizeChangedLayoutNotifier(
                      child: KeyedSubtree(
                        key: _barKey,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: PdfViewerMarkupPalette.railWidth,
                            maxHeight: maxHeight,
                          ),
                          child: _Bar(
                            collapsed: collapsed,
                            enabled: widget.enabled,
                            armed: armed,
                            onSelect: widget.onSelect,
                            onDrag: _dragBy,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.collapsed,
    required this.enabled,
    required this.armed,
    required this.onSelect,
    required this.onDrag,
  });

  final bool collapsed;
  final bool enabled;
  final MarkupTool? armed;
  final ValueChanged<MarkupTool> onSelect;
  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;
    final surface = isDark
        ? DsColors.surfaceContainerDark
        : DsColors.surfaceContainerLight;
    return Material(
      key: const Key('pdf_viewer_markup_palette'),
      elevation: 6,
      shadowColor: const Color(0x330F172A),
      color: surface,
      borderRadius: BorderRadius.circular(10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 2),
            _DragGrip(onDrag: onDrag),
            _CollapseButton(collapsed: collapsed),
            if (!collapsed)
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _IconTool(
                        tool: MarkupTool.select,
                        enabled: enabled,
                        selected: armed == MarkupTool.select,
                        onPressed: () => onSelect(MarkupTool.select),
                      ),
                      _IconTool(
                        tool: MarkupTool.text,
                        enabled: enabled,
                        selected: armed == MarkupTool.text,
                        onPressed: () => onSelect(MarkupTool.text),
                      ),
                      _MarkGroup(
                        enabled: enabled,
                        armed: armed,
                        onSelect: onSelect,
                      ),
                      _IconTool(
                        tool: MarkupTool.pen,
                        tooltip: 'Draw',
                        enabled: enabled,
                        selected:
                            armed == MarkupTool.pen ||
                            armed == MarkupTool.highlighter,
                        onPressed: () => onSelect(MarkupTool.pen),
                      ),
                      _ShapeButton(
                        enabled: enabled,
                        armed: armed,
                        onSelect: onSelect,
                      ),
                      _IconTool(
                        tool: MarkupTool.note,
                        enabled: enabled,
                        selected: armed == MarkupTool.note,
                        onPressed: () => onSelect(MarkupTool.note),
                      ),
                      _IconTool(
                        tool: MarkupTool.eraser,
                        enabled: enabled,
                        selected: armed == MarkupTool.eraser,
                        onPressed: () => onSelect(MarkupTool.eraser),
                      ),
                    ],
                  ),
                ),
              ),
            if (collapsed) const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }
}

class _DragGrip extends StatelessWidget {
  const _DragGrip({required this.onDrag});

  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    final color = DsColors.textSecondary(Theme.of(context).brightness);
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Listener(
        key: const Key('pdf_viewer_markup_palette_drag'),
        behavior: HitTestBehavior.opaque,
        onPointerMove: (event) {
          if (event.down) onDrag(event.delta);
        },
        child: Tooltip(
          message: 'Move comment tools',
          child: SizedBox(
            width: PdfViewerMarkupPalette.railWidth,
            height: 18,
            child: Icon(Icons.drag_indicator, size: 16, color: color),
          ),
        ),
      ),
    );
  }
}

class _CollapseButton extends StatelessWidget {
  const _CollapseButton({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: Key(
        collapsed
            ? 'pdf_viewer_markup_palette_expand'
            : 'pdf_viewer_markup_palette_collapse',
      ),
      tooltip: collapsed ? 'Comment tools' : 'Hide comment tools',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: PdfViewerMarkupPalette.railWidth,
        minHeight: 36,
      ),
      onPressed: () => PdfViewerMarkupPalette.setSessionCollapsed(!collapsed),
      icon: Icon(
        collapsed ? Icons.draw_outlined : Icons.chevron_right,
        color: DsColors.primary,
        size: 22,
      ),
    );
  }
}

class _MarkGroup extends StatelessWidget {
  const _MarkGroup({
    required this.enabled,
    required this.armed,
    required this.onSelect,
  });

  final bool enabled;
  final MarkupTool? armed;
  final ValueChanged<MarkupTool> onSelect;

  @override
  Widget build(BuildContext context) {
    final border = DsColors.border(Theme.of(context).brightness);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final tool in _markTools)
              _IconTool(
                tool: tool,
                enabled: enabled,
                selected: armed == tool,
                onPressed: () => onSelect(tool),
                tight: true,
              ),
          ],
        ),
      ),
    );
  }
}

class _IconTool extends StatelessWidget {
  const _IconTool({
    required this.tool,
    required this.enabled,
    required this.selected,
    required this.onPressed,
    this.tooltip,
    this.tight = false,
  });

  final MarkupTool tool;
  final bool enabled;
  final bool selected;
  final VoidCallback onPressed;
  final String? tooltip;
  final bool tight;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: Key('pdf_viewer_markup_palette_${tool.name}'),
      tooltip: tooltip ?? tool.label,
      visualDensity: VisualDensity.compact,
      iconSize: 20,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(
        minWidth: tight ? 36 : PdfViewerMarkupPalette.railWidth,
        minHeight: tight ? 32 : 36,
      ),
      onPressed: enabled ? onPressed : null,
      style: IconButton.styleFrom(
        foregroundColor: selected
            ? DsColors.primary
            : Theme.of(context).colorScheme.onSurface,
        backgroundColor: selected
            ? DsColors.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        shape: const RoundedRectangleBorder(),
      ),
      icon: Icon(tool.icon),
    );
  }
}

class _ShapeButton extends StatefulWidget {
  const _ShapeButton({
    required this.enabled,
    required this.armed,
    required this.onSelect,
  });

  final bool enabled;
  final MarkupTool? armed;
  final ValueChanged<MarkupTool> onSelect;

  @override
  State<_ShapeButton> createState() => _ShapeButtonState();
}

class _ShapeButtonState extends State<_ShapeButton> {
  final _link = LayerLink();
  OverlayEntry? _entry;
  bool _openUp = false;

  bool get _shapeArmed =>
      widget.armed != null && pdfViewerMarkupShapeTools.contains(widget.armed);

  @override
  void didUpdateWidget(_ShapeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry?.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  void _toggle() {
    if (_entry != null) {
      _close();
      return;
    }
    final box = context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    final screenH = MediaQuery.sizeOf(context).height;
    final menuH = pdfViewerMarkupShapeTools.length * 40.0 + 8;
    _openUp = origin.dy + menuH > screenH - 12;
    _entry = OverlayEntry(
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final surface = isDark
            ? DsColors.surfaceContainerDark
            : DsColors.surfaceLight;
        final border = DsColors.border(Theme.of(context).brightness);
        return Positioned.fill(
          child: Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: const SizedBox.expand(),
              ),
              CompositedTransformFollower(
                link: _link,
                showWhenUnlinked: false,
                targetAnchor: _openUp
                    ? Alignment.bottomLeft
                    : Alignment.topLeft,
                followerAnchor: _openUp
                    ? Alignment.bottomRight
                    : Alignment.topRight,
                offset: const Offset(-6, 0),
                child: Material(
                  elevation: 8,
                  color: surface,
                  shadowColor: const Color(0x330F172A),
                  borderRadius: BorderRadius.circular(8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: border),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 196,
                        maxWidth: 240,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final tool in pdfViewerMarkupShapeTools)
                            _ShapeRow(
                              tool: tool,
                              selected: widget.armed == tool,
                              onPressed: widget.enabled
                                  ? () {
                                      widget.onSelect(tool);
                                      _close();
                                    }
                                  : null,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final on = _shapeArmed || _entry != null;
    final icon = _shapeArmed ? widget.armed!.icon : Icons.category_outlined;
    return CompositedTransformTarget(
      link: _link,
      child: IconButton(
        key: const Key('pdf_viewer_markup_palette_shapes'),
        tooltip: 'Shapes',
        visualDensity: VisualDensity.compact,
        iconSize: 20,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
          minWidth: PdfViewerMarkupPalette.railWidth,
          minHeight: 36,
        ),
        onPressed: widget.enabled ? _toggle : null,
        style: IconButton.styleFrom(
          foregroundColor: on
              ? DsColors.primary
              : Theme.of(context).colorScheme.onSurface,
          backgroundColor: on
              ? DsColors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
        ),
        icon: Icon(icon),
      ),
    );
  }
}

class _ShapeRow extends StatelessWidget {
  const _ShapeRow({
    required this.tool,
    required this.selected,
    required this.onPressed,
  });

  final MarkupTool tool;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final color = selected ? DsColors.primary : onSurface;
    return InkWell(
      key: Key('pdf_viewer_markup_palette_${tool.name}'),
      onTap: onPressed,
      child: ColoredBox(
        color: selected
            ? DsColors.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        child: SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(tool.icon, size: 18, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _shapeLabel(tool),
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: color),
                  ),
                ),
                if (selected)
                  const Icon(Icons.check, size: 16, color: DsColors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
