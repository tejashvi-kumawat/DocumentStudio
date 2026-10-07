import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_overlay_common.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_page_geom.dart';
import 'package:document_studio/features/pdf_viewer/widgets/pointer_claim_region.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_page_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum _Drag { none, move, tl, tr, bl, br }

/// Edit PDF: pictures already on the page can be selected, moved, resized,
/// replaced or deleted, like Acrobat's "Edit a PDF".
///
/// Sits above the text layer; it only takes pointers that land on a picture
/// and not on a text block, so text editing keeps priority over a caption
/// drawn on top of an image.
class LiveImageEditLayer extends StatefulWidget {
  const LiveImageEditLayer({
    super.key,
    required this.session,
    required this.geom,
  });

  final ViewerLiveToolSession session;
  final LivePageGeom geom;

  @override
  State<LiveImageEditLayer> createState() => _LiveImageEditLayerState();
}

class _LiveImageEditLayerState extends State<LiveImageEditLayer> {
  final FocusNode _focus = FocusNode(debugLabel: 'live-image-edit');
  _Drag _drag = _Drag.none;
  Offset? _start;
  Rect? _base;
  Offset? _hover;

  /// Picture of the object being dragged (see [ViewerLiveToolSession.objectSnapshot]).
  ui.Image? _ghost;
  Rect? _ghostFrom;

  void _grabGhost(EditableImage obj) {
    final from = _rectOf(obj);
    _ghostFrom = from;
    _ghost = null;
    for (final g in _s.ghostsForPage(_g.pageNumber)) {
      if (g.to == from && g.image != null) {
        _ghost = g.image;
        return;
      }
    }
    final snap = _s.objectSnapshot;
    if (snap == null) return;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    snap(_g.pageNumber, from, _g.rectToPx(from).width * dpr).then((img) {
      if (!mounted || _ghostFrom != from) return;
      setState(() => _ghost = img);
    });
  }

  /// Records what to show until the change is written into the PDF.
  void _leaveGhost(Rect from, Rect? to) {
    _s.addGhost(
      LiveObjectGhost(page: _g.pageNumber, from: from, to: to, image: _ghost),
    );
  }

  ViewerLiveToolSession get _s => widget.session;
  LivePageGeom get _g => widget.geom;

  List<EditableImage> get _images => _s.imagesForPage(_g.pageNumber);

  EditableImage? get _selected {
    final sel = _s.selectedImage;
    return sel != null && sel.page == _g.pageNumber ? sel : null;
  }

  Rect _rectOf(EditableImage i) =>
      (_selected == i ? _s.imageDraft : null) ?? i.normRect;

  bool _onText(Offset local) {
    final n = Offset(local.dx / _g.pagePx.width, local.dy / _g.pagePx.height);
    for (final t in _s.textRunsForPage(_g.pageNumber)) {
      if (t.hitRect.contains(n)) return true;
    }
    return false;
  }

  /// The object under [local]: comments first, then the smallest picture
  /// or shape. A shape only wins over a picture when it is clearly a detail
  /// on it (a quarter of its size or less) — a stray line must not steal
  /// the click meant for the photo behind it.
  EditableImage? _imageAt(Offset local) {
    final n = Offset(local.dx / _g.pagePx.width, local.dy / _g.pagePx.height);
    double area(EditableImage i) => _rectOf(i).width * _rectOf(i).height;
    EditableImage? best(EditableKind k) {
      EditableImage? b;
      for (final i in _images) {
        if (i.kind != k) continue;
        final r = _rectOf(i);
        // Thin lines get a few pixels of grab room.
        // (normalised x and y have different pixel sizes on most pages).
        final dx = 4 / _g.pagePx.width, dy = 4 / _g.pagePx.height;
        final hit = r.width < 0.01 || r.height < 0.01
            ? Rect.fromLTRB(
                r.left - dx,
                r.top - dy,
                r.right + dx,
                r.bottom + dy,
              ).contains(n)
            : r.contains(n);
        if (hit && (b == null || area(i) < area(b))) b = i;
      }
      return b;
    }

    final annot = best(EditableKind.annotation);
    if (annot != null) return annot;
    final img = best(EditableKind.image);
    final shape = best(EditableKind.shape);
    if (img == null) return shape;
    if (shape == null) return img;
    return area(shape) <= area(img) * 0.25 ? shape : img;
  }

  _Drag _handleAt(Offset local) {
    final sel = _selected;
    if (sel == null) return _Drag.none;
    final r = _g.rectToPx(_rectOf(sel));
    const hit = kLiveHandleHitPad + 2;
    if ((local - r.topLeft).distance <= hit) return _Drag.tl;
    if ((local - r.topRight).distance <= hit) return _Drag.tr;
    if ((local - r.bottomLeft).distance <= hit) return _Drag.bl;
    if ((local - r.bottomRight).distance <= hit) return _Drag.br;
    return _Drag.none;
  }

