import 'package:document_studio/design_system/shell/ds_status_bar.dart';
import 'package:document_studio/design_system/shell/ds_toolbar.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_fit_display.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Toolbar zoom actions enabled when the pdfrx controller is ready.
class PdfViewerZoomAvailability {
  const PdfViewerZoomAvailability({required this.enabled});

  final bool enabled;
}

PdfViewerZoomAvailability pdfViewerZoomAvailability({required bool isReady}) {
  return PdfViewerZoomAvailability(enabled: isReady);
}

Future<void> pdfViewerApplyFitPage(PdfViewerController controller) async {
  if (!controller.isReady) return;
  final page = (controller.pageNumber ?? 1).clamp(1, controller.pageCount);
  final matrix = controller.calcMatrixForFit(pageNumber: page);
  if (matrix != null) {
    await controller.goTo(matrix);
  }
}

Future<void> pdfViewerApplyFitWidth(PdfViewerController controller) async {
  if (!controller.isReady) return;
  final page = (controller.pageNumber ?? 1).clamp(1, controller.pageCount);
  final matrix = controller.calcMatrixFitWidthForPage(pageNumber: page);
  if (matrix != null) {
    await controller.goTo(matrix);
  }
}

Future<void> pdfViewerApplyFitHeight(PdfViewerController controller) async {
  if (!controller.isReady) return;
  final page = (controller.pageNumber ?? 1).clamp(1, controller.pageCount);
  final matrix = controller.calcMatrixFitHeightForPage(pageNumber: page);
  if (matrix != null) {
    await controller.goTo(matrix);
  }
}

Future<void> pdfViewerZoomIn(PdfViewerController controller) async {
  if (!controller.isReady) return;
  await controller.zoomUp();
}

Future<void> pdfViewerZoomOut(PdfViewerController controller) async {
  if (!controller.isReady) return;
  await controller.zoomDown();
}

enum PdfViewerZoomMenuAction { zoomOut, fitWidth, fitHeight, fitPage, zoomIn }

/// Applies a zoom menu selection when [controller] is ready.
Future<void> pdfViewerApplyZoomMenuAction(
  PdfViewerController controller,
  PdfViewerZoomMenuAction action,
) async {
  switch (action) {
    case PdfViewerZoomMenuAction.zoomOut:
      await pdfViewerZoomOut(controller);
    case PdfViewerZoomMenuAction.fitWidth:
      await pdfViewerApplyFitWidth(controller);
    case PdfViewerZoomMenuAction.fitHeight:
      await pdfViewerApplyFitHeight(controller);
    case PdfViewerZoomMenuAction.fitPage:
      await pdfViewerApplyFitPage(controller);
    case PdfViewerZoomMenuAction.zoomIn:
      await pdfViewerZoomIn(controller);
  }
}

/// Fit page, fit width, zoom in/out for [PdfViewerScreen] ([DS-READ-004-A/B] partial).
class PdfViewerZoomToolbarControls extends StatelessWidget {
  const PdfViewerZoomToolbarControls({
    super.key,
    this.controller,
    this.availability,
    this.dense = false,
    this.compact,
    this.onFitWidthApplied,
    this.onFitHeightApplied,
    this.onFitPageApplied,
    this.onManualZoomApplied,
    this.fitDisplay,
  });

  final PdfViewerController? controller;
  final PdfViewerZoomAvailability? availability;
  final bool dense;
  final PdfViewerFitDisplay? fitDisplay;

  /// When null, uses [kDsStatusBarCompactBreakpoint] from [MediaQuery].
  final bool? compact;
  final VoidCallback? onFitWidthApplied;
  final VoidCallback? onFitHeightApplied;
  final VoidCallback? onFitPageApplied;
  final VoidCallback? onManualZoomApplied;

