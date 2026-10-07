import 'package:document_studio/features/pdf_viewer/widgets/viewer_nav_forwarder.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:document_studio/app/tree_unlock.dart';
import 'package:document_studio/domain/pdf_markup/markup_geometry.dart';
import 'package:document_studio/domain/pdf_markup/markup_objects.dart';
import 'package:document_studio/domain/pdf_markup/pdf_page_geometry.dart';
import 'package:document_studio/features/annotations/markup/markup_context_toolbar.dart';
import 'package:document_studio/features/annotations/markup/markup_dialogs.dart';
import 'package:document_studio/features/annotations/markup/markup_editor_controller.dart';
import 'package:document_studio/features/annotations/markup/markup_format_bar.dart';
import 'package:document_studio/features/annotations/markup/markup_keyboard.dart';
import 'package:document_studio/features/annotations/markup/markup_painter.dart';
import 'package:document_studio/features/annotations/markup/markup_text_layout.dart';
import 'package:document_studio/features/annotations/markup/markup_text_snap.dart';
import 'package:document_studio/features/annotations/markup/markup_tool.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

/// Viewer callbacks the page layer needs.
class MarkupPageActions {
  const MarkupPageActions({
    required this.activateLink,
    required this.editLink,
    required this.pickImage,
  });

  /// Read mode click on a link: open the URL / go to the page.
  final void Function(LinkMarkup link) activateLink;

  /// Link editor dialog. Returns null when cancelled.
  final Future<LinkMarkup?> Function(LinkMarkup link, {required bool isNew})
  editLink;

  /// Image picker: encoded bytes + aspect ratio (w/h).
  final Future<(Uint8List, double)?> Function() pickImage;
}

/// Builds the markup overlay for one page (use from `pageOverlaysBuilder`).
Widget buildMarkupPageLayer({
  required MarkupEditorController controller,
  required PdfPage page,
  required Rect pageRect,
  required MarkupPageActions actions,
  PdfViewerController? viewerController,
}) {
  return Positioned.fill(
    child: MarkupPageLayer(
      key: ValueKey('markup-page-${page.pageNumber}'),
      controller: controller,
      page: page,
      pageSize: pageRect.size,
      actions: actions,
      viewerController: viewerController,
    ),
  );
}

enum _DragKind {
  none,
  move,
  resize,
  rotate,
  lineEnd,
  calloutTarget,
  calloutKnee,
  marquee,
  freehand,
  shape,
  textMarkup,
  eraser,
  linkRect,
  textRect,
  callout,
  imageRect,
  groupResize,
  tap,
}

class _Handle {
  const _Handle(this.kind, this.index, this.at);
  final _DragKind kind;
  final int index;
  final Offset at;
}

class MarkupPageLayer extends StatefulWidget {
  const MarkupPageLayer({
    super.key,
    required this.controller,
    required this.page,
    required this.pageSize,
    required this.actions,
    this.viewerController,
  });

  final MarkupEditorController controller;
  final PdfPage page;
  final Size pageSize;
  final MarkupPageActions actions;
  final PdfViewerController? viewerController;

  @override
  State<MarkupPageLayer> createState() => _MarkupPageLayerState();
}

