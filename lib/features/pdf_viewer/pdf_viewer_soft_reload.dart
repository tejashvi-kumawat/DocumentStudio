import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Seamless document swap provided by the widget hosting a [PdfViewer]
/// (see `PdfDocumentWorkspace`). Returns false when it could not swap.
typedef PdfViewerSeamlessReload = Future<bool> Function({
  int? preferredPage,
  double? preferredZoom,
  Offset? preferredCenter,
});

final Expando<PdfViewerSeamlessReload> _seamlessReloaders =
    Expando<PdfViewerSeamlessReload>('pdfViewerSeamlessReload');

/// Registers (or clears with null) the seamless reload for [controller].
void registerPdfViewerSeamlessReload(
  PdfViewerController controller,
  PdfViewerSeamlessReload? reload,
) {
  _seamlessReloaders[controller] = reload;
}

/// Reloads document bytes for the same file path without remounting [PdfViewer].
///
/// Preserves page index, zoom, and document center so Apply/undo do not flash
/// or jump to page 1.
Future<void> softReloadPdfViewerDocument(
  PdfViewerController controller, {
  int? preferredPage,
  double? preferredZoom,
  Offset? preferredCenter,
}) async {
  final seamless = _seamlessReloaders[controller];
  if (seamless != null) {
    final swapped = await seamless(
      preferredPage: preferredPage,
      preferredZoom: preferredZoom,
      preferredCenter: preferredCenter,
    );
    if (swapped) return;
  }
  if (!controller.isReady) return;
  final page = preferredPage ?? controller.pageNumber ?? 1;
  final zoom = preferredZoom ?? controller.currentZoom;
  final center = preferredCenter ?? controller.centerPosition;
  try {
    await controller.documentRef.resolveListenable().load(forceReload: true);
  } catch (_) {
    return;
  }
  // Wait a frame for layout after reload, then restore view.
  await SchedulerBinding.instance.endOfFrame;
  if (!controller.isReady) return;
  try {
    await controller.goToPage(
      pageNumber: page.clamp(1, controller.pageCount),
      duration: Duration.zero,
    );
    await controller.setZoom(center, zoom, duration: Duration.zero);
  } catch (_) {}
}
