import 'package:document_studio/features/annotations/markup/markup_tool_icon.dart';
import 'dart:math' as math;

import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
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
/// One button on the right of the page, left of the Tools rail (the parent
/// stacks this on the page, not over that rail or the top tool row). Drag
/// the grip to move it; it stays inside the page. On a phone it sits inset
/// from the edges. Collapsed and dragged position last for this process
/// session. Color, bold, size, and alignment stay on the floating format bar.
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

  /// Extra gap on the right of the page (in addition to the edge inset).
  final double pageRightInset;

  /// Extra gap at the bottom of the page (in addition to the edge inset).
  final double pageBottomInset;

  static const railWidth = 46.0;
  static const dockTop = 12.0;

  /// Remembered for the app session. Not written to disk.
  /// Starts collapsed: one button, until the user expands it.
  static bool sessionCollapsed = false;

  static final ValueNotifier<bool> collapsed = ValueNotifier<bool>(false);

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
  Size? _barSize;
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

  bool get _phone =>
      MediaQuery.sizeOf(context).width < DsSpacing.breakpointCompact;

  /// Phone sits further in from the screen edge. Desktop keeps a small side
  /// gap and [PdfViewerMarkupPalette.dockTop] under the tool row.
  double get _edge => _phone ? 12.0 : 8.0;

  double get _topEdge => _phone ? 12.0 : PdfViewerMarkupPalette.dockTop;

  ({double minLeft, double maxLeft, double minTop, double maxTop}) _limits(
    Size stack,
    Size bar,
  ) {
    final pad = MediaQuery.paddingOf(context);
    final insetL = math.max(_edge, pad.left);
    final insetR = math.max(
      _edge,
      math.max(pad.right, widget.pageRightInset),
    );
    final insetT = _topEdge;
    final insetB = math.max(
      _edge,
      math.max(pad.bottom, widget.pageBottomInset),
    );
    final minLeft = math.min(insetL, math.max(0.0, stack.width - bar.width));
    final maxLeft = math.max(
      minLeft,
      stack.width - insetR - bar.width,
    );
    final minTop = math.min(insetT, math.max(0.0, stack.height - bar.height));
    final maxTop = math.max(
      minTop,
      stack.height - insetB - bar.height,
    );
    return (
      minLeft: minLeft,
      maxLeft: maxLeft,
      minTop: minTop,
      maxTop: maxTop,
    );
  }

  Offset _originFor(Size stack, Size bar) {
    final limits = _limits(stack, bar);
    final raw =
        PdfViewerMarkupPalette.sessionOrigin ??
        Offset(limits.maxLeft, limits.minTop);
    return Offset(
      raw.dx.clamp(limits.minLeft, limits.maxLeft).toDouble(),
      raw.dy.clamp(limits.minTop, limits.maxTop).toDouble(),
    );
  }

  void _dragBy(Offset delta) {
    final stack = _stack;
    if (stack == null) return;
    final bar = _barSize ?? Size(PdfViewerMarkupPalette.railWidth, 64);
    final current = _pos ?? _originFor(stack, bar);
    PdfViewerMarkupPalette.sessionOrigin = current + delta;
    _clamp();
  }

  void _clamp() {
    final stack = _stack;
    final barBox = _barKey.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null || barBox == null || !barBox.hasSize) return;
    final bar = barBox.size;
    _barSize = bar;
    final next = _originFor(stack, bar);
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
            final barGuess =
                _barSize ??
                Size(
                  PdfViewerMarkupPalette.railWidth,
                  collapsed ? 64 : math.min(320, stack.height),
                );
            final placed = _originFor(stack, barGuess);
            final left = placed.dx;
            final top = placed.dy;
            final pad = MediaQuery.paddingOf(context);
            final insetB = math.max(
              _edge,
              math.max(pad.bottom, widget.pageBottomInset),
            );
            final maxHeight = math.max(48.0, stack.height - top - insetB);
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
                      const _Sep(),
                      _IconTool(
                        tool: MarkupTool.note,
                        tooltip: 'Add a sticky note',
                        enabled: enabled,
                        selected: armed == MarkupTool.note,
                        onPressed: () => onSelect(MarkupTool.note),
                      ),
                      _GroupButton(
                        label: 'Text',
                        tools: const [MarkupTool.text, MarkupTool.callout],
                        enabled: enabled,
                        armed: armed,
                        onSelect: onSelect,
                      ),
                      _GroupButton(
                        label: 'Mark up text',
                        tools: const [
                          MarkupTool.highlight,
                          MarkupTool.underline,
                          MarkupTool.strikeout,
                          MarkupTool.squiggly,
                        ],
                        enabled: enabled,
                        armed: armed,
                        onSelect: onSelect,
                      ),
                      const _Sep(),
                      _GroupButton(
                        label: 'Draw',
                        tools: const [
                          MarkupTool.pen,
                          MarkupTool.highlighter,
                          MarkupTool.eraser,
                        ],
                        enabled: enabled,
                        armed: armed,
                        onSelect: onSelect,
                      ),
                      _GroupButton(
                        label: 'Shapes',
                        tools: const [
                          MarkupTool.line,
                          MarkupTool.arrow,
                          MarkupTool.rectangle,
                          MarkupTool.ellipse,
                          MarkupTool.polygon,
                          MarkupTool.cloud,
                        ],
                        enabled: enabled,
                        armed: armed,
                        onSelect: onSelect,
                      ),
                      const _Sep(),
                      _GroupButton(
                        label: 'Insert',
                        tools: const [MarkupTool.link, MarkupTool.image],
                        enabled: enabled,
                        armed: armed,
                        onSelect: onSelect,
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

class _Sep extends StatelessWidget {
  const _Sep();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
        child: Divider(height: 1, color: DsColors.border(Theme.of(context).brightness)),
      );
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
      tooltip: tool.shortcutHint == null
          ? (tooltip ?? tool.label)
          : '${tooltip ?? tool.label}  (${tool.shortcutHint})',
      visualDensity: VisualDensity.compact,
      iconSize: 22,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
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
      icon: MarkupToolIcon(tool, size: 22),
    );
  }
}