class _MarkupPageLayerState extends State<MarkupPageLayer>
    with SingleTickerProviderStateMixin {
  MarkupEditorController get c => widget.controller;
  int get pageNo => widget.page.pageNumber;

  PdfPageGeometry get geo =>
      c.geometryOf(pageNo) ??
      PdfPageGeometry.display(widget.page.width, widget.page.height);

  double get s => widget.pageSize.width / geo.displayWidth;

  Offset _pt(Offset local) => local / s;

  // Pointer state.
  int? _pointer;
  _DragKind _drag = _DragKind.none;
  Offset _start = Offset.zero;
  bool _moved = false;
  Map<String, MarkupObject> _originals = {};
  _Handle? _handle;
  double _rotateStartAngle = 0;
  final List<Offset> _points = [];
  final Set<String> _erased = {};
  Future<MarkupPageText?>? _text;
  MarkupPageText? _textReady;
  DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastTapId;
  Offset _lastTapPt = Offset.zero;
  MouseCursor _cursor = MouseCursor.defer;
  String? _hoverId;
  String? _flashId;
  Timer? _flashTimer;
  bool _dragging = false;

  /// Selection handles fade/scale in when the selection changes.
  late final AnimationController _selAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: 1,
  );
  String _selSig = '';

  /// Bigger handles and hit targets for fingers.
  bool _touchUi =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  // Snapping state captured at drag start.
  List<double> _snapXs = const [];
  List<double> _snapYs = const [];
  Rect? _box0;

  @override
  void initState() {
    super.initState();
    c.addListener(_onController);
    c.reveal.addListener(_onReveal);
    _onReveal();
  }

  @override
  void didUpdateWidget(covariant MarkupPageLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onController);
      oldWidget.controller.reveal.removeListener(_onReveal);
      c.addListener(_onController);
      c.reveal.addListener(_onReveal);
    }
    if (!identical(oldWidget.page, widget.page)) {
      _text = null;
      _textReady = null;
    }
  }

  @override
  void dispose() {
    c.removeListener(_onController);
    c.reveal.removeListener(_onReveal);
    _flashTimer?.cancel();
    _selAnim.dispose();
    super.dispose();
  }

  void _onController() {
    if (!mounted) return;
    final sig = [
      for (final o in c.selectedObjects)
        if (o.page == pageNo) o.id,
    ].join('|');
    if (sig != _selSig) {
      _selSig = sig;
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (sig.isNotEmpty && !reduce) {
        _selAnim.forward(from: 0);
      } else {
        _selAnim.value = 1;
      }
    }
    setState(() {});
  }

  void _onReveal() {
    final id = c.reveal.value;
    if (id == null) return;
    final o = c.objectById(id);
    if (o == null || o.page != pageNo) return;
    setState(() => _flashId = id);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _flashId = null);
    });
  }

  // --------------------------------------------------------------- hits

  double get _tol => 5 / s;

  MarkupObject? _hitObject(Offset p) {
    final list = c.objectsOn(pageNo);
    for (var i = list.length - 1; i >= 0; i--) {
      final o = c.displayed(list[i]);
      if (o.hidden) continue;
      if (o.hitTest(p, _tol)) return o;
    }
    return null;
  }

  MarkupObject? get _single {
    final sel = c.selectedObjects;
    if (sel.length != 1 || sel.first.page != pageNo) return null;
    return c.displayed(sel.first);
  }

  List<MarkupObject> get _pageSelection => [
    for (final o in c.selectedObjects)
      if (o.page == pageNo) c.displayed(o),
  ];

  /// Union box of a multi-selection (group or several objects).
  Rect? get _groupBox {
    final sel = _pageSelection;
    if (sel.length < 2) return null;
    return sel.map((o) => o.bounds).reduce((a, b) => a.expandToInclude(b));
  }

  List<_Handle> _groupHandles() {
    final b = _groupBox;
    if (b == null || _pageSelection.any((o) => o.locked)) return const [];
    if (!_pageSelection.any((o) => o.canResize)) return const [];
    return [
      _Handle(_DragKind.groupResize, 0, b.topLeft),
      _Handle(_DragKind.groupResize, 2, b.topRight),
      _Handle(_DragKind.groupResize, 4, b.bottomRight),
      _Handle(_DragKind.groupResize, 6, b.bottomLeft),
    ];
  }

  List<_Handle> get _visibleHandles {
    final o = _single;
    if (o != null) return _handlesFor(o);
    return _groupHandles();
  }

  double get _rotateOffsetPx => _touchUi ? 34.0 : 26.0;

  List<_Handle> _handlesFor(MarkupObject o) {
    if (o.locked) return const [];
    final out = <_Handle>[];
    if (o is ShapeMarkup &&
        (o.kind == ShapeKind.line || o.kind == ShapeKind.arrow) &&
        o.points.length >= 2) {
      out
        ..add(_Handle(_DragKind.lineEnd, 0, o.points.first))
        ..add(_Handle(_DragKind.lineEnd, 1, o.points.last));
      return out;
    }
    if (o is TextBoxMarkup && o.isCallout) {
      out
        ..add(_Handle(_DragKind.calloutTarget, 0, o.calloutPoints[0]))
        ..add(_Handle(_DragKind.calloutKnee, 1, o.calloutPoints[1]));
    }
    final frameBased =
        o is TextBoxMarkup ||
        o is ImageMarkup ||
        o is LinkMarkup ||
        (o is ShapeMarkup && o.isFrameBased);
    final f = frameBased ? o.frame : o.bounds;
    final rot = frameBased ? o.rotation : 0.0;
    final m = frameToDisplay(f, rot);
    if (o.canResize) {
      final w = f.width, h = f.height;
      final local = <Offset>[
        Offset.zero,
        Offset(w / 2, 0),
        Offset(w, 0),
        Offset(w, h / 2),
        Offset(w, h),
        Offset(w / 2, h),
        Offset(0, h),
        Offset(0, h / 2),
      ];
      for (var i = 0; i < 8; i++) {
        if (o is TextBoxMarkup && (i == 1 || i == 5)) continue;
        out.add(_Handle(_DragKind.resize, i, m.apply(local[i])));
      }
    }
    if (o.canRotate && o is! LinkMarkup) {
      out.add(
        _Handle(
          _DragKind.rotate,
          0,
          m.apply(Offset(f.width / 2, -_rotateOffsetPx / s)),
        ),
      );
    }
    return out;
  }

  _Handle? _hitHandle(Offset p) {
    final r = (_touchUi ? 20.0 : 8.0) / s;
    _Handle? best;
    var bestD = double.infinity;
    for (final h in _visibleHandles.reversed) {
      final d = (h.at - p).distance;
      if (d <= r && d < bestD) {
        best = h;
        bestD = d;
      }
    }
    return best;
  }

  // ----------------------------------------------------------- snapping

  bool get _snapOn => c.snapEnabled && !HardwareKeyboard.instance.isAltPressed;

  double get _snapTol => (_touchUi ? 8.0 : 6.0) / s;

  /// Page edges/center and the edges/centers of other visible objects.
  void _captureSnapTargets(Set<String> exclude) {
    final w = geo.displayWidth, h = geo.displayHeight;
    final xs = <double>[0, w / 2, w];
    final ys = <double>[0, h / 2, h];
    for (final o in c.objectsOn(pageNo)) {
      if (o.hidden || exclude.contains(o.id) || o is TextMarkupMarkup) continue;
      final b = c.displayed(o).bounds;
      xs.addAll([b.left, b.center.dx, b.right]);
      ys.addAll([b.top, b.center.dy, b.bottom]);
    }
    _snapXs = xs;
    _snapYs = ys;
  }

  /// Smallest correction bringing one of [features] onto a target.
  double? _bestDelta(List<double> features, List<double> targets) {
    double? best;
    for (final f in features) {
      for (final t in targets) {
        final d = t - f;
        if (d.abs() <= _snapTol && (best == null || d.abs() < best.abs())) {
          best = d;
        }
      }
    }
    return best;
  }

  /// Guide lines for targets that [box] now touches.
  MarkupGuides _guidesFor(Rect box, {String? label, Offset? labelAt}) {
    final eps = 0.5 / s;
    final v = <double>{};
    final h = <double>{};
    for (final t in _snapXs) {
      for (final f in [box.left, box.center.dx, box.right]) {
        if ((t - f).abs() <= eps) v.add(t);
      }
    }
    for (final t in _snapYs) {
      for (final f in [box.top, box.center.dy, box.bottom]) {
        if ((t - f).abs() <= eps) h.add(t);
      }
    }
    return MarkupGuides(
      page: pageNo,
      vertical: v.toList(),
      horizontal: h.toList(),
      label: label,
      labelAt: labelAt,
    );
  }

  static String _fmtPt(double v) => v.round().toString();

  /// Extra grab slop so a finger on a selected text box, image, or link is
  /// not handed to the page scroller.
  double get _grabPadPt {
    final coarse =
        _touchUi ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return (coarse ? 28.0 : 10.0) / s;
  }

  MarkupObject? _selectedMovableAt(Offset p) {
    final pad = _grabPadPt;
    for (final o in _pageSelection.reversed) {
      if (o.locked || !o.canMove) continue;
      if (o is! TextBoxMarkup && o is! ImageMarkup && o is! LinkMarkup) {
        continue;
      }
      if (o.bounds.inflate(pad).contains(p)) return o;
    }
    return null;
  }

  bool _wantsPointer(Offset local) {
    // Keep an in-progress drag if the overlay is hit-tested again.
    if (_pointer != null && _drag != _DragKind.none && _drag != _DragKind.tap) {
      return true;
    }
    if (!c.editMode) {
      final o = _hitObject(_pt(local));
      return o is LinkMarkup || o is NoteMarkup;
    }
    if (c.readOnly) return false;
    if (c.tool != MarkupTool.select) return true;
    final p = _pt(local);
    if (_hitHandle(p) != null) return true;
    if (_hitObject(p) != null) return true;
    if (_selectedMovableAt(p) != null) return true;
    if (c.editingId != null) return true;
    // Marquee / deselect on desktop; touch drags keep panning the page.
    return RendererBinding.instance.mouseTracker.mouseIsConnected;
  }

  // ------------------------------------------------------------ pointer

  void _onDown(PointerDownEvent e) {
    if (_pointer != null) return;
    if (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryButton) {
      return;
    }
    _pointer = e.pointer;
    final touch =
        e.kind == PointerDeviceKind.touch ||
        e.kind == PointerDeviceKind.stylus ||
        e.kind == PointerDeviceKind.invertedStylus;
    if (touch != _touchUi) setState(() => _touchUi = touch);
    final p = _pt(e.localPosition);
    _start = p;
    _moved = false;
    _originals = {};
    _handle = null;
    _points.clear();
    _erased.clear();

    if (c.editingId != null) {
      c.commitTextEditing();
      if (c.tool == MarkupTool.text) {
        _drag = _DragKind.none;
        return;
      }
    }
    if (!c.keyboardFocus.hasFocus) c.keyboardFocus.requestFocus();

    if (!c.editMode) {
      _drag = _DragKind.tap;
      return;
    }
    final shift = HardwareKeyboard.instance.isShiftPressed;
    switch (c.tool) {
      case MarkupTool.select:
        final h = _hitHandle(p);
        if (h != null) {
          _handle = h;
          _drag = h.kind;
          if (h.kind == _DragKind.groupResize) {
            _originals = {
              for (final o in _pageSelection)
                if (!o.locked && (o.canResize || o.canMove)) o.id: o,
            };
            _box0 = _groupBox;
            _captureSnapTargets(_originals.keys.toSet());
            return;
          }
          final o = _single!;
          _originals = {o.id: o};
          _captureSnapTargets({o.id});
          if (h.kind == _DragKind.rotate) {
            final center = _rotationCenter(o);
            _rotateStartAngle = math.atan2(p.dy - center.dy, p.dx - center.dx);
          }
          return;
        }
        final hit = _hitObject(p) ?? _selectedMovableAt(p);
        if (hit == null) {
          if (!shift) c.clearSelection();
          _drag = _DragKind.marquee;
          return;
        }
        final now = DateTime.now();
        final isDouble =
            _lastTapId == hit.id &&
            now.difference(_lastTapAt) < const Duration(milliseconds: 380) &&
            (p - _lastTapPt).distance < 6 / s;
        _lastTapAt = now;
        _lastTapId = hit.id;
        _lastTapPt = p;
        if (isDouble) {
          _drag = _DragKind.none;
          _pointer = null;
          unawaited(_onDoubleClick(hit));
          return;
        }
        if (shift) {
          c.select(hit.id, additive: true);
        } else if (!c.isSelected(hit.id)) {
          c.select(hit.id);
        }
        _drag = _DragKind.move;
        _originals = {
          for (final o in c.selectedObjects)
            if (o.canMove && !o.locked && o.page == pageNo) o.id: o,
        };
        _box0 = _originals.isEmpty
            ? null
            : _originals.values
                  .map((o) => o.bounds)
                  .reduce((a, b) => a.expandToInclude(b));
        _captureSnapTargets(_originals.keys.toSet());
      case MarkupTool.eraser:
        _drag = _DragKind.eraser;
        _eraseAt(p);
      case MarkupTool.pen:
      case MarkupTool.highlighter:
        _drag = _DragKind.freehand;
        _points.add(p);
        _updateFreehandDraft();
      case MarkupTool.rectangle:
      case MarkupTool.ellipse:
      case MarkupTool.line:
      case MarkupTool.arrow:
        _drag = _DragKind.shape;
      case MarkupTool.polygon:
      case MarkupTool.cloud:
        _drag = _DragKind.tap;
      case MarkupTool.highlight:
      case MarkupTool.underline:
      case MarkupTool.strikeout:
      case MarkupTool.squiggly:
        _drag = _DragKind.textMarkup;
        _ensureText();
      case MarkupTool.text:
        _drag = _DragKind.textRect;
      case MarkupTool.callout:
        _drag = _DragKind.callout;
      case MarkupTool.note:
        _drag = _DragKind.tap;
      case MarkupTool.link:
        _drag = _DragKind.linkRect;
      case MarkupTool.image:
        _drag = _DragKind.imageRect;
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final p = _pt(e.localPosition);
    if (!_moved && (p - _start).distance * s < 3) return;
    _moved = true;
    if (!_dragging && _drag != _DragKind.none && _drag != _DragKind.tap) {
      setState(() => _dragging = true);
    }
    final shift = HardwareKeyboard.instance.isShiftPressed;
    switch (_drag) {
      case _DragKind.move:
        var d = p - _start;
        var lockX = false, lockY = false;
        if (shift) {
          if (d.dx.abs() > d.dy.abs()) {
            d = Offset(d.dx, 0);
            lockY = true;
          } else {
            d = Offset(0, d.dy);
            lockX = true;
          }
        }
        final box0 = _box0;
        if (box0 != null && _snapOn) {
          final b = box0.shift(d);
          final dx = lockX
              ? null
              : _bestDelta([b.left, b.center.dx, b.right], _snapXs);
          final dy = lockY
              ? null
              : _bestDelta([b.top, b.center.dy, b.bottom], _snapYs);
          d += Offset(dx ?? 0, dy ?? 0);
          c.guides.value = _guidesFor(box0.shift(d));
        } else {
          c.guides.value = null;
        }
        c.setPreview({for (final o in _originals.values) o.id: o.moved(d)});
      case _DragKind.resize:
        _resizeTo(p, shift);
      case _DragKind.groupResize:
        _groupResizeTo(p);
      case _DragKind.rotate:
        _rotateTo(p, shift);
      case _DragKind.lineEnd:
        final o = _originals.values.first as ShapeMarkup;
        final pts = List.of(o.points);
        final i = _handle!.index == 0 ? 0 : pts.length - 1;
        final other = pts[i == 0 ? pts.length - 1 : 0];
        pts[i] = shift ? _snap45(other, p) : p;
        c.setPreview({o.id: o.copyWith(points: pts)});
      case _DragKind.calloutTarget:
      case _DragKind.calloutKnee:
        final o = _originals.values.first as TextBoxMarkup;
        final pts = List.of(o.calloutPoints);
        pts[_drag == _DragKind.calloutTarget ? 0 : 1] = p;
        c.setPreview({o.id: o.copyWith(calloutPoints: pts)});
      case _DragKind.marquee:
        c.draft.value = MarkupDraft(
          page: pageNo,
          marquee: Rect.fromPoints(_start, p),
        );
      case _DragKind.eraser:
        _eraseAt(p);
      case _DragKind.freehand:
        if ((_points.last - p).distance * s >= 1.2) {
          _points.add(p);
          _updateFreehandDraft();
        }
      case _DragKind.shape:
        c.draft.value = MarkupDraft(page: pageNo, object: _shapeFor(p, shift));
      case _DragKind.textMarkup:
        c.draft.value = MarkupDraft(page: pageNo, object: _textMarkupFor(p));
      case _DragKind.linkRect:
      case _DragKind.textRect:
      case _DragKind.imageRect:
        c.draft.value = MarkupDraft(
          page: pageNo,
          marquee: Rect.fromPoints(_start, p),
        );
      case _DragKind.callout:
        c.draft.value = MarkupDraft(page: pageNo, object: _calloutFor(p));
      case _DragKind.none:
      case _DragKind.tap:
        break;
    }
  }

  void _onUp(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    final p = _pt(e.localPosition);
    final drag = _drag;
    _drag = _DragKind.none;
    if (_dragging) setState(() => _dragging = false);
    c.draft.value = null;
    c.guides.value = null;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    switch (drag) {
      case _DragKind.tap:
        if (_moved) return;
        _onTap(p);
      case _DragKind.move:
      case _DragKind.resize:
      case _DragKind.groupResize:
      case _DragKind.rotate:
      case _DragKind.lineEnd:
      case _DragKind.calloutTarget:
      case _DragKind.calloutKnee:
        if (_moved) {
          c.commitPreview();
        } else {
          c.clearPreview();
        }
      case _DragKind.marquee:
        if (!_moved) return;
        final r = Rect.fromPoints(_start, p);
        c.selectMany([
          for (final o in c.objectsOn(pageNo))
            if (!o.hidden && !o.locked && o.bounds.overlaps(r)) o.id,
        ], additive: shift);
      case _DragKind.eraser:
        c.clearPreview();
        if (_erased.isNotEmpty) c.deleteObjects(Set.of(_erased));
        _erased.clear();
      case _DragKind.freehand:
        _finishFreehand();
      case _DragKind.shape:
        final shape = _moved ? _shapeFor(p, shift) : null;
        if (shape != null && _shapeBigEnough(shape)) {
          c.addObject(shape);
          c.setTool(MarkupTool.select);
          c.select(shape.id);
        }
      case _DragKind.textMarkup:
        final tm = _textMarkupFor(_moved ? p : _start + const Offset(1, 0));
        if (tm != null && tm.rects.isNotEmpty) c.addObject(tm, select: false);
      case _DragKind.textRect:
        _createText(_moved ? Rect.fromPoints(_start, p) : null);
      case _DragKind.callout:
        _createCallout(p);
      case _DragKind.linkRect:
        unawaited(_createLink(_moved ? Rect.fromPoints(_start, p) : null));
      case _DragKind.imageRect:
        unawaited(_placeImage(_moved ? Rect.fromPoints(_start, p) : null));
      case _DragKind.none:
        break;
    }
  }

  void _onCancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _drag = _DragKind.none;
    c.draft.value = null;
    c.guides.value = null;
    c.clearPreview();
    if (_dragging) setState(() => _dragging = false);
  }

  // ---------------------------------------------------------- actions

  void _onTap(Offset p) {
    if (!c.editMode) {
      final o = _hitObject(p);
      if (o is LinkMarkup) widget.actions.activateLink(o);
      if (o is NoteMarkup) c.setNoteOpen(o.id, !c.isNoteOpen(o.id));
      return;
    }
    switch (c.tool) {
      case MarkupTool.polygon:
      case MarkupTool.cloud:
        final pending = c.pendingPolygon;
        if (pending != null &&
            c.pendingPolygonPage == pageNo &&
            pending.length >= 3 &&
            (pending.first - p).distance * s < 10) {
          c.finishPolygon();
          return;
        }
        final now = DateTime.now();
        final dbl =
            now.difference(_lastTapAt) < const Duration(milliseconds: 350);
        _lastTapAt = now;
        if (dbl && pending != null && pending.length >= 3) {
          c.finishPolygon();
          return;
        }
        c.addPolygonPoint(pageNo, p);
      case MarkupTool.note:
        final n = NoteMarkup(
          id: c.newId(),
          page: pageNo,
          anchor: _clampAnchor(
            p - const Offset(kNoteIconSize / 2, kNoteIconSize / 2),
          ),
          noteColor: c.noteColor,
          author: c.author,
          opacity: c.opacity,
        );
        c.addObject(n);
        c.setTool(MarkupTool.select);
        c.select(n.id);
        c.setNoteOpen(n.id, true);
      default:
        break;
    }
  }

  Future<void> _onDoubleClick(MarkupObject o) async {
    if (o.locked) return;
    switch (o) {
      case TextBoxMarkup():
        c.startEditing(o.id);
      case NoteMarkup():
        c.setNoteOpen(o.id, true);
      case LinkMarkup():
        final edited = await widget.actions.editLink(o, isNew: false);
        if (edited != null) c.replaceObjects([fitMarkupLinkFrame(edited)]);
      default:
        break;
    }
  }

  Offset _clampAnchor(Offset a) => Offset(
    a.dx.clamp(0, math.max(0, geo.displayWidth - kNoteIconSize)),
    a.dy.clamp(0, math.max(0, geo.displayHeight - kNoteIconSize)),
  );

  Offset _snap45(Offset from, Offset to) {
    final d = to - from;
    final ang = math.atan2(d.dy, d.dx);
    final snapped = (ang / (math.pi / 4)).round() * (math.pi / 4);
    final len = d.distance;
    return from + Offset(math.cos(snapped), math.sin(snapped)) * len;
  }

  Offset _rotationCenter(MarkupObject o) {
    if (o is ShapeMarkup && !o.isFrameBased) {
      return boundsOfPoints(o.points).center;
    }
    if (o is InkMarkup) return o.bounds.center;
    return o.frame.center;
  }

  void _rotateTo(Offset p, bool shift) {
    final o = _originals.values.first;
    final center = _rotationCenter(o);
    final ang = math.atan2(p.dy - center.dy, p.dx - center.dx);
    var delta = (ang - _rotateStartAngle) * 180 / math.pi;
    final frameBased =
        o is TextBoxMarkup ||
        o is ImageMarkup ||
        (o is ShapeMarkup && o.isFrameBased);
    double snapAngle(double deg) {
      if (shift) return (deg / 15).round() * 15.0;
      // Gentle magnet to the right angles.
      final right = (deg / 90).round() * 90.0;
      return (deg - right).abs() < 4 ? right : deg;
    }

    MarkupObject next;
    double shown;
    if (frameBased) {
      var r = snapAngle(o.rotation + delta);
      r = ((r % 360) + 360) % 360;
      next = o.rotatedTo(r);
      shown = r;
    } else {
      delta = snapAngle(delta);
      next = o.rotatedTo(delta);
      shown = ((delta % 360) + 360) % 360;
    }
    c.guides.value = MarkupGuides(
      page: pageNo,
      label: '${shown.round() % 360}°',
      labelAt: p,
    );
    c.setPreview({o.id: next});
  }

  void _groupResizeTo(Offset p) {
    final box0 = _box0;
    final h = _handle;
    if (box0 == null || h == null || box0.width <= 0 || box0.height <= 0) {
      return;
    }
    final anchor = switch (h.index) {
      0 => box0.bottomRight,
      2 => box0.bottomLeft,
      4 => box0.topLeft,
      _ => box0.topRight,
    };
    var target = p;
    if (_snapOn) {
      final dx = _bestDelta([p.dx], _snapXs);
      final dy = _bestDelta([p.dy], _snapYs);
      target = p + Offset(dx ?? 0, dy ?? 0);
    }
    final kx = (target.dx - anchor.dx).abs() / box0.width;
    final ky = (target.dy - anchor.dy).abs() / box0.height;
    final k = math.max(0.05, math.max(kx, ky));
    Offset map(Offset q) => anchor + (q - anchor) * k;
    Rect mapRect(Rect r) => Rect.fromCenter(
      center: map(r.center),
      width: r.width * k,
      height: r.height * k,
    );
    final next = <String, MarkupObject>{};
    for (final o in _originals.values) {
      next[o.id] = switch (o) {
        TextBoxMarkup() => relayoutTextBox(
          o.copyWith(
            frame: mapRect(o.frame),
            fontSize: o.fontSize * k,
            letterSpacing: o.letterSpacing * k,
            padding: o.padding * k,
            calloutPoints: [for (final q in o.calloutPoints) map(q)],
          ),
        ),
        ImageMarkup() || LinkMarkup() => o.resizedTo(mapRect(o.frame)),
        ShapeMarkup(isFrameBased: true) => o.resizedTo(mapRect(o.frame)),
        NoteMarkup() => o.moved(map(o.bounds.center) - o.bounds.center),
        _ when o.canResize => o.resizedTo(mapRect(o.bounds)),
        _ => o.moved(map(o.bounds.center) - o.bounds.center),
      };
    }
    final box = mapRect(box0);
    c.guides.value = _guidesFor(
      box,
      label: '${_fmtPt(box.width)} × ${_fmtPt(box.height)}',
      labelAt: target,
    );
    c.setPreview(next);
  }

  void _resizeTo(Offset pointer, bool shift) {
    var p = pointer;
    final o = _originals.values.first;
    final frameBased =
        o is TextBoxMarkup ||
        o is ImageMarkup ||
        o is LinkMarkup ||
        (o is ShapeMarkup && o.isFrameBased);
    final f = frameBased ? o.frame : o.bounds;
    final rot = frameBased ? o.rotation : 0.0;
    final m = frameToDisplay(f, rot);
    final i = _handle!.index;
    final leftSide = i == 0 || i == 6 || i == 7;
    final rightSide = i == 2 || i == 3 || i == 4;
    final topSide = i == 0 || i == 1 || i == 2;
    final bottomSide = i == 4 || i == 5 || i == 6;
    final upright = rot % 360 == 0;
    if (upright && _snapOn) {
      final dx = leftSide || rightSide ? _bestDelta([p.dx], _snapXs) : null;
      final dy = topSide || bottomSide ? _bestDelta([p.dy], _snapYs) : null;
      p = p + Offset(dx ?? 0, dy ?? 0);
    }
    final local = m.inverse().apply(p);
    var l = 0.0, t = 0.0, r = f.width, b = f.height;
    final minSize = 4.0;
    if (leftSide) l = math.min(local.dx, r - minSize);
    if (rightSide) r = math.max(local.dx, l + minSize);
    if (topSide) t = math.min(local.dy, b - minSize);
    if (bottomSide) b = math.max(local.dy, t + minSize);
    final corner = i == 0 || i == 2 || i == 4 || i == 6;
    final keepAspect = corner && (c.aspectLockedFor(o) != shift);
    if (keepAspect && f.width > 0 && f.height > 0) {
      final sx = (r - l) / f.width, sy = (b - t) / f.height;
      final k = math.max(sx, sy);
      final w = f.width * k, h = f.height * k;
      if (leftSide) {
        l = f.width - w;
      } else {
        r = w;
      }
      if (topSide) {
        t = f.height - h;
      } else {
        b = h;
      }
    }
    if (o is TextBoxMarkup) {
      // Width only; height follows the text.
      t = 0;
      b = f.height;
    }
    final lr = Rect.fromLTRB(l, t, r, b);
    final center = m.apply(lr.center);
    final nf = Rect.fromCenter(
      center: center,
      width: lr.width,
      height: lr.height,
    );
    MarkupObject next = o.resizedTo(nf);
    if (next is TextBoxMarkup) {
      next = _relayoutKeepingTop(next.copyWith(autoWidth: false), nf);
    }
    final shownFrame = next.frame;
    c.guides.value = upright
        ? _guidesFor(
            next.bounds,
            label: '${_fmtPt(shownFrame.width)} × ${_fmtPt(shownFrame.height)}',
            labelAt: p,
          )
        : MarkupGuides(
            page: pageNo,
            label: '${_fmtPt(shownFrame.width)} × ${_fmtPt(shownFrame.height)}',
            labelAt: p,
          );
    c.setPreview({o.id: next});
  }

  TextBoxMarkup _relayoutKeepingTop(TextBoxMarkup t, Rect nf) {
    final re = relayoutTextBox(t);
    if (t.rotation == 0) {
      return re.copyWith(
        frame: Rect.fromLTWH(nf.left, nf.top, re.frame.width, re.frame.height),
      );
    }
    return re;
  }

  bool _shapeBigEnough(ShapeMarkup s) {
    if (s.isFrameBased) {
      return s.shapeFrame!.width >= 2 && s.shapeFrame!.height >= 2;
    }
    return s.points.length >= 2 &&
        (s.points.first - s.points.last).distance >= 2;
  }

  ShapeMarkup? _shapeFor(Offset p, bool shift) {
    final kind = c.tool.shapeKind;
    if (kind == null) return null;
    if (kind == ShapeKind.line || kind == ShapeKind.arrow) {
      final end = shift ? _snap45(_start, p) : p;
      return ShapeMarkup(
        id: c.newId(),
        page: pageNo,
        kind: kind,
        points: [_start, end],
        strokeColor: c.strokeColor,
        strokeWidth: c.strokeWidth,
        dash: c.dash,
        opacity: c.opacity,
      );
    }
    var r = Rect.fromPoints(_start, p);
    if (shift) {
      final side = math.max(r.width, r.height);
      r = Rect.fromLTWH(
        p.dx < _start.dx ? _start.dx - side : _start.dx,
        p.dy < _start.dy ? _start.dy - side : _start.dy,
        side,
        side,
      );
    }
    return ShapeMarkup(
      id: c.newId(),
      page: pageNo,
      kind: kind,
      shapeFrame: r,
      strokeColor: c.strokeColor,
      fillColor: c.fillColor,
      strokeWidth: c.strokeWidth,
      dash: c.dash,
      opacity: c.opacity,
    );
  }

  void _updateFreehandDraft() {
    final hl = c.tool == MarkupTool.highlighter;
    c.draft.value = MarkupDraft(
      page: pageNo,
      object: InkMarkup(
        id: 'draft',
        page: pageNo,
        strokes: [List.of(_points)],
        strokeColor: hl ? c.highlighterColor : c.penColor,
        strokeWidth: hl ? c.highlighterWidth : c.penWidth,
        highlighter: hl,
        opacity: c.opacity,
      ),
    );
  }

  void _finishFreehand() {
    if (_points.isEmpty) return;
    final hl = c.tool == MarkupTool.highlighter;
    final smoothed = smoothStroke(_points, minDistance: 0.6 / s * 2);
    c.addObject(
      InkMarkup(
        id: c.newId(),
        page: pageNo,
        strokes: [smoothed],
        strokeColor: hl ? c.highlighterColor : c.penColor,
        strokeWidth: hl ? c.highlighterWidth : c.penWidth,
        highlighter: hl,
        opacity: c.opacity,
      ),
      select: false,
    );
    _points.clear();
  }

  void _ensureText() {
    _text ??= MarkupPageText.of(widget.page).then((t) {
      _textReady = t;
      return t;
    });
  }

  TextMarkupMarkup? _textMarkupFor(Offset p) {
    final kind = c.tool.textMarkupKind;
    if (kind == null) return null;
    final txt = _textReady;
    List<Rect> rects;
    var content = '';
    if (txt != null && !txt.isEmpty) {
      final sel = txt.selection(_start, p);
      if (sel == null) return null;
      rects = sel.$1;
      content = sel.$2;
    } else if (_text != null && txt == null && _textReadyPending) {
      return null;
    } else {
      // Scanned page (no text layer): area markup.
      final r = Rect.fromPoints(_start, p);
      if (r.width < 2 || r.height < 2) return null;
      rects = [r];
    }
    return TextMarkupMarkup(
      id: c.newId(),
      page: pageNo,
      kind: kind,
      rects: rects,
      markupColor: c.textMarkupColor(kind),
      text: content,
      opacity: c.opacity,
    );
  }

  bool get _textReadyPending => _textReady == null && _text != null;

  void _eraseAt(Offset p) {
    final hit = _hitObject(p);
    if (hit == null || hit.locked || _erased.contains(hit.id)) return;
    _erased.add(hit.id);
    c.setPreview({
      for (final id in _erased)
        if (c.objectById(id) case final o?) id: o.withCommon(hidden: true),
    });
  }

  void _createText(Rect? dragged) {
    final fixed = dragged != null && dragged.width * s > 24;
    final pad = 2.0;
    final top = (dragged?.top ?? _start.dy - c.fontSize * 0.7);
    final left = dragged?.left ?? _start.dx - pad;
    var t = TextBoxMarkup(
      id: c.newId(),
      page: pageNo,
      frame: Rect.fromLTWH(
        left,
        top,
        fixed ? dragged.width : c.fontSize * 2,
        c.fontSize * 1.2 + pad * 2,
      ),
      fontFamily: c.fontFamily,
      fontSize: c.fontSize,
      bold: c.bold,
      italic: c.italic,
      textColor: c.textColor,
      align: c.textAlign,
      underline: c.underline,
      strike: c.strike,
      letterSpacing: c.letterSpacing,
      lineHeight: c.lineHeight,
      autoWidth: !fixed,
      opacity: c.opacity,
      padding: pad,
    );
    t = relayoutTextBox(t);
    c.setTool(MarkupTool.select);
    c.addPending(t);
  }

  void _createCallout(Offset p) {
    final target = _start;
    final boxAt = _moved ? p : target + const Offset(36, -56);
    final pad = 3.0;
    var t = TextBoxMarkup(
      id: c.newId(),
      page: pageNo,
      frame: Rect.fromLTWH(boxAt.dx, boxAt.dy, 120, c.fontSize * 1.2 + pad * 2),
      fontFamily: c.fontFamily,
      fontSize: c.fontSize,
      bold: c.bold,
      italic: c.italic,
      underline: c.underline,
      strike: c.strike,
      letterSpacing: c.letterSpacing,
      lineHeight: c.lineHeight,
      textColor: c.textColor,
      fillColor: 0xFFFFFFFF,
      borderColor: c.strokeColor,
      borderWidth: 1,
      padding: pad,
      opacity: c.opacity,
    );
    t = relayoutTextBox(t);
    final f = t.frame;
    final kneeX = target.dx < f.left ? f.left - 14 : f.right + 14;
    t = t.copyWith(calloutPoints: [target, Offset(kneeX, f.center.dy)]);
    c.setTool(MarkupTool.select);
    c.addPending(t);
  }

  TextBoxMarkup? _calloutFor(Offset p) {
    final f = Rect.fromLTWH(p.dx, p.dy, 120, c.fontSize * 1.2 + 6);
    final kneeX = _start.dx < f.left ? f.left - 14 : f.right + 14;
    return TextBoxMarkup(
      id: 'draft',
      page: pageNo,
      frame: f,
      fillColor: 0xFFFFFFFF,
      borderColor: c.strokeColor,
      calloutPoints: [_start, Offset(kneeX, f.center.dy)],
    );
  }

  Future<void> _createLink(Rect? dragged) async {
    final frame =
        dragged != null && dragged.width * s > 8 && dragged.height * s > 6
        ? dragged
        : Rect.fromLTWH(_start.dx, _start.dy - 8, 120, 18);
    final draftLink = LinkMarkup(id: c.newId(), page: pageNo, linkFrame: frame);
    c.draft.value = MarkupDraft(page: pageNo, marquee: frame);
    final result = await widget.actions.editLink(draftLink, isNew: true);
    c.draft.value = null;
    if (result == null) return;
    final fitted = fitMarkupLinkFrame(result);
    c.addObject(fitted);
    c.setTool(MarkupTool.select);
    c.select(fitted.id);
  }

  Future<void> _placeImage(Rect? dragged) async {
    var bytes = c.pendingImage;
    var aspect = c.pendingImageAspect;
    if (bytes == null) {
      final picked = await widget.actions.pickImage();
      if (picked == null || !mounted) return;
      (bytes, aspect) = picked;
    }
    Rect frame;
    if (dragged != null && dragged.width * s > 10 && dragged.height * s > 10) {
      // Fit inside the dragged box, keeping the image's aspect.
      var w = dragged.width, h = w / aspect;
      if (h > dragged.height) {
        h = dragged.height;
        w = h * aspect;
      }
      frame = Rect.fromCenter(center: dragged.center, width: w, height: h);
    } else {
      final w = math.min(200.0, geo.displayWidth * 0.5);
      frame = Rect.fromCenter(center: _start, width: w, height: w / aspect);
    }
    final im = ImageMarkup(
      id: c.newId(),
      page: pageNo,
      frame: frame,
      bytes: bytes,
      opacity: c.opacity,
    );
    c.addObject(im);
    c.setPendingImage(null, 1);
    c.setTool(MarkupTool.select);
    c.select(im.id);
  }

  // ------------------------------------------------------------ cursor

  void _onHover(PointerHoverEvent e) {
    if (_touchUi &&
        e.kind == PointerDeviceKind.mouse &&
        defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      setState(() => _touchUi = false);
    }
    final p = _pt(e.localPosition);
    MouseCursor cursor = MouseCursor.defer;
    String? hover;
    if (!c.editMode) {
      final o = _hitObject(p);
      if (o is LinkMarkup || o is NoteMarkup) cursor = SystemMouseCursors.click;
    } else if (c.tool == MarkupTool.select) {
      final h = _hitHandle(p);
      if (h != null) {
        cursor = switch (h.kind) {
          _DragKind.rotate => SystemMouseCursors.grab,
          _DragKind.resize || _DragKind.groupResize => _resizeCursor(h.index),
          _ => SystemMouseCursors.precise,
        };
      } else {
        final o = _hitObject(p);
        if (o != null) {
          hover = o.id;
          cursor = o.locked
              ? SystemMouseCursors.basic
              : (o.canMove
                    ? SystemMouseCursors.move
                    : SystemMouseCursors.click);
        }
      }
    } else if (c.tool == MarkupTool.text || c.tool == MarkupTool.callout) {
      cursor = SystemMouseCursors.text;
    } else if (c.tool.isTextMarkup) {
      cursor = SystemMouseCursors.text;
    } else if (c.tool == MarkupTool.eraser) {
      cursor = SystemMouseCursors.disappearing;
    } else {
      cursor = SystemMouseCursors.precise;
    }
    if (cursor != _cursor || hover != _hoverId) {
      setState(() {
        _cursor = cursor;
        _hoverId = hover;
      });
    }
  }

  MouseCursor _resizeCursor(int i) {
    final o = _single;
    final rot = ((o?.rotation ?? 0) % 180 + 180) % 180;
    final swap = rot > 45 && rot < 135;
    final base = switch (i) {
      0 || 4 => SystemMouseCursors.resizeUpLeftDownRight,
      2 || 6 => SystemMouseCursors.resizeUpRightDownLeft,
      1 || 5 => SystemMouseCursors.resizeUpDown,
      _ => SystemMouseCursors.resizeLeftRight,
    };
    if (!swap) return base;
    return switch (i) {
      1 || 5 => SystemMouseCursors.resizeLeftRight,
      3 || 7 => SystemMouseCursors.resizeUpDown,
      _ => base,
    };
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final size = widget.pageSize;
    final scale = s;
    final editing = c.editingId;
    final editObj = editing == null ? null : c.objectById(editing);
    final sel = c.selectedObjects.where((o) => o.page == pageNo).toList();
    final editingText = editObj is TextBoxMarkup && editObj.page == pageNo;
    final showToolbar =
        c.editMode &&
        sel.isNotEmpty &&
        !_dragging &&
        (editing == null || editingText) &&
        c.tool == MarkupTool.select;
    final showFormatBar =
        c.editMode &&
        !_dragging &&
        sel.any((o) => markupObjectUsesFormatBar(c.displayed(o))) &&
        (editing == null || editingText);

    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: _HitGate(
              test: _wantsPointer,
              child: MouseRegion(
                cursor: _cursor,
                onHover: _onHover,
                onExit: (_) {
                  if (_hoverId != null || _cursor != MouseCursor.defer) {
                    setState(() {
                      _hoverId = null;
                      _cursor = MouseCursor.defer;
                    });
                  }
                },
                child: ViewerNavForwarder(
                  controller: widget.viewerController,
                  behavior: HitTestBehavior.opaque,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _onDown,
                    onPointerMove: _onMove,
                    onPointerUp: _onUp,
                    onPointerCancel: _onCancel,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: size,
                        painter: _ObjectsPainter(
                          controller: c,
                          page: pageNo,
                          scale: scale,
                          editMode: c.editMode,
                          editingId: editing,
                          repaint: Listenable.merge([
                            c.previewTick,
                            c.draft,
                            MarkupImageCache.instance,
                          ]),
                        ),
                        foregroundPainter: _SelectionPainter(
                          controller: c,
                          page: pageNo,
                          scale: scale,
                          handles: editing != null ? const [] : _visibleHandles,
                          rotateHandle: _single,
                          groupBox: _groupBox,
                          hoverId: c.editMode ? _hoverId : null,
                          flashId: _flashId,
                          touch: _touchUi,
                          appear: _selAnim,
                          repaint: Listenable.merge([
                            c.previewTick,
                            c.guides,
                            _selAnim,
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (editingText)
            _InlineTextEditor(
              key: ValueKey('markup-edit-${editObj.id}'),
              controller: c,
              id: editObj.id,
              scale: scale,
            ),
          for (final o in c.objectsOn(pageNo))
            if (o is NoteMarkup && c.isNoteOpen(o.id) && !o.hidden)
              _NotePopup(
                key: ValueKey('markup-note-${o.id}'),
                controller: c,
                note: c.displayed(o) as NoteMarkup,
                scale: scale,
                pageWidthPt: geo.displayWidth,
                pageHeightPt: geo.displayHeight,
              ),
          if (showToolbar)
            ValueListenableBuilder<int>(
              valueListenable: c.textEditTick,
              builder: (context, _, _) => MarkupContextToolbarAnchor(
                key: ValueKey('markup-toolbar-$_selSig'),
                controller: c,
                selection: [
                  for (final o in c.selectedObjects)
                    if (o.page == pageNo) c.displayed(o),
                ],
                scale: scale,
                pageSize: size,
                actions: widget.actions,
              ),
            ),
          if (showFormatBar)
            MarkupFormatBarAnchor(
              key: const Key('markup_format_bar_anchor'),
              controller: c,
              selection: [for (final o in sel) c.displayed(o)],
              scale: scale,
            ),
        ],
      ),
    );
  }
}

// ================================================================ painters

class _ObjectsPainter extends CustomPainter {
  _ObjectsPainter({
    required this.controller,
    required this.page,
    required this.scale,
    required this.editMode,
    required this.editingId,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final MarkupEditorController controller;
  final int page;
  final double scale;
  final bool editMode;
  final String? editingId;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    for (final o in controller.objectsOn(page)) {
      final d = controller.displayed(o);
      paintMarkupObject(
        canvas,
        d,
        editing: d.id == editingId,
        showLinks: editMode,
      );
    }
    final draft = controller.draft.value;
    if (draft != null && draft.page == page) {
      final obj = draft.object;
      if (obj != null) {
        if (markupUsesMultiply(obj)) {
          // Approximate multiply while drawing (committed version multiplies).
          canvas.saveLayer(
            Offset.zero & (size / scale),
            Paint()..color = const Color.fromRGBO(0, 0, 0, 0.55),
          );
          paintMarkupObject(canvas, obj, multiply: true);
          canvas.restore();
        } else {
          paintMarkupObject(canvas, obj, showLinks: true);
        }
      }
      final r = draft.marquee;
      if (r != null) {
        canvas.drawRect(
          r,
          Paint()..color = const Color(0xFF1E88E5).withValues(alpha: 0.08),
        );
        canvas.drawRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1 / scale
            ..color = const Color(0xFF1E88E5),
        );
      }
    }
    final poly = controller.pendingPolygon;
    if (poly != null && controller.pendingPolygonPage == page) {
      final path = Path()..moveTo(poly.first.dx, poly.first.dy);
      for (final p in poly.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = controller.strokeWidth
          ..color = Color(controller.strokeColor | 0xFF000000),
      );
      final dot = Paint()..color = const Color(0xFF1E88E5);
      for (final p in poly) {
        canvas.drawCircle(p, 3 / scale, dot);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ObjectsPainter old) =>
      old.scale != scale ||
      old.editMode != editMode ||
      old.editingId != editingId ||
      old.page != page ||
      !identical(old.controller, controller);
}

class _SelectionPainter extends CustomPainter {
  _SelectionPainter({
    required this.controller,
    required this.page,
    required this.scale,
    required this.handles,
    required this.rotateHandle,
    required this.groupBox,
    required this.hoverId,
    required this.flashId,
    required this.touch,
    required this.appear,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final MarkupEditorController controller;
  final int page;
  final double scale;
  final List<_Handle> handles;
  final MarkupObject? rotateHandle;
  final Rect? groupBox;
  final String? hoverId;
  final String? flashId;
  final bool touch;
  final Animation<double> appear;

  static const _accent = Color(0xFF1E88E5);
  static const _guide = Color(0xFFFF2D87);

  List<Offset> _outline(MarkupObject o) {
    final frameBased =
        o is TextBoxMarkup ||
        o is ImageMarkup ||
        o is LinkMarkup ||
        (o is ShapeMarkup && o.isFrameBased);
    if (frameBased) return rotatedFrameCorners(o.frame, o.rotation);
    final b = o.bounds;
    return [b.topLeft, b.topRight, b.bottomRight, b.bottomLeft];
  }

  void _drawOutline(Canvas canvas, MarkupObject o, Paint paint) {
    final pts = [for (final p in _outline(o)) p * scale];
    canvas.drawPath(Path()..addPolygon(pts, true), paint);
  }

  Rect _px(Rect r) => Rect.fromLTRB(
    r.left * scale,
    r.top * scale,
    r.right * scale,
    r.bottom * scale,
  );

  void _dashedRect(Canvas canvas, Rect r, Paint paint) {
    const dash = 4.0, gap = 3.0;
    void line(Offset a, Offset b) {
      final len = (b - a).distance;
      if (len <= 0) return;
      final dir = (b - a) / len;
      for (var d = 0.0; d < len; d += dash + gap) {
        canvas.drawLine(a + dir * d, a + dir * math.min(len, d + dash), paint);
      }
    }

    line(r.topLeft, r.topRight);
    line(r.topRight, r.bottomRight);
    line(r.bottomRight, r.bottomLeft);
    line(r.bottomLeft, r.topLeft);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = Curves.easeOutBack.transform(appear.value.clamp(0.0, 1.0));
    final fade = appear.value.clamp(0.0, 1.0);
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = _accent;
    final selected = [
      for (final o in controller.selectedObjects)
        if (o.page == page) controller.displayed(o),
    ];
    if (hoverId != null && !controller.isSelected(hoverId!)) {
      final o = controller.objectById(hoverId!);
      if (o != null && o.page == page) {
        _drawOutline(
          canvas,
          o,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = _accent.withValues(alpha: 0.5),
        );
      }
    }
    if (flashId != null) {
      final o = controller.objectById(flashId!);
      if (o != null && o.page == page) {
        final r = _px(o.bounds.inflate(3));
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(4)),
          Paint()..color = _accent.withValues(alpha: 0.12),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(4)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = _accent,
        );
      }
    }
    final multi = selected.length > 1;
    for (final o in selected) {
      final paint = multi
          ? (Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = _accent.withValues(alpha: 0.55))
          : outline;
      if (o is ShapeMarkup &&
          (o.kind == ShapeKind.line || o.kind == ShapeKind.arrow)) {
        canvas.drawLine(
          o.points.first * scale,
          o.points.last * scale,
          Paint()
            ..strokeWidth = 1.2
            ..color = _accent.withValues(alpha: 0.45),
        );
        continue;
      }
      if (o is TextMarkupMarkup) {
        for (final r in o.rects) {
          canvas.drawRect(_px(r), paint);
        }
        continue;
      }
      _drawOutline(canvas, o, paint);
      if (o.locked) {
        final b = o.bounds;
        final icon = Icons.lock_outline;
        final tp = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
              fontSize: 14,
              color: _accent,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(b.right * scale + 2, b.top * scale - 16));
        tp.dispose();
      }
    }
    final gb = groupBox;
    if (gb != null) {
      _dashedRect(
        canvas,
        _px(gb).inflate(2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = _accent,
      );
    }
    _paintGuides(canvas, size);
    if (handles.isEmpty || fade <= 0) return;
    final o = rotateHandle;
    final base = touch ? 7.0 : 5.0;
    final r = base * (0.55 + 0.45 * t);
    final fill = Paint()..color = Colors.white.withValues(alpha: fade);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = _accent.withValues(alpha: fade);
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.22 * fade)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6);
    void knob(Offset at, double radius) {
      canvas.drawCircle(at + const Offset(0, 0.8), radius, shadow);
      canvas.drawCircle(at, radius, fill);
      canvas.drawCircle(at, radius, stroke);
    }

    for (final h in handles) {
      final at = h.at * scale;
      if (h.kind == _DragKind.rotate && o != null) {
        final frameBased =
            o is TextBoxMarkup ||
            o is ImageMarkup ||
            (o is ShapeMarkup && o.isFrameBased);
        final f = frameBased ? o.frame : o.bounds;
        final m = frameToDisplay(f, frameBased ? o.rotation : 0);
        final top = m.apply(Offset(f.width / 2, 0)) * scale;
        canvas.drawLine(top, at, stroke);
        knob(at, r + 1.5);
        // Circular-arrow glyph.
        final gr = (r + 1.5) * 0.52;
        final arc = Path()
          ..addArc(
            Rect.fromCircle(center: at, radius: gr),
            -math.pi * 0.35,
            math.pi * 1.45,
          );
        final glyph = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round
          ..color = _accent.withValues(alpha: fade);
        canvas.drawPath(arc, glyph);
        final tip =
            at +
            Offset(math.cos(-math.pi * 0.35), math.sin(-math.pi * 0.35)) * gr;
        canvas.drawLine(tip, tip + const Offset(-2.4, -0.6), glyph);
        canvas.drawLine(tip, tip + const Offset(0.2, 2.4), glyph);
        continue;
      }
      if (h.kind == _DragKind.resize && (h.index.isOdd)) {
        // Edge handles: pills along the edge.
        final sel = rotateHandle;
        final rot = (sel?.rotation ?? 0) * math.pi / 180;
        final horizontal = h.index == 1 || h.index == 5;
        final len = (touch ? 18.0 : 12.0) * (0.55 + 0.45 * t);
        final thick = (touch ? 7.0 : 5.0) * (0.55 + 0.45 * t);
        canvas.save();
        canvas.translate(at.dx, at.dy);
        canvas.rotate(rot);
        final rr = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: horizontal ? len : thick,
            height: horizontal ? thick : len,
          ),
          Radius.circular(thick / 2),
        );
        canvas.drawRRect(rr.shift(const Offset(0, 0.8)), shadow);
        canvas.drawRRect(rr, fill);
        canvas.drawRRect(rr, stroke);
        canvas.restore();
        continue;
      }
      knob(at, r);
    }
  }

  void _paintGuides(Canvas canvas, Size size) {
    final g = controller.guides.value;
    if (g == null || g.page != page) return;
    final paint = Paint()
      ..strokeWidth = 1
      ..color = _guide;
    for (final x in g.vertical) {
      final px = x * scale;
      canvas.drawLine(Offset(px, 0), Offset(px, size.height), paint);
    }
    for (final y in g.horizontal) {
      final py = y * scale;
      canvas.drawLine(Offset(0, py), Offset(size.width, py), paint);
    }
    final label = g.label;
    final at = g.labelAt;
    if (label == null || at == null) return;
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var pos = at * scale + const Offset(14, 16);
    pos = Offset(
      pos.dx.clamp(2, math.max(2, size.width - tp.width - 14)),
      pos.dy.clamp(2, math.max(2, size.height - tp.height - 8)),
    );
    final bg = RRect.fromRectAndRadius(
      Rect.fromLTWH(pos.dx, pos.dy, tp.width + 12, tp.height + 6),
      const Radius.circular(6),
    );
    canvas.drawRRect(bg, Paint()..color = const Color(0xE6202124));
    tp.paint(canvas, pos + const Offset(6, 3));
    tp.dispose();
  }

  @override
  bool shouldRepaint(covariant _SelectionPainter old) => true;
}

