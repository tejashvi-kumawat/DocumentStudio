import 'dart:math' as math;

import 'package:document_studio/app/keyboard/text_input_guard.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/features/form_sign/sign_placement_bridge.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_overlay_common.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_page_geom.dart';
import 'package:document_studio/features/pdf_viewer/widgets/page_placement_math.dart';
import 'package:document_studio/features/pdf_viewer/widgets/pointer_claim_region.dart';
import 'package:document_studio/infrastructure/pdf/signing/pdf_incremental_signer.dart';
import 'package:document_studio/infrastructure/pdf/signing/pdf_signature_validator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

Rect signFieldRect(PdfSignatureFieldInfo f) =>
    Rect.fromLTRB(f.normLeft, f.normTop, f.normRight, f.normBottom);

Color signVerdictColor(PdfSignatureVerdict v) => switch (v) {
      PdfSignatureVerdict.valid => DsColors.success,
      PdfSignatureVerdict.identityUnknown => DsColors.warning,
      PdfSignatureVerdict.modified => DsColors.warning,
      PdfSignatureVerdict.invalid => DsColors.error,
      PdfSignatureVerdict.unknown => const Color(0xFF64748B),
    };

IconData signVerdictIcon(PdfSignatureVerdict v) => switch (v) {
      PdfSignatureVerdict.valid => Icons.verified_rounded,
      PdfSignatureVerdict.identityUnknown => Icons.gpp_maybe_rounded,
      PdfSignatureVerdict.modified => Icons.edit_note_rounded,
      PdfSignatureVerdict.invalid => Icons.gpp_bad_rounded,
      PdfSignatureVerdict.unknown => Icons.help_outline_rounded,
    };

enum _Mode { none, move, resize, rotate, drawField, placeDrag }

/// A click or a twitch is not a signature field. Both axes must move.
const _minCommitWidthPx = 24.0;
const _minCommitHeightPx = 16.0;

const _rotateKnobOffset = LiveSelectionPainter.rotateHandleOffset;

/// Sign / stamp overlay for one page: drop target for library drags, click to
/// place the armed item, move / resize / rotate placed items, "Sign here"
/// fields and drawing new signature fields.
///
/// Only claims pointer hits on its own objects (or the whole page while an
/// item is armed / a field is being drawn), so the page still scrolls.
class SignPageLayer extends ConsumerStatefulWidget {
  const SignPageLayer({super.key, required this.geom, this.viewer});

  final LivePageGeom geom;
  final PdfViewerController? viewer;

  @override
  ConsumerState<SignPageLayer> createState() => _SignPageLayerState();
}

class _SignPageLayerState extends ConsumerState<SignPageLayer> {
  final FocusNode _focus = FocusNode(debugLabel: 'sign-page-layer');
  final GlobalKey _boxKey = GlobalKey();
  Offset? _hover;
  Offset? _dragGhostAt;
  SignPlaceable? _dragItem;
  _Mode _mode = _Mode.none;
  int? _activeId;
  Rect? _baseRect;
  Offset? _start;
  PlacementHandle? _handle;
  double _rotBase = 0;
  double _rotStartAngle = 0;
  Offset? _drawOrigin;
  Rect? _drawRect;
  Rect? _toolbarRect;
  MouseCursor _cursor = MouseCursor.defer;

  SignPlacementController get _c => ref.read(signPlacementControllerProvider);
  LivePageGeom get _g => widget.geom;
  int get _page => _g.pageNumber;
  Size get _pagePt => Size(_g.pageWidthPt, _g.pageHeightPt);

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  // ---- geometry -----------------------------------------------------------

  Rect _px(Rect norm) => _g.rectToPx(norm);

  double _rad(SignPlacedItem i) => i.rotationDegrees * math.pi / 180;

  Offset _toItemFrame(SignPlacedItem i, Offset local) =>
      rotateAround(local, _px(i.rectNorm).center, -_rad(i));

  Offset _knob(Rect box) => Offset(box.center.dx, box.top - _rotateKnobOffset);

