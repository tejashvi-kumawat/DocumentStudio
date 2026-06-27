import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:document_studio/design_system/adaptive/ds_adaptive.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/compare/compare_controller.dart';
import 'package:document_studio/features/compare/compare_visual_diff.dart';
import 'package:flutter/material.dart';

/// Pixel-level comparison of one aligned page pair: swipe (draggable
/// divider), onion skin (opacity), or a difference heatmap with boxed change
/// regions. Rendering and pixel diffing happen in [CompareVisualDiffer].
class CompareOverlayView extends StatelessWidget {
  const CompareOverlayView({super.key, required this.controller});

  final CompareController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final r = c.result!;
    final row = c.overlayRow.clamp(0, r.rows.length - 1);
    final pair = r.rows[row];
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final secondary = DsColors.textSecondary(brightness);

    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 560;
        final modes = DsAdaptiveSegmented<CompareOverlayMode>(
          value: c.overlayMode,
          onChanged: c.setOverlayMode,
          segments: {
            CompareOverlayMode.swipe: (
              label: narrow ? null : 'Swipe',
              icon: Icons.compare_rounded,
              tooltip: 'Drag the divider to reveal original vs revised',
            ),
            CompareOverlayMode.onion: (
              label: narrow ? null : 'Onion skin',
              icon: Icons.layers_outlined,
              tooltip: 'Blend the revised page over the original',
            ),
            CompareOverlayMode.heatmap: (
              label: narrow ? null : 'Heatmap',
              icon: Icons.blur_on_rounded,
              tooltip: 'Highlight every pixel that differs',
            ),
          },
        );
        final pager = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Previous page pair (←)',
              visualDensity: VisualDensity.compact,
              onPressed: row > 0 ? () => c.setOverlayRow(row - 1) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              '${pair.a == null ? '–' : 'p.${pair.a! + 1}'}  ⇄  '
              '${pair.b == null ? '–' : 'p.${pair.b! + 1}'}',
              style: theme.textTheme.labelLarge,
            ),
            IconButton(
              tooltip: 'Next page pair (→)',
              visualDensity: VisualDensity.compact,
              onPressed: row < r.rows.length - 1
                  ? () => c.setOverlayRow(row + 1)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        );

        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                  narrow ? DsSpacing.sm : DsSpacing.lg,
                  DsSpacing.sm,
                  narrow ? DsSpacing.xs : DsSpacing.lg,
                  0),
              child: Row(
                children: [
                  Flexible(child: modes),
                  const Spacer(),
                  pager,
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<CompareVisualFrame?>(
                key: ValueKey('overlay-$row'),
                future: c.visual?.frame(row, pair),
                builder: (context, snap) {
                  final frame = snap.data;
                  return AnimatedSwitcher(
                    duration: DsMotion.switchDuration,
                    switchInCurve: DsMotion.switchCurve,
                    child: frame == null
                        ? Center(
                            key: const ValueKey('loading'),
                            child: snap.connectionState == ConnectionState.done
                                ? Text('Nothing to render',
                                    style: TextStyle(color: secondary))
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const DsAdaptiveProgress(size: 24),
                                      const SizedBox(height: DsSpacing.sm),
                                      Text('Rendering & diffing pixels…',
                                          style: TextStyle(color: secondary)),
                                    ],
                                  ),
                          )
                        : _FrameView(
                            key: ValueKey('frame-$row'),
                            frame: frame,
                            mode: c.overlayMode,
                            mix: c.overlayMix,
                          ),
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  narrow ? DsSpacing.md : DsSpacing.xl,
                  0,
                  narrow ? DsSpacing.md : DsSpacing.xl,
                  DsSpacing.sm),
              child: AnimatedSwitcher(
                duration: DsMotion.switchDuration,
                child: c.overlayMode == CompareOverlayMode.heatmap
                    ? const _HeatLegend(key: ValueKey('heat'))
                    : Row(
                        key: const ValueKey('slider'),
                        children: [
                          Text('Original', style: TextStyle(color: secondary)),
                          Expanded(
                            child: ValueListenableBuilder<double>(
                              valueListenable: c.overlayMix,
                              builder: (context, v, _) => Slider(
                                value: v,
                                onChanged: (x) => c.overlayMix.value = x,
                              ),
                            ),
                          ),
                          Text('Revised', style: TextStyle(color: secondary)),
                        ],
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HeatLegend extends StatelessWidget {
  const _HeatLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final secondary = DsColors.textSecondary(Theme.of(context).brightness);
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Small difference', style: TextStyle(color: secondary, fontSize: 12)),
          const SizedBox(width: DsSpacing.sm),
          Container(
            width: 120,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: const LinearGradient(
                colors: [Color(0xFFFFD200), Color(0xFFFF0000)],
              ),
            ),
          ),
          const SizedBox(width: DsSpacing.sm),
          Text('Large', style: TextStyle(color: secondary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _FrameView extends StatelessWidget {
  const _FrameView({
    super.key,
    required this.frame,
    required this.mode,
    required this.mix,
  });

  final CompareVisualFrame frame;
  final CompareOverlayMode mode;
  final ValueNotifier<double> mix;

  @override
  Widget build(BuildContext context) {
    final ref = frame.a ?? frame.b!;
    final aspect = ref.width / ref.height;
    final pct = frame.changedRatio * 100;
    final n = frame.boxes.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          DsSpacing.md, DsSpacing.sm, DsSpacing.md, 0),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: aspect,
                child: LayoutBuilder(
                  builder: (context, box) {
                    final size = box.biggest;
                    final Widget body = switch (mode) {
                      CompareOverlayMode.swipe => GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragUpdate: (d) => mix.value =
                              (mix.value + d.delta.dx / size.width)
                                  .clamp(0.0, 1.0),
                          onTapDown: (d) => mix.value =
                              (d.localPosition.dx / size.width).clamp(0.0, 1.0),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.resizeColumn,
                            child: CustomPaint(
                              size: size,
                              painter: _SwipePainter(frame, mix),
                            ),
                          ),
                        ),
                      CompareOverlayMode.onion => InteractiveViewer(
                          maxScale: 6,
                          child: CustomPaint(
                            size: size,
                            painter: _OnionPainter(frame, mix),
                          ),
                        ),
                      CompareOverlayMode.heatmap => InteractiveViewer(
                          maxScale: 6,
                          child: CustomPaint(
                            size: size,
                            painter: _HeatPainter(frame),
                          ),
                        ),
                    };
                    return RepaintBoundary(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: DsSpacing.cardShadowLight(opacity: 0.16),
                        ),
                        child: ClipRect(child: body),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: DsSpacing.xs),
          Text(
            frame.a == null || frame.b == null
                ? 'Page exists in only one document'
                : pct < 0.01
                    ? 'Pixel-identical'
                    : '${pct.toStringAsFixed(pct < 1 ? 2 : 1)}% of pixels differ · '
                        '$n region${n == 1 ? '' : 's'}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

void _drawImage(Canvas canvas, ui.Image? img, Size size, {double opacity = 1}) {
  if (img == null) return;
  final paint = Paint()
    ..filterQuality = FilterQuality.medium
    ..color = Color.fromRGBO(0, 0, 0, opacity);
  canvas.drawImageRect(
    img,
    Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
    Offset.zero & size,
    paint,
  );
}

class _SwipePainter extends CustomPainter {
  _SwipePainter(this.frame, this.mix) : super(repaint: mix);

  final CompareVisualFrame frame;
  final ValueNotifier<double> mix;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width * mix.value;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    _drawImage(canvas, frame.b, size);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, x, size.height));
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    _drawImage(canvas, frame.a, size);
    canvas.restore();
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = DsColors.textPrimaryLight
        ..strokeWidth = 2,
    );
    final knob = Offset(x, size.height / 2);
    canvas.drawCircle(
      knob,
      15,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(knob, 14, Paint()..color = Colors.white);
    final arrow = Paint()
      ..color = DsColors.textPrimaryLight
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(knob.dx - 3, knob.dy - 5)
        ..lineTo(knob.dx - 8, knob.dy)
        ..lineTo(knob.dx - 3, knob.dy + 5)
        ..moveTo(knob.dx + 3, knob.dy - 5)
        ..lineTo(knob.dx + 8, knob.dy)
        ..lineTo(knob.dx + 3, knob.dy + 5),
      arrow,
    );
    _tag(canvas, 'ORIGINAL', const Offset(8, 8), math.max(0, x - 16));
    _tag(canvas, 'REVISED', Offset(size.width - 72, 8), size.width - x - 16);
  }

  void _tag(Canvas canvas, String s, Offset at, double room) {
    if (room < 80) return;
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(at.dx, at.dy, tp.width + 12, tp.height + 6),
      const Radius.circular(4),
    );
    canvas.drawRRect(r, Paint()..color = Colors.black54);
    tp.paint(canvas, at + const Offset(6, 3));
  }

  @override
  bool shouldRepaint(_SwipePainter old) =>
      old.frame != frame || old.mix != mix;
}

class _OnionPainter extends CustomPainter {
  _OnionPainter(this.frame, this.mix) : super(repaint: mix);

  final CompareVisualFrame frame;
  final ValueNotifier<double> mix;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    _drawImage(canvas, frame.a, size);
    _drawImage(canvas, frame.b, size, opacity: mix.value);
  }

  @override
  bool shouldRepaint(_OnionPainter old) =>
      old.frame != frame || old.mix != mix;
}

class _HeatPainter extends CustomPainter {
  _HeatPainter(this.frame);

  final CompareVisualFrame frame;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final base = frame.b ?? frame.a;
    if (base != null) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()
          ..colorFilter = const ColorFilter.matrix([
            0.2126, 0.7152, 0.0722, 0, 0, //
            0.2126, 0.7152, 0.0722, 0, 0,
            0.2126, 0.7152, 0.0722, 0, 0,
            0, 0, 0, 0.35, 0,
          ]),
      );
      _drawImage(canvas, base, size);
      canvas.restore();
    }
    _drawImage(canvas, frame.heat, size);
    final stroke = Paint()
      ..color = const Color(0xFFE0342F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final b in frame.boxes) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(b.l * size.width, b.t * size.height, b.r * size.width,
                  b.b * size.height)
              .inflate(3),
          const Radius.circular(3),
        ),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_HeatPainter old) => old.frame != frame;
}