  @override
  Widget build(BuildContext context) {
    final useCompact =
        compact ??
        MediaQuery.sizeOf(context).width < kDsStatusBarCompactBreakpoint;
    final override = availability;
    if (override != null) {
      return useCompact
          ? _buildCompactMenu(context, override)
          : _buildRow(override);
    }
    final ctrl = controller;
    if (ctrl == null) {
      final state = pdfViewerZoomAvailability(isReady: false);
      return useCompact ? _buildCompactMenu(context, state) : _buildRow(state);
    }
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final state = pdfViewerZoomAvailability(isReady: ctrl.isReady);
        return useCompact
            ? _buildCompactMenu(context, state)
            : _buildRow(state);
      },
    );
  }

  Widget _buildCompactMenu(
    BuildContext context,
    PdfViewerZoomAvailability state,
  ) {
    final enabled = state.enabled;
    final ctrl = controller;
    return PopupMenuButton<PdfViewerZoomMenuAction>(
      key: const Key('pdf_viewer_zoom_menu'),
      tooltip: 'Zoom',
      enabled: enabled && ctrl != null,
      icon: const Icon(Icons.zoom_in_outlined),
      onSelected: (action) {
        final c = controller;
        if (c == null || !c.isReady) return;
        switch (action) {
          case PdfViewerZoomMenuAction.fitWidth:
            onFitWidthApplied?.call();
          case PdfViewerZoomMenuAction.fitHeight:
            onFitHeightApplied?.call();
          case PdfViewerZoomMenuAction.fitPage:
            onFitPageApplied?.call();
          case PdfViewerZoomMenuAction.zoomIn:
          case PdfViewerZoomMenuAction.zoomOut:
            onManualZoomApplied?.call();
        }
        pdfViewerApplyZoomMenuAction(c, action);
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: PdfViewerZoomMenuAction.zoomOut,
          child: ListTile(
            leading: Icon(Icons.remove),
            title: Text('Zoom out'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: PdfViewerZoomMenuAction.fitWidth,
          child: ListTile(
            leading: Icon(Icons.fit_screen_outlined),
            title: Text('Fit width'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: PdfViewerZoomMenuAction.fitHeight,
          child: ListTile(
            leading: Icon(Icons.height),
            title: Text('Fit height'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: PdfViewerZoomMenuAction.fitPage,
          child: ListTile(
            leading: Icon(Icons.crop_free),
            title: Text('Fit page'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: PdfViewerZoomMenuAction.zoomIn,
          child: ListTile(
            leading: Icon(Icons.add),
            title: Text('Zoom in'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Widget _buildRow(PdfViewerZoomAvailability state) {
    final enabled = state.enabled;
    final ctrl = controller;
    final fitSegmentSelected = switch (fitDisplay) {
      PdfViewerFitDisplay.fitWidth => _FitSegment.fitWidth,
      PdfViewerFitDisplay.fitPage => _FitSegment.fitPage,
      _ => _FitSegment.fitWidth,
    };
    final segmentSelected = fitDisplay == PdfViewerFitDisplay.fitPage
        ? _FitSegment.fitPage
        : fitDisplay == PdfViewerFitDisplay.fitWidth
        ? _FitSegment.fitWidth
        : fitSegmentSelected;

    void applyFit(_FitSegment segment) {
      if (ctrl == null || !enabled) return;
      switch (segment) {
        case _FitSegment.fitWidth:
          onFitWidthApplied?.call();
          pdfViewerApplyFitWidth(ctrl);
        case _FitSegment.fitPage:
          onFitPageApplied?.call();
          pdfViewerApplyFitPage(ctrl);
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DsToolbarIconButton(
          key: const Key('pdf_viewer_zoom_out'),
          icon: Icons.remove,
          tooltip: 'Zoom out',
          dense: dense,
          onPressed: enabled && ctrl != null
              ? () {
                  onManualZoomApplied?.call();
                  pdfViewerZoomOut(ctrl);
                }
              : null,
        ),
        DsToolbarSegmentedControl<_FitSegment>(
          enabled: enabled && ctrl != null,
          dense: dense,
          selected: segmentSelected,
          onSelected: enabled && ctrl != null ? applyFit : null,
          segments: const [
            DsToolbarSegment(
              key: Key('pdf_viewer_fit_width'),
              value: _FitSegment.fitWidth,
              icon: Icons.fit_screen_outlined,
              tooltip: 'Fit width (Ctrl+1)',
            ),
            DsToolbarSegment(
              key: Key('pdf_viewer_fit_page'),
              value: _FitSegment.fitPage,
              icon: Icons.crop_free,
              tooltip: 'Fit page (Ctrl+0)',
            ),
          ],
        ),
        DsToolbarIconButton(
          key: const Key('pdf_viewer_fit_height'),
          icon: Icons.height,
          tooltip: 'Fit height',
          dense: dense,
          onPressed: enabled && ctrl != null
              ? () {
                  onFitHeightApplied?.call();
                  pdfViewerApplyFitHeight(ctrl);
                }
              : null,
        ),
        DsToolbarIconButton(
          key: const Key('pdf_viewer_zoom_in'),
          icon: Icons.add,
          tooltip: 'Zoom in',
          dense: dense,
          onPressed: enabled && ctrl != null
              ? () {
                  onManualZoomApplied?.call();
                  pdfViewerZoomIn(ctrl);
                }
              : null,
        ),
      ],
    );
  }
}

enum _FitSegment { fitWidth, fitPage }