  bool _hitsItem(SignPlacedItem i, Offset local, {bool withHandles = false}) {
    final q = _toItemFrame(i, local);
    final box = _px(i.rectNorm);
    if (withHandles) {
      if ((q - _knob(box)).distance <= kLiveHandleHitPad + 3) return true;
      return box.inflate(kLiveHandleHitPad).contains(q);
    }
    return box.inflate(2).contains(q);
  }

  SignPlacedItem? _itemAt(Offset local) {
    final c = _c;
    final sel = c.selected;
    if (sel != null && sel.page1Based == _page &&
        _hitsItem(sel, local, withHandles: true)) {
      return sel;
    }
    final onPage = c.itemsOnPage(_page).toList().reversed;
    for (final i in onPage) {
      if (_hitsItem(i, local)) return i;
    }
    return null;
  }

  PdfSignatureFieldInfo? _fieldAt(Offset local, {bool unsignedOnly = false}) {
    for (final f in _c.fields) {
      if (f.pageIndex1Based != _page) continue;
      if (unsignedOnly && f.signed) continue;
      if (_px(signFieldRect(f)).contains(local)) return f;
    }
    return null;
  }

  bool _claims(Offset local) {
    final c = _c;
    // Hold the pointer for the whole gesture once it starts, including when
    // the finger leaves the box. Otherwise the viewer scroller joins the hit
    // test and pans the page out from under the drag.
    if (_activePointer != null || _mode != _Mode.none) return true;
    if (c.armed != null || c.drawFieldMode || c.libraryDrag) return true;
    if (_itemAt(local) != null) return true;
    return _fieldAt(local) != null;
  }

  Offset? _globalToLocal(Offset global) {
    final box = _boxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.globalToLocal(global);
  }

  // ---- pointer ------------------------------------------------------------
  //
  // Use Listener (not PanGestureRecognizer): pdfrx InteractiveViewer also
  // listens for pan/scale. The claim region must be the hit target
  // (MouseRegion.opaque stays true, hit test defers to the child). A
  // MouseRegion with opaque: false returns false from hitTest even when the
  // claim region accepted the point, so the viewer scroller was in the same
  // path and panned the page. The drag then never reached a real box.

  int? _activePointer;

  void _pointerDown(PointerDownEvent e) {
    if (_activePointer != null) return;
    final local = e.localPosition;
    if (_toolbarRect?.contains(local) ?? false) return;
    if (!_claims(local)) {
      final sel = _c.selected;
      if (sel != null && sel.page1Based == _page) _c.select(null);
      return;
    }
    _activePointer = e.pointer;
    _focus.requestFocus();
    final c = _c;
    _start = local;
    if (c.drawFieldMode) {
      _mode = _Mode.drawField;
      _drawOrigin = _g.toNorm(local);
      _drawRect = null;
      return;
    }
    if (c.armed != null) {
      // Ghost follows the finger (MouseRegion.onHover is mouse-only).
      // The box is committed on pointer-up only when the drag is real.
      _mode = _Mode.placeDrag;
      _drawOrigin = _g.toNorm(local);
      _drawRect = null;
      setState(() => _hover = local);
      return;
    }
    final item = _itemAt(local);
    if (item == null) return;
    final box = _px(item.rectNorm);
    final q = _toItemFrame(item, local);
    final selected = c.selectedId == item.id;
    _activeId = item.id;
    _baseRect = item.rectNorm;
    if (selected && (q - _knob(box)).distance <= kLiveHandleHitPad + 3) {
      _mode = _Mode.rotate;
      _rotBase = item.rotationDegrees;
      _rotStartAngle =
          math.atan2(local.dy - box.center.dy, local.dx - box.center.dx);
    } else {
      _handle = selected
          ? hitTestPlacementHandle(
              boxPx: box,
              local: q,
              handleHitPad: kLiveHandleHitPad,
            )
          : null;
      _mode = _handle == null ? _Mode.move : _Mode.resize;
    }
    c.select(item.id);
  }

