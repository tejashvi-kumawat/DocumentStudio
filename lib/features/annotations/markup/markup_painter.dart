import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:document_studio/domain/pdf_markup/markup_geometry.dart';
import 'package:document_studio/domain/pdf_markup/markup_objects.dart';
import 'package:document_studio/domain/pdf_markup/pdf_page_geometry.dart';
import 'package:document_studio/features/annotations/markup/markup_text_layout.dart';
import 'package:flutter/material.dart';

/// Decoded images for [ImageMarkup] (keyed by the immutable byte buffer).
class MarkupImageCache extends ChangeNotifier {
  MarkupImageCache._();

  static final MarkupImageCache instance = MarkupImageCache._();

  final Expando<ui.Image> _images = Expando<ui.Image>('markupImages');
  final Expando<bool> _pending = Expando<bool>('markupImagesPending');

  ui.Image? imageFor(Uint8List bytes) {
    final img = _images[bytes];
    if (img != null) return img;
    if (_pending[bytes] == true) return null;
    _pending[bytes] = true;
    unawaited(_decode(bytes));
    return null;
  }

  Future<void> _decode(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      _images[bytes] = frame.image;
      notifyListeners();
    } catch (_) {
      // Undecodable: stays a placeholder.
    }
  }
}

/// Highlights and the highlighter pen multiply with the page (like the PDF
/// `/BM /Multiply`), so they're painted on the page canvas, not the overlay.
bool markupUsesMultiply(MarkupObject o) =>
    (o is TextMarkupMarkup && o.kind == TextMarkupKind.highlight) ||
    (o is InkMarkup && o.highlighter);

Float64List affineToMatrix4(Affine2 m) => Float64List.fromList([
  m.a, m.b, 0, 0, //
  m.c, m.d, 0, 0,
  0, 0, 1, 0,
  m.e, m.f, 0, 1,
]);

Color _rgb(int argb, double alpha) =>
    Color(argb | 0xFF000000).withValues(alpha: alpha.clamp(0.0, 1.0));

double _alphaOf(int argb) => ((argb >> 24) & 0xff) / 255;

Paint _stroke(int argb, double alpha, double width, {bool round = true}) =>
    Paint()
      ..style = PaintingStyle.stroke
      ..color = _rgb(argb, alpha)
      ..strokeWidth = width
      ..strokeCap = round ? StrokeCap.round : StrokeCap.butt
      ..strokeJoin = round ? StrokeJoin.round : StrokeJoin.miter
      ..isAntiAlias = true;

Paint _fill(int argb, double alpha) => Paint()
  ..style = PaintingStyle.fill
  ..color = _rgb(argb, alpha)
  ..isAntiAlias = true;

Path _polyline(List<Offset> pts, {bool closed = false}) {
  final p = Path();
  if (pts.isEmpty) return p;
  p.moveTo(pts.first.dx, pts.first.dy);
  for (final q in pts.skip(1)) {
    p.lineTo(q.dx, q.dy);
  }
  if (closed) p.close();
  return p;
}

Path _dashed(Path source, List<double>? pattern) {
  if (pattern == null || pattern.isEmpty) return source;
  final out = Path();
  for (final metric in source.computeMetrics()) {
    var d = 0.0;
    var i = 0;
    var draw = true;
    while (d < metric.length) {
      final len = pattern[i % pattern.length];
      final next = math.min(d + len, metric.length);
      if (draw) out.addPath(metric.extractPath(d, next), Offset.zero);
      d = next;
      draw = !draw;
      i++;
    }
  }
  return out;
}

/// Paints [o] in page display points. [multiply] paints the multiply-blended
/// objects (for the page canvas); otherwise they're skipped.
void paintMarkupObject(
  Canvas canvas,
  MarkupObject o, {
  bool multiply = false,
  bool editing = false,
  bool showLinks = false,
}) {
  if (o.hidden) return;
  if (markupUsesMultiply(o) != multiply) return;
  final a = o.opacity;
  switch (o) {
    case TextBoxMarkup():
      _paintTextBox(canvas, o, a, editing: editing);
    case ImageMarkup():
      _paintImage(canvas, o, a);
    case InkMarkup():
      _paintInk(canvas, o, a);
    case ShapeMarkup():
      _paintShape(canvas, o, a);
    case TextMarkupMarkup():
      _paintTextMarkup(canvas, o, a);
    case NoteMarkup():
      _paintNote(canvas, o, a);
    case LinkMarkup():
      _paintLink(canvas, o, showHint: showLinks);
  }
}

