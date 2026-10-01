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

/// Long edge cap for the whole-page render. Screen pixels
/// (zoom × device pixel ratio) are used when they are smaller. Past this,
/// pdfrx renders only the visible region at real pixel size on top.
const double kPdfSettledRenderLongEdgePx = 4096;

/// A zoom-in must grow the needed scale by this much before an already
/// screen-quality page is decoded again. Zooming out keeps the sharper bitmap.
const double kPdfZoomRerenderFactor = 1.35;

/// A held bitmap under this fraction of the screen scale would look soft.
/// It is left on screen until a decode at [pdfViewerSettledRenderScale] arrives.
const double kPdfSettledScaleFloor = 0.9;

/// How long the matrix must stay still before scrolling counts as finished.
const Duration kPdfScrollSettleDelay = Duration(milliseconds: 140);

/// Extra band around the viewport, as a fraction of the viewport.
///
/// pdfrx renders every page that intersects this band and cancels a render
/// when the page leaves it. Half a viewport reaches the page just ahead and
/// the page just behind without pulling in the rest of the document.
const double kPdfViewerNeighborCacheExtent = 0.5;

/// Notices when the matrix is moving. The decode scale does not change
/// with motion.
class PdfViewerRenderPace {
  bool _moving = false;
  Timer? _settleTimer;

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
  }

  void dispose() {
    clear();
    onSettled = null;
  }

  /// The one scale a page may be decoded at.
  ///
  /// Screen pixels (zoom × device pixel ratio), with the long edge capped at
  /// [kPdfSettledRenderLongEdgePx]. Scrolling, flinging, and which page this
  /// is do not select another scale.
  double scaleFor({
    required double pageWidth,
    required double pageHeight,
    required double zoom,
    required double devicePixelRatio,
  }) {
    return pdfViewerSettledRenderScale(
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      zoom: zoom,
      devicePixelRatio: devicePixelRatio,
    );
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

/// [scale] with a sub-pixel fingerprint of the page geometry.
///
/// pdfrx re-renders a cached page only when the requested scale differs or the
/// image is marked dirty. It stamps a finished render with the geometry read
/// after the render, so a page measured mid-render keeps its estimate-sized
/// bitmap until a zoom changes the scale. Folding the geometry into the scale
/// makes any measurement change a new request. The bitmap grows by at most
/// 0.0001 %.
double pdfViewerGeometryKeyedScale({
  required double scale,
  required double pageWidth,
  required double pageHeight,
  int rotation = 0,
}) {
  final w = (pageWidth * 8).round();
  final h = (pageHeight * 8).round();
  final mark = ((w * 7919 + h * 104729 + rotation * 31) % 997) + 1;
  return scale * (1 + mark * 1e-9);
}

/// Whether [held] is still the right bitmap for screen-quality [target].
///
/// Zooming out keeps a sharper bitmap so it is not replaced by a smaller
/// decode. A small zoom-in keeps a bitmap that is already screen quality.
/// A bitmap under [kPdfSettledScaleFloor] of [target] would look soft, so a
/// new decode at [target] is requested while the current image stays up.
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

  /// Settles scroll motion. The page scale stays the screen scale.
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
    // A page is white until its one whole-page render at screen scale lands.
    // pdfrx calls that render a "preview", but it is requested at
    // [getPageRenderingScale], which is the full screen scale, so no coarse
    // stage exists. Zoomed past [kPdfSettledRenderLongEdgePx], the visible
    // region is rendered at real pixel size on top with no delay.
    behaviorControlParams: const PdfViewerBehaviorControlParams(
      loadPageDimensionsOnDemand: true,
      enableLowResolutionPagePreview: true,
      partialImageLoadingDelay: Duration.zero,
    ),
    // One neighbor past the viewport, not another full screen of pages.
    verticalCacheExtent: kPdfViewerNeighborCacheExtent,
    horizontalCacheExtent: kPdfViewerNeighborCacheExtent,
    onePassRenderingSizeThreshold: 100000,
    limitRenderingCache: true,
    sizeDelegateProvider: const PdfViewerSizeDelegateProviderLegacy(
      minScale: 0.5,
      maxScale: 8,
    ),
    getPageRenderingScale: (context, page, controller, _) {
      final zoom = controller.currentZoom;
      // An unmeasured page has an estimated size. A render now would be the
      // wrong shape and stretched, so the page stays blank until measured.
      if (!page.isLoaded) return 0;
      final dpr = MediaQuery.devicePixelRatioOf(context);
      // The screen scale only. pdfrx must not be given a smaller scale.
      final scale = pace != null
          ? pace.scaleFor(
              pageWidth: page.width,
              pageHeight: page.height,
              zoom: zoom,
              devicePixelRatio: dpr,
            )
          : pdfViewerSettledRenderScale(
              pageWidth: page.width,
              pageHeight: page.height,
              zoom: zoom,
              devicePixelRatio: dpr,
            );
      return pdfViewerGeometryKeyedScale(
        scale: scale,
        pageWidth: page.width,
        pageHeight: page.height,
        rotation: page.rotation.index,
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