  void _pointerMove(PointerMoveEvent e) {
    if (_activePointer != e.pointer) return;
    final local = e.localPosition;
    final start = _start;
    if (start == null) return;
    final c = _c;
    switch (_mode) {
      case _Mode.none:
        if (c.armed != null) {
          setState(() => _hover = local);
        }
        return;
      case _Mode.placeDrag:
        _trackDragRect(local, followPointer: true);
        return;
      case _Mode.drawField:
        _trackDragRect(local, followPointer: false);
        return;
      case _Mode.move:
        final base = _baseRect!;
        final delta = _g.deltaToNorm(local - start);
        c.update(_activeId!, rectNorm: base.shift(delta), draft: true);
        return;
      case _Mode.resize:
        final base = _baseRect!;
        final item = c.selected;
        if (item == null) return;
        final delta = _g.deltaToNorm(rotateVector(local - start, -_rad(item)));
        final keep = !HardwareKeyboard.instance.isShiftPressed;
        final next = resizePagePlacement(
          normRectToPlacement(base),
          handle: _handle!,
          dx: delta.dx,
          dy: delta.dy,
          keepAspect: keep,
          aspectWidthOverHeight: base.width / math.max(base.height, 1e-9),
          minFraction: 0.01,
        );
        c.update(_activeId!, rectNorm: placementToNormRect(next), draft: true);
        return;
      case _Mode.rotate:
        final item = c.selected;
        if (item == null) return;
        final center = _px(item.rectNorm).center;
        final a = math.atan2(local.dy - center.dy, local.dx - center.dx);
        var deg = _rotBase + (a - _rotStartAngle) * 180 / math.pi;
        deg = ((deg + 180) % 360) - 180;
        if (HardwareKeyboard.instance.isShiftPressed) {
          deg = (deg / 15).round() * 15.0;
        } else {
          for (final snap in const [-180.0, -90.0, 0.0, 90.0, 180.0]) {
            if ((deg - snap).abs() < 3) deg = snap;
          }
        }
        c.update(_activeId!, rotationDegrees: deg, draft: true);
        return;
    }
  }

  void _trackDragRect(Offset local, {required bool followPointer}) {
    final o = _drawOrigin;
    if (o == null) return;
    final n = _g.toNorm(local);
    setState(() {
      if (followPointer) _hover = local;
      _drawRect = Rect.fromPoints(
        o,
        Offset(n.dx.clamp(0.0, 1.0), n.dy.clamp(0.0, 1.0)),
      );
    });
  }

  bool _dragCommits(Rect? r) {
    if (r == null) return false;
    final pxW = r.width * _g.pagePx.width;
    final pxH = r.height * _g.pagePx.height;
    return pxW >= _minCommitWidthPx && pxH >= _minCommitHeightPx;
  }

  void _pointerUp(PointerEvent e) {
    if (_activePointer != null && e.pointer != _activePointer) return;
    final c = _c;
    final endLocal = e.localPosition;
    final canceled = e is PointerCancelEvent;
    if (_mode == _Mode.drawField) {
      final r = _drawRect;
      // A click or a tiny flick is not a field. Stay in draw mode so the
      // next drag can set the box. Only a real drag is committed.
      if (!canceled && _dragCommits(r)) {
        c.setDrawFieldMode(false);
        c.onFieldDrawn?.call(_page, _fitFieldRect(r!));
      }
      setState(() {
        _drawRect = null;
        _drawOrigin = null;
      });
    } else if (_mode == _Mode.placeDrag) {
      final armed = c.armed;
      final r = _drawRect;
      if (!canceled && armed != null && _dragCommits(r)) {
        final fitted = _fitFieldRect(r!);
        c.place(
          armed,
          page1Based: _page,
          centerNorm: fitted.center,
          pageSizePt: _pagePt,
          fitInto: fitted,
        );
      } else if (!canceled && armed != null) {
        // Clicking an existing unsigned field still drops into that field.
        // A click on empty page does not create a box.
        final field = _fieldAt(endLocal, unsignedOnly: true);
        if (field != null) {
          c.place(
            armed,
            page1Based: _page,
            centerNorm: _g.toNorm(endLocal),
            pageSizePt: _pagePt,
            fitInto: signFieldRect(field),
          );
        }
      }
      setState(() {
        _drawRect = null;
        _drawOrigin = null;
        _hover = null;
      });
    } else if (_mode != _Mode.none) {
      if (!canceled) c.commitDraft();
    } else if (!canceled && _start != null) {
      // Armed tap/drag-place, or field tap: use lift position so drag-to-place
      // on touch lands where the finger released.
      _tapUp(TapUpDetails(
        kind: e.kind,
        globalPosition: e.position,
        localPosition: endLocal,
      ));
    }
    _mode = _Mode.none;
    _activeId = null;
    _baseRect = null;
    _handle = null;
    _start = null;
    _activePointer = null;
  }

