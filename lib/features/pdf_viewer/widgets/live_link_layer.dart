import 'package:document_studio/app/keyboard/text_input_guard.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_overlay_common.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_page_geom.dart';
import 'package:document_studio/features/pdf_viewer/widgets/pointer_claim_region.dart';
import 'package:document_studio/features/pdf_viewer/widgets/page_placement_math.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum _LinkDrag { none, create, move, resize }

/// Add / edit link rectangles on any page.
class LiveLinkLayer extends StatefulWidget {
  const LiveLinkLayer({super.key, required this.session, required this.geom});

  final ViewerLiveToolSession session;
  final LivePageGeom geom;

  @override
  State<LiveLinkLayer> createState() => _LiveLinkLayerState();
}

class _LiveLinkLayerState extends State<LiveLinkLayer> {
  final FocusNode _focus = FocusNode(debugLabel: 'live-link');
  _LinkDrag _drag = _LinkDrag.none;
  Offset? _startNorm;
  Offset? _startLocal;
  Rect? _base;
  PlacementHandle? _handle;
  int? _hoverLink;
  MouseCursor _cursor = SystemMouseCursors.precise;

  ViewerLiveToolSession get _live => widget.session;
  LivePageGeom get _g => widget.geom;
  bool get _onThisPage => _live.pageIndex1Based == _g.pageNumber;

  List<LiveLinkHit> get _hits =>
      _live.linkHitsPage == _g.pageNumber ? _live.linkHits : const [];

