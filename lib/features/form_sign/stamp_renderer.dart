import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:document_studio/domain/pdf_stamp/stamp_library_models.dart';
import 'package:flutter/material.dart';

/// Rasterized stamp PNG + its natural size in PDF points.
class RenderedStamp {
  const RenderedStamp({required this.png, required this.sizePt});
  final Uint8List png;
  final Size sizePt;
}

/// Checkerboard backdrop for stamp/signature image previews.
class CheckerboardPainter extends CustomPainter {
  const CheckerboardPainter({this.cell = 8});
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    final light = Paint()..color = const Color(0xFFF1F3F5);
    final dark = Paint()..color = const Color(0xFFE2E6EA);
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        final odd = ((x / cell).floor() + (y / cell).floor()).isOdd;
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), odd ? dark : light);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CheckerboardPainter oldDelegate) =>
      oldDelegate.cell != cell;
}

/// Lines a stamp prints for [ctx] (title, second line, user, date/time).
List<String> stampLines(StampDesign design, StampContext ctx) {
  final sub = design.subtitle?.trim();
  final when = <String>[
    if (design.includeDate) formatStampDate(ctx.now, design.dateFormat),
    if (design.includeTime) formatStampTime(ctx.now),
  ].join(', ');
  final byline = <String>[
    if (design.includeUser && ctx.userName.trim().isNotEmpty)
      'By ${ctx.userName.trim()}',
    if (when.isNotEmpty) when,
  ];
  return [
    design.title.trim().isEmpty ? 'STAMP' : design.title.trim(),
    if (sub != null && sub.isNotEmpty) sub,
    if (byline.isNotEmpty)
      design.includeUser && when.isNotEmpty ? byline.join(' at ') : byline.first,
  ];
}

/// Measured stamp: all sizes are PDF points (1 logical pixel = 1 pt).
class StampLayout {
  StampLayout._(this.design, this.painters, this.size, this.iconSize,
      this.padLeft, this.padTop);

  final StampDesign design;
  final List<TextPainter> painters;
  final Size size;
  final double iconSize;
  final double padLeft;
  final double padTop;

  static const _titleSize = 20.0;
  static const _lineSize = 8.5;