  /// Grows tiny drags to a usable minimum (72 × 24 pt) and keeps the field
  /// on the page.
  Rect _fitFieldRect(Rect r) {
    final minW = 72 / _g.pageWidthPt, minH = 24 / _g.pageHeightPt;
    var w = math.max(r.width, minW), h = math.max(r.height, minH);
    w = math.min(w, 1.0);
    h = math.min(h, 1.0);
    final left = r.left.clamp(0.0, 1.0 - w);
    final top = r.top.clamp(0.0, 1.0 - h);
    return Rect.fromLTWH(left, top, w, h);
  }

  void _tapUp(TapUpDetails d) {
    final local = d.localPosition;
    final c = _c;
    // Armed placement and new signature fields commit from a real drag only.
    if (c.drawFieldMode || c.armed != null) return;
    if (_itemAt(local) != null) return;
    final field = _fieldAt(local);
    if (field == null) return;
    if (field.signed) {
      final status = c.statusForField(field.name);
      if (status != null) c.onSignedFieldTap?.call(status);
    } else {
      c.onFieldTap?.call(field);
    }
  }

  void _onHover(PointerHoverEvent e) {
    final local = e.localPosition;
    final c = _c;
    MouseCursor cursor = MouseCursor.defer;
    if (c.drawFieldMode) {
      cursor = SystemMouseCursors.precise;
    } else if (c.armed != null) {
      cursor = SystemMouseCursors.copy;
    } else {
      final item = _itemAt(local);
      if (item != null) {
        final box = _px(item.rectNorm);
        final q = _toItemFrame(item, local);
        final selected = c.selectedId == item.id;
        final handle = selected
            ? hitTestPlacementHandle(
                boxPx: box,
                local: q,
                handleHitPad: kLiveHandleHitPad,
              )
            : null;
        if (selected && (q - _knob(box)).distance <= kLiveHandleHitPad + 3) {
          cursor = SystemMouseCursors.grab;
        } else if (handle != null) {
          cursor = item.rotationDegrees.abs() < 10
              ? cursorForPlacementHandle(handle)
              : SystemMouseCursors.precise;
        } else {
          cursor = SystemMouseCursors.move;
        }
      } else if (_fieldAt(local) != null) {
        cursor = SystemMouseCursors.click;
      }
    }
    final needsGhost = c.armed != null;
    if (cursor != _cursor || needsGhost || _hover == null) {
      setState(() {
        _cursor = cursor;
        _hover = local;
      });
    }
  }