void _paintTextBox(
  Canvas canvas,
  TextBoxMarkup t,
  double a, {
  bool editing = false,
}) {
  final f = t.frame;
  if (t.isCallout) {
    final lineColor = t.borderColor ?? t.textColor;
    final w = math.max(0.75, t.borderWidth);
    final target = t.calloutPoints[0], knee = t.calloutPoints[1];
    canvas.drawPath(
      _polyline([target, knee, t.calloutAttachPoint()]),
      _stroke(lineColor, a, w),
    );
    canvas.drawPath(
      _polyline(arrowHead(knee, target, w), closed: true),
      _fill(lineColor, a),
    );
  }
  canvas.save();
  canvas.transform(affineToMatrix4(frameToDisplay(f, t.rotation)));
  final box = Rect.fromLTWH(0, 0, f.width, f.height);
  if (t.fillColor != null) {
    canvas.drawRect(box, _fill(t.fillColor!, a * _alphaOf(t.fillColor!)));
  }
  if (t.borderColor != null && t.borderWidth > 0) {
    canvas.drawRect(
      box.deflate(t.borderWidth / 2),
      _stroke(t.borderColor!, a, t.borderWidth, round: false),
    );
  }
  if (!editing) {
    if (a < 1) {
      canvas.saveLayer(
        box.inflate(t.fontSize),
        Paint()..color = Color.fromRGBO(0, 0, 0, a),
      );
      _paintTextContent(canvas, t);
      canvas.restore();
    } else {
      _paintTextContent(canvas, t);
    }
  }
  canvas.restore();
}

void _paintTextContent(Canvas canvas, TextBoxMarkup t) {
  paintMarkupTextLines(canvas, t);
  final bars = textDecorationRects(t);
  if (bars.isEmpty) return;
  final paint = _fill(t.textColor, 1);
  for (final r in bars) {
    canvas.drawRect(r, paint);
  }
}

void _paintImage(Canvas canvas, ImageMarkup im, double a) {
  final f = im.frame;
  canvas.save();
  canvas.transform(
    affineToMatrix4(
      frameToDisplay(f, im.rotation, flipH: im.flipH, flipV: im.flipV),
    ),
  );
  final dst = Rect.fromLTWH(0, 0, f.width, f.height);
  final radius = effectiveCornerRadius(im.cornerRadius, f.width, f.height);
  final shape = RRect.fromRectAndRadius(dst, Radius.circular(radius));
  if (radius > 0) canvas.clipRRect(shape);
  final img = MarkupImageCache.instance.imageFor(im.bytes);
  if (img == null) {
    canvas.drawRect(dst, _fill(0xFFE0E0E0, 0.6 * a));
  } else {
    final w = img.width.toDouble(), h = img.height.toDouble();
    final c = im.crop;
    canvas.drawImageRect(
      img,
      Rect.fromLTRB(c.left * w, c.top * h, c.right * w, c.bottom * h),
      dst,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(0, 0, 0, a),
    );
  }
  if (im.hasBorder) {
    final bw = im.borderWidth;
    canvas.drawRRect(
      shape.deflate(bw / 2),
      _stroke(im.borderColor!, a * _alphaOf(im.borderColor!), bw, round: false),
    );
  }
  canvas.restore();
}

void _paintInk(Canvas canvas, InkMarkup ink, double a) {
  final paint = _stroke(ink.strokeColor, a, ink.strokeWidth);
  final dot = _fill(ink.strokeColor, a);
  if (ink.highlighter) {
    paint.blendMode = BlendMode.multiply;
    dot.blendMode = BlendMode.multiply;
  }
  for (final s in ink.strokes) {
    if (s.isEmpty) continue;
    if (s.length == 1) {
      canvas.drawCircle(s.first, ink.strokeWidth / 2, dot);
      continue;
    }
    canvas.drawPath(_polyline(s), paint);
  }
}

