import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// DS-READ-003-A/B — how pages are laid out in the pdfrx viewer.
enum PdfViewerScrollLayoutMode {
  /// Vertical stack (pdfrx default): pages follow one another with [PdfViewerParams.margin].
  continuous,

  /// One page per viewport slot: page down / scroll snaps between slots (via layout spacing).
  singlePage,

  /// DS-READ-003-C — two pages side-by-side per row (desktop/tablet spread).
  twoPage,
}

extension PdfViewerScrollLayoutModeLabel on PdfViewerScrollLayoutMode {
  String get statusLabel => switch (this) {
        PdfViewerScrollLayoutMode.continuous => 'Continuous',
        PdfViewerScrollLayoutMode.singlePage => 'Single page',
        PdfViewerScrollLayoutMode.twoPage => 'Two page',
      };
}

double _twoPageMaxRowWidth(List<Size> pageSizes) {
  const pairGap = 8.0;
  var maxRowWidth = 0.0;
  for (var i = 0; i < pageSizes.length; i += 2) {
    final left = pageSizes[i];
    final right = i + 1 < pageSizes.length ? pageSizes[i + 1] : null;
    final rowWidth =
        left.width + (right != null ? pairGap + right.width : 0);
    maxRowWidth = math.max(maxRowWidth, rowWidth);
  }
  return maxRowWidth;
}

/// Pure layout math for tests (no [PdfPage] / PDFium).
({List<Rect> pageLayouts, Size documentSize}) computePdfViewerPageLayout({
  required List<Size> pageSizes,
  required double margin,
  required PdfViewerScrollLayoutMode mode,
  double viewportHeight = 0,
}) {
  if (pageSizes.isEmpty) {
    return (pageLayouts: <Rect>[], documentSize: Size.zero);
  }

  final contentMaxWidth = mode == PdfViewerScrollLayoutMode.twoPage
      ? _twoPageMaxRowWidth(pageSizes)
      : pageSizes.fold(0.0, (w, s) => math.max(w, s.width));
  final documentWidth = contentMaxWidth + margin * 2;
  final maxPageHeight =
      pageSizes.fold(0.0, (h, s) => math.max(h, s.height));

  final slotHeight = mode == PdfViewerScrollLayoutMode.singlePage
      ? (viewportHeight > margin * 2
          ? viewportHeight
          : maxPageHeight + margin * 2)
      : 0.0;

  final pageLayouts = <Rect>[];
  var y = margin;

  if (mode == PdfViewerScrollLayoutMode.twoPage) {
    const pairGap = 8.0;
    for (var i = 0; i < pageSizes.length; i += 2) {
      final left = pageSizes[i];
      final right = i + 1 < pageSizes.length ? pageSizes[i + 1] : null;
      final rowWidth = left.width + (right != null ? pairGap + right.width : 0);
      final rowHeight = math.max(left.height, right?.height ?? 0);
      var x = margin + (contentMaxWidth - rowWidth) / 2;
      pageLayouts.add(Rect.fromLTWH(x, y, left.width, left.height));
      if (right != null) {
        x += left.width + pairGap;
        pageLayouts.add(Rect.fromLTWH(x, y, right.width, right.height));
      }
      y += rowHeight + margin;
    }
    return (
      pageLayouts: pageLayouts,
      documentSize: Size(documentWidth, y),
    );
  }

  for (final size in pageSizes) {
    pageLayouts.add(
      Rect.fromLTWH(
        margin + (contentMaxWidth - size.width) / 2,
        y,
        size.width,
        size.height,
      ),
    );
    if (mode == PdfViewerScrollLayoutMode.singlePage) {
      y += slotHeight;
    } else {
      y += size.height + margin;
    }
  }

  return (
    pageLayouts: pageLayouts,
    documentSize: Size(documentWidth, y),
  );
}

/// Returns a pdfrx [layoutPages] override, or `null` to use the library default (continuous).
PdfPageLayoutFunction? pdfViewerLayoutPagesForMode({
  required PdfViewerScrollLayoutMode mode,
  required double viewportHeight,
}) {
  if (mode == PdfViewerScrollLayoutMode.continuous) {
    return null;
  }
  // twoPage and singlePage use custom layoutPages.
  return (pages, params) {
    final sizes = [for (final page in pages) Size(page.width, page.height)];
    final computed = computePdfViewerPageLayout(
      pageSizes: sizes,
      margin: params.margin,
      mode: mode,
      viewportHeight: viewportHeight,
    );
    return PdfPageLayout(
      pageLayouts: computed.pageLayouts,
      documentSize: computed.documentSize,
    );
  };
}