  Rect? get _activePx {
    final r = _onThisPage ? _live.dragRectNorm : null;
    return r == null ? null : _g.rectToPx(r);
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  int? _linkAt(Offset local) {
    final hits = _hits;
    for (var i = hits.length - 1; i >= 0; i--) {
      if (_g
          .rectToPx(hits[i].normRect)
          .inflate(kLiveHandleHitPad + 12)
          .contains(local)) {
        return i;
      }
    }
    return null;
  }

  bool _claims(Offset local) {
    if (_drag != _LinkDrag.none) return true;
    final active = _activePx;
    if (active != null &&
        active.inflate(kLiveHandleHitPad + 16).contains(local)) {
      return true;
    }
    if (_linkAt(local) != null) return true;
    // A new link is drawn from empty page space; that gesture must not scroll.
    return _onThisPage;
  }

  void _down(PointerDownEvent e) {
    if (e.buttons != kPrimaryButton) return;
    _focus.requestFocus();
    final local = e.localPosition;
    if (!_onThisPage) _live.focusPage(_g.pageNumber);
    final active = _activePx;
    if (active != null) {
      final handle = hitTestPlacementHandle(
        boxPx: active,
        local: local,
        handleHitPad: kLiveHandleHitPad,
      );
      if (handle != null ||
          active.inflate(kLiveHandleHitPad + 8).contains(local)) {
        _drag = handle == null ? _LinkDrag.move : _LinkDrag.resize;
        _handle = handle;
        _base = _live.dragRectNorm;
        _startLocal = local;
        return;
      }
    }
    final hit = _linkAt(local);
    if (hit != null) {
      _live.selectLink(hit);
      _drag = _LinkDrag.move;
      _base = _live.dragRectNorm;
      _startLocal = local;
      return;
    }
    _live.selectLink(null);
    _drag = _LinkDrag.create;
    _startNorm = _g.toNorm(local);
    _startLocal = local;
  }

  void _move(PointerMoveEvent e) {
    final local = e.localPosition;
    switch (_drag) {
      case _LinkDrag.none:
        return;
      case _LinkDrag.create:
        if ((local - _startLocal!).distance < 3) return;
        _live.setDragRectNorm(
          Rect.fromPoints(_startNorm!, _g.toNorm(local)),
          origin: _startNorm,
          draft: true,
        );
      case _LinkDrag.move:
        final d = _g.deltaToNorm(local - _startLocal!);
        _live.setDragRectNorm(
          moveNormRect(_base!, dx: d.dx, dy: d.dy, minFraction: 0.002),
          draft: true,
        );
      case _LinkDrag.resize:
        final d = _g.deltaToNorm(local - _startLocal!);
        _live.setDragRectNorm(
          resizeNormRect(
            _base!,
            handle: _handle!,
            dx: d.dx,
            dy: d.dy,
            minFraction: 0.004,
          ),
          draft: true,
        );
    }
  }

  void _up(PointerEvent e) {
    final was = _drag;
    _drag = _LinkDrag.none;
    _base = null;
    _handle = null;
    if (was == _LinkDrag.create) {
      final r = _live.dragRectNorm;
      final tooSmall =
          r == null ||
          r.width * _g.pageWidthPt < 4 ||
          r.height * _g.pageHeightPt < 4;
      if (tooSmall) {
        _live.clearDragRect();
        return;
      }
    }
    _live.commitDraft();
  }

  void _hoverAt(PointerHoverEvent e) {
    final local = e.localPosition;
    final active = _activePx;
    MouseCursor cursor = SystemMouseCursors.precise;
    final link = _linkAt(local);
    if (active != null) {
      final handle = hitTestPlacementHandle(
        boxPx: active,
        local: local,
        handleHitPad: kLiveHandleHitPad,
      );
      if (handle != null) {
        cursor = cursorForPlacementHandle(handle);
      } else if (active.contains(local)) {
        cursor = SystemMouseCursors.move;
      } else if (link != null) {
        cursor = SystemMouseCursors.click;
      }
    } else if (link != null) {
      cursor = SystemMouseCursors.click;
    }
    if (cursor != _cursor || link != _hoverLink) {
      setState(() {
        _cursor = cursor;
        _hoverLink = link;
      });
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final rect = _live.dragRectNorm;
    if (!_onThisPage || rect == null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      if (_live.selectedLink != null) {
        _live.requestDelete();
      } else {
        _live.clearDragRect();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _live.clearDragRect();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _live.requestApply();
      return KeyEventResult.handled;
    }
    final step = HardwareKeyboard.instance.isShiftPressed ? 10.0 : 1.0;
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
    _live.setDragRectNorm(
      moveNormRect(
        rect,
        dx: _g.ptToNormX(dx),
        dy: _g.ptToNormY(dy),
        minFraction: 0.002,
      ),
    );
    return KeyEventResult.handled;
  }

  String _describe(LiveLinkHit h) {
    if (h.destPage1Based != null) return 'Go to page ${h.destPage1Based}';
    return h.uri ?? 'Link';
  }

  @override
  Widget build(BuildContext context) {
    final hits = _hits;
    final selected = _onThisPage ? _live.selectedLinkIndex : null;
    final active = _activePx;
    final hover = _hoverLink;
    return Focus(
      focusNode: _focus,
      onKeyEvent: TextInputGuard.guardFocusHandler(_onKey),
      child: MouseRegion(
        cursor: _cursor,
        onHover: _hoverAt,
        onExit: (_) {
          if (_hoverLink != null) setState(() => _hoverLink = null);
        },
        child: PointerClaimRegion(
          claims: _claims,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _up,
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                CustomPaint(
                  painter: _ExistingLinksPainter(
                    rects: [
                      for (var i = 0; i < hits.length; i++)
                        if (i != selected) _g.rectToPx(hits[i].normRect),
                    ],
                    hovered: hover != null && hover != selected
                        ? _g.rectToPx(hits[hover].normRect)
                        : null,
                  ),
                ),
                if (active != null)
                  CustomPaint(
                    painter: LiveSelectionPainter(
                      boxPx: active,
                      fill: kLiveSelectionColor.withValues(alpha: 0.10),
                    ),
                  ),
                if (hover != null &&
                    hover < hits.length &&
                    _drag == _LinkDrag.none)
                  Positioned(
                    left: _g.rectToPx(hits[hover].normRect).left,
                    top: _g.rectToPx(hits[hover].normRect).bottom + 4,
                    child: IgnorePointer(
                      child: DsMotion.fadeRiseIn(
                        duration: DsMotion.hoverDuration,
                        risePx: 3,
                        child: LiveHintChip(
                          text: _describe(hits[hover]),
                          icon: hits[hover].destPage1Based != null
                              ? Icons.menu_book_outlined
                              : Icons.link,
                        ),
                      ),
                    ),
                  ),
                if (_onThisPage && active == null && hits.isEmpty)
                  const Positioned(
                    top: 12,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: LiveHintChip(
                          text: 'Drag a rectangle over the text to link',
                          icon: Icons.add_link,
                        ),
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

class _ExistingLinksPainter extends CustomPainter {
  _ExistingLinksPainter({required this.rects, this.hovered});

  final List<Rect> rects;
  final Rect? hovered;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = kLiveSelectionColor.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final fill = Paint()..color = kLiveSelectionColor.withValues(alpha: 0.06);
    for (final r in rects) {
      canvas.drawRect(r, fill);
      paintDashedRect(canvas, r, stroke, dash: 4, gap: 3);
    }
    final h = hovered;
    if (h != null) {
      canvas.drawRect(
        h,
        Paint()..color = kLiveSelectionColor.withValues(alpha: 0.14),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ExistingLinksPainter old) =>
      old.hovered != hovered ||
      old.rects.length != rects.length ||
      !_same(old.rects);

  bool _same(List<Rect> other) {
    for (var i = 0; i < rects.length; i++) {
      if (rects[i] != other[i]) return false;
    }
    return true;
  }
}
