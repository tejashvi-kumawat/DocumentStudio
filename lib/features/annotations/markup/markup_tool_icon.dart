import 'dart:math' as math;

import 'package:document_studio/features/annotations/markup/markup_tool.dart';
import 'package:flutter/material.dart';

/// Hand-drawn glyphs for the comment tools (Acrobat-style: a recognisable
/// sticky note, highlighter, underline "A", pencil, eraser, …) in a 24-unit
/// box, so they read clearly at 18–22 px where Material look-alikes do not.
class MarkupToolIcon extends StatelessWidget {
  const MarkupToolIcon(this.tool, {super.key, this.size = 20, this.color});

  final MarkupTool tool;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.black87;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GlyphPainter(tool, c)),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.tool, this.color);

  final MarkupTool tool;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    canvas.scale(s);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    final soft = Paint()..color = color.withValues(alpha: 0.28);

    // "A" with a bar underneath / through it, used by the text-markup tools.
    void letterA(double barY, {bool through = false}) {
      final a = Path()
        ..moveTo(6.5, 16)
        ..lineTo(12, 4.5)
        ..lineTo(17.5, 16)
        ..moveTo(8.4, 12.2)
        ..lineTo(15.6, 12.2);
      canvas.drawPath(a, stroke);
      canvas.drawLine(
        Offset(4.5, barY),
        Offset(19.5, barY),
        stroke..strokeWidth = through ? 1.9 : 2.1,
      );
      stroke.strokeWidth = 1.7;
    }

    switch (tool) {
      case MarkupTool.select:
        final p = Path()
          ..moveTo(6, 3.5)
          ..lineTo(6, 19)
          ..lineTo(10.2, 15.3)
          ..lineTo(13, 21)
          ..lineTo(15.4, 19.9)
          ..lineTo(12.7, 14.4)
          ..lineTo(18, 14.2)
          ..close();
        canvas.drawPath(p, fill);
      case MarkupTool.text:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(3.5, 4.5, 17, 15),
            const Radius.circular(2),
          ),
          stroke,
        );
        canvas.drawLine(const Offset(8.5, 9), const Offset(15.5, 9), stroke);
        canvas.drawLine(const Offset(12, 9), const Offset(12, 16), stroke);
      case MarkupTool.callout:
        final p = Path()
          ..moveTo(4, 5)
          ..lineTo(20, 5)
          ..lineTo(20, 15)
          ..lineTo(11, 15)
          ..lineTo(6.5, 19.5)
          ..lineTo(6.5, 15)
          ..lineTo(4, 15)
          ..close();
        canvas.drawPath(p, stroke);
        canvas.drawLine(const Offset(8, 9), const Offset(16, 9), stroke);
        canvas.drawLine(const Offset(8, 12), const Offset(13, 12), stroke);
      case MarkupTool.note:
        final p = Path()
          ..moveTo(4.5, 4.5)
          ..lineTo(19.5, 4.5)
          ..lineTo(19.5, 14)
          ..lineTo(14, 19.5)
          ..lineTo(4.5, 19.5)
          ..close();
        canvas.drawPath(p, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(19.5, 14)
            ..lineTo(14, 14)
            ..lineTo(14, 19.5),
          stroke,
        );
        canvas.drawLine(const Offset(8, 9), const Offset(16, 9), stroke);
        canvas.drawLine(const Offset(8, 12.5), const Offset(12, 12.5), stroke);
      case MarkupTool.highlight:
        // Marker pen over a highlighted band of text.
        canvas.drawRect(const Rect.fromLTWH(3, 16, 18, 4.2), soft);
        final pen = Path()
          ..moveTo(14.8, 3.8)
          ..lineTo(19.6, 8.6)
          ..lineTo(11.4, 16.8)
          ..lineTo(6.6, 12)
          ..close();
        canvas.drawPath(pen, fill);
        canvas.drawPath(
          Path()
            ..moveTo(6.6, 12)
            ..lineTo(5, 16.6)
            ..lineTo(9.6, 15.2),
          stroke,
        );
      case MarkupTool.underline:
        letterA(19.5);
      case MarkupTool.strikeout:
        letterA(11.2, through: true);
      case MarkupTool.squiggly:
        final p = Path()..moveTo(4, 19);
        for (var i = 0; i < 6; i++) {
          p.relativeQuadraticBezierTo(1.25, i.isEven ? -2.4 : 2.4, 2.5, 0);
        }
        canvas.drawPath(
          Path()
            ..moveTo(6.5, 16)
            ..lineTo(12, 4.5)
            ..lineTo(17.5, 16)
            ..moveTo(8.4, 12.2)
            ..lineTo(15.6, 12.2),
          stroke,
        );
        canvas.drawPath(p, stroke);
      case MarkupTool.pen:
        final p = Path()
          ..moveTo(4.5, 19.5)
          ..lineTo(5.6, 15)
          ..lineTo(16, 4.6)
          ..lineTo(19.4, 8)
          ..lineTo(9, 18.4)
          ..close();
        canvas.drawPath(p, stroke);
        canvas.drawLine(const Offset(14, 6.6), const Offset(17.4, 10), stroke);
      case MarkupTool.highlighter:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(3.5, 14, 17, 5.5),
            const Radius.circular(2.5),
          ),
          soft,
        );
        canvas.drawPath(
          Path()
            ..moveTo(8, 12)
            ..lineTo(14, 4.5)
            ..lineTo(18, 7.6)
            ..lineTo(12, 15),
          stroke,
        );
      case MarkupTool.rectangle:
        canvas.drawRect(const Rect.fromLTWH(4, 6, 16, 12), stroke);
      case MarkupTool.ellipse:
        canvas.drawOval(const Rect.fromLTWH(3.5, 6, 17, 12), stroke);
      case MarkupTool.line:
        canvas.drawLine(const Offset(5, 19), const Offset(19, 5), stroke);
      case MarkupTool.arrow:
        canvas.drawLine(const Offset(5, 19), const Offset(18, 6), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(10.5, 6)
            ..lineTo(18, 6)
            ..lineTo(18, 13.5),
          stroke,
        );
      case MarkupTool.polygon:
        final p = Path();
        for (var i = 0; i < 5; i++) {
          final a = -math.pi / 2 + i * 2 * math.pi / 5;
          final pt = Offset(12 + 8 * math.cos(a), 12.5 + 8 * math.sin(a));
          i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
        }
        p.close();
        canvas.drawPath(p, stroke);
      case MarkupTool.cloud:
        final p = Path()
          ..moveTo(7, 18)
          ..cubicTo(2.5, 18, 2.5, 11.5, 7.5, 11.5)
          ..cubicTo(8, 6.5, 15, 6, 16, 10.8)
          ..cubicTo(21.5, 10.5, 21.5, 18, 17, 18)
          ..close();
        canvas.drawPath(p, stroke);
      case MarkupTool.eraser:
        final p = Path()
          ..moveTo(4.5, 15)
          ..lineTo(13, 6.5)
          ..lineTo(19.5, 13)
          ..lineTo(13, 19.5)
          ..lineTo(8, 19.5)
          ..close();
        canvas.drawPath(p, stroke);
        canvas.drawLine(const Offset(9, 10.5), const Offset(15.5, 17), stroke);
        canvas.drawLine(const Offset(12, 19.5), const Offset(20, 19.5), stroke);
      case MarkupTool.link:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(3.5, 9, 9.5, 6.5),
            const Radius.circular(3.2),
          ),
          stroke,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(11, 8.5, 9.5, 6.5),
            const Radius.circular(3.2),
          ),
          stroke,
        );
      case MarkupTool.image:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(3.5, 5, 17, 14),
            const Radius.circular(2),
          ),
          stroke,
        );
        canvas.drawCircle(const Offset(9, 10), 1.7, fill);
        canvas.drawPath(
          Path()
            ..moveTo(4.5, 17.5)
            ..lineTo(10, 12.5)
            ..lineTo(14, 16)
            ..lineTo(16.5, 13.8)
            ..lineTo(19.5, 17.5),
          stroke,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter old) =>
      old.tool != tool || old.color != color;
}
