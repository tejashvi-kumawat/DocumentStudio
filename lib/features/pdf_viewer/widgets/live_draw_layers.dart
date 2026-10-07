import 'dart:math' as math;

import 'package:document_studio/features/pdf_viewer/live_text_edit_math.dart';
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_overlay_common.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_page_geom.dart';
import 'package:document_studio/features/pdf_viewer/widgets/watermark_preview_painter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Unburned marks on [page] (ink, shapes, stamps, text markup).
List<LiveDrawCommit> liveCommitsForPage(
  ViewerLiveToolSession live,
  int page,
) => [
  for (final c in live.queuedDrawCommits)
    if ((c.pageIndex1Based > 0 ? c.pageIndex1Based : live.pageIndex1Based) ==
        page)
      c,
];

/// Paints committed marks exactly as the writer burns them (same widths in
/// points, colors, opacity, stamp and note layout).
class LiveMarksPainter extends CustomPainter {
  LiveMarksPainter({required this.commits, required this.geom});

  final List<LiveDrawCommit> commits;
  final LivePageGeom geom;

  @override
  void paint(Canvas canvas, Size size) {
    for (final c in commits) {
      paintLiveCommit(canvas, size, c, geom);
    }
  }

  @override
  bool shouldRepaint(covariant LiveMarksPainter old) {
    if (old.geom != geom || old.commits.length != commits.length) return true;
    for (var i = 0; i < commits.length; i++) {
      if (!identical(old.commits[i], commits[i])) return true;
    }
    return false;
  }
}

Path _polylinePath(List<Offset> pts, Size size, {bool closed = false}) {
  final path = Path();
  if (pts.isEmpty) return path;
  final first = Offset(pts.first.dx * size.width, pts.first.dy * size.height);
  path.moveTo(first.dx, first.dy);
  for (var i = 1; i < pts.length; i++) {
    path.lineTo(pts[i].dx * size.width, pts[i].dy * size.height);
  }
  if (closed) path.close();
  return path;
}

/// Quadratic-midpoint path for the stroke being drawn (smooth while drawing).
Path _smoothLivePath(List<Offset> pts, Size size) {
  final path = Path();
  if (pts.isEmpty) return path;
  Offset px(Offset o) => Offset(o.dx * size.width, o.dy * size.height);
  final p0 = px(pts.first);
  path.moveTo(p0.dx, p0.dy);
  if (pts.length == 1) {
    path.lineTo(p0.dx + 0.01, p0.dy);
    return path;
  }
  for (var i = 1; i < pts.length - 1; i++) {
    final a = px(pts[i]);
    final b = px(pts[i + 1]);
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    path.quadraticBezierTo(a.dx, a.dy, mid.dx, mid.dy);
  }
  final last = px(pts.last);
  path.lineTo(last.dx, last.dy);
  return path;
}

Paint _strokePaint(Color color, double opacity, double widthPx) => Paint()
  ..color = color.withValues(alpha: (color.a * opacity).clamp(0.0, 1.0))
  ..style = PaintingStyle.stroke
  ..strokeWidth = math.max(0.5, widthPx)
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..isAntiAlias = true;

void paintLiveCommit(
  Canvas canvas,
  Size size,
  LiveDrawCommit c,
  LivePageGeom geom,
) {
  final kind = c.markupKind;
  final pxPerPt = geom.pxPerPt;
  if (kind != null) {
    final fill = Paint()
      ..color = c.color.withValues(alpha: c.opacity.clamp(0.0, 1.0));
    if (kind != LiveMarkupKind.note) {
      for (final r in c.rectsNorm) {
        canvas.drawRect(geom.rectToPx(r), fill);
      }
      return;
    }
    if (c.rectsNorm.isEmpty) return;
    final box = geom.rectToPx(c.rectsNorm.first);
    canvas.drawRect(box, fill);
    canvas.drawRect(
      box,
      Paint()
        ..color = kLiveNoteStroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75 * pxPerPt,
    );
    final lines = liveNoteLines(
      c.labelText ?? '',
      widthPt: box.width / pxPerPt,
    );
    paintLiveTextBox(
      canvas,
      boxPx: box.deflate(kLiveNotePadPt * pxPerPt),
      lines: lines,
      fontSizePt: kLiveNoteFontPt,
      pxPerPt: pxPerPt,
      color: const Color(0xFF212121),
      bold: false,
      align: LiveMarginAlign.left,
    );
    return;
  }
  if (c.tool == LiveDrawTool.stamp) {
    var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
    for (final o in c.pointsNorm) {
      minX = math.min(minX, o.dx);
      minY = math.min(minY, o.dy);
      maxX = math.max(maxX, o.dx);
      maxY = math.max(maxY, o.dy);
    }
    paintStampLabel(
      canvas,
      size,
      boxNorm: Rect.fromLTRB(minX, minY, maxX, maxY),
      label: c.labelText ?? 'APPROVED',
      color: c.color,
      pageWidthPt: geom.pageWidthPt,
      pageHeightPt: geom.pageHeightPt,
    );
    return;
  }
  if (c.pointsNorm.isEmpty) return;
  canvas.drawPath(
    _polylinePath(c.pointsNorm, size, closed: c.closed),
    _strokePaint(c.color, c.opacity, c.strokeWidthPt * pxPerPt),
  );
}