  // ---- keyboard -----------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final c = _c;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (c.armed != null) {
        c.arm(null);
      } else if (c.drawFieldMode) {
        c.setDrawFieldMode(false);
      } else if (c.selectedId != null) {
        c.select(null);
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    final sel = c.selected;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (!c.hasItems) return KeyEventResult.ignored;
      c.requestApply();
      return KeyEventResult.handled;
    }
    if (sel == null) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      c.remove(sel.id);
      return KeyEventResult.handled;
    }
    final hw = HardwareKeyboard.instance;
    final primary = defaultTargetPlatform == TargetPlatform.macOS
        ? hw.isMetaPressed
        : hw.isControlPressed;
    if (primary && key == LogicalKeyboardKey.keyD) {
      c.duplicate(sel.id);
      return KeyEventResult.handled;
    }
    if (!primary && key == LogicalKeyboardKey.keyR) {
      c.rotateBy(sel.id, hw.isShiftPressed ? -90 : 90);
      return KeyEventResult.handled;
    }
    final step = hw.isShiftPressed ? 10.0 : 1.0;
    final dx = key == LogicalKeyboardKey.arrowLeft
        ? -step
        : key == LogicalKeyboardKey.arrowRight
            ? step
            : 0.0;
    final dy = key == LogicalKeyboardKey.arrowUp
        ? -step
        : key == LogicalKeyboardKey.arrowDown
            ? step
            : 0.0;
    if (dx == 0 && dy == 0) return KeyEventResult.ignored;
    c.update(
      sel.id,
      rectNorm: sel.rectNorm.shift(Offset(_g.ptToNormX(dx), _g.ptToNormY(dy))),
    );
    return KeyEventResult.handled;
  }

  // ---- drag & drop from the library --------------------------------------

  void _dragMove(DragTargetDetails<SignPlaceable> d) {
    final local = _globalToLocal(d.offset);
    if (local == null) return;
    _c.setDragHover(true);
    setState(() {
      _dragGhostAt = local;
      _dragItem = d.data;
    });
  }

  void _dragLeave(SignPlaceable? _) {
    _c.setDragHover(false);
    setState(() {
      _dragGhostAt = null;
      _dragItem = null;
    });
  }

  void _dragAccept(DragTargetDetails<SignPlaceable> d) {
    final at = _globalToLocal(d.offset) ?? _dragGhostAt;
    _c.setDragHover(false);
    setState(() {
      _dragGhostAt = null;
      _dragItem = null;
    });
    if (at == null) return;
    final field = _fieldAt(at, unsignedOnly: true);
    _c.place(
      d.data,
      page1Based: _page,
      centerNorm: _g.toNorm(at),
      pageSizePt: _pagePt,
      fitInto: field == null ? null : signFieldRect(field),
    );
    _focus.requestFocus();
  }

  // ---- build --------------------------------------------------------------

  /// Signature image under the pointer. Until the drag is large enough to
  /// commit, the default-sized image stays centered on the pointer. A real
  /// drag shows the signature fitted in that box, still tracking the pointer.
  Rect? _armedGhost(SignPlacementController c) {
    final armed = c.armed;
    if (armed == null) return null;
    final drag = _mode == _Mode.placeDrag ? _drawRect : null;
    if (drag != null && _dragCommits(drag)) {
      final fitted = _fitFieldRect(drag);
      return _px(c.defaultRect(
        armed,
        pageSizePt: _pagePt,
        centerNorm: fitted.center,
        fitInto: fitted,
      ));
    }
    return _ghostRect(armed, _hover);
  }

  Rect? _ghostRect(SignPlaceable? item, Offset? at) {
    if (item == null || at == null) return null;
    final field = _fieldAt(at, unsignedOnly: true);
    return _px(_c.defaultRect(
      item,
      pageSizePt: _pagePt,
      centerNorm: _g.toNorm(at),
      fitInto: field == null ? null : signFieldRect(field),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(signPlacementControllerProvider);
    c.notePage(_page, _pagePt);
    c.attachViewer(widget.viewer);
    return ListenableBuilder(
      listenable: c.pageListenable,
      builder: (context, _) => _buildLayer(context, c),
    );
  }

  Widget _buildLayer(BuildContext context, SignPlacementController c) {
    final items = c.itemsOnPage(_page).toList();
    final sel = c.selected;
    final selOnPage = sel != null && sel.page1Based == _page ? sel : null;
    final fields = [
      for (final f in c.fields)
        if (f.pageIndex1Based == _page) f,
    ];
    final ghost = _dragItem != null
        ? _ghostRect(_dragItem, _dragGhostAt)
        : _armedGhost(c);
    final ghostPng = _dragItem?.png ?? c.armed?.png;
    final flash = c.flash?.page1Based == _page ? c.flash : null;
    final hoverField = _hover == null ? null : _fieldAt(_hover!);

    Widget? toolbar;
    _toolbarRect = null;
    if (selOnPage != null && _mode == _Mode.none) {
      final box = _px(selOnPage.rectNorm);
      final rad = _rad(selOnPage);
      final corners = [box.topLeft, box.topRight, box.bottomLeft, box.bottomRight]
          .map((p) => rotateAround(p, box.center, rad));
      var top = corners.map((p) => p.dy).reduce(math.min);
      final bottom = corners.map((p) => p.dy).reduce(math.max);
      const barW = 148.0;
      const barH = 36.0;
      var y = top - _rotateKnobOffset - 14 - barH;
      if (y < 4) y = bottom + 10;
      if (y + barH > _g.pagePx.height - 2) y = math.max(4, top + 4);
      final x = (box.center.dx - barW / 2)
          .clamp(4.0, math.max(4.0, _g.pagePx.width - barW - 4))
          .toDouble();
      _toolbarRect = Rect.fromLTWH(x, y, barW, barH);
      toolbar = Positioned.fromRect(
        rect: _toolbarRect!,
        child: _ItemToolbar(
          key: ValueKey(selOnPage.id),
          onRotate: () => c.rotateBy(selOnPage.id, 90),
          onDuplicate: () => c.duplicate(selOnPage.id),
          onDelete: () => c.remove(selOnPage.id),
        ),
      );
    }

    final hint = c.drawFieldMode
        ? 'Drag on the page to draw the signature field · Esc to cancel'
        : c.armed != null
            ? 'Drag on the page to place “${c.armed!.label}” · Esc to cancel'
            : null;

    return DragTarget<SignPlaceable>(
      onWillAcceptWithDetails: (_) => true,
      onMove: _dragMove,
      onLeave: _dragLeave,
      onAcceptWithDetails: _dragAccept,
      builder: (context, candidates, rejected) {
        return Focus(
          focusNode: _focus,
          onKeyEvent: TextInputGuard.guardFocusHandler(_onKey),
          child: MouseRegion(
            key: _boxKey,
            // opaque must stay true. opaque: false forces hitTest to return
            // false and the viewer scroller pans under the signature drag.
            opaque: true,
            hitTestBehavior: HitTestBehavior.deferToChild,
            cursor: _cursor,
            onHover: _onHover,
            onExit: (_) {
              if (_hover != null && _activePointer == null) {
                setState(() => _hover = null);
              }
            },
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                for (final f in fields)
                  Positioned.fromRect(
                    rect: _px(signFieldRect(f)),
                    child: IgnorePointer(
                      child: f.signed
                          ? _SignedFieldChrome(
                              status: c.statusForField(f.name),
                              hovered: identical(hoverField, f),
                            )
                          : _SignHereChrome(
                              hovered: identical(hoverField, f) ||
                                  (ghost != null &&
                                      _px(signFieldRect(f)).overlaps(ghost)),
                              compact: _px(signFieldRect(f)).height < 26,
                            ),
                    ),
                  ),
                for (final i in items)
                  Positioned.fromRect(
                    rect: _px(i.rectNorm),
                    child: IgnorePointer(
                      child: _PlacedItemView(
                        key: ValueKey(i.id),
                        item: i,
                      ),
                    ),
                  ),
                if (selOnPage != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: LiveSelectionPainter(
                          boxPx: _px(selOnPage.rectNorm),
                          rotationRadians: _rad(selOnPage),
                          showRotateHandle: true,
                        ),
                      ),
                    ),
                  ),
                if (ghost != null && ghostPng != null)
                  Positioned.fromRect(
                    rect: ghost,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: kLiveSelectionColor.withValues(alpha: 0.7),
                          ),
                        ),
                        child: Opacity(
                          opacity: 0.6,
                          child: Image.memory(
                            ghostPng,
                            fit: BoxFit.fill,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_mode == _Mode.drawField && _drawRect != null)
                  Positioned.fromRect(
                    rect: _px(_drawRect!),
                    child: const IgnorePointer(child: _DrawFieldChrome()),
                  ),
                if (flash != null)
                  Positioned.fromRect(
                    rect: _px(flash.rectNorm).inflate(6),
                    child: IgnorePointer(
                      child: _FlashChrome(key: ValueKey(flash.generation)),
                    ),
                  ),
                Positioned.fill(
                  child: PointerClaimRegion(
                    claims: _claims,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _pointerDown,
                      onPointerMove: _pointerMove,
                      onPointerUp: _pointerUp,
                      onPointerCancel: _pointerUp,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                ?toolbar,
                if (hint != null && _hover != null)
                  Positioned(
                    top: 10,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: DsMotion.fadeRiseIn(
                          child: LiveHintChip(
                            text: hint,
                            icon: c.drawFieldMode
                                ? Icons.crop_free_rounded
                                : Icons.touch_app_outlined,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlacedItemView extends StatelessWidget {
  const _PlacedItemView({super.key, required this.item});

  final SignPlacedItem item;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.86, end: 1),
      duration: DsMotion.switchDuration,
      curve: Curves.easeOutBack,
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      child: Transform.rotate(
        angle: item.rotationDegrees * math.pi / 180,
        child: Image.memory(
          item.png,
          fit: BoxFit.fill,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

class _SignHereChrome extends StatefulWidget {
  const _SignHereChrome({required this.hovered, required this.compact});

  final bool hovered;
  final bool compact;

  @override
  State<_SignHereChrome> createState() => _SignHereChromeState();
}

class _SignHereChromeState extends State<_SignHereChrome>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const c = Color(0xFFE0561B);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = widget.hovered ? 1.0 : Curves.easeInOut.transform(_pulse.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.06 + 0.08 * t),
            border: Border.all(
              color: c.withValues(alpha: 0.55 + 0.45 * t),
              width: widget.hovered ? 1.8 : 1.3,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.draw_rounded, size: 13, color: c),
                    if (!widget.compact) ...[
                      const SizedBox(width: 4),
                      const Text(
                        'Sign here',
                        style: TextStyle(
                          fontSize: 11,
                          color: c,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SignedFieldChrome extends StatelessWidget {
  const _SignedFieldChrome({required this.status, required this.hovered});

  final PdfSignatureStatus? status;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final color = s == null ? const Color(0xFF64748B) : signVerdictColor(s.verdict);
    return AnimatedContainer(
      duration: DsMotion.hoverDuration,
      decoration: BoxDecoration(
        color: color.withValues(alpha: hovered ? 0.08 : 0.0),
        border: Border.all(
          color: color.withValues(alpha: hovered ? 0.9 : 0.35),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            s == null ? Icons.lock_outline : signVerdictIcon(s.verdict),
            size: 13,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _DrawFieldChrome extends StatelessWidget {
  const _DrawFieldChrome();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBoxPainter(),
      child: const Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: EdgeInsets.all(4),
            child: Text(
              'Signature field',
              style: TextStyle(
                color: kLiveSelectionColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBoxPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(
      r,
      Paint()..color = kLiveSelectionColor.withValues(alpha: 0.08),
    );
    paintDashedRect(
      canvas,
      r,
      Paint()
        ..color = kLiveSelectionColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FlashChrome extends StatelessWidget {
  const _FlashChrome({super.key});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1800),
      builder: (context, t, _) {
        final pulse = (math.sin(t * math.pi * 4) + 1) / 2;
        final fade = t < 0.8 ? 1.0 : (1 - t) / 0.2;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: kLiveSelectionColor.withValues(alpha: fade * (0.5 + pulse * 0.5)),
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: kLiveSelectionColor.withValues(alpha: fade * 0.25 * pulse),
                blurRadius: 14,
                spreadRadius: 2,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ItemToolbar extends StatelessWidget {
  const _ItemToolbar({
    super.key,
    required this.onRotate,
    required this.onDuplicate,
    required this.onDelete,
  });

  final VoidCallback onRotate;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DsMotion.fadeRiseIn(
      duration: DsMotion.switchDuration,
      risePx: 4,
      child: Material(
        color: dark ? DsColors.surfaceContainerDark : Colors.white,
        elevation: 4,
        shadowColor: const Color(0x44000000),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BarIcon(icon: Icons.rotate_right_rounded, tip: 'Rotate 90° (R)', onTap: onRotate),
              _BarIcon(icon: Icons.copy_rounded, tip: 'Duplicate (Ctrl+D)', onTap: onDuplicate),
              _BarIcon(icon: Icons.delete_outline_rounded, tip: 'Remove (Delete)', onTap: onDelete),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({required this.icon, required this.tip, required this.onTap});

  final IconData icon;
  final String tip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tip,
      child: InkResponse(
        onTap: onTap,
        radius: 16,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 18,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }
}
