import 'dart:math' as math;

import 'package:document_studio/domain/compare/compare_models.dart';
import 'package:flutter/material.dart';

const compareInsertColor = Color(0xFF000000 | compareInsertRgb);
const compareDeleteColor = Color(0xFF000000 | compareDeleteRgb);
const compareReplaceColor = Color(0xFF000000 | compareReplaceRgb);
const compareChangedColor = Color(0xFF000000 | compareChangedRgb);

Color compareKindColor(CompareChangeKind k) =>
    Color(0xFF000000 | compareKindRgb(k));

Color compareColor(CompareChange c) => compareKindColor(c.kind);

IconData compareCategoryIcon(CompareCategory c) => switch (c) {
  CompareCategory.text => Icons.text_fields_rounded,
  CompareCategory.formatting => Icons.format_color_text_rounded,
  CompareCategory.images => Icons.image_outlined,
  CompareCategory.annotations => Icons.comment_outlined,
  CompareCategory.pages => Icons.auto_stories_outlined,
};

/// Legend entries in display order (kind, label).
const compareLegend = [
  (CompareChangeKind.inserted, 'Inserted'),
  (CompareChangeKind.deleted, 'Deleted'),
  (CompareChangeKind.replaced, 'Replaced'),
  (CompareChangeKind.changed, 'Changed / moved'),
];

/// Paints change highlights for one side of one page, in the page's displayed
/// rect (normalized top-left coordinates scaled to [Size]). [flash] pulses
/// the selected change after a jump; only this layer repaints.
class CompareHighlightPainter extends CustomPainter {
  CompareHighlightPainter({
    required this.changes,
    required this.page,
    required this.oldSide,
    required this.selectedId,
    required this.flash,
  }) : super(repaint: flash);

  final List<CompareChange> changes;
  final int page;
  final bool oldSide;
  final int? selectedId;
  final Animation<double> flash;

  @override
  void paint(Canvas canvas, Size size) {
    CompareChange? selected;
    for (final c in changes) {
      if (c.id == selectedId) {
        selected = c;
        continue;
      }
      _paintChange(canvas, size, c, false);
    }
    if (selected != null) _paintChange(canvas, size, selected, true);
  }

  void _paintChange(Canvas canvas, Size size, CompareChange c, bool sel) {
    final rects = (oldSide ? c.aRects : c.bRects)[page];
    if (rects == null || rects.isEmpty) return;
    final color = compareColor(c);
    final boxy =
        c.category == CompareCategory.images ||
        c.category == CompareCategory.annotations;

    for (final n in rects) {
      final r = Rect.fromLTRB(
        n.l * size.width,
        n.t * size.height,
        n.r * size.width,
        n.b * size.height,
      );
      final wholePage = n.area > 0.95;
      if (wholePage) {
        final ring = (Offset.zero & size).deflate(1.5);
        canvas.drawRect(
          ring,
          Paint()
            ..color = color.withValues(alpha: sel ? 0.95 : 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = sel ? 3 : 2,
        );
        canvas.drawRect(ring, Paint()..color = color.withValues(alpha: 0.05));
      } else if (n.width < 0.004) {
        final bar = Rect.fromCenter(
          center: r.center,
          width: 2.2,
          height: math.max(r.height, 8),
        );
        canvas.drawRect(bar, Paint()..color = color);
        final tri = Path()
          ..moveTo(bar.center.dx - 4, bar.bottom + 4)
          ..lineTo(bar.center.dx + 4, bar.bottom + 4)
          ..lineTo(bar.center.dx, bar.bottom - 1)
          ..close();
        canvas.drawPath(tri, Paint()..color = color);
      } else if (boxy) {
        canvas.drawRect(r, Paint()..color = color.withValues(alpha: 0.10));
        canvas.drawRect(
          r,
          Paint()
            ..color = color.withValues(alpha: 0.9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
      } else {
        final rr = RRect.fromRectAndRadius(r, const Radius.circular(2));
        canvas.drawRRect(rr, Paint()..color = color.withValues(alpha: 0.24));
        canvas.drawLine(
          r.bottomLeft,
          r.bottomRight,
          Paint()
            ..color = color.withValues(alpha: 0.9)
            ..strokeWidth = 1.4,
        );
      }
      if (sel && !wholePage) {
        final t = flash.value;
        final glow = r.inflate(3 + (1 - t) * 8);
        canvas.drawRRect(
          RRect.fromRectAndRadius(glow, const Radius.circular(4)),
          Paint()
            ..color = color.withValues(alpha: 0.35 + 0.5 * t)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(CompareHighlightPainter old) =>
      old.changes != changes ||
      old.page != page ||
      old.selectedId != selectedId ||
      old.oldSide != oldSide;
}
