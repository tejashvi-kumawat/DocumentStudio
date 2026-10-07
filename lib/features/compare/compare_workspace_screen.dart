import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:document_studio/app/keyboard/text_input_guard.dart';
import 'package:document_studio/app/providers.dart';
import 'package:document_studio/design_system/adaptive/ds_adaptive.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/domain/compare/compare_models.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/compare/compare_controller.dart';
import 'package:document_studio/features/compare/compare_overlay_view.dart';
import 'package:document_studio/features/compare/compare_page_painter.dart';
import 'package:document_studio/features/compare/compare_report_export.dart';
import 'package:document_studio/features/compare/compare_results_sidebar.dart';
import 'package:document_studio/features/compare/compare_side_by_side.dart';
import 'package:document_studio/features/document_lifecycle/document_save_result_actions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the full-screen Compare workspace with a fade/scale transition.
Future<void> openCompareWorkspace(
  BuildContext context, {
  required CompareSource oldSource,
  required CompareSource newSource,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: DsMotion.contentReveal,
      reverseTransitionDuration: DsMotion.dialogDuration,
      pageBuilder: (_, _, _) =>
          CompareWorkspaceScreen(oldSource: oldSource, newSource: newSource),
      transitionsBuilder: (_, animation, _, child) =>
          DsMotion.fadeScaleTransition(animation, child, scaleBegin: 0.985),
    ),
  );
}

const _phoneBreakpoint = 600.0;
const _originalColor = Color(0xFF6B7280);

/// Compare PDFs: synchronized side-by-side pages with word-level highlights,
/// a filterable change list, pixel overlay modes and a PDF report.
class CompareWorkspaceScreen extends ConsumerStatefulWidget {
  const CompareWorkspaceScreen({
    super.key,
    required this.oldSource,
    required this.newSource,
  });

  final CompareSource oldSource;
  final CompareSource newSource;

  @override
  ConsumerState<CompareWorkspaceScreen> createState() =>
      _CompareWorkspaceScreenState();
}

