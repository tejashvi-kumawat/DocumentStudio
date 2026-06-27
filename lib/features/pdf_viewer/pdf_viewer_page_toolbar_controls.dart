import 'package:document_studio/design_system/shell/ds_toolbar.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_controller_safe.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_page_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Enabled/disabled state for first/prev/next/last toolbar actions ([DS-READ-009-C]).
class PdfViewerPageNavAvailability {
  const PdfViewerPageNavAvailability({
    required this.navigationEnabled,
    required this.canGoPrevious,
    required this.canGoNext,
  });

  final bool navigationEnabled;
  final bool canGoPrevious;
  final bool canGoNext;
}

PdfViewerPageNavAvailability pdfViewerPageNavAvailability({
  required bool isReady,
  int? pageNumber,
  required int pageCount,
}) {
  if (!isReady || pageCount < 1) {
    return const PdfViewerPageNavAvailability(
      navigationEnabled: false,
      canGoPrevious: false,
      canGoNext: false,
    );
  }
  final page = (pageNumber ?? 1).clamp(1, pageCount);
  return PdfViewerPageNavAvailability(
    navigationEnabled: true,
    canGoPrevious: page > 1,
    canGoNext: page < pageCount,
  );
}

/// Toolbar first / previous / next / last page controls wired to [PdfViewerController].
class PdfViewerPageToolbarControls extends StatelessWidget {
  const PdfViewerPageToolbarControls({
    super.key,
    this.controller,
    this.availability,
    required this.onNavigate,
    this.dense = false,
  });

  final PdfViewerController? controller;
  final PdfViewerPageNavAvailability? availability;
  final void Function(PdfViewerPageStep step) onNavigate;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ctrl = controller;
    if (ctrl != null) {
      return ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          final nav = PdfViewerControllerNavSnapshot.of(ctrl);
          return _buildRow(
            pdfViewerPageNavAvailability(
              isReady: nav.isReady,
              pageNumber: nav.pageNumber,
              pageCount: nav.pageCount,
            ),
          );
        },
      );
    }
    return _buildRow(
      availability ??
          const PdfViewerPageNavAvailability(
            navigationEnabled: false,
            canGoPrevious: false,
            canGoNext: false,
          ),
    );
  }

  Widget _buildRow(PdfViewerPageNavAvailability state) {
    final enabled = state.navigationEnabled;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DsToolbarIconButton(
          key: const Key('pdf_viewer_page_first'),
          icon: Icons.skip_previous,
          tooltip: 'First page',
          dense: dense,
          onPressed: enabled && state.canGoPrevious
              ? () => onNavigate(PdfViewerPageStep.first)
              : null,
        ),
        DsToolbarIconButton(
          key: const Key('pdf_viewer_page_previous'),
          icon: Icons.navigate_before,
          tooltip: 'Previous page',
          dense: dense,
          onPressed: enabled && state.canGoPrevious
              ? () => onNavigate(PdfViewerPageStep.previous)
              : null,
        ),
        DsToolbarIconButton(
          key: const Key('pdf_viewer_page_next'),
          icon: Icons.navigate_next,
          tooltip: 'Next page',
          dense: dense,
          onPressed: enabled && state.canGoNext
              ? () => onNavigate(PdfViewerPageStep.next)
              : null,
        ),
        DsToolbarIconButton(
          key: const Key('pdf_viewer_page_last'),
          icon: Icons.skip_next,
          tooltip: 'Last page',
          dense: dense,
          onPressed: enabled && state.canGoNext
              ? () => onNavigate(PdfViewerPageStep.last)
              : null,
        ),
        DsToolbarDivider(dense: dense),
      ],
    );
  }
}