/// A tool button with a small ▾ that opens the rest of its group, like
/// Acrobat's comment bar. The button repeats the last tool used from the
/// group; the arrow (or a right-click) lists every tool with its shortcut.
class _GroupButton extends StatefulWidget {
  const _GroupButton({
    required this.label,
    required this.tools,
    required this.enabled,
    required this.armed,
    required this.onSelect,
  });

  final String label;
  final List<MarkupTool> tools;
  final bool enabled;
  final MarkupTool? armed;
  final ValueChanged<MarkupTool> onSelect;

  @override
  State<_GroupButton> createState() => _GroupButtonState();
}

class _GroupButtonState extends State<_GroupButton> {
  late MarkupTool _last = widget.tools.first;

  MarkupTool get _shown =>
      widget.armed != null && widget.tools.contains(widget.armed)
          ? widget.armed!
          : _last;

  Future<void> _openMenu() async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final pos = RelativeRect.fromLTRB(
      topLeft.dx - 190,
      topLeft.dy,
      overlay.size.width - topLeft.dx,
      0,
    );
    final picked = await showMenu<MarkupTool>(
      context: context,
      position: pos,
      constraints: const BoxConstraints(minWidth: 190),
      items: [
        for (final t in widget.tools)
          PopupMenuItem<MarkupTool>(
            value: t,
            height: 34,
            child: Row(
              children: [
                MarkupToolIcon(t, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_shapeLabel(t), style: const TextStyle(fontSize: 13)),
                ),
                if (t.shortcutHint != null)
                  Text(
                    t.shortcutHint!,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
    if (picked != null) {
      setState(() => _last = picked);
      widget.onSelect(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tool = _shown;
    final on = widget.armed != null && widget.tools.contains(widget.armed);
    final color =
        on ? DsColors.primary : Theme.of(context).colorScheme.onSurface;
    final hint = tool.shortcutHint;
    return Tooltip(
      message: hint == null
          ? _shapeLabel(tool)
          : '${_shapeLabel(tool)}  ($hint)',
      child: GestureDetector(
        onSecondaryTap: widget.enabled ? _openMenu : null,
        child: SizedBox(
          width: 40,
          height: 36,
          child: Stack(
            children: [
              Positioned.fill(
                child: InkWell(
                  onTap: widget.enabled
                      ? () {
                          setState(() => _last = tool);
                          widget.onSelect(tool);
                        }
                      : null,
                  child: Container(
                    color: on ? DsColors.primary.withValues(alpha: 0.12) : null,
                    alignment: Alignment.center,
                    child: MarkupToolIcon(tool, size: 22, color: color),
                  ),
                ),
              ),
              // Acrobat-style corner marker: opens the rest of the group.
              Positioned(
                right: 0,
                bottom: 0,
                child: InkWell(
                  onTap: widget.enabled ? _openMenu : null,
                  child: SizedBox(
                    width: 11,
                    height: 11,
                    child: CustomPaint(painter: _CornerTriangle(color)),
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

class _CornerTriangle extends CustomPainter {
  _CornerTriangle(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width, size.height * 0.35)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width * 0.35, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.85));
  }

  @override
  bool shouldRepaint(_CornerTriangle old) => old.color != color;
}