/// In-progress stroke / shape (repaints on draft ticks only).
class _LiveStrokePainter extends CustomPainter {
  _LiveStrokePainter({
    required this.points,
    required this.tool,
    required this.color,
    required this.opacity,
    required this.widthPx,
  });

  final List<Offset>? points;
  final LiveDrawTool tool;
  final Color color;
  final double opacity;
  final double widthPx;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = points;
    if (pts == null || pts.isEmpty) return;
    final paint = _strokePaint(color, opacity, widthPx);
    if (tool == LiveDrawTool.pen || tool == LiveDrawTool.highlighter) {
      canvas.drawPath(_smoothLivePath(pts, size), paint);
      return;
    }
    if (pts.length < 2) return;
    final shape = ViewerLiveToolSession.expandShapePoints(
      tool,
      pts.first,
      pts.last,
    );
    final closed =
        tool == LiveDrawTool.rectangle ||
        tool == LiveDrawTool.ellipse ||
        tool == LiveDrawTool.callout;
    canvas.drawPath(_polylinePath(shape, size, closed: closed), paint);
  }

  @override
  bool shouldRepaint(covariant _LiveStrokePainter old) => true;
}

/// Freehand pen / highlighter / shapes / stamps on any page.
class LiveInkLayer extends StatefulWidget {
  const LiveInkLayer({super.key, required this.session, required this.geom});

  final ViewerLiveToolSession session;
  final LivePageGeom geom;

  @override
  State<LiveInkLayer> createState() => _LiveInkLayerState();
}

class _LiveInkLayerState extends State<LiveInkLayer> {
  Offset? _shapeStart;
  int? _pointer;

  ViewerLiveToolSession get _live => widget.session;
  LivePageGeom get _g => widget.geom;

  bool get _isFreehand =>
      _live.drawTool == LiveDrawTool.pen ||
      _live.drawTool == LiveDrawTool.highlighter;

  Offset _constrained(Offset startNorm, Offset curNorm) {
    if (!HardwareKeyboard.instance.isShiftPressed) return curNorm;
    // Work in points so 45° / squares are true on non-square pages.
    final w = _g.pageWidthPt;
    final h = _g.pageHeightPt;
    final dx = (curNorm.dx - startNorm.dx) * w;
    final dy = (curNorm.dy - startNorm.dy) * h;
    switch (_live.drawTool) {
      case LiveDrawTool.line:
      case LiveDrawTool.arrow:
        final len = math.sqrt(dx * dx + dy * dy);
        final ang =
            (math.atan2(dy, dx) / (math.pi / 4)).round() * (math.pi / 4);
        return Offset(
          (startNorm.dx + math.cos(ang) * len / w).clamp(0.0, 1.0),
          (startNorm.dy + math.sin(ang) * len / h).clamp(0.0, 1.0),
        );
      case LiveDrawTool.rectangle:
      case LiveDrawTool.ellipse:
      case LiveDrawTool.callout:
        final s = math.max(dx.abs(), dy.abs());
        return Offset(
          (startNorm.dx + s * dx.sign / w).clamp(0.0, 1.0),
          (startNorm.dy + s * dy.sign / h).clamp(0.0, 1.0),
        );
      default:
        return curNorm;
    }
  }

  void _down(PointerDownEvent e) {
    if (e.buttons != kPrimaryButton || _pointer != null) return;
    if (_live.pageIndex1Based != _g.pageNumber) _live.focusPage(_g.pageNumber);
    final n = _g.toNorm(e.localPosition);
    if (_live.drawTool == LiveDrawTool.stamp) {
      _live.placeStampAtNorm(n);
      return;
    }
    _pointer = e.pointer;
    if (_isFreehand) {
      _live.beginInkStroke(n);
    } else {
      _shapeStart = n;
      _live.setShapeDraft(n, n);
    }
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final n = _g.toNorm(e.localPosition);
    if (_isFreehand) {
      _live.appendInkStroke(n);
    } else if (_shapeStart != null) {
      _live.setShapeDraft(_shapeStart!, _constrained(_shapeStart!, n));
    }
  }

