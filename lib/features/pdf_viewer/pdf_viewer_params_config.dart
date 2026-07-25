import 'dart:async';
import 'dart:math' as math;

import 'package:document_studio/app/keyboard/text_input_guard.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/features/annotations/markup/markup_keyboard.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_gesture_zoom.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_page_shortcuts.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_scroll_layout.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Long edge of the bitmap drawn while a fling is still moving.
///
/// This preview is replaced once the matrix has been still for
/// [kPdfScrollSettleDelay]. It is not the scale a settled page keeps.
const double kPdfMovingPreviewLongEdgePx = 400;

/// Long edge cap for one full-quality render. Screen pixels
/// (zoom × device pixel ratio) are used when they are smaller.
const double kPdfSettledRenderLongEdgePx = 1600;

/// A zoom-in must grow the needed scale by this much before an already
/// screen-quality page is decoded again. Zooming out keeps the sharper bitmap.
const double kPdfZoomRerenderFactor = 1.35;

/// A held bitmap under this fraction of [pdfViewerSettledRenderScale] is still
/// a preview. Stopping on the page decodes it once at screen quality.
const double kPdfSettledScaleFloor = 0.9;

/// How long the matrix must stay still before a visible page is decoded at
/// full quality.
const Duration kPdfScrollSettleDelay = Duration(milliseconds: 140);

/// Extra band around the viewport, as a fraction of the viewport.
///
/// pdfrx renders every page that intersects this band and cancels a render
/// when the page leaves it. Half a viewport reaches the page just ahead and
/// the page just behind without pulling in the rest of the document.
const double kPdfViewerNeighborCacheExtent = 0.5;

/// Tracks which pages already have a bitmap so a small zoom change does not
/// decode them again, and so a moving preview is replaced after the scroll
/// settles.
class PdfViewerRenderPace {
  bool _moving = false;
  Timer? _settleTimer;
  final Map<int, double> _settledScale = {};

  /// Called once the matrix has been still for [kPdfScrollSettleDelay].
  VoidCallback? onSettled;

  bool get isMoving => _moving;

  void noteMotion() {
    _moving = true;
    _settleTimer?.cancel();
    _settleTimer = Timer(kPdfScrollSettleDelay, () {
      _moving = false;
      onSettled?.call();
    });
  }

  void clear() {
    _settleTimer?.cancel();
    _settleTimer = null;
    _moving = false;
    _settledScale.clear();
  }

  void dispose() {
    clear();
    onSettled = null;
  }

  /// Pixels per PDF point for [pageNumber].
  ///
  /// While the matrix is moving, a page that does not already have a
  /// screen-quality bitmap is requested at the [kPdfMovingPreviewLongEdgePx]
  /// preview. Once motion stops, a bitmap below [kPdfSettledScaleFloor] of
  /// [pdfViewerSettledRenderScale] is requested once at that screen scale
  /// (capped at [kPdfSettledRenderLongEdgePx]). Zooming out keeps a sharper
  /// bitmap. A zoom-in smaller than [kPdfZoomRerenderFactor] keeps a bitmap
  /// that is already near screen quality.
  double scaleFor({
    required int pageNumber,
    required double pageWidth,
    required double pageHeight,
    required double zoom,
    required double devicePixelRatio,
  }) {
    final target = pdfViewerSettledRenderScale(
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      zoom: zoom,
      devicePixelRatio: devicePixelRatio,
    );
    final kept = _settledScale[pageNumber];
    if (_moving) {
      final preview = pdfViewerMovingPreviewScale(
        pageWidth: pageWidth,
        pageHeight: pageHeight,
        settledScale: target,
      );
      if (kept != null && kept + 0.02 >= preview) return kept;
      _settledScale[pageNumber] = preview;
      return preview;
    }
    if (kept != null &&
        pdfViewerKeepsRenderedScale(held: kept, target: target)) {
      return kept;
    }
    _settledScale[pageNumber] = target;
    return target;
  }
}

/// Scale that makes the page's long edge [kPdfSettledRenderLongEdgePx], or the
/// on-screen scale when that is already smaller.
double pdfViewerSettledRenderScale({
  required double pageWidth,
  required double pageHeight,
  required double zoom,
  required double devicePixelRatio,
}) {
  final longPt = math.max(pageWidth, pageHeight);
  if (longPt <= 1 || !zoom.isFinite || zoom <= 0) return 1;
  final screen = zoom * (devicePixelRatio > 0 ? devicePixelRatio : 1);
  return math.min(screen, kPdfSettledRenderLongEdgePx / longPt);
}

/// Cheap scale used while the view is still moving.
///
/// Never sharper than [settledScale]. A settled page does not stay on this
/// scale.
double pdfViewerMovingPreviewScale({
  required double pageWidth,
  required double pageHeight,
  required double settledScale,
}) {
  final longPt = math.max(pageWidth, pageHeight);
  if (longPt <= 1) return settledScale;
  return math.min(kPdfMovingPreviewLongEdgePx / longPt, settledScale);
}

/// Whether [held] is still the right bitmap for screen-quality [target].
///
/// A preview (under [kPdfSettledScaleFloor] of [target]) is not kept, so
/// stopping on the page requests [target] without a zoom change. Zooming out
/// keeps a sharper bitmap. A small zoom-in keeps a bitmap that is already
/// near screen quality.
bool pdfViewerKeepsRenderedScale({
  required double held,
  required double target,
}) {
  if (!(held > 0) || !(target > 0)) return false;
  if (held + 0.02 >= target) return true;
  if (held + 0.02 < target * kPdfSettledScaleFloor) return false;
  return target < held * kPdfZoomRerenderFactor;
}

