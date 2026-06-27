import 'package:document_studio/app/keyboard/text_input_guard.dart';

import 'dart:math' as math;

import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_overlay_common.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_page_geom.dart';
import 'package:document_studio/features/pdf_viewer/widgets/pointer_claim_region.dart';
import 'package:document_studio/features/pdf_viewer/widgets/page_placement_canvas.dart';
import 'package:document_studio/features/pdf_viewer/widgets/page_placement_math.dart';
import 'package:document_studio/infrastructure/pdf/pdf_form_spot_detector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Arms [bytes] for placement: correct aspect on the active page, centered on
/// the last pointer position (or the page), ready to move / resize.
void placeLiveImage(
  ViewerLiveToolSession session, {
  required Uint8List bytes,
  required double aspectWidthOverHeight,
  Offset? centerNorm,
}) {
  final size = session.pageSizePtFor(session.pageIndex1Based);
  session.setImageBytes(bytes);
  session.setPlacement(
    centeredPlacementForAspect(
      imageAspectWidthOverHeight: aspectWidthOverHeight,
      centerNorm: centerNorm ?? session.lastPointerNorm,
      pageWidthPt: size?.width ?? session.pageWidthPt,
      pageHeightPt: size?.height ?? session.pageHeightPt,
    ),
  );
  session.setAwaitingClickPlacement(false);
  session.setKeepAspectRatio(true);
}

enum _DragMode { none, move, resize, rotate }

/// Image / signature placement on any page: click to drop, drag to move,
/// handles to resize, knob to rotate (images), arrows to nudge, Delete to
/// remove.
class LivePlacementLayer extends StatefulWidget {
  const LivePlacementLayer({
    super.key,
    required this.session,
    required this.geom,
  });

  final ViewerLiveToolSession session;
  final LivePageGeom geom;

  @override
  State<LivePlacementLayer> createState() => _LivePlacementLayerState();
}

class _LivePlacementLayerState extends State<LivePlacementLayer> {
  final FocusNode _focus = FocusNode(debugLabel: 'live-placement');
  _DragMode _mode = _DragMode.none;
  PagePlacementNorm? _base;
  Offset? _startLocal;
  PlacementHandle? _handle;
  double _rotBaseDeg = 0;
  double _rotStartAngle = 0;
  Offset? _hover;
  MouseCursor _cursor = SystemMouseCursors.basic;
  int _dropGen = 0;
  bool _selected = true;

  ViewerLiveToolSession get _live => widget.session;
  LivePageGeom get _g => widget.geom;
  bool get _isSign => _live.toolId == ViewerToolId.visualSign;
  bool get _onThisPage => _live.pageIndex1Based == _g.pageNumber;
  bool get _hasImage => _live.imageBytes != null;
  bool get _boxVisible =>
      _onThisPage && _hasImage && !_live.awaitingClickPlacement;
  double get _rotRad => _live.toolId == ViewerToolId.placeImage
      ? _live.rotationDegrees * math.pi / 180
      : 0.0;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Rect get _boxPx => _g.rectToPx(_live.placement.rect);

  /// Placement size in points carried over to another page / click point.
  PagePlacementNorm _placementCenteredAt(Offset normCenter) {
    final from =
        _live.pageSizePtFor(_live.pageIndex1Based) ??
        Size(_live.pageWidthPt, _live.pageHeightPt);
    final p = _live.placement;
    final wN = (p.width * from.width / _g.pageWidthPt).clamp(0.005, 1.0);
    final hN = (p.height * from.height / _g.pageHeightPt).clamp(0.005, 1.0);
    return clampPagePlacement(
      PagePlacementNorm(
        left: normCenter.dx - wN / 2,
        top: normCenter.dy - hN / 2,
        width: wN,
        height: hN,
      ),
      minFraction: 0.005,
    );
  }

  PdfFormSpot? _signatureFieldAt(Offset local) {
    if (!_isSign) return null;
    for (final s in _live.formSpots) {
      if (s.kind != PdfFormSpotKind.signature) continue;
      if (s.pageIndex1Based != 0 && s.pageIndex1Based != _g.pageNumber) {
        continue;
      }
      if (_g.rectToPx(s.normRect).contains(local)) return s;
    }
    return null;
  }

