import 'package:document_studio/features/pdf_viewer/pdf_viewer_zoom_controls.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// DS-READ-004-E — double-tap on page background toggles zoom in / fit width.
Future<void> pdfViewerHandleDoubleTapZoom(
  PdfViewerController controller,
  Offset localPosition,
) async {
  if (!controller.isReady) return;
  final zoom = controller.value.zoom;
  const zoomInThreshold = 1.05;
  if (zoom <= zoomInThreshold) {
    await controller.zoomUpOnLocalPosition(localPosition: localPosition);
  } else {
    await pdfViewerApplyFitWidth(controller);
  }
}

/// Returns true when the tap was handled (double-tap zoom).
bool handlePdfViewerGeneralTap(
  BuildContext context,
  PdfViewerController controller,
  PdfViewerGeneralTapHandlerDetails details,
) {
  if (details.type != PdfViewerGeneralTapType.doubleTap) return false;
  if (details.tapOn != PdfViewerPart.background &&
      details.tapOn != PdfViewerPart.nonSelectedText) {
    return false;
  }
  pdfViewerHandleDoubleTapZoom(controller, details.localPosition);
  return true;
}