/// Shared [PdfViewerParams] for Document Studio (pdfrx 2.6+ sizing API).
///
/// [scrollLayoutMode]: DS-READ-003-A/B — `continuous` uses pdfrx default vertical
/// stacking; `singlePage` sets [PdfViewerParams.layoutPages] with viewport-sized slots.
/// [viewportHeight] should match the viewer area height when in single-page mode.
PdfViewerParams buildPdfViewerParams({
  List<PdfViewerPagePaintCallback>? pagePaintCallbacks,
  PdfViewerController? pageNavigationController,
  PdfLinkHandlerParams? linkHandlerParams,
  PdfViewerScrollLayoutMode scrollLayoutMode =
      PdfViewerScrollLayoutMode.continuous,
  double viewportHeight = 0,
  PdfPageOverlaysBuilder? pageOverlaysBuilder,

  /// Presentation: one-page layout without remounting (not part of PdfViewer key).
  bool immersiveSinglePage = false,

  /// Presentation: single-tap advances to the next page.
  bool presentationAdvanceOnTap = false,

  /// Preview while scrolling, then one screen-quality decode after settle.
  PdfViewerRenderPace? renderPace,
}) {
  final effectiveMode = immersiveSinglePage
      ? PdfViewerScrollLayoutMode.singlePage
      : scrollLayoutMode;
  final pace = renderPace;
  return PdfViewerParams(
    // Measure only pages that intersect the cache band. Never walk the
    // document for sizes on open or on a fling.
    //
    // pdfrx fills a page that has no bitmap yet with white. Page 1 of a
    // drawing set is often a blank white sheet, so that fill looked like
    // page 1 on every other page. Leave both of pdfrx's decodes off.
    // [PdfApproachDecoder] paints a flat fill until that page's own pixels
    // arrive, and never substitutes another page's bitmap.
    behaviorControlParams: const PdfViewerBehaviorControlParams(
      loadPageDimensionsOnDemand: true,
      enableLowResolutionPagePreview: false,
      partialImageLoadingDelay: Duration(days: 1),
    ),
    // One neighbor past the viewport, not another full screen of pages.
    verticalCacheExtent: kPdfViewerNeighborCacheExtent,
    horizontalCacheExtent: kPdfViewerNeighborCacheExtent,
    // One decode at the requested size. A low threshold makes pdfrx paint a
    // coarse image and then the real one.
    onePassRenderingSizeThreshold: 100000,
    limitRenderingCache: true,
    sizeDelegateProvider: const PdfViewerSizeDelegateProviderLegacy(
      minScale: 0.5,
      maxScale: 8,
    ),
    getPageRenderingScale: (context, page, controller, _) {
      final zoom = controller.currentZoom;
      final dpr = MediaQuery.devicePixelRatioOf(context);
      if (pace == null) {
        return pdfViewerSettledRenderScale(
          pageWidth: page.width,
          pageHeight: page.height,
          zoom: zoom,
          devicePixelRatio: dpr,
        );
      }
      return pace.scaleFor(
        pageNumber: page.pageNumber,
        pageWidth: page.width,
        pageHeight: page.height,
        zoom: zoom,
        devicePixelRatio: dpr,
      );
    },
    // DS-READ-007-B — find match highlight colors on canvas.
    matchTextColor: DsColors.warning.withValues(alpha: 0.35),
    activeMatchTextColor: DsColors.primary.withValues(alpha: 0.45),
    // DS-READ-008-A — pdfrx text selection (enabled by default; set explicitly).
    textSelectionParams: PdfTextSelectionParams(
      enabled: !presentationAdvanceOnTap,
      showContextMenuAutomatically: !presentationAdvanceOnTap,
    ),
    panEnabled: !presentationAdvanceOnTap,
    // DS-READ-004-D — pinch + Ctrl+wheel zoom (pdfrx default wheel handler).
    scaleEnabled: !presentationAdvanceOnTap,
    scrollByMouseWheel: presentationAdvanceOnTap ? 0 : 0.2,
    onGeneralTap: (context, controller, details) {
      if (presentationAdvanceOnTap &&
          details.type == PdfViewerGeneralTapType.tap) {
        navigatePdfViewerPage(
          controller: controller,
          step: PdfViewerPageStep.next,
        );
        return true;
      }
      return handlePdfViewerGeneralTap(context, controller, details);
    },
    layoutPages: pdfViewerLayoutPagesForMode(
      mode: effectiveMode,
      viewportHeight: viewportHeight,
    ),
    pagePaintCallbacks: pagePaintCallbacks,
    linkHandlerParams: linkHandlerParams,
    pageOverlaysBuilder: pageOverlaysBuilder,
    onKey: (params, key, isRealKeyPress) {
      if (!TextInputGuard.allowsKey(key)) return false;
      if (MarkupKeyRouting.claims(key)) return false;
      if (pageNavigationController == null) return null;
      return handlePdfViewerPageNavigationKey(pageNavigationController, key);
    },
  );
}

/// Minimum width to show the optional thumbnail sidebar as a side column.
const kPdfViewerThumbnailSidebarBreakpoint = 600.0;

bool shouldShowPdfThumbnailSidebar({
  required double viewportWidth,
  required bool sidebarEnabled,
}) {
  return sidebarEnabled &&
      viewportWidth >= kPdfViewerThumbnailSidebarBreakpoint;
}