  void _up(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (_isFreehand) {
      _live.endInkStroke(queueCommit: true);
    } else {
      _shapeStart = null;
      _live.commitShapeDraft(queueCommit: true);
    }
  }

  void _cancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _shapeStart = null;
    _live.cancelCurrentStroke();
  }

  @override
  Widget build(BuildContext context) {
    final live = _live;
    final isActive = live.pageIndex1Based == _g.pageNumber;
    final commits = liveCommitsForPage(live, _g.pageNumber);
    final tool = live.drawTool;
    final highlighter = tool == LiveDrawTool.highlighter;
    return MouseRegion(
      cursor: tool == LiveDrawTool.stamp
          ? SystemMouseCursors.copy
          : SystemMouseCursors.precise,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _cancel,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                painter: LiveMarksPainter(commits: commits, geom: _g),
              ),
            ),
            if (isActive && live.currentInkStroke != null)
              CustomPaint(
                painter: _LiveStrokePainter(
                  points: live.currentInkStroke,
                  tool: tool,
                  color: highlighter
                      ? (live.markupColor.toARGB32() == 0xFFE4002B
                            ? kLiveHighlightColor
                            : live.markupColor)
                      : live.markupColor,
                  opacity: highlighter ? kLiveHighlightOpacity : 1,
                  widthPx:
                      (highlighter
                          ? math.max(live.strokeWidthPt, 8)
                          : live.strokeWidthPt) *
                      _g.pxPerPt,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Converts a pointer drag into markup bands snapped to the page's text lines.
List<Rect> snapMarkupBands({
  required List<Rect>? chars,
  required Offset startNorm,
  required Offset endNorm,
  required LiveMarkupKind kind,
  required double pageWidthPt,
  required double pageHeightPt,
}) {
  final drag = Rect.fromPoints(startNorm, endNorm);
  List<Rect> lines = const [];
  if (chars != null && chars.isNotEmpty) {
    lines = _selectTextLines(chars, startNorm, endNorm);
  }
  final tiny = drag.width * pageWidthPt < 3 && drag.height * pageHeightPt < 3;
  if (lines.isEmpty) {
    if (tiny) return const [];
    lines = [drag];
  }
  double thick(Rect line) =>
      math.max(0.9, line.height * pageHeightPt * 0.075) / pageHeightPt;
  return [
    for (final r in lines)
      switch (kind) {
        LiveMarkupKind.highlight => Rect.fromLTRB(
          r.left,
          r.top - r.height * 0.08,
          r.right,
          r.bottom + r.height * 0.08,
        ),
        LiveMarkupKind.underline => Rect.fromLTRB(
          r.left,
          r.bottom,
          r.right,
          r.bottom + thick(r),
        ),
        LiveMarkupKind.strikethrough => () {
          final cy = r.top + r.height * 0.55;
          final t = thick(r);
          return Rect.fromLTRB(r.left, cy - t / 2, r.right, cy + t / 2);
        }(),
        LiveMarkupKind.note => r,
      },
  ];
}

/// Reading-order selection from the char nearest [a] to the char nearest [b],
/// grouped into one rect per text line (like selecting text in Acrobat).
List<Rect> _selectTextLines(List<Rect> chars, Offset a, Offset b) {
  (int, double) nearest(Offset p) {
    var best = -1;
    var bestD = double.infinity;
    for (var i = 0; i < chars.length; i++) {
      final r = chars[i];
      if (r.width <= 0 || r.height <= 0) continue;
      final dx = p.dx < r.left
          ? r.left - p.dx
          : (p.dx > r.right ? p.dx - r.right : 0.0);
      final dy = p.dy < r.top
          ? r.top - p.dy
          : (p.dy > r.bottom ? p.dy - r.bottom : 0.0);
      final d = dx * dx * 4 + dy * dy * 16;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return (best, math.sqrt(bestD));
  }

  final (i0, d0) = nearest(a);
  final (i1, d1) = nearest(b);
  if (i0 < 0 || i1 < 0) return const [];
  const reach = 0.05;
  if (d0 > reach && d1 > reach) return const [];
  final lo = math.min(i0, i1);
  final hi = math.max(i0, i1);
  final out = <Rect>[];
  Rect? cur;
  for (var i = lo; i <= hi; i++) {
    final r = chars[i];
    if (r.width <= 0 || r.height <= 0) continue;
    if (cur == null) {
      cur = r;
      continue;
    }
    final overlap = math.min(cur.bottom, r.bottom) - math.max(cur.top, r.top);
    final sameLine =
        overlap > 0.5 * math.min(cur.height, r.height) &&
        r.left >= cur.left - cur.height;
    if (sameLine) {
      cur = cur.expandToInclude(r);
    } else {
      out.add(cur);
      cur = r;
    }
  }
  if (cur != null) out.add(cur);
  return out;
}

/// Highlight / underline / strikethrough by dragging over text; sticky notes
/// by clicking.
class LiveMarkupLayer extends StatefulWidget {
  const LiveMarkupLayer({super.key, required this.session, required this.geom});

  final ViewerLiveToolSession session;
  final LivePageGeom geom;

  @override
  State<LiveMarkupLayer> createState() => _LiveMarkupLayerState();
}

class _LiveMarkupLayerState extends State<LiveMarkupLayer> {
  Offset? _start;
  Offset? _end;
  int? _pointer;

  ViewerLiveToolSession get _live => widget.session;
  LivePageGeom get _g => widget.geom;

  List<Rect> _bands() {
    final s = _start;
    final e = _end;
    if (s == null || e == null) return const [];
    return snapMarkupBands(
      chars: _live.textCharRectsFor(_g.pageNumber),
      startNorm: s,
      endNorm: e,
      kind: _live.markupKind,
      pageWidthPt: _g.pageWidthPt,
      pageHeightPt: _g.pageHeightPt,
    );
  }

  void _down(PointerDownEvent e) {
    if (e.buttons != kPrimaryButton || _pointer != null) return;
    if (_live.pageIndex1Based != _g.pageNumber) _live.focusPage(_g.pageNumber);
    final n = _g.toNorm(e.localPosition);
    if (_live.markupKind == LiveMarkupKind.note) {
      final text = _live.labelText ?? '';
      final wN = _g.ptToNormX(kLiveNoteWidthPt).clamp(0.05, 1.0);
      final hN = _g
          .ptToNormY(liveNoteHeightPt(liveNoteLines(text).length))
          .clamp(0.02, 1.0);
      final left = n.dx.clamp(0.0, 1.0 - wN);
      final top = n.dy.clamp(0.0, 1.0 - hN);
      _live.queueMarkup(
        kind: LiveMarkupKind.note,
        rectsNorm: [Rect.fromLTWH(left, top, wN, hN)],
        noteText: text.trim().isEmpty ? 'Note' : text.trim(),
      );
      return;
    }
    _pointer = e.pointer;
    setState(() {
      _start = n;
      _end = n;
    });
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    setState(() => _end = _g.toNorm(e.localPosition));
  }

  void _up(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    final bands = _bands();
    setState(() {
      _start = null;
      _end = null;
    });
    if (bands.isNotEmpty) {
      _live.queueMarkup(kind: _live.markupKind, rectsNorm: bands);
    }
  }

  void _cancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    setState(() {
      _start = null;
      _end = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final commits = liveCommitsForPage(_live, _g.pageNumber);
    final kind = _live.markupKind;
    final previewColor = switch (kind) {
      LiveMarkupKind.highlight => kLiveHighlightColor.withValues(
        alpha: kLiveHighlightOpacity,
      ),
      LiveMarkupKind.underline => kLiveUnderlineColor,
      LiveMarkupKind.strikethrough => kLiveStrikeColor,
      LiveMarkupKind.note => kLiveNoteFill,
    };
    final bands = _bands();
    final hasText = _live.textCharRectsFor(_g.pageNumber)?.isNotEmpty ?? false;
    return MouseRegion(
      cursor: kind == LiveMarkupKind.note
          ? SystemMouseCursors.copy
          : (hasText ? SystemMouseCursors.text : SystemMouseCursors.precise),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _cancel,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                painter: LiveMarksPainter(commits: commits, geom: _g),
              ),
            ),
            if (bands.isNotEmpty)
              CustomPaint(
                painter: _BandsPainter(
                  bands: [for (final b in bands) _g.rectToPx(b)],
                  color: previewColor,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BandsPainter extends CustomPainter {
  _BandsPainter({required this.bands, required this.color});

  final List<Rect> bands;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (final b in bands) {
      canvas.drawRect(b, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BandsPainter old) => true;
}
