import 'dart:ui' as ui;

import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:flutter/material.dart';

/// Minimum width for the horizontal icon + label + browse row.
const kHomeDropZoneHorizontalMinWidth = 220.0;

/// Drop / browse affordance. Dashed outline that lights up while a file
/// is dragged over Home ([active]).
class HomeDropZone extends StatefulWidget {
  const HomeDropZone({
    super.key,
    required this.onBrowse,
    this.enabled = true,
    this.compact = false,
    this.active = false,
    this.tall = false,
  });

  final VoidCallback? onBrowse;
  final bool enabled;
  final bool compact;

  /// A file is currently hovering over the drop target.
  final bool active;

  /// Vertical hero layout that fills the available height.
  final bool tall;

  @override
  State<HomeDropZone> createState() => _HomeDropZoneState();
}

class _HomeDropZoneState extends State<HomeDropZone> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = DsColors.textSecondary(theme.brightness);
    const primary = DsColors.primary;
    final active = widget.active;
    final lit = active || _hovered;
    final radius = BorderRadius.circular(DsSpacing.radiusCard);

    final fill = active
        ? primary.withValues(alpha: isDark ? 0.16 : 0.07)
        : _hovered
            ? primary.withValues(alpha: isDark ? 0.08 : 0.035)
            : DsColors.groupedCell(theme.brightness)
                .withValues(alpha: isDark ? 0.6 : 0.7);
    final stroke = lit
        ? primary.withValues(alpha: active ? 0.9 : 0.5)
        : DsColors.border(theme.brightness).withValues(alpha: 1);

    return RepaintBoundary(
      child: Semantics(
        button: true,
        label: 'Drop PDF files to choose how to open, or browse',
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Material(
            key: const Key('home_drop_zone'),
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.enabled ? widget.onBrowse : null,
              borderRadius: radius,
              hoverColor: Colors.transparent,
              child: CustomPaint(
                painter: _DashedRRectPainter(
                  color: stroke,
                  radius: DsSpacing.radiusCard,
                  strokeWidth: active ? 1.6 : 1.1,
                ),
                child: AnimatedContainer(
                  duration: DsMotion.hoverDuration,
                  curve: DsMotion.switchCurve,
                  decoration: BoxDecoration(color: fill, borderRadius: radius),
                  // Avoid LayoutBuilder when [tall] is already decided by the
                  // parent — IntrinsicHeight (or any intrinsic pass) cannot
                  // size a LayoutBuilder child.
                  child: widget.tall
                      ? _content(
                          theme: theme,
                          secondary: secondary,
                          isDark: isDark,
                          vertical: true,
                          layoutWidth: kHomeDropZoneHorizontalMinWidth,
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final layoutWidth = constraints.maxWidth.isFinite
                                ? constraints.maxWidth
                                : MediaQuery.sizeOf(context).width;
                            final vertical =
                                layoutWidth < kHomeDropZoneHorizontalMinWidth;
                            return _content(
                              theme: theme,
                              secondary: secondary,
                              isDark: isDark,
                              vertical: vertical,
                              layoutWidth: layoutWidth,
                            );
                          },
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content({
    required ThemeData theme,
    required Color secondary,
    required bool isDark,
    required bool vertical,
    required double layoutWidth,
  }) {
    const primary = DsColors.primary;
    final active = widget.active;
    final iconSize = widget.tall ? 52.0 : DsSpacing.iconWellSize;

    final iconBox = AnimatedScale(
      scale: active ? 1.12 : 1,
      duration: DsMotion.switchDuration,
      curve: DsMotion.emphasizedCurve,
      child: AnimatedContainer(
        duration: DsMotion.hoverDuration,
        width: iconSize,
        height: iconSize,
        decoration: BoxDecoration(
          color: primary.withValues(
            alpha: active ? 0.22 : (isDark ? 0.18 : 0.08),
          ),
          borderRadius: BorderRadius.circular(widget.tall ? 16 : 8),
        ),
        child: Icon(
          active ? Icons.file_download_rounded : Icons.upload_file_outlined,
          size: widget.tall ? 26 : 20,
          color: primary,
        ),
      ),
    );

    final title = Text(
      active ? 'Release to open' : 'Drop PDFs here',
      textAlign: vertical ? TextAlign.center : TextAlign.start,
      style: theme.textTheme.labelLarge?.copyWith(
        fontSize: widget.tall ? 14 : 13,
        fontWeight: FontWeight.w600,
        color: active ? primary : null,
      ),
    );

    final subtitle = Text(
      'or browse from your device',
      textAlign: vertical ? TextAlign.center : TextAlign.start,
      style: theme.textTheme.bodySmall?.copyWith(
        fontSize: 12,
        color: secondary,
      ),
    );

    final browse = widget.onBrowse != null
        ? OutlinedButton(
            onPressed: widget.enabled ? widget.onBrowse : null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: DsSpacing.md),
              foregroundColor: primary,
              side: BorderSide(color: primary.withValues(alpha: 0.5)),
              textStyle: theme.textTheme.labelLarge?.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('Browse'),
          )
        : null;

    final pad = EdgeInsets.symmetric(
      vertical: widget.compact ? DsSpacing.md : DsSpacing.lg,
      horizontal: vertical ? DsSpacing.md : DsSpacing.lg,
    );

    if (vertical) {
      return Padding(
        padding: pad,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconBox,
              if (layoutWidth >= 96) ...[
                SizedBox(height: widget.tall ? DsSpacing.md : DsSpacing.sm),
                title,
                const SizedBox(height: DsSpacing.xs),
                subtitle,
                if (browse != null) ...[
                  const SizedBox(height: DsSpacing.md),
                  browse,
                ],
              ],
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: pad,
      child: Row(
        children: [
          iconBox,
          const SizedBox(width: DsSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: DsSpacing.xs),
                subtitle,
              ],
            ),
          ),
          ?browse,
        ],
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
  });

  final Color color;
  final double radius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    const dash = 6.0;
    const gap = 4.0;
    for (final ui.PathMetric metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}