class _CompareWorkspaceScreenState extends ConsumerState<CompareWorkspaceScreen>
    with SingleTickerProviderStateMixin {
  late final CompareController _c = CompareController(
    oldSource: widget.oldSource,
    newSource: widget.newSource,
  );
  final _scroll = ScrollController();
  final _hScroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'compare-workspace');
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    value: 1,
  );
  final _visibleRow = ValueNotifier<int>(0);

  /// Live pinch / trackpad scale preview; committed to the zoom on release.
  final _pinch = ValueNotifier<double>(1);
  Offset _pinchFocal = Offset.zero;
  final _touches = <int, Offset>{};
  double? _pinchStartDistance;

  final _exportProgress = ValueNotifier<double?>(null);
  CompareSbsGeometry? _geometry;
  double _viewportH = 600;
  bool? _sidebarOpen;
  bool _phone = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChanged);
    _scroll.addListener(_onScroll);
    unawaited(_c.run());
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    _c.dispose();
    _scroll.dispose();
    _hScroll.dispose();
    _focus.dispose();
    _flash.dispose();
    _visibleRow.dispose();
    _pinch.dispose();
    _exportProgress.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    final g = _geometry;
    if (g == null || !_scroll.hasClients) return;
    _visibleRow.value = g.rowAt(_scroll.offset + _viewportH * 0.3);
  }

  // ---------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------

  void _open(CompareChange ch) {
    _c.select(ch.id);
    _flash.forward(from: 0);
    if (_c.viewMode == CompareViewMode.sideBySide) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(ch));
    }
  }

  void _scrollTo(CompareChange ch) {
    final g = _geometry;
    final r = _c.result;
    if (g == null || r == null || !_scroll.hasClients) return;
    final pos = _scroll.position;
    final t = g.targetFor(r, ch, pos.viewportDimension);
    final target = t.y.clamp(0.0, pos.maxScrollExtent);
    if ((target - pos.pixels).abs() > pos.viewportDimension * 6) {
      _scroll.jumpTo(target);
    } else {
      unawaited(
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 420),
          curve: DsMotion.emphasizedCurve,
        ),
      );
    }
    if (_hScroll.hasClients && _hScroll.position.maxScrollExtent > 0) {
      final h = _hScroll.position;
      unawaited(
        _hScroll.animateTo(
          (t.x - h.viewportDimension * 0.25).clamp(0.0, h.maxScrollExtent),
          duration: const Duration(milliseconds: 420),
          curve: DsMotion.emphasizedCurve,
        ),
      );
    }
  }

  void _step(int delta) {
    final ch = _c.step(delta);
    if (ch != null) _open(ch);
  }

  void _scrollToRow(int row) {
    final g = _geometry;
    if (g == null || !_scroll.hasClients || row >= g.offsets.length) return;
    unawaited(
      _scroll.animateTo(
        g.offsets[row].clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 380),
        curve: DsMotion.emphasizedCurve,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Zoom (buttons, Ctrl+wheel, trackpad, pinch) anchored at a focal point
  // ---------------------------------------------------------------------

  void _zoom(double factor, {Offset? focal}) {
    final g = _geometry;
    final before = _c.zoom;
    _c.setZoom(before * factor);
    if (g == null || _c.zoom == before) return;
    final f = focal ?? Offset(0, _viewportH / 2);
    final y = _scroll.hasClients ? _scroll.offset : 0.0;
    final x = _hScroll.hasClients ? _hScroll.offset : 0.0;
    final ratioY = g.total <= 0 ? 0.0 : (y + f.dy) / g.total;
    final ratioX = g.contentWidth <= 0 ? 0.0 : (x + f.dx) / g.contentWidth;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ng = _geometry;
      if (ng == null) return;
      if (_scroll.hasClients) {
        _scroll.jumpTo(
          (ratioY * ng.total - f.dy).clamp(
            0.0,
            _scroll.position.maxScrollExtent,
          ),
        );
      }
      if (_hScroll.hasClients) {
        _hScroll.jumpTo(
          (ratioX * ng.contentWidth - f.dx).clamp(
            0.0,
            _hScroll.position.maxScrollExtent,
          ),
        );
      }
    });
  }

  void _resetZoom() => _zoom(1 / _c.zoom);

  double _clampPinch(double s) =>
      s.clamp(0.5 / _c.zoom, 4.0 / _c.zoom).toDouble();

  void _commitPinch() {
    final s = _pinch.value;
    _pinch.value = 1;
    if ((s - 1).abs() > 0.02) _zoom(s, focal: _pinchFocal);
  }

  double _touchDistance() {
    final p = _touches.values.take(2).toList();
    return (p[0] - p[1]).distance;
  }

  void _onPointerDown(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.touch) return;
    _touches[e.pointer] = e.localPosition;
    if (_touches.length == 2) {
      _pinchStartDistance = math.max(1, _touchDistance());
      final p = _touches.values.toList();
      _pinchFocal = (p[0] + p[1]) / 2;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_touches.containsKey(e.pointer)) return;
    _touches[e.pointer] = e.localPosition;
    final start = _pinchStartDistance;
    if (start != null && _touches.length >= 2) {
      _pinch.value = _clampPinch(_touchDistance() / start);
    }
  }

  void _onPointerUp(PointerEvent e) {
    if (_touches.remove(e.pointer) == null) return;
    if (_pinchStartDistance != null && _touches.length < 2) {
      _pinchStartDistance = null;
      _commitPinch();
    }
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final hw = HardwareKeyboard.instance;
    if (!hw.isControlPressed && !hw.isMetaPressed) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
      final dy = (ev as PointerScrollEvent).scrollDelta.dy;
      _zoom(dy < 0 ? 1.1 : 1 / 1.1, focal: ev.localPosition);
    });
  }

  // ---------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------

  Future<void> _export() async {
    final r = _c.result;
    final a = _c.oldPdf;
    final b = _c.newPdf;
    if (r == null || a == null || b == null || _exportProgress.value != null) {
      return;
    }
    _exportProgress.value = 0;
    try {
      final bytes = await buildCompareReport(
        result: r,
        oldPdf: a,
        newPdf: b,
        oldName: _c.oldSource.file.displayName,
        newName: _c.newSource.file.displayName,
        onProgress: (p) {
          if (mounted) _exportProgress.value = p;
        },
      );
      if (!mounted) return;
      final storage = ref.read(fileStorageProvider);
      final base = _c.newSource.file.displayName.replaceAll(
        RegExp(r'\.pdf$', caseSensitive: false),
        '',
      );
      final path = await storage.pickSavePath(
        suggestedName: 'Compare report - $base.pdf',
        bytes: bytes,
        allowedExtensions: const ['pdf'],
        mimeType: 'application/pdf',
      );
      if (path == null) return;
      await storage.writeAtomic(
        destinationPath: path,
        writeToTemp: (t) => File(t).writeAsBytes(bytes, flush: true),
      );
      if (!mounted) return;
      showDocumentSaveResultActions(
        context,
        file: LocalFileRef(
          path: path,
          displayName: path.split(Platform.pathSeparator).last,
        ),
        message: 'Compare report saved',
        showEditInWorkspace: false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not export report: $e')));
      }
    } finally {
      if (mounted) _exportProgress.value = null;
    }
  }

  // ---------------------------------------------------------------------
  // Keyboard
  // ---------------------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    final hw = HardwareKeyboard.instance;
    final ctrl = hw.isControlPressed || hw.isMetaPressed;
    final shift = hw.isShiftPressed;
    if (k == LogicalKeyboardKey.escape) {
      if (_c.selectedId != null) {
        _c.select(null);
      } else if (_c.running) {
        _c.cancel();
      } else {
        unawaited(Navigator.of(context).maybePop());
      }
      return KeyEventResult.handled;
    }
    if (_c.result == null) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.f3 || (k == LogicalKeyboardKey.keyN && !ctrl)) {
      _step(shift ? -1 : 1);
    } else if (k == LogicalKeyboardKey.keyP && !ctrl) {
      _step(-1);
    } else if (ctrl &&
        (k == LogicalKeyboardKey.equal ||
            k == LogicalKeyboardKey.add ||
            k == LogicalKeyboardKey.numpadAdd)) {
      _zoom(1.2);
    } else if (ctrl &&
        (k == LogicalKeyboardKey.minus ||
            k == LogicalKeyboardKey.numpadSubtract)) {
      _zoom(1 / 1.2);
    } else if (ctrl &&
        (k == LogicalKeyboardKey.digit0 || k == LogicalKeyboardKey.numpad0)) {
      _resetZoom();
    } else if (_c.viewMode == CompareViewMode.overlay &&
        !ctrl &&
        (k == LogicalKeyboardKey.arrowLeft ||
            k == LogicalKeyboardKey.arrowRight)) {
      _c.setOverlayRow(
        _c.overlayRow + (k == LogicalKeyboardKey.arrowLeft ? -1 : 1),
      );
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  void _setViewMode(CompareViewMode m) {
    if (m == CompareViewMode.overlay && _c.selected == null) {
      _c.setOverlayRow(_visibleRow.value);
    }
    _c.setViewMode(m);
  }

  Future<void> _showChangesSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: DsColors.groupedBackground(Theme.of(context).brightness),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(DsSpacing.radiusHero),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => CompareResultsSidebar(
          controller: _c,
          scrollController: scroll,
          showHandle: true,
          onOpenChange: (ch) {
            Navigator.of(ctx).pop();
            _open(ch);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: TextInputGuard.guardFocusHandler(_onKey),
      child: Scaffold(
        backgroundColor: DsColors.groupedBackground(brightness),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              _phone = box.maxWidth < _phoneBreakpoint;
              final ready = _c.result != null;
              return Column(
                children: [
                  _Toolbar(
                    controller: _c,
                    width: box.maxWidth,
                    phone: _phone,
                    sidebarOpen: _sidebarOpen ?? box.maxWidth >= 900,
                    exportProgress: _exportProgress,
                    onToggleSidebar: () => setState(
                      () =>
                          _sidebarOpen = !(_sidebarOpen ?? box.maxWidth >= 900),
                    ),
                    onZoomIn: () => _zoom(1.2),
                    onZoomOut: () => _zoom(1 / 1.2),
                    onZoomReset: _resetZoom,
                    onPrev: () => _step(-1),
                    onNext: () => _step(1),
                    onExport: () => unawaited(_export()),
                    onSwap: () => unawaited(_c.swap()),
                    onViewMode: _setViewMode,
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: DsMotion.contentReveal,
                      switchInCurve: DsMotion.switchCurve,
                      transitionBuilder: (child, a) =>
                          DsMotion.fadeRiseTransition(a, child),
                      child: ready
                          ? _results(box.maxWidth)
                          : _c.stage == CompareStage.failed ||
                                _c.stage == CompareStage.cancelled
                          ? _Failed(
                              key: const ValueKey('failed'),
                              controller: _c,
                            )
                          : _CompareProgress(
                              key: const ValueKey('progress'),
                              controller: _c,
                            ),
                    ),
                  ),
                  if (_phone && ready)
                    _PhoneBar(
                      controller: _c,
                      onList: () => unawaited(_showChangesSheet()),
                      onPrev: () => _step(-1),
                      onNext: () => _step(1),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _results(double width) {
    final view = AnimatedSwitcher(
      duration: DsMotion.switchDuration,
      switchInCurve: DsMotion.switchCurve,
      child: _c.viewMode == CompareViewMode.sideBySide
          ? _sideBySide()
          : CompareOverlayView(key: const ValueKey('overlay'), controller: _c),
    );
    if (_phone)
      return KeyedSubtree(key: const ValueKey('results'), child: view);
    final sidebarW = width < 1100 ? 300.0 : 360.0;
    final open = _sidebarOpen ?? width >= 900;
    return Row(
      key: const ValueKey('results'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: DsMotion.sidebarDuration,
          curve: DsMotion.shellCurve,
          width: open ? sidebarW : 0,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: sidebarW,
              maxWidth: sidebarW,
              child: CompareResultsSidebar(controller: _c, onOpenChange: _open),
            ),
          ),
        ),
        if (open) const VerticalDivider(width: 1),
        Expanded(child: view),
      ],
    );
  }

  Widget _sideBySide() {
    return LayoutBuilder(
      key: const ValueKey('sbs'),
      builder: (context, box) {
        final r = _c.result!;
        final g = _geometry = CompareSbsGeometry(r, box.maxWidth, _c.zoom);
        _viewportH = box.maxHeight;
        return Listener(
          onPointerSignal: _onPointerSignal,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          onPointerPanZoomStart: (e) => _pinchFocal = e.localPosition,
          onPointerPanZoomUpdate: (e) {
            if ((e.scale - 1).abs() > 0.001) {
              _pinch.value = _clampPinch(e.scale);
            }
          },
          onPointerPanZoomEnd: (_) => _commitPinch(),
          child: Stack(
            children: [
              Positioned.fill(
                child: ValueListenableBuilder<double>(
                  valueListenable: _pinch,
                  builder: (context, s, child) {
                    if (s == 1) return child!;
                    final f = _pinchFocal;
                    return Transform(
                      transform: Matrix4.diagonal3Values(s, s, 1)
                        ..setTranslationRaw(f.dx * (1 - s), f.dy * (1 - s), 0),
                      child: child,
                    );
                  },
                  child: RepaintBoundary(
                    child: CompareSideBySide(
                      controller: _c,
                      geometry: g,
                      scroll: _scroll,
                      hScroll: _hScroll,
                      flash: _flash,
                    ),
                  ),
                ),
              ),
              if (!_phone)
                Positioned(
                  right: 18,
                  bottom: 18,
                  child: _Minimap(
                    controller: _c,
                    visibleRow: _visibleRow,
                    onRow: _scrollToRow,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Toolbar
// ---------------------------------------------------------------------------

enum _MenuAction {
  zoomIn,
  zoomOut,
  zoomReset,
  swap,
  export,
  sideBySide,
  overlay,
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.width,
    required this.phone,
    required this.sidebarOpen,
    required this.exportProgress,
    required this.onToggleSidebar,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomReset,
    required this.onPrev,
    required this.onNext,
    required this.onExport,
    required this.onSwap,
    required this.onViewMode,
  });

  final CompareController controller;
  final double width;
  final bool phone;
  final bool sidebarOpen;
  final ValueNotifier<double?> exportProgress;
  final VoidCallback onToggleSidebar;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomReset;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onExport;
  final VoidCallback onSwap;
  final ValueChanged<CompareViewMode> onViewMode;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final ready = c.result != null;
    final sbs = c.viewMode == CompareViewMode.sideBySide;
    final showChips = width >= 1100;
    final showZoom = ready && sbs && width >= 820;
    final showNav = ready && !phone;
    final exportLabel = width >= 980;

    final menu = PopupMenuButton<_MenuAction>(
      tooltip: 'More',
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (a) => switch (a) {
        _MenuAction.zoomIn => onZoomIn(),
        _MenuAction.zoomOut => onZoomOut(),
        _MenuAction.zoomReset => onZoomReset(),
        _MenuAction.swap => onSwap(),
        _MenuAction.export => onExport(),
        _MenuAction.sideBySide => onViewMode(CompareViewMode.sideBySide),
        _MenuAction.overlay => onViewMode(CompareViewMode.overlay),
      },
      itemBuilder: (context) => [
        if (ready && phone) ...[
          CheckedPopupMenuItem(
            value: _MenuAction.sideBySide,
            checked: sbs,
            child: const Text('Side by side'),
          ),
          CheckedPopupMenuItem(
            value: _MenuAction.overlay,
            checked: !sbs,
            child: const Text('Overlay'),
          ),
          const PopupMenuDivider(),
        ],
        if (ready && sbs && !showZoom) ...[
          const PopupMenuItem(
            value: _MenuAction.zoomIn,
            child: Text('Zoom in'),
          ),
          const PopupMenuItem(
            value: _MenuAction.zoomOut,
            child: Text('Zoom out'),
          ),
          PopupMenuItem(
            value: _MenuAction.zoomReset,
            child: Text('Fit width (${(c.zoom * 100).round()}%)'),
          ),
          const PopupMenuDivider(),
        ],
        PopupMenuItem(
          value: _MenuAction.swap,
          enabled: !c.running,
          child: const Text('Swap original and revised'),
        ),
        if (ready && phone)
          const PopupMenuItem(
            value: _MenuAction.export,
            child: Text('Export PDF report'),
          ),
      ],
    );

    Widget fileChip(String role, LocalFileRef f, Color color) => Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              role,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: color,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                f.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );

    final title = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Compare',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          '${c.oldSource.file.displayName}  ⇄  ${c.newSource.file.displayName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall,
        ),
      ],
    );

    return Container(
      height: 52,
      color: DsColors.windowChrome(brightness),
      padding: const EdgeInsets.symmetric(horizontal: DsSpacing.xs),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close compare (Esc)',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          if (!phone)
            IconButton(
              tooltip: sidebarOpen ? 'Hide changes' : 'Show changes',
              icon: Icon(
                sidebarOpen ? Icons.view_sidebar : Icons.view_sidebar_outlined,
              ),
              onPressed: ready ? onToggleSidebar : null,
            ),
          const SizedBox(width: DsSpacing.xs),
          Expanded(
            child: showChips
                ? Row(
                    children: [
                      fileChip('ORIGINAL', c.oldSource.file, _originalColor),
                      IconButton(
                        tooltip: 'Swap original and revised',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                        onPressed: c.running ? null : onSwap,
                      ),
                      fileChip(
                        'REVISED',
                        c.newSource.file,
                        compareChangedColor,
                      ),
                    ],
                  )
                : title,
          ),
          const SizedBox(width: DsSpacing.sm),
          if (ready && !phone)
            DsAdaptiveSegmented<CompareViewMode>(
              value: c.viewMode,
              onChanged: onViewMode,
              segments: {
                CompareViewMode.sideBySide: (
                  label: width >= 1000 ? 'Side by side' : null,
                  icon: Icons.view_column_outlined,
                  tooltip: 'Side by side',
                ),
                CompareViewMode.overlay: (
                  label: width >= 1000 ? 'Overlay' : null,
                  icon: Icons.layers_outlined,
                  tooltip: 'Overlay (swipe, onion skin, heatmap)',
                ),
              },
            ),
          if (showZoom) ...[
            const SizedBox(width: DsSpacing.xs),
            IconButton(
              tooltip: 'Zoom out (Ctrl −)',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove, size: 18),
              onPressed: onZoomOut,
            ),
            InkWell(
              onTap: onZoomReset,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text(
                  '${(c.zoom * 100).round()}%',
                  style: theme.textTheme.labelMedium,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Zoom in (Ctrl +)',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add, size: 18),
              onPressed: onZoomIn,
            ),
          ],
          if (showNav) ...[
            const SizedBox(width: DsSpacing.xs),
            _ChangeNav(controller: c, onPrev: onPrev, onNext: onNext),
          ],
          if (ready && !phone) ...[
            const SizedBox(width: DsSpacing.xs),
            ValueListenableBuilder<double?>(
              valueListenable: exportProgress,
              builder: (context, p, _) {
                final busy = p != null;
                final icon = busy
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: p <= 0 ? null : p,
                        ),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined, size: 18);
                if (!exportLabel) {
                  return IconButton(
                    tooltip: 'Export PDF report',
                    onPressed: busy ? null : onExport,
                    icon: icon,
                  );
                }
                return FilledButton.icon(
                  onPressed: busy ? null : onExport,
                  icon: icon,
                  label: Text(busy ? 'Exporting…' : 'Export report'),
                );
              },
            ),
          ],
          menu,
        ],
      ),
    );
  }
}

class _ChangeNav extends StatelessWidget {
  const _ChangeNav({
    required this.controller,
    required this.onPrev,
    required this.onNext,
  });

  final CompareController controller;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = controller.visibleChanges.length;
    final idx = controller.selectedVisibleIndex;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Previous change (Shift+F3 / P)',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
          onPressed: visible == 0 ? null : onPrev,
        ),
        AnimatedSwitcher(
          duration: DsMotion.hoverDuration,
          child: Text(
            visible == 0 ? '0' : '${idx < 0 ? '–' : idx + 1} / $visible',
            key: ValueKey('$idx/$visible'),
            style: theme.textTheme.labelMedium?.copyWith(
              color: DsColors.textSecondary(theme.brightness),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next change (F3 / N)',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          onPressed: visible == 0 ? null : onNext,
        ),
      ],
    );
  }
}