  bool _claims(Offset local) {
    if (_drag != _Drag.none) return true;
    if (_images.isEmpty) return false;
    if (_handleAt(local) != _Drag.none) return true;
    if (_selected != null && _toolbarRect().contains(local)) return true;
    final hit = _imageAt(local);
    if (hit == null) return false;
    // Comments / drawings sit on top of text (highlights!) and win; a
    // picture under a text block lets the text be edited.
    return hit.kind == EditableKind.annotation || !_onText(local);
  }

  Rect _toolbarRect() {
    final sel = _selected;
    if (sel == null) return Rect.zero;
    final r = _g.rectToPx(_rectOf(sel));
    // Shapes get a colour row too, so their bar is wider.
    final w = switch (sel.kind) {
      EditableKind.shape => 330.0,
      EditableKind.image => 214.0,
      EditableKind.annotation => 196.0,
    };
    final top = (r.top - 40).clamp(2.0, _g.pagePx.height - 40);
    return Rect.fromLTWH(
      (r.center.dx - w / 2).clamp(2.0, math.max(2.0, _g.pagePx.width - w - 2)),
      top.toDouble(),
      w,
      34,
    );
  }

  void _down(PointerDownEvent e) {
    if (e.buttons != kPrimaryButton) return;
    final p = e.localPosition;
    final handle = _handleAt(p);
    final sel = _selected;
    if (handle != _Drag.none && sel != null) {
      _drag = handle;
      _start = p;
      _base = _rectOf(sel);
      _grabGhost(sel);
      return;
    }
    final hit = _imageAt(p);
    if (hit == null) return;
    // Drag ticks repaint only the focused page.
    if (_s.pageIndex1Based != _g.pageNumber) _s.focusPage(_g.pageNumber);
    _s.selectImage(hit);
    _focus.requestFocus();
    _grabGhost(hit);
    _drag = _Drag.move;
    _start = p;
    _base = hit.normRect;
  }

  void _move(PointerMoveEvent e) {
    final base = _base;
    final start = _start;
    if (_drag == _Drag.none || base == null || start == null) return;
    final d = _g.deltaToNorm(e.localPosition - start);
    Rect next;
    switch (_drag) {
      case _Drag.move:
        next = base.shift(d);
        // Keep the picture on the page.
        final dx = next.left < 0
            ? -next.left
            : (next.right > 1 ? 1 - next.right : 0.0);
        final dy = next.top < 0
            ? -next.top
            : (next.bottom > 1 ? 1 - next.bottom : 0.0);
        next = next.shift(Offset(dx, dy));
      case _Drag.br:
        next = _scaled(base, base.topLeft, d, 1, 1);
      case _Drag.tr:
        next = _scaled(base, base.bottomLeft, d, 1, -1);
      case _Drag.bl:
        next = _scaled(base, base.topRight, d, -1, 1);
      case _Drag.tl:
        next = _scaled(base, base.bottomRight, d, -1, -1);
      case _Drag.none:
        return;
    }
    _s.setImageDraft(next);
  }

  /// Corner resize with the picture's aspect ratio kept (Shift frees it).
  Rect _scaled(Rect base, Offset anchor, Offset d, int sx, int sy) {
    final free = HardwareKeyboard.instance.isShiftPressed;
    var w = (base.width + d.dx * sx).clamp(0.02, 2.0).toDouble();
    var h = (base.height + d.dy * sy).clamp(0.02, 2.0).toDouble();
    if (!free) {
      // Same factor on both axes keeps the picture's proportions.
      final k =
          ((base.width + d.dx * sx) / base.width +
              (base.height + d.dy * sy) / base.height) /
          2;
      w = (base.width * k).clamp(0.02, 2.0).toDouble();
      h = base.height * (w / base.width);
    }
    final left = sx > 0 ? anchor.dx : anchor.dx - w;
    final top = sy > 0 ? anchor.dy : anchor.dy - h;
    return Rect.fromLTWH(left, top, w, h);
  }