// ============================================================ hit gating

/// Takes pointer events only where [test] says so; elsewhere events fall
/// through to the page viewer (text selection, panning, links).
class _HitGate extends SingleChildRenderObjectWidget {
  const _HitGate({required this.test, super.child});

  final bool Function(Offset local) test;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHitGate(test);

  @override
  void updateRenderObject(BuildContext context, _RenderHitGate renderObject) {
    renderObject.test = test;
  }
}

class _RenderHitGate extends RenderProxyBox {
  _RenderHitGate(this.test);

  bool Function(Offset local) test;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    if (!test(position)) return false;
    return super.hitTest(result, position: position);
  }
}

// ========================================================= inline editor

class _InlineTextEditor extends StatefulWidget {
  const _InlineTextEditor({
    super.key,
    required this.controller,
    required this.id,
    required this.scale,
  });

  final MarkupEditorController controller;
  final String id;
  final double scale;

  @override
  State<_InlineTextEditor> createState() => _InlineTextEditorState();
}

class _InlineTextEditorState extends State<_InlineTextEditor> {
  late final TextEditingController _text;
  final FocusNode _focus = FocusNode(debugLabel: 'markupInlineText');
  Timer? _noticeTimer;
  bool _notice = false;

  MarkupEditorController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    final o = c.objectById(widget.id);
    final initial = o is TextBoxMarkup ? markupPdfSafeText(o.text) : '';
    _text = TextEditingController(text: initial);
    _text.selection = c.editingIsNew || initial.isEmpty
        ? TextSelection.collapsed(offset: initial.length)
        : TextSelection(baseOffset: 0, extentOffset: initial.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onUnsupported() {
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _notice = false);
    });
    if (!_notice) setState(() => _notice = true);
  }

  void _finish() {
    c.commitTextEditing();
    c.keyboardFocus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final hw = HardwareKeyboard.instance;
    final primary = defaultTargetPlatform == TargetPlatform.macOS
        ? hw.isMetaPressed
        : hw.isControlPressed;
    if (e.logicalKey == LogicalKeyboardKey.escape ||
        (primary &&
            (e.logicalKey == LogicalKeyboardKey.enter ||
                e.logicalKey == LogicalKeyboardKey.numpadEnter))) {
      _finish();
      return KeyEventResult.handled;
    }
    if (primary &&
        !hw.isShiftPressed &&
        !hw.isAltPressed &&
        (e.logicalKey == LogicalKeyboardKey.keyB ||
            e.logicalKey == LogicalKeyboardKey.keyI ||
            e.logicalKey == LogicalKeyboardKey.keyU)) {
      toggleMarkupTextStyle(c, e.logicalKey);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: c.textEditTick,
      builder: (context, _, _) {
        final t = c.objectById(widget.id);
        if (t is! TextBoxMarkup) return const SizedBox.shrink();
        return _buildFor(context, t);
      },
    );
  }

  Widget _buildFor(BuildContext context, TextBoxMarkup t) {
    final s = widget.scale;
    final f = t.frame;
    // Frame-local points → page pixels: the field lays out at the real
    // font size, so it wraps exactly like the saved text.
    final m = Affine2.scale(s, s).multiply(frameToDisplay(f, t.rotation));
    final style = markupTextStyleFor(t).copyWith(
      color: Color(t.textColor | 0xFF000000),
      decoration: TextDecoration.none,
    );
    final dark =
        t.fillColor != null &&
        Color(t.fillColor! | 0xFF000000).computeLuminance() < 0.35 &&
        ((t.fillColor! >> 24) & 0xff) > 0x80;
    final accent = dark ? Colors.white : const Color(0xFF1E88E5);
    final field = Transform(
      transform: Matrix4.fromFloat64List(affineToMatrix4(m)),
      child: SizedBox(
        width: f.width,
        height: f.height,
        child: Listener(
          // Clicks on the padding stay in the editor.
          behavior: HitTestBehavior.opaque,
          child: CustomPaint(
            foregroundPainter: _EditorFramePainter(
              color: accent.withValues(alpha: 0.75),
              pixel: 1 / s,
              decorations: textDecorationRects(t),
              decorationColor: Color(t.textColor | 0xFF000000),
            ),
            child: Padding(
              padding: EdgeInsets.all(t.padding),
              child: Focus(
                onKeyEvent: _onKey,
                child: TextField(
                  controller: _text,
                  focusNode: _focus,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  textAlign: markupTextAlign(t.align),
                  style: style,
                  strutStyle: markupStrutStyle(
                    family: t.fontFamily,
                    fontSize: t.fontSize,
                    lineHeight: t.lineHeight,
                  ),
                  inputFormatters: [_PdfSafeTextFormatter(_onUnsupported)],
                  cursorColor: accent,
                  cursorWidth: math.max(0.5, 1.6 / s),
                  cursorHeight: t.fontSize * 1.15,
                  decoration: null,
                  scrollPadding: EdgeInsets.zero,
                  enableInteractiveSelection: true,
                  onChanged: c.updateEditingText,
                  onTapOutside: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final bounds = t.bounds;
    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: f.width,
            height: f.height,
            child: field,
          ),
          Positioned(
            left: bounds.left * s,
            top: bounds.bottom * s + 8,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _notice ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: _Pill(
                  text:
                      'Only Latin characters are supported in PDF text '
                      '— others show as ?',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps typed text within what the PDF standard fonts can show.
class _PdfSafeTextFormatter extends TextInputFormatter {
  _PdfSafeTextFormatter(this.onUnsupported);

  final VoidCallback onUnsupported;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }
    final safe = markupPdfSafeText(newValue.text);
    if (safe == newValue.text) return newValue;
    if (markupHasUnsupportedChars(newValue.text)) onUnsupported();
    final sel = newValue.selection;
    int mapOffset(int o) => markupPdfSafeText(
      newValue.text.substring(0, o.clamp(0, newValue.text.length)),
    ).length;
    return TextEditingValue(
      text: safe,
      selection: sel.isValid
          ? TextSelection(
              baseOffset: mapOffset(sel.baseOffset),
              extentOffset: mapOffset(sel.extentOffset),
            )
          : TextSelection.collapsed(offset: safe.length),
    );
  }
}

class _EditorFramePainter extends CustomPainter {
  _EditorFramePainter({
    required this.color,
    required this.pixel,
    required this.decorations,
    required this.decorationColor,
  });

  final Color color;
  final double pixel;
  final List<Rect> decorations;
  final Color decorationColor;

  @override
  void paint(Canvas canvas, Size size) {
    final deco = Paint()..color = decorationColor;
    for (final r in decorations) {
      canvas.drawRect(r, deco);
    }
    canvas.drawRect(
      (Offset.zero & size).deflate(pixel / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = pixel
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _EditorFramePainter old) =>
      old.color != color ||
      old.pixel != pixel ||
      old.decorationColor != decorationColor ||
      !listEquals(old.decorations, decorations);
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE6202124),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 11.5),
        ),
      ),
    );
  }
}

// ============================================================ note popup

class _NotePopup extends StatefulWidget {
  const _NotePopup({
    super.key,
    required this.controller,
    required this.note,
    required this.scale,
    required this.pageWidthPt,
    required this.pageHeightPt,
  });

  final MarkupEditorController controller;
  final NoteMarkup note;
  final double scale;
  final double pageWidthPt;
  final double pageHeightPt;

  @override
  State<_NotePopup> createState() => _NotePopupState();
}

class _NotePopupState extends State<_NotePopup> {
  late final TextEditingController _text = TextEditingController(
    text: widget.note.text,
  );
  final FocusNode _focus = FocusNode(debugLabel: 'markupNote');

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
    });
    if (widget.note.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _NotePopup old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.note.text != _text.text) {
      _text.text = widget.note.text;
    }
  }

  void _save() {
    final current = widget.controller.objectById(widget.note.id);
    if (current is NoteMarkup && current.text != _text.text) {
      widget.controller.replaceObjects([current.copyWith(text: _text.text)]);
    }
  }

  @override
  void dispose() {
    // Saving notifies every page layer; not allowed while unmounting.
    final current = widget.controller.objectById(widget.note.id);
    final text = _text.text;
    if (current is NoteMarkup && current.text != text) {
      final controller = widget.controller;
      runWhenTreeUnlocked(() {
        final now = controller.objectById(current.id);
        if (now is NoteMarkup && now.text != text) {
          controller.replaceObjects([now.copyWith(text: text)]);
        }
      });
    }
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.note;
    final s = widget.scale;
    final r = notePopupRect(n.anchor, widget.pageWidthPt, widget.pageHeightPt);
    const w = 230.0, h = 150.0;
    var left = r.left * s;
    final pageW = widget.pageWidthPt * s;
    if (left + w > pageW) left = math.max(0, n.anchor.dx * s - w - 6);
    final theme = Theme.of(context);
    final header = Color(n.noteColor | 0xFF000000);
    return Positioned(
      left: left,
      top: r.top * s,
      width: w,
      height: h,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        color: Color.alphaBlend(
          header.withValues(alpha: 0.18),
          theme.colorScheme.surface,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: header.withValues(alpha: 0.85),
              padding: const EdgeInsets.fromLTRB(10, 4, 2, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      n.author.isEmpty ? 'Note' : n.author,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.controller.editMode)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      tooltip: 'Delete note',
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.black87,
                      ),
                      onPressed: () => widget.controller.deleteObjects({n.id}),
                    ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, color: Colors.black87),
                    onPressed: () {
                      _save();
                      widget.controller.setNoteOpen(n.id, false);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                child: TextField(
                  controller: _text,
                  focusNode: _focus,
                  readOnly: n.locked || widget.controller.readOnly,
                  maxLines: null,
                  expands: true,
                  keyboardType: TextInputType.multiline,
                  style: theme.textTheme.bodyMedium,
                  decoration: const InputDecoration.collapsed(
                    hintText: 'Add a comment…',
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