  /// Fits the signature inside [field] keeping its aspect (never stretched).
  PagePlacementNorm _fitInField(Rect fieldNorm) {
    final p = _live.placement;
    final from =
        _live.pageSizePtFor(_live.pageIndex1Based) ??
        Size(_live.pageWidthPt, _live.pageHeightPt);
    final aspectPt =
        (p.width * from.width) / math.max(1e-6, p.height * from.height);
    final fw = fieldNorm.width * _g.pageWidthPt;
    final fh = fieldNorm.height * _g.pageHeightPt;
    var w = fw * 0.94;
    var h = w / aspectPt;
    if (h > fh * 0.9) {
      h = fh * 0.9;
      w = h * aspectPt;
    }
    final wN = w / _g.pageWidthPt;
    final hN = h / _g.pageHeightPt;
    return clampPagePlacement(
      PagePlacementNorm(
        left: fieldNorm.center.dx - wN / 2,
        top: fieldNorm.center.dy - hN / 2,
        width: wN,
        height: hN,
      ),
      minFraction: 0.005,
    );
  }

  Offset _toBoxFrame(Offset local) =>
      rotateAround(local, _boxPx.center, -_rotRad);

  bool _hitRotateKnob(Offset q) {
    if (_live.toolId != ViewerToolId.placeImage) return false;
    final box = _boxPx;
    final knob = Offset(
      box.center.dx,
      box.top - LiveSelectionPainter.rotateHandleOffset,
    );
    return (q - knob).distance <= kLiveHandleHitPad + 2;
  }

  void _drop(PagePlacementNorm placement) {
    if (!_onThisPage) _live.focusPage(_g.pageNumber);
    _live.setPlacement(placement);
    _live.setAwaitingClickPlacement(false);
    setState(() {
      _dropGen++;
      _selected = true;
    });
  }

  bool _claims(Offset local) {
    if (_mode != _DragMode.none) return true;
    if (!_hasImage) return false;
    // Armed image: the drop gesture owns the page. Once placed, only the
    // box (and rotate knob) is claimed so the viewer can still scroll.
    if (!_boxVisible) return true;
    final q = _toBoxFrame(local);
    if (_boxPx.inflate(kLiveHandleHitPad + 18).contains(q)) return true;
    return _hitRotateKnob(q);
  }

  void _down(PointerDownEvent e) {
    if (e.buttons != kPrimaryButton) return;
    _focus.requestFocus();
    final local = e.localPosition;
    final n = _g.toNorm(local);
    _live.setLastPointerNorm(n);
    if (!_hasImage) {
      if (!_onThisPage) _live.focusPage(_g.pageNumber);
      return;
    }
    final field = _signatureFieldAt(local);
    if (field != null) {
      _drop(_fitInField(field.normRect));
      return;
    }
    if (!_boxVisible) {
      // Armed signature / image not on this page yet: drop it where clicked.
      _drop(_placementCenteredAt(n));
      return;
    }
    final q = _toBoxFrame(local);
    final box = _boxPx;
    if (_hitRotateKnob(q)) {
      _mode = _DragMode.rotate;
      _rotBaseDeg = _live.rotationDegrees;
      final c = box.center;
      _rotStartAngle = math.atan2(local.dy - c.dy, local.dx - c.dx);
      setState(() => _selected = true);
      return;
    }
    final handle = _selected
        ? hitTestPlacementHandle(
            boxPx: box,
            local: q,
            handleHitPad: kLiveHandleHitPad,
          )
        : null;
    if (handle != null || box.inflate(kLiveHandleHitPad + 12).contains(q)) {
      _mode = handle == null ? _DragMode.move : _DragMode.resize;
      _handle = handle;
      _base = _live.placement;
      _startLocal = local;
      setState(() => _selected = true);
      return;
    }
    setState(() => _selected = false);
  }

  void _move(PointerMoveEvent e) {
    final local = e.localPosition;
    switch (_mode) {
      case _DragMode.none:
        return;
      case _DragMode.rotate:
        final c = _boxPx.center;
        final angle = math.atan2(local.dy - c.dy, local.dx - c.dx);
        var deg = _rotBaseDeg + (angle - _rotStartAngle) * 180 / math.pi;
        if (HardwareKeyboard.instance.isShiftPressed) {
          deg = (deg / 15).round() * 15.0;
        }
        _live.setRotationDegrees(deg, draft: true);
      case _DragMode.move:
        final base = _base!;
        final d = _g.deltaToNorm(local - _startLocal!);
        _live.setPlacement(
          movePagePlacement(base, dx: d.dx, dy: d.dy, minFraction: 0.005),
          draft: true,
        );
      case _DragMode.resize:
        final base = _base!;
        final d = _g.deltaToNorm(rotateVector(local - _startLocal!, -_rotRad));
        _live.setPlacement(
          resizePagePlacement(
            base,
            handle: _handle!,
            dx: d.dx,
            dy: d.dy,
            keepAspect: _live.effectiveKeepAspect,
            aspectWidthOverHeight: base.height > 1e-9
                ? base.width / base.height
                : 1.0,
            minFraction: 0.01,
          ),
          draft: true,
        );
    }
  }