  void _up(PointerEvent e) {
    final sel = _selected;
    final draft = _s.imageDraft;
    final moved = _drag != _Drag.none && draft != null && sel != null;
    _drag = _Drag.none;
    _start = null;
    _base = null;
    final changed =
        moved &&
        ((draft.topLeft - sel.normRect.topLeft).distance +
                (draft.width - sel.normRect.width).abs() +
                (draft.height - sel.normRect.height).abs()) >
            0.002;
    if (changed) {
      _leaveGhost(sel.normRect, draft);
      _s.imageEditHandler?.call(
        ImageEditRequest(ImageEditKind.move, sel, draft),
      );
    }
    _s.setImageDraft(null);
  }

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    final sel = _selected;
    if (e is! KeyDownEvent || sel == null) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.delete ||
        e.logicalKey == LogicalKeyboardKey.backspace) {
      _leaveGhost(sel.normRect, null);
      _s.imageEditHandler?.call(ImageEditRequest(ImageEditKind.delete, sel));
      _s.selectImage(null);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      _s.selectImage(null);
      return KeyEventResult.handled;
    }
    final step = HardwareKeyboard.instance.isShiftPressed ? 0.01 : 0.002;
    final d = switch (e.logicalKey) {
      LogicalKeyboardKey.arrowLeft => Offset(-step, 0),
      LogicalKeyboardKey.arrowRight => Offset(step, 0),
      LogicalKeyboardKey.arrowUp => Offset(0, -step),
      LogicalKeyboardKey.arrowDown => Offset(0, step),
      _ => null,
    };
    if (d == null) return KeyEventResult.ignored;
    _grabGhost(sel);
    _leaveGhost(sel.normRect, sel.normRect.shift(d));
    _s.imageEditHandler?.call(
      ImageEditRequest(ImageEditKind.move, sel, sel.normRect.shift(d)),
    );
    return KeyEventResult.handled;
  }

  MouseCursor _cursor() {
    final p = _hover;
    if (p == null) return MouseCursor.defer;
    switch (_handleAt(p)) {
      case _Drag.tl:
      case _Drag.br:
        return SystemMouseCursors.resizeUpLeftDownRight;
      case _Drag.tr:
      case _Drag.bl:
        return SystemMouseCursors.resizeUpRightDownLeft;
      default:
    }
    final i = _imageAt(p);
    if (i == null) return MouseCursor.defer;
    if (i.kind != EditableKind.annotation && _onText(p)) {
      return MouseCursor.defer;
    }
    return _selected == i ? SystemMouseCursors.move : SystemMouseCursors.click;
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selected;
    final hover = _hover == null || !_claims(_hover!)
        ? null
        : _imageAt(_hover!);
    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: MouseRegion(
        // Defer to the claim region: pointers this layer does not claim reach
        // the text layer and the viewer underneath. (opaque: false would let
        // claimed pointers fall through to the layer below as well.)
        hitTestBehavior: HitTestBehavior.deferToChild,
        cursor: _cursor(),
        onHover: (e) => setState(() => _hover = e.localPosition),
        onExit: (_) => setState(() => _hover = null),
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: PointerClaimRegion(
                claims: _claims,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _down,
                  onPointerMove: _move,
                  onPointerUp: _up,
                  onPointerCancel: _up,
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ImagePainter(
                        ghosts: [
                          for (final g in _s.ghostsForPage(_g.pageNumber))
                            (
                              _g.rectToPx(g.from),
                              g.to == null ? null : _g.rectToPx(g.to!),
                              g.image,
                            ),
                          if (_drag != _Drag.none &&
                              _ghostFrom != null &&
                              _s.imageDraft != null)
                            (
                              _g.rectToPx(_ghostFrom!),
                              _g.rectToPx(_s.imageDraft!),
                              _ghost,
                            ),
                        ],
                        outlines: [
                          for (final i in _images)
                            if (i.kind != EditableKind.shape ||
                                _images.length < 80)
                              (_g.rectToPx(_rectOf(i)), i.kind),
                        ],
                        hover: hover == null
                            ? null
                            : _g.rectToPx(_rectOf(hover)),
                        selected: sel == null
                            ? null
                            : _g.rectToPx(_rectOf(sel)),
                        dragging: _drag != _Drag.none,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (sel != null && _drag == _Drag.none)
              Positioned.fromRect(
                rect: _toolbarRect(),
                child: _ImageToolbar(
                  label: sel.label,
                  isShape: sel.kind == EditableKind.shape,
                  canReplace: sel.kind == EditableKind.image,
                  onColor: (c) => _s.imageEditHandler?.call(
                    ImageEditRequest(ImageEditKind.recolor, sel, null, c),
                  ),
                  onReplace: () => _s.imageEditHandler?.call(
                    ImageEditRequest(ImageEditKind.replace, sel),
                  ),
                  onDelete: () {
                    _leaveGhost(sel.normRect, null);
                    _s.imageEditHandler?.call(
                      ImageEditRequest(ImageEditKind.delete, sel),
                    );
                    _s.selectImage(null);
                  },
                  onDeselect: () => _s.selectImage(null),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ImageToolbar extends StatelessWidget {
  const _ImageToolbar({
    required this.label,
    required this.canReplace,
    required this.isShape,
    required this.onColor,
    required this.onReplace,
    required this.onDelete,
    required this.onDeselect,
  });

  final String label;
  final bool canReplace;
  final bool isShape;
  final ValueChanged<Color> onColor;
  final VoidCallback onReplace;
  final VoidCallback onDelete;
  final VoidCallback onDeselect;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, String tip, VoidCallback onTap) => Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 34,
          child: Icon(icon, size: 18, color: const Color(0xFF333333)),
        ),
      ),
    );
    return Material(
      color: Colors.white,
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(left: 10, right: 4),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF333333),
                ),
              ),
            ),
          ),
          if (isShape)
            for (final c in const [
              Color(0xFF111111),
              Color(0xFFE4002B),
              Color(0xFF1473E6),
              Color(0xFF34C759),
              Color(0xFFFFB300),
            ])
              Tooltip(
                message: 'Recolor',
                child: InkWell(
                  onTap: () => onColor(c),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black26),
                    ),
                  ),
                ),
              )
          else if (canReplace)
            btn(Icons.swap_horiz, 'Replace image…', onReplace),
          btn(Icons.delete_outline, 'Delete (Del)', onDelete),
          btn(Icons.close, 'Deselect (Esc)', onDeselect),
        ],
      ),
    );
  }
}

