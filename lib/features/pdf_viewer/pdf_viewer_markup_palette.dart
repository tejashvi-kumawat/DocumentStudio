import 'package:document_studio/features/annotations/markup/markup_tool_icon.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/annotations/markup/markup_editor_controller.dart';
import 'package:document_studio/features/annotations/markup/markup_tool.dart';
import 'package:document_studio/features/pdf_viewer/quick_tools/quick_tools.dart';
import 'package:document_studio/features/pdf_viewer/quick_tools/quick_tools_panel.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:flutter/material.dart';

/// Floating Quick Tools on the open PDF page.
///
/// A slim rail on the right of the page, left of the Tools rail. It holds
/// the tools the user pinned (comment tools and any viewer tool; the blue
/// "…" opens every tool and lets them pin, unpin and reorder, like Acrobat's
/// "Customize quick tools"). Drag the grip to move it; it stays inside the
/// page. On a phone it sits inset from the edges. Collapsed state and
/// position last for this process session; the pinned tools are saved.
class PdfViewerMarkupPalette extends StatefulWidget {
  const PdfViewerMarkupPalette({
    super.key,
    required this.enabled,
    required this.markup,
    required this.onSelect,
    this.onViewerTool,
    this.activeViewerTool,
    this.pageRightInset = 8,
    this.pageBottomInset = 8,
  });

  final bool enabled;
  final MarkupEditorController markup;
  final ValueChanged<MarkupTool> onSelect;

  /// Opens a viewer tool pinned to the bar (Edit PDF, Redact, Crop…).
  final ValueChanged<ViewerToolId>? onViewerTool;

  /// The viewer tool currently open, shown as selected on the bar.
  final ViewerToolId? activeViewerTool;

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
    QuickToolsConfig.instance.addListener(_scheduleClamp);
    unawaited(QuickToolsConfig.instance.ensureLoaded());
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
    QuickToolsConfig.instance.removeListener(_scheduleClamp);
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
    final insetR = math.max(_edge, math.max(pad.right, widget.pageRightInset));
    final insetT = _topEdge;
    final insetB = math.max(
      _edge,
      math.max(pad.bottom, widget.pageBottomInset),
    );
    final minLeft = math.min(insetL, math.max(0.0, stack.width - bar.width));
    final maxLeft = math.max(minLeft, stack.width - insetR - bar.width);
    final minTop = math.min(insetT, math.max(0.0, stack.height - bar.height));
    final maxTop = math.max(minTop, stack.height - insetB - bar.height);
    return (minLeft: minLeft, maxLeft: maxLeft, minTop: minTop, maxTop: maxTop);
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
        QuickToolsConfig.instance,
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
                            activeViewerTool: widget.activeViewerTool,
                            onSelect: widget.onSelect,
                            onViewerTool: widget.onViewerTool,
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
    required this.activeViewerTool,
    required this.onSelect,
    required this.onViewerTool,
    required this.onDrag,
  });

  final bool collapsed;
  final bool enabled;
  final MarkupTool? armed;
  final ViewerToolId? activeViewerTool;
  final ValueChanged<MarkupTool> onSelect;
  final ValueChanged<ViewerToolId>? onViewerTool;
  final ValueChanged<Offset> onDrag;

  bool _isOn(QuickToolDef t) => t.markup != null
      ? armed == t.markup
      : (t.viewer != null && activeViewerTool == t.viewer);

  void _run(QuickToolDef t) {
    QuickToolsConfig.instance.used(t.id);
    final m = t.markup;
    if (m != null) {
      onSelect(m);
    } else {
      onViewerTool?.call(t.viewer!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;
    final surface = isDark
        ? DsColors.surfaceContainerDark
        : DsColors.surfaceContainerLight;
    final cfg = QuickToolsConfig.instance;
    final ids = [...cfg.pinned, ?cfg.recent];
    return Material(
      key: const Key('pdf_viewer_markup_palette'),
      elevation: 6,
      shadowColor: const Color(0x330F172A),
      color: surface,
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DragGrip(
              onDrag: onDrag,
              onDoubleTap: () =>
                  PdfViewerMarkupPalette.setSessionCollapsed(true),
              collapsed: collapsed,
            ),
            if (collapsed)
              _CollapseButton(collapsed: collapsed)
            else ...[
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final id in ids)
                        if (quickToolById(id) case final t?)
                          _QuickButton(
                            def: t,
                            enabled:
                                enabled &&
                                (t.markup != null || onViewerTool != null),
                            selected: _isOn(t),
                            temporary: id == cfg.recent,
                            onPressed: () => _run(t),
                          ),
                    ],
                  ),
                ),
              ),
              _MoreButton(
                onOpen: (anchor) => showQuickToolsPanel(
                  context,
                  anchor: anchor,
                  enabled: enabled,
                  isOn: _isOn,
                  onRun: _run,
                  onHide: () =>
                      PdfViewerMarkupPalette.setSessionCollapsed(true),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }
}