  void _up(PointerEvent e) {
    if (_mode == _DragMode.none) return;
    _mode = _DragMode.none;
    _base = null;
    _startLocal = null;
    _handle = null;
    _live.commitDraft();
  }

  void _hoverAt(PointerHoverEvent e) {
    final local = e.localPosition;
    MouseCursor cursor = SystemMouseCursors.basic;
    if (_hasImage && (!_boxVisible || _signatureFieldAt(local) != null)) {
      cursor = SystemMouseCursors.copy;
    } else if (_boxVisible) {
      final q = _toBoxFrame(local);
      final handle = _selected
          ? hitTestPlacementHandle(
              boxPx: _boxPx,
              local: q,
              handleHitPad: kLiveHandleHitPad,
            )
          : null;
      if (_hitRotateKnob(q)) {
        cursor = SystemMouseCursors.grab;
      } else if (handle != null) {
        cursor = _rotRad.abs() < 0.2
            ? cursorForPlacementHandle(handle)
            : SystemMouseCursors.precise;
      } else if (_boxPx.contains(q)) {
        cursor = SystemMouseCursors.move;
      }
    }
    final ghost = _hasImage && !_boxVisible;
    if (cursor != _cursor || ghost) {
      setState(() {
        _cursor = cursor;
        _hover = ghost ? local : null;
      });
    }
  }

