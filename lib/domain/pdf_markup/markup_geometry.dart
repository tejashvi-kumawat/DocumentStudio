import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:document_studio/domain/pdf_markup/markup_objects.dart';

/// Shared stroke geometry for underline / strikeout / squiggly so the
/// on-screen painter and the PDF appearance stream draw identical marks.
class TextMarkupStroke {
  const TextMarkupStroke(this.points, this.width);
  final List<Offset> points;
  final double width;
}

TextMarkupStroke? textMarkupStroke(TextMarkupKind kind, Rect r) {
  final w = math.max(0.6, r.height / 14);
  switch (kind) {
    case TextMarkupKind.highlight:
      return null;
    case TextMarkupKind.underline:
      final y = r.bottom - w / 2;
      return TextMarkupStroke([Offset(r.left, y), Offset(r.right, y)], w);
    case TextMarkupKind.strikeout:
      final y = r.top + r.height * 0.55;
      return TextMarkupStroke([Offset(r.left, y), Offset(r.right, y)], w);
    case TextMarkupKind.squiggly:
      final amp = math.max(1.0, r.height / 10);
      final step = amp * 2;
      final base = r.bottom - amp;
      final pts = <Offset>[];
      var x = r.left;
      var up = true;
      while (x <= r.right) {
        pts.add(Offset(x, up ? base - amp : base + amp * 0.2));
        up = !up;
        x += step;
      }
      if (pts.length < 2) {
        pts
          ..clear()
          ..add(Offset(r.left, base))
          ..add(Offset(r.right, base));
      }
      return TextMarkupStroke(pts, w * 0.8);
  }
}

/// Underline / strikethrough bars for a text box, frame-local (y down).
/// Positions follow the standard-14 AFM metrics (underline at 0.1 em below
/// the baseline, 0.05 em thick), so screen and PDF agree.
List<Rect> textDecorationRects(TextBoxMarkup t) {
  if (!t.underline && !t.strike) return const [];
  final thick = math.max(0.5, t.fontSize * 0.05);
  final out = <Rect>[];
  for (final line in t.lines) {
    if (line.text.trim().isEmpty) continue;
    // Trailing letter spacing isn't part of the visible run.
    final w = math.max(0.0, line.width - t.letterSpacing);
    if (t.underline) {
      out.add(
        Rect.fromLTWH(line.left, line.baseline + t.fontSize * 0.1, w, thick),
      );
    }
    if (t.strike) {
      out.add(
        Rect.fromLTWH(
          line.left,
          line.baseline - t.fontSize * 0.28 - thick / 2,
          w,
          thick,
        ),
      );
    }
  }
  return out;
}

/// Corner radius actually drawn for a [width] × [height] box.
double effectiveCornerRadius(double radius, double width, double height) =>
    radius.clamp(0.0, math.min(width, height) / 2);

/// Sticky-note icon parts (display points, relative to the icon top-left).
class NoteIconGeometry {
  NoteIconGeometry(double size)
    : body = Rect.fromLTWH(1, 1, size - 2, size - 5),
      tail = [
        Offset(size * 0.28, size - 4),
        Offset(size * 0.28, size - 0.5),
        Offset(size * 0.5, size - 4),
      ],
      lines = [
        for (final f in [0.3, 0.5, 0.7])
          (
            Offset(size * 0.22, (size - 5) * f + 1),
            Offset(size * 0.78, (size - 5) * f + 1),
          ),
      ];

  final Rect body;
  final List<Offset> tail;
  final List<(Offset, Offset)> lines;
  static const double radius = 3;
}

/// Popup rectangle for a note (display points), placed beside the icon and
/// kept inside the page.
Rect notePopupRect(Offset anchor, double pageW, double pageH) {
  const w = 200.0, h = 120.0;
  var left = anchor.dx + kNoteIconSize + 6;
  if (left + w > pageW) left = math.max(0, anchor.dx - w - 6);
  var top = anchor.dy;
  if (top + h > pageH) top = math.max(0, pageH - h);
  return Rect.fromLTWH(left, top, w, h);
}