  factory StampLayout.of(StampDesign design, StampContext ctx) {
    final color = Color(design.colorArgb);
    final lines = stampLines(design, ctx);
    final painters = <TextPainter>[
      for (var i = 0; i < lines.length; i++)
        TextPainter(
          text: TextSpan(
            text: lines[i],
            style: TextStyle(
              fontFamily: 'DS Sans',
              color: color,
              fontSize: i == 0 ? _titleSize : _lineSize,
              fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w400,
              letterSpacing: i == 0 ? 1.1 : 0.2,
              height: 1.12,
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          maxLines: 1,
        )..layout(),
    ];
    var textW = 0.0;
    var textH = 0.0;
    for (final p in painters) {
      textW = math.max(textW, p.width);
      textH += p.height;
    }
    final hasIcon = design.icon != StampIcon.none;
    final iconSize = hasIcon ? math.max(18.0, textH * 0.9) : 0.0;
    final iconGap = hasIcon ? 6.0 : 0.0;
    var padX = 10.0;
    var padY = 5.0;
    var extraLeft = 0.0;
    switch (design.shape) {
      case StampShape.oval:
        padX = 18 + textH * 0.25;
        padY = 7;
      case StampShape.arrow:
        extraLeft = (textH + padY * 2) * 0.45;
      case StampShape.rectangle:
      case StampShape.rounded:
        break;
    }
    final contentW = textW + iconSize + iconGap;
    final w = contentW + padX * 2 + extraLeft;
    final h = math.max(textH, iconSize) + padY * 2;
    return StampLayout._(
      design,
      painters,
      Size(w.ceilToDouble(), h.ceilToDouble()),
      iconSize,
      padX + extraLeft,
      padY,
    );
  }

  Path _outline(Rect r) {
    switch (design.shape) {
      case StampShape.rectangle:
        return Path()..addRect(r);
      case StampShape.rounded:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(r, Radius.circular(r.height * 0.18)));
      case StampShape.oval:
        return Path()..addOval(r);
      case StampShape.arrow:
        final tip = r.height * 0.45;
        final rad = r.height * 0.12;
        return Path()
          ..moveTo(r.left, r.center.dy)
          ..lineTo(r.left + tip, r.top)
          ..lineTo(r.right - rad, r.top)
          ..arcToPoint(Offset(r.right, r.top + rad), radius: Radius.circular(rad))
          ..lineTo(r.right, r.bottom - rad)
          ..arcToPoint(Offset(r.right - rad, r.bottom),
              radius: Radius.circular(rad))
          ..lineTo(r.left + tip, r.bottom)
          ..close();
    }
  }

  void paint(Canvas canvas) {
    final color = Color(design.colorArgb);
    final outer = (Offset.zero & size).deflate(1.2);
    final path = _outline(outer);
    if (design.shape == StampShape.arrow) {
      canvas.drawPath(path, Paint()..color = color);
    } else if (design.filled) {
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.10));
    }
    if (design.border != StampBorder.none && design.shape != StampShape.arrow) {
      final stroke = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = design.border == StampBorder.doubleLine ? 1.8 : 1.6;
      canvas.drawPath(path, stroke);
      if (design.border == StampBorder.doubleLine) {
        canvas.drawPath(_outline(outer.deflate(3)), stroke..strokeWidth = 0.9);
      }
    }
    final textW = painters.fold<double>(0, (m, p) => math.max(m, p.width));
    final textH = painters.fold<double>(0, (s, p) => s + p.height);
    final innerH = size.height - padTop * 2;
    var x = padLeft;
    if (iconSize > 0) {
      _paintIcon(canvas, Rect.fromLTWH(x, padTop + (innerH - iconSize) / 2,
          iconSize, iconSize), color);
      x += iconSize + 6;
    }
    var y = padTop + (innerH - textH) / 2;
    for (final p in painters) {
      if (design.shape == StampShape.arrow) {
        final white = TextPainter(
          text: TextSpan(
            text: p.plainText,
            style: (p.text! as TextSpan).style!.copyWith(color: Colors.white),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        white.paint(canvas, Offset(x + (textW - white.width) / 2, y));
        white.dispose();
      } else {
        p.paint(canvas, Offset(x + (textW - p.width) / 2, y));
      }
      y += p.height;
    }
  }

  void _paintIcon(Canvas canvas, Rect r, Color color) {
    final paint = Paint()
      ..color = design.shape == StampShape.arrow ? Colors.white : color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = r.width * 0.16;
    final s = r.deflate(r.width * 0.12);
    switch (design.icon) {
      case StampIcon.none:
        return;
      case StampIcon.check:
        canvas.drawPath(
          Path()
            ..moveTo(s.left, s.top + s.height * 0.55)
            ..lineTo(s.left + s.width * 0.38, s.bottom - s.height * 0.08)
            ..lineTo(s.right, s.top + s.height * 0.1),
          paint,
        );
      case StampIcon.cross:
        canvas.drawLine(s.topLeft, s.bottomRight, paint);
        canvas.drawLine(s.topRight, s.bottomLeft, paint);
      case StampIcon.star:
        final path = Path();
        final c = s.center;
        final ro = s.width / 2;
        final ri = ro * 0.45;
        for (var i = 0; i < 10; i++) {
          final a = -math.pi / 2 + i * math.pi / 5;
          final rr = i.isEven ? ro : ri;
          final pt = c + Offset(math.cos(a) * rr, math.sin(a) * rr);
          i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
        }
        path.close();
        canvas.drawPath(path, paint..style = PaintingStyle.fill);
    }
  }

  void dispose() {
    for (final p in painters) {
      p.dispose();
    }
  }
}

/// Live stamp preview. Draws exactly what [rasterizeStamp] burns, scaled to
/// fit the available space.
class StampPreview extends StatelessWidget {
  const StampPreview({
    super.key,
    required this.design,
    required this.stampContext,
    this.maxHeight,
  });

  final StampDesign design;
  final StampContext stampContext;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final layout = StampLayout.of(design, stampContext);
    final child = FittedBox(
      fit: BoxFit.contain,
      child: CustomPaint(
        size: layout.size,
        painter: _StampPainter(layout),
      ),
    );
    final h = maxHeight;
    return h == null ? child : ConstrainedBox(
      constraints: BoxConstraints(maxHeight: h),
      child: child,
    );
  }
}

class _StampPainter extends CustomPainter {
  _StampPainter(this.layout);
  final StampLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(
      size.width / layout.size.width,
      size.height / layout.size.height,
    );
    layout.paint(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StampPainter old) =>
      old.layout.design != layout.design ||
      old.layout.size != layout.size ||
      !_samePainters(old.layout.painters, layout.painters);

  static bool _samePainters(List<TextPainter> a, List<TextPainter> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].plainText != b[i].plainText) return false;
    }
    return true;
  }
}

/// Renders [design] at [pxPerPt] pixels per point. [RenderedStamp.sizePt] is
/// the stamp's natural size; the PNG has exactly that aspect.
Future<RenderedStamp> rasterizeStamp(
  StampDesign design,
  StampContext ctx, {
  double pxPerPt = 4,
}) async {
  final layout = StampLayout.of(design, ctx);
  final w = math.max(1, (layout.size.width * pxPerPt).round());
  final h = math.max(1, (layout.size.height * pxPerPt).round());
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(w / layout.size.width, h / layout.size.height);
  layout.paint(canvas);
  layout.dispose();
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  picture.dispose();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) throw StateError('Could not encode stamp');
  return RenderedStamp(png: bytes.buffer.asUint8List(), sizePt: layout.size);
}