  void _removeObject() {
    if (_isSign) {
      _live.setAwaitingClickPlacement(true);
    } else {
      _live.setImageBytes(null);
      _live.setAwaitingClickPlacement(true);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_boxVisible) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _removeObject();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _live.requestApply();
      return KeyEventResult.handled;
    }
    final stepPt = HardwareKeyboard.instance.isShiftPressed ? 10.0 : 1.0;
    final dx = key == LogicalKeyboardKey.arrowLeft
        ? -stepPt
        : key == LogicalKeyboardKey.arrowRight
        ? stepPt
        : 0.0;
    final dy = key == LogicalKeyboardKey.arrowUp
        ? -stepPt
        : key == LogicalKeyboardKey.arrowDown
        ? stepPt
        : 0.0;
    if (dx == 0 && dy == 0) return KeyEventResult.ignored;
    _live.setPlacement(
      movePagePlacement(
        _live.placement,
        dx: _g.ptToNormX(dx),
        dy: _g.ptToNormY(dy),
        minFraction: 0.005,
      ),
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final live = _live;
    final bytes = live.imageBytes;
    final box = _boxPx;
    final opacity = live.toolId == ViewerToolId.placeImage
        ? live.opacity.clamp(0.05, 1.0)
        : 1.0;
    final ghostPlacement =
        _hover != null &&
            bytes != null &&
            !_boxVisible &&
            _signatureFieldAt(_hover!) == null
        ? _placementCenteredAt(_g.toNorm(_hover!))
        : null;
    final sigFields = _isSign
        ? [
            for (final s in live.formSpots)
              if (s.kind == PdfFormSpotKind.signature &&
                  (s.pageIndex1Based == 0 ||
                      s.pageIndex1Based == _g.pageNumber))
                s,
          ]
        : const <PdfFormSpot>[];
    final hint = !_onThisPage && _hasImage && !live.awaitingClickPlacement
        ? null
        : !_hasImage
        ? (_isSign
              ? 'Create or choose a signature in the panel'
              : 'Choose an image in the panel')
        : live.awaitingClickPlacement
        ? (_isSign
              ? (sigFields.isEmpty
                    ? 'Click where the signature should go'
                    : 'Click a signature field or anywhere on the page')
              : 'Click to place the image')
        : null;

    final toolbar = _boxVisible && _selected && _mode == _DragMode.none
        ? _ObjectToolbar(
            anchor: box,
            pageSize: _g.pagePx,
            rotated: _rotRad != 0,
            onDelete: _removeObject,
            onRotate: live.toolId == ViewerToolId.placeImage
                ? live.rotatePlacementBy90Clockwise
                : null,
            applyLabel: _isSign ? 'Sign' : 'Place',
            onApply: live.requestApply,
          )
        : null;

    return Focus(
      focusNode: _focus,
      onKeyEvent: TextInputGuard.guardFocusHandler(_onKey),
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          MouseRegion(
            cursor: _cursor,
            onHover: _hoverAt,
            onExit: (_) {
              if (_hover != null) setState(() => _hover = null);
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
                    for (final s in sigFields)
                      Positioned.fromRect(
                        rect: _g.rectToPx(s.normRect),
                        child: IgnorePointer(
                          child: _SignatureFieldBadge(
                            highlighted:
                                _hover != null &&
                                _g.rectToPx(s.normRect).contains(_hover!),
                          ),
                        ),
                      ),
                    if (ghostPlacement != null)
                      Positioned.fromRect(
                        rect: _g.rectToPx(ghostPlacement.rect),
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: 0.55,
                            child: Image.memory(
                              bytes!,
                              fit: BoxFit.fill,
                              gaplessPlayback: true,
                              filterQuality: FilterQuality.medium,
                            ),
                          ),
                        ),
                      ),
                    if (_boxVisible) ...[
                      Positioned.fromRect(
                        rect: box,
                        child: IgnorePointer(
                          child: TweenAnimationBuilder<double>(
                            key: ValueKey(_dropGen),
                            tween: Tween(
                              begin: _dropGen == 0 ? 1.0 : 0.92,
                              end: 1.0,
                            ),
                            duration: DsMotion.switchDuration,
                            curve: DsMotion.switchCurve,
                            builder: (context, s, child) =>
                                Transform.scale(scale: s, child: child),
                            child: Transform.rotate(
                              angle: _rotRad,
                              child: Opacity(
                                opacity: opacity,
                                child: Image.memory(
                                  bytes!,
                                  fit: BoxFit.fill,
                                  gaplessPlayback: true,
                                  filterQuality: FilterQuality.medium,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: _selected ? 1 : 0.35,
                            duration: DsMotion.hoverDuration,
                            child: CustomPaint(
                              painter: LiveSelectionPainter(
                                boxPx: box,
                                rotationRadians: _rotRad,
                                showHandles: _selected,
                                showRotateHandle:
                                    _selected &&
                                    live.toolId == ViewerToolId.placeImage,
                                dashed: !_selected,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (hint != null && _onThisPage)
                      Positioned(
                        top: 12,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Center(
                            child: DsMotion.fadeRiseIn(
                              child: LiveHintChip(
                                text: hint,
                                icon: _isSign
                                    ? Icons.draw_outlined
                                    : Icons.image_outlined,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          ?toolbar,
        ],
      ),
    );
  }
}

class _SignatureFieldBadge extends StatelessWidget {
  const _SignatureFieldBadge({required this.highlighted});

  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    const c = kLiveSelectionColor;
    return AnimatedContainer(
      duration: DsMotion.hoverDuration,
      decoration: BoxDecoration(
        color: c.withValues(alpha: highlighted ? 0.16 : 0.07),
        border: Border.all(
          color: c.withValues(alpha: highlighted ? 1 : 0.6),
          width: 1.2,
        ),
        borderRadius: BorderRadius.circular(2),
      ),
      child: const Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: EdgeInsets.fromLTRB(3, 1, 3, 1),
          child: Text(
            'Sign here',
            style: TextStyle(
              fontSize: 9.5,
              color: c,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Floating mini toolbar above (or below) the selected object.
class _ObjectToolbar extends StatelessWidget {
  const _ObjectToolbar({
    required this.anchor,
    required this.pageSize,
    required this.rotated,
    required this.onDelete,
    required this.onApply,
    required this.applyLabel,
    this.onRotate,
  });

  final Rect anchor;
  final Size pageSize;
  final bool rotated;
  final VoidCallback onDelete;
  final VoidCallback onApply;
  final String applyLabel;
  final VoidCallback? onRotate;

  @override
  Widget build(BuildContext context) {
    const barH = 32.0;
    final barW = onRotate == null ? 128.0 : 160.0;
    final gap = rotated ? 36.0 : (onRotate != null ? 34.0 : 8.0);
    var top = anchor.top - gap - barH;
    if (top < 4) top = anchor.bottom + 8;
    final left = (anchor.center.dx - barW / 2)
        .clamp(4.0, math.max(4.0, pageSize.width - barW - 4))
        .toDouble();
    return Positioned(
      left: left,
      top: top,
      width: barW,
      height: barH,
      child: DsMotion.fadeRiseIn(
        child: Material(
          color: Colors.white,
          elevation: 3,
          shadowColor: const Color(0x44000000),
          borderRadius: BorderRadius.circular(8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (onRotate != null)
                _BarIcon(
                  icon: Icons.rotate_right,
                  tip: 'Rotate 90°',
                  onTap: onRotate!,
                ),
              _BarIcon(
                icon: Icons.delete_outline,
                tip: 'Remove (Delete)',
                onTap: onDelete,
              ),
              Tooltip(
                message: '$applyLabel on page (Enter)',
                child: TextButton(
                  onPressed: onApply,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                    applyLabel,
                    style: const TextStyle(fontSize: 12.5),
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
          child: Icon(icon, size: 17, color: const Color(0xFF3C3C43)),
        ),
      ),
    );
  }
}
