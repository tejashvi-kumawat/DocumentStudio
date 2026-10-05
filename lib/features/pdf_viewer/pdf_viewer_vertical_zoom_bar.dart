import 'dart:async';
import 'dart:math' as math;

import 'package:document_studio/design_system/ds_colors.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Slim vertical zoom control docked to the right edge of the page area:
/// + / − buttons, a log-scale slider, and the current percentage (click it for
/// 100 %).
class PdfViewerVerticalZoomBar extends StatefulWidget {
  const PdfViewerVerticalZoomBar({super.key, required this.controller});

  final PdfViewerController controller;

  /// Offset from the bottom-right corner; kept for the session after the
  /// user drags the bar somewhere else.
  static Offset sessionOffset = const Offset(16, 16);

  @override
  State<PdfViewerVerticalZoomBar> createState() =>
      _PdfViewerVerticalZoomBarState();
}

class _PdfViewerVerticalZoomBarState extends State<PdfViewerVerticalZoomBar> {
  PdfViewerController get controller => widget.controller;
  static const _w = 36.0;
  static const _h = 250.0;


  static const _minZoom = 0.25;
  static const _maxZoom = 8.0;

  double _toSlider(double zoom) =>
      (math.log(zoom.clamp(_minZoom, _maxZoom)) / math.ln2);

  double _fromSlider(double v) => math.pow(2, v).toDouble();

  Future<void> _setZoom(double zoom) async {
    if (!controller.isReady) return;
    final center = controller.centerPosition;
    await controller.setZoom(center, zoom, duration: Duration.zero);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return LayoutBuilder(builder: (context, c) {
      final off = PdfViewerVerticalZoomBar.sessionOffset;
      final right = off.dx.clamp(4.0, (c.maxWidth - _w - 4).clamp(4.0, 4000));
      final bottom = off.dy.clamp(4.0, (c.maxHeight - _h - 4).clamp(4.0, 4000));
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: right.toDouble(),
            bottom: bottom.toDouble(),
            child: Material(
          color: (dark ? const Color(0xFF2B2B2B) : Colors.white)
              .withValues(alpha: 0.94),
          elevation: 3,
          borderRadius: BorderRadius.circular(20),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final ready = controller.isReady;
              final zoom = ready ? controller.currentZoom : 1.0;
              return SizedBox(
                width: _w,
                height: _h,
                child: Column(
                  children: [
                    // Drag this handle to move the zoom bar anywhere.
                    MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (d) => setState(() {
                          final o = PdfViewerVerticalZoomBar.sessionOffset;
                          PdfViewerVerticalZoomBar.sessionOffset = Offset(
                            (o.dx - d.delta.dx).clamp(4.0, c.maxWidth - _w - 4),
                            (o.dy - d.delta.dy).clamp(4.0, c.maxHeight - _h - 4),
                          );
                        }),
                        child: SizedBox(
                          height: 18,
                          width: _w,
                          child: Icon(
                            Icons.drag_indicator,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Zoom in',
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      onPressed: ready
                          ? () => unawaited(
                                _setZoom((zoom * 1.25).clamp(_minZoom, _maxZoom)),
                              )
                          : null,
                      icon: const Icon(Icons.add),
                    ),
                    Expanded(
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                            overlayShape: SliderComponentShape.noOverlay,
                            activeTrackColor: DsColors.primary,
                            thumbColor: DsColors.primary,
                          ),
                          child: Slider(
                            min: _toSlider(_minZoom),
                            max: _toSlider(_maxZoom),
                            value: _toSlider(zoom),
                            onChanged: ready
                                ? (v) => unawaited(_setZoom(_fromSlider(v)))
                                : null,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Zoom out',
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      onPressed: ready
                          ? () => unawaited(
                                _setZoom((zoom / 1.25).clamp(_minZoom, _maxZoom)),
                              )
                          : null,
                      icon: const Icon(Icons.remove),
                    ),
                    Tooltip(
                      message: 'Reset to 100%',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: ready ? () => unawaited(_setZoom(1)) : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            '${(zoom * 100).round()}%',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
            ),
          ),
        ],
      );
    });
  }
}