/// Slim handle on top of the rail: drag to move; double-click to hide.
class _DragGrip extends StatelessWidget {
  const _DragGrip({
    required this.onDrag,
    required this.onDoubleTap,
    required this.collapsed,
  });

  final ValueChanged<Offset> onDrag;
  final VoidCallback onDoubleTap;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final color = DsColors.textSecondary(Theme.of(context).brightness)
        .withValues(alpha: 0.45);
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: GestureDetector(
        onDoubleTap: collapsed ? null : onDoubleTap,
        child: Listener(
          key: const Key('pdf_viewer_markup_palette_drag'),
          behavior: HitTestBehavior.opaque,
          onPointerMove: (event) {
            if (event.down) onDrag(event.delta);
          },
          child: Tooltip(
            message: collapsed
                ? 'Move quick tools'
                : 'Move quick tools (double-click to hide)',
            child: SizedBox(
              width: PdfViewerMarkupPalette.railWidth,
              height: 16,
              child: Center(
                child: Container(
                  width: 22,
                  height: 3,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
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
      tooltip: collapsed ? 'Quick tools' : 'Hide quick tools',
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

/// One pinned tool: a quiet icon with a soft hover and a tinted selected
/// state. No menu arrows: everything else is under the blue "…".
class _QuickButton extends StatefulWidget {
  const _QuickButton({
    required this.def,
    required this.enabled,
    required this.selected,
    required this.onPressed,
    this.temporary = false,
  });

  final QuickToolDef def;
  final bool enabled;
  final bool selected;
  final bool temporary;
  final VoidCallback onPressed;

  @override
  State<_QuickButton> createState() => _QuickButtonState();
}

class _QuickButtonState extends State<_QuickButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = widget.def;
    final hint = d.markup?.shortcutHint;
    final color = !widget.enabled
        ? theme.disabledColor
        : widget.selected
        ? DsColors.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.86);
    return Tooltip(
      message: hint == null ? d.title : '${d.title}  ($hint)',
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          key: Key('pdf_viewer_markup_palette_${d.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onPressed : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            width: 38,
            height: 36,
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: widget.selected
                  ? DsColors.primary.withValues(alpha: 0.13)
                  : (_hover && widget.enabled
                        ? theme.colorScheme.onSurface.withValues(alpha: 0.07)
                        : Colors.transparent),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Stack(
              alignment: Alignment.center,
              children: [
                d.markup != null
                    ? MarkupToolIcon(d.markup!, size: 21, color: color)
                    : Icon(d.icon, size: 21, color: color),
                // A tool picked from "More" that is not pinned yet.
                if (widget.temporary)
                  Positioned(
                    right: -2,
                    bottom: -1,
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: DsColors.primary,
                        shape: BoxShape.circle,
                      ),
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

/// The blue "…" under the tools: all tools and the customise panel.
class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.onOpen});

  final ValueChanged<Rect> onOpen;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) => Tooltip(
        message: 'More tools · customise this bar',
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 3, 5, 0),
          child: Material(
            color: DsColors.primary,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              key: const Key('pdf_viewer_markup_palette_more'),
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                final box = context.findRenderObject()! as RenderBox;
                onOpen(box.localToGlobal(Offset.zero) & box.size);
              },
              child: const SizedBox(
                width: 36,
                height: 30,
                child: Icon(Icons.more_horiz, color: Colors.white, size: 20),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
