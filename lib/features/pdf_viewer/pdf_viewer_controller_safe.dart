import 'package:pdfrx/pdfrx.dart';

/// Snapshot of page nav fields that never bangs when the controller is detached.
///
/// pdfrx's [PdfViewerController.pageNumber] / [pageCount] use `__state!`. During
/// remount / soft-reload, [isReady] can race with detach and throw
/// "Null check operator used on a null value", which then loops into
/// `semantics.parentDataDirty` while Flutter keeps rebuilding.
class PdfViewerControllerNavSnapshot {
  const PdfViewerControllerNavSnapshot({
    required this.isReady,
    this.pageNumber,
    this.pageCount = 0,
  });

  final bool isReady;
  final int? pageNumber;
  final int pageCount;

  static const notReady = PdfViewerControllerNavSnapshot(isReady: false);

  factory PdfViewerControllerNavSnapshot.of(PdfViewerController controller) {
    try {
      if (!controller.isReady) return notReady;
      return PdfViewerControllerNavSnapshot(
        isReady: true,
        pageNumber: controller.pageNumber,
        pageCount: controller.pageCount,
      );
    } catch (_) {
      return notReady;
    }
  }
}
