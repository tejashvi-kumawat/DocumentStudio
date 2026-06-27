import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Read-only zoom percentage field (Acrobat-style toolbar).
class PdfViewerAcrobatZoomField extends StatelessWidget {
  const PdfViewerAcrobatZoomField({
    super.key,
    this.controller,
  });

  final PdfViewerController? controller;

  @override
  Widget build(BuildContext context) {
    final ctrl = controller;
    if (ctrl == null) {
      return _label(context, percent: 100);
    }
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final pct = ctrl.isReady ? (ctrl.value.zoom * 100).round() : 100;
        return _label(context, percent: pct);
      },
    );
  }

  Widget _label(BuildContext context, {required int percent}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;
    final bg = isDark ? DsColors.surfaceDark : DsColors.surfaceLight;

    return Tooltip(
      message: 'Zoom level',
      child: Container(
        key: const Key('pdf_viewer_acrobat_zoom_field'),
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: DsSpacing.sm),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: border),
        ),
        alignment: Alignment.center,
        child: Text(
          '$percent%',
          style: theme.textTheme.labelMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
