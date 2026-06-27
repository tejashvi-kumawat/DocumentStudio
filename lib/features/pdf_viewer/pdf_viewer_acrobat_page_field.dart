import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Acrobat-style compact page indicator: **n / N** (editable via [onGoToPage]).
class PdfViewerAcrobatPageField extends StatelessWidget {
  const PdfViewerAcrobatPageField({
    super.key,
    this.controller,
    required this.onGoToPage,
    this.fieldHeight = 26,
  });

  final PdfViewerController? controller;
  final VoidCallback onGoToPage;
  final double fieldHeight;

  @override
  Widget build(BuildContext context) {
    final ctrl = controller;
    if (ctrl == null) {
      return _field(
        context,
        page: 1,
        total: 1,
        enabled: false,
        height: fieldHeight,
      );
    }
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final ready = ctrl.isReady;
        final page = ready ? (ctrl.pageNumber ?? 1) : 1;
        final total = ready ? ctrl.pageCount : 1;
        return _field(
          context,
          page: page,
          total: total,
          enabled: ready,
          height: fieldHeight,
        );
      },
    );
  }

  Widget _field(
    BuildContext context, {
    required int page,
    required int total,
    required bool enabled,
    required double height,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;
    final bg = isDark ? DsColors.surfaceDark : DsColors.surfaceLight;

    return Semantics(
      button: true,
      label: 'Page $page of $total',
      enabled: enabled,
      child: Tooltip(
        message: 'Go to page',
        child: InkWell(
          key: const Key('pdf_viewer_acrobat_page_field'),
          onTap: enabled ? onGoToPage : null,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: DsSpacing.sm),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: border),
            ),
            alignment: Alignment.center,
            child: Text(
              '$page / $total',
              style: theme.textTheme.labelMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