class _PhoneBar extends StatelessWidget {
  const _PhoneBar({
    required this.controller,
    required this.onList,
    required this.onPrev,
    required this.onNext,
  });

  final CompareController controller;
  final VoidCallback onList;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final n = controller.visibleChanges.length;
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: DsColors.windowChrome(brightness),
        border: Border(top: BorderSide(color: DsColors.border(brightness))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: DsSpacing.xs),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: onList,
            icon: const Icon(Icons.list_alt_rounded, size: 18),
            label: Text(
              n == 0 ? 'No changes' : '$n change${n == 1 ? '' : 's'}',
            ),
          ),
          const Spacer(),
          _ChangeNav(controller: controller, onPrev: onPrev, onNext: onNext),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Progress / failure
// ---------------------------------------------------------------------------

class _CompareProgress extends StatelessWidget {
  const _CompareProgress({super.key, required this.controller});

  final CompareController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    const stages = [
      CompareStage.readingOld,
      CompareStage.readingNew,
      CompareStage.analyzing,
    ];
    final current = stages.indexOf(c.stage);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DsSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.all(DsSpacing.xl),
            decoration: BoxDecoration(
              color: DsColors.groupedCell(brightness),
              borderRadius: BorderRadius.circular(DsSpacing.radiusHero),
              border: Border.all(color: DsColors.border(brightness)),
              boxShadow: DsSpacing.cardShadowLight(opacity: 0.08),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.difference_outlined,
                      color: compareChangedColor,
                    ),
                    const SizedBox(width: DsSpacing.sm),
                    Expanded(
                      child: Text(
                        'Comparing documents',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DsSpacing.lg),
                ValueListenableBuilder<double>(
                  valueListenable: c.progress,
                  builder: (context, p, _) => TweenAnimationBuilder<double>(
                    tween: Tween(end: p),
                    duration: const Duration(milliseconds: 250),
                    builder: (context, v, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: v, minHeight: 6),
                    ),
                  ),
                ),
                const SizedBox(height: DsSpacing.lg),
                for (var i = 0; i < stages.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: DsSpacing.sm),
                    child: Row(
                      children: [
                        AnimatedSwitcher(
                          duration: DsMotion.switchDuration,
                          transitionBuilder: (child, a) =>
                              ScaleTransition(scale: a, child: child),
                          child: i < current
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  key: ValueKey('done'),
                                  size: 20,
                                  color: compareInsertColor,
                                )
                              : i == current
                              ? const SizedBox(
                                  key: ValueKey('run'),
                                  width: 20,
                                  height: 20,
                                  child: Center(
                                    child: DsAdaptiveProgress(size: 16),
                                  ),
                                )
                              : Icon(
                                  Icons.radio_button_unchecked,
                                  key: const ValueKey('todo'),
                                  size: 20,
                                  color: theme.disabledColor,
                                ),
                        ),
                        const SizedBox(width: DsSpacing.sm),
                        Expanded(
                          child: AnimatedDefaultTextStyle(
                            duration: DsMotion.switchDuration,
                            style: theme.textTheme.bodyMedium!.copyWith(
                              fontWeight: i == current
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: i > current
                                  ? DsColors.textSecondary(brightness)
                                  : DsColors.textPrimary(brightness),
                            ),
                            child: Text(stages[i].label),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: DsSpacing.xs),
                Text(
                  'Text is read on the PDF engine’s worker and diffed in a '
                  'background isolate, so the app stays responsive.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: DsSpacing.md),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: c.cancel,
                    child: const Text('Cancel'),
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

class _Failed extends StatefulWidget {
  const _Failed({super.key, required this.controller});

  final CompareController controller;

  @override
  State<_Failed> createState() => _FailedState();
}

class _FailedState extends State<_Failed> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _unlock() {
    final pw = _password.text;
    if (pw.isEmpty) return;
    unawaited(widget.controller.unlock(pw));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final cancelled = c.stage == CompareStage.cancelled;
    final locked = c.lockedIsOld;
    if (locked != null) {
      final name = (locked ? c.oldSource : c.newSource).file.displayName;
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(DsSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 40),
                const SizedBox(height: DsSpacing.sm),
                Text(
                  '“$name” is password protected',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: DsSpacing.md),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _unlock(),
                ),
                const SizedBox(height: DsSpacing.md),
                DsPrimaryButton(
                  label: 'Unlock & compare',
                  icon: Icons.lock_open_rounded,
                  onPressed: _unlock,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Center(
      child: DsEmptyState(
        title: cancelled ? 'Compare cancelled' : 'Compare failed',
        subtitle: cancelled ? null : (c.error ?? 'Unknown error'),
        action: DsPrimaryButton(
          label: cancelled ? 'Compare again' : 'Try again',
          icon: Icons.refresh,
          onPressed: () => unawaited(c.run()),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Minimap
// ---------------------------------------------------------------------------

/// Compact vertical strip of aligned rows; marks show rows with changes.
class _Minimap extends StatelessWidget {
  const _Minimap({
    required this.controller,
    required this.visibleRow,
    required this.onRow,
  });

  final CompareController controller;
  final ValueListenable<int> visibleRow;
  final ValueChanged<int> onRow;

  @override
  Widget build(BuildContext context) {
    final r = controller.result!;
    final n = r.rows.length;
    if (n < 2) return const SizedBox.shrink();
    final brightness = Theme.of(context).brightness;
    return Container(
      width: 22,
      height: 180,
      decoration: BoxDecoration(
        color: DsColors.groupedCell(brightness).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: DsColors.border(brightness)),
        boxShadow: DsSpacing.cardShadowLight(opacity: 0.1),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final inner = box.maxHeight - 12;
          double y(int row) => 6 + inner * row / (n - 1);
          Color? markColor(int row) {
            final pair = r.rows[row];
            if (pair.a == null) return compareInsertColor;
            if (pair.b == null) return compareDeleteColor;
            final changes = controller.changesOnRow(row);
            if (changes.isEmpty) return null;
            return compareColor(changes.first);
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => onRow(
              (((d.localPosition.dy - 6) / inner) * (n - 1)).round().clamp(
                0,
                n - 1,
              ),
            ),
            child: Stack(
              children: [
                for (var row = 0; row < n; row++)
                  if (markColor(row) case final color?)
                    Positioned(
                      left: 7,
                      top: y(row) - 2,
                      child: Container(
                        width: 8,
                        height: 4,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ValueListenableBuilder<int>(
                  valueListenable: visibleRow,
                  builder: (context, v, _) => AnimatedPositioned(
                    duration: DsMotion.hoverDuration,
                    left: 3,
                    top: y(v.clamp(0, n - 1)) - 5,
                    child: Container(
                      width: 16,
                      height: 10,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: DsColors.textPrimary(brightness),
                          width: 1.4,
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