class _ImagePainter extends CustomPainter {
  _ImagePainter({
    this.ghosts = const [],
    this.outlines = const [],
    this.hover,
    this.selected,
    required this.dragging,
  });

  /// (old spot to cover, new spot, picture) of changes not yet written.
  final List<(Rect, Rect?, ui.Image?)> ghosts;

  /// Every editable object on the page, drawn faintly so the layers show.
  final List<(Rect, EditableKind)> outlines;

  final Rect? hover;
  final Rect? selected;
  final bool dragging;

  @override
  void paint(Canvas canvas, Size size) {
    // Changes not written yet. No white cover over the old spot: text drawn
    // on top of a picture would vanish with it. The old spot is outlined and
    // the picture is shown at its new place until the page re-renders.
    final pending = Paint()
      ..color = const Color(0xFFE4002B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    // A moved object's old spot: fainter than a deletion (own paint, so the
    // order of ghosts never changes how a deletion looks).
    final movedFrom = Paint()
      ..color = const Color(0x99E4002B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final (from, to, img) in ghosts) {
      if (to == null) {
        canvas.drawRect(from, Paint()..color = const Color(0x22E4002B));
        _dashed(canvas, from, pending);
        continue;
      }
      _dashed(canvas, from, movedFrom);
      if (img != null) {
        canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          to,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..color = const Color(0xF0FFFFFF),
        );
      }
    }
    for (final (r, kind) in outlines) {
      final color = switch (kind) {
        EditableKind.image => const Color(0xFF1473E6),
        EditableKind.shape => const Color(0xFF8E8E93),
        EditableKind.annotation => const Color(0xFFE68A00),
      };
      _dashed(
        canvas,
        r,
        Paint()
          ..color = color.withValues(
            alpha: kind == EditableKind.shape ? 0.35 : 0.7,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    final h = hover;
    if (h != null && h != selected) {
      canvas.drawRect(
        h,
        Paint()..color = kLiveSelectionColor.withValues(alpha: 0.08),
      );
      canvas.drawRect(
        h,
        Paint()
          ..color = kLiveSelectionColor.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
    final s = selected;
    if (s == null) return;
    canvas.drawRect(
      s,
      Paint()
        ..color = kLiveSelectionColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = dragging ? 1.6 : 1.4,
    );
    if (dragging) {
      canvas.drawRect(
        s,
        Paint()..color = kLiveSelectionColor.withValues(alpha: 0.10),
      );
    }
    for (final c in [s.topLeft, s.topRight, s.bottomLeft, s.bottomRight]) {
      final r = Rect.fromCenter(center: c, width: 9, height: 9);
      canvas.drawRect(r, Paint()..color = Colors.white);
      canvas.drawRect(
        r,
        Paint()
          ..color = kLiveSelectionColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
  }

  static void _dashed(Canvas canvas, Rect r, Paint p) {
    const dash = 4.0, gap = 3.0;
    void line(Offset a, Offset b) {
      final len = (b - a).distance;
      if (len <= 0) return;
      final dir = (b - a) / len;
      for (var d = 0.0; d < len; d += dash + gap) {
        canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, len), p);
      }
    }

    line(r.topLeft, r.topRight);
    line(r.topRight, r.bottomRight);
    line(r.bottomRight, r.bottomLeft);
    line(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(covariant _ImagePainter old) =>
      old.hover != hover ||
      old.selected != selected ||
      old.dragging != dragging ||
      old.ghosts.length != ghosts.length ||
      ghosts.isNotEmpty ||
      old.outlines.length != outlines.length ||
      (outlines.isNotEmpty && old.outlines.first != outlines.first);
}