void _paintShape(Canvas canvas, ShapeMarkup s, double a) {
  final dash = dashPatternFor(s.dash, s.strokeWidth);
  final stroke = _stroke(
    s.strokeColor,
    a,
    s.strokeWidth,
    round: s.kind != ShapeKind.rectangle,
  );
  if (s.dash == StrokeDash.dotted) stroke.strokeCap = StrokeCap.round;
  if (s.kind == ShapeKind.rectangle && s.dash != StrokeDash.dotted) {
    stroke.strokeCap = StrokeCap.butt;
  }
  final fill = s.fillColor == null
      ? null
      : _fill(s.fillColor!, a * _alphaOf(s.fillColor!));

  switch (s.kind) {
    case ShapeKind.rectangle:
    case ShapeKind.ellipse:
      final f = s.shapeFrame!;
      canvas.save();
      canvas.transform(affineToMatrix4(frameToDisplay(f, s.rotation)));
      final box = Rect.fromLTWH(0, 0, f.width, f.height);
      final Path path;
      if (s.kind == ShapeKind.rectangle) {
        // Same start corner and direction as PDF `re` (bottom-left, y-up).
        path = _polyline([
          Offset(0, f.height),
          Offset(f.width, f.height),
          Offset(f.width, 0),
          Offset.zero,
        ], closed: true);
      } else {
        path = Path()..addOval(box);
      }
      if (fill != null) canvas.drawPath(path, fill);
      canvas.drawPath(_dashed(path, dash), stroke);
      canvas.restore();
    case ShapeKind.line:
    case ShapeKind.arrow:
      if (s.points.length < 2) return;
      final p0 = s.points.first, p1 = s.points.last;
      canvas.drawPath(_dashed(_polyline([p0, p1]), dash), stroke);
      if (s.kind == ShapeKind.arrow) {
        canvas.drawPath(
          _polyline(arrowHead(p0, p1, s.strokeWidth), closed: true),
          _fill(s.strokeColor, a),
        );
      }
    case ShapeKind.polygon:
      if (s.points.length < 2) return;
      final path = _polyline(s.points, closed: true);
      if (fill != null) canvas.drawPath(path, fill);
      canvas.drawPath(_dashed(path, dash), stroke);
    case ShapeKind.cloud:
      final arcs = cloudArcs(s.points, s.cloudRadius());
      if (arcs.isEmpty) return;
      final path = Path()..moveTo(arcs.first.$1.dx, arcs.first.$1.dy);
      for (final (_, c, e) in arcs) {
        path.quadraticBezierTo(c.dx, c.dy, e.dx, e.dy);
      }
      path.close();
      if (fill != null) canvas.drawPath(path, fill);
      canvas.drawPath(_dashed(path, dash), stroke);
  }
}

void _paintTextMarkup(Canvas canvas, TextMarkupMarkup t, double a) {
  if (t.kind == TextMarkupKind.highlight) {
    final paint = _fill(t.markupColor, a)..blendMode = BlendMode.multiply;
    final path = Path();
    for (final r in t.rects) {
      path.addRect(r);
    }
    canvas.drawPath(path, paint);
    return;
  }
  for (final r in t.rects) {
    final st = textMarkupStroke(t.kind, r);
    if (st == null) continue;
    canvas.drawPath(
      _polyline(st.points),
      _stroke(t.markupColor, a, st.width, round: false)
        ..strokeJoin = StrokeJoin.round,
    );
  }
}

void _paintNote(Canvas canvas, NoteMarkup n, double a) {
  final g = NoteIconGeometry(kNoteIconSize);
  Offset at(Offset local) => n.anchor + local;
  final body = g.body;
  final outline = _polyline([
    at(body.topLeft),
    at(body.topRight),
    at(body.bottomRight),
    at(g.tail[2]),
    at(g.tail[1]),
    at(g.tail[0]),
    at(body.bottomLeft),
  ], closed: true);
  canvas.drawPath(outline, _fill(n.noteColor, a));
  canvas.drawPath(
    outline,
    _stroke(0xFF5D4B1F, a, 0.8, round: false)..strokeJoin = StrokeJoin.round,
  );
  final line = _stroke(0xFF5D4B1F, a, 1, round: false);
  for (final (p, q) in g.lines) {
    canvas.drawLine(at(p), at(q), line);
  }
}

void _paintLink(Canvas canvas, LinkMarkup l, {required bool showHint}) {
  final label = l.text.trim();
  if (label.isNotEmpty) {
    final style = TextStyle(
      color: _rgb(l.color, l.opacity),
      fontSize: LinkMarkup.textFontSize,
      decoration: TextDecoration.underline,
      decorationColor: _rgb(l.color, l.opacity),
      height: 1.15,
    );
    final tp = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 4,
      ellipsis: '…',
    )..layout(maxWidth: math.max(8, l.linkFrame.width));
    final origin = Offset(
      l.linkFrame.left,
      l.linkFrame.top + math.max(0, (l.linkFrame.height - tp.height) / 2),
    );
    tp.paint(canvas, origin);
  }
  if (l.showBorder) {
    canvas.drawRect(
      l.linkFrame.deflate(0.5),
      _stroke(0xFF1F70D9, l.opacity, 1, round: false),
    );
  }
  if (!showHint) return;
  canvas.drawRect(l.linkFrame, _fill(0xFF1E6FD9, 0.08));
  canvas.drawPath(
    _dashed(Path()..addRect(l.linkFrame), const [3, 2]),
    _stroke(0xFF1E6FD9, 0.8, 0.8, round: false),
  );
}
