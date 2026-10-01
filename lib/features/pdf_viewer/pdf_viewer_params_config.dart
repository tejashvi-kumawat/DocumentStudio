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
/// A full sheet at screen size is what made each page take a noticeable
/// slice of the PDFium worker, so the next scroll tick looked like it was
/// waiting on that decode.
const double kPdfMovingPreviewLongEdgePx = 400;

/// Long edge cap once scrolling has settled. Screen pixels
/// (zoom × device pixel ratio) are used when they are smaller.
const double kPdfSettledRenderLongEdgePx = 1600;

/// How long the matrix must stay still before the visible page is upgraded
/// from the moving preview to screen resolution.
const Duration kPdfScrollSettleDelay = Duration(milliseconds: 140);

/// Extra band around the viewport, as a fraction of the viewport.
///
/// pdfrx renders every page that intersects this band and cancels a render
/// when the page leaves it. Half a viewport reaches the page just ahead and
/// the page just behind without pulling in the rest of the document.
const double kPdfViewerNeighborCacheExtent = 0.5;

/// Tracks whether the viewer matrix is still moving, and which pages already
/// have a settled bitmap so a fling does not decode them again at preview size.
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
  /// While moving, a page without a settled bitmap uses the 400px preview.
  /// A page that already has a settled bitmap keeps it. After motion stops,
  /// the page is requested at screen resolution capped at 1600px.
  double scaleFor({
    required int pageNumber,
    required double pageWidth,
    required double pageHeight,
    required double zoom,
    required double devicePixelRatio,
  }) {
    final settled = pdfViewerSettledRenderScale(
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      zoom: zoom,
      devicePixelRatio: devicePixelRatio,
    );
    final preview = pdfViewerMovingPreviewScale(
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      settledScale: settled,
    );
    if (!_moving) {
      _settledScale[pageNumber] = settled;
      return settled;
    }
    final kept = _settledScale[pageNumber];
    if (kept != null && (kept - settled).abs() < 0.02) return kept;
    return preview;
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

/// Cheap scale used for a page that does not yet have a settled bitmap.
double pdfViewerMovingPreviewScale({
  required double pageWidth,
  required double pageHeight,
  required double settledScale,
}) {
  final longPt = math.max(pageWidth, pageHeight);
  if (longPt <= 1) return settledScale;
  return math.min(kPdfMovingPreviewLongEdgePx / longPt, settledScale);
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

  /// Motion flag for preview vs screen-resolution renders. Null treats the
  /// view as settled.
  PdfViewerRenderPace? renderPace,
}) {
  final effectiveMode = immersiveSinglePage
      ? PdfViewerScrollLayoutMode.singlePage
      : scrollLayoutMode;
  final pace = renderPace;
  return PdfViewerParams(
    // Measure only pages that intersect the cache band. Never walk the
    // document for sizes on open or on a fling.
    behaviorControlParams: const PdfViewerBehaviorControlParams(
      loadPageDimensionsOnDemand: true,
      enableLowResolutionPagePreview: true,
      // Screen-resolution tiles wait until the visible rect stops changing.
      // A fling resets this timer every frame, so it never queues a full
      // decode for a page the user has already left.
      partialImageLoadingDelay: Duration(milliseconds: 180),
    ),
    // One neighbor past the viewport, not another full screen of pages.
    verticalCacheExtent: kPdfViewerNeighborCacheExtent,
    horizontalCacheExtent: kPdfViewerNeighborCacheExtent,
    onePassRenderingSizeThreshold: kPdfSettledRenderLongEdgePx,
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
