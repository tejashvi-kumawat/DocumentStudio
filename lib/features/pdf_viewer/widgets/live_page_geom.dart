import 'dart:ui';

import 'package:document_studio/features/pdf_viewer/widgets/live_overlay_common.dart';

/// Geometry of one page overlay: displayed pixels ↔ normalized (0–1,
/// top-left) ↔ PDF points of the displayed (rotated / cropped) page.
///
/// The PDF writers use the same displayed page size, so a normalized rect
/// maps to the same spot on screen and in the saved file.
class LivePageGeom {
  const LivePageGeom({
    required this.pageNumber,
    required this.pagePx,
    required this.pageWidthPt,
    required this.pageHeightPt,
  });

  final int pageNumber;
  final Size pagePx;
  final double pageWidthPt;
  final double pageHeightPt;

  double get pxPerPt => livePxPerPt(pagePx, pageWidthPt);

  Offset toNorm(Offset local) => Offset(
    (local.dx / pagePx.width).clamp(0.0, 1.0),
    (local.dy / pagePx.height).clamp(0.0, 1.0),
  );

  /// Unclamped variant for deltas.
  Offset deltaToNorm(Offset delta) =>
      Offset(delta.dx / pagePx.width, delta.dy / pagePx.height);

  Offset toPx(Offset norm) =>
      Offset(norm.dx * pagePx.width, norm.dy * pagePx.height);

  Rect rectToPx(Rect norm) => Rect.fromLTRB(
    norm.left * pagePx.width,
    norm.top * pagePx.height,
    norm.right * pagePx.width,
    norm.bottom * pagePx.height,
  );

  /// Normalized x-extent of [pt] points.
  double ptToNormX(double pt) => pt / pageWidthPt;
  double ptToNormY(double pt) => pt / pageHeightPt;

  @override
  bool operator ==(Object other) =>
      other is LivePageGeom &&
      other.pageNumber == pageNumber &&
      other.pagePx == pagePx &&
      other.pageWidthPt == pageWidthPt &&
      other.pageHeightPt == pageHeightPt;

  @override
  int get hashCode =>
      Object.hash(pageNumber, pagePx, pageWidthPt, pageHeightPt);
}
