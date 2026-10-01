import 'dart:math' as math;

import 'package:document_studio/features/pdf_viewer/pdf_viewer_params_config.dart';
import 'package:flutter/material.dart';

/// How many page decodes may run at once while scrolling.
const int kPdfApproachMaxDecodes = 2;

/// How many thumbnail decodes may run at once.
const int kPdfThumbMaxDecodes = 2;

/// Pages intersecting [visible], plus one page before and one after.
///
/// [visiblePages] and [decodePages] are 1-based. A page is chosen by its own
/// layout rect. Nothing here copies another page's pixels.
({Set<int> visiblePages, Set<int> decodePages}) pdfApproachPageWindow({
  required List<Rect> layouts,
  required Rect visible,
}) {
  if (layouts.isEmpty || visible.isEmpty) {
    return (visiblePages: const <int>{}, decodePages: const <int>{});
  }
  final visiblePages = <int>{};
  var index = _firstPageThatMayIntersect(layouts, visible);
  if (index > 0) index--;
  for (var i = index; i < layouts.length; i++) {
    final rect = layouts[i];
    final past = _primaryPast(layouts, rect, visible);
    if (past && visiblePages.isNotEmpty) break;
    if (rect.overlaps(visible)) visiblePages.add(i + 1);
  }
  if (visiblePages.isEmpty) {
    final nearest = _nearestPage(layouts, visible.center);
    visiblePages.add(nearest);
  }
  final first = visiblePages.reduce(math.min);
  final last = visiblePages.reduce(math.max);
  final decodePages = <int>{};
  for (var page = first - 1; page <= last + 1; page++) {
    if (page >= 1 && page <= layouts.length) decodePages.add(page);
  }
  return (visiblePages: visiblePages, decodePages: decodePages);
}

/// Visible page first (the current page before the others), then the page
/// ahead, then the page behind.
List<int> pdfApproachDecodeOrder({
  required Set<int> visiblePages,
  required Set<int> decodePages,
  int? currentPage,
}) {
  final visible = visiblePages.toList()..sort();
  if (currentPage != null && visible.remove(currentPage)) {
    visible.insert(0, currentPage);
  }
  final neighbors = decodePages.difference(visiblePages).toList();
  neighbors.sort((a, b) {
    final aAhead = currentPage != null && a > currentPage;
    final bAhead = currentPage != null && b > currentPage;
    if (aAhead != bAhead) return aAhead ? -1 : 1;
    return a.compareTo(b);
  });
  return [...visible, ...neighbors];
}

/// Pixels per PDF point for one page.
///
/// While the view is moving, or the page is only a neighbor, this is the
/// 400px preview. After motion settles, a page actually in the viewport is
/// the screen scale capped at 1600px.
double pdfApproachScaleFor({
  required bool moving,
  required bool inViewport,
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
  if (!moving && inViewport) return settled;
  return pdfViewerMovingPreviewScale(
    pageWidth: pageWidth,
    pageHeight: pageHeight,
    settledScale: settled,
  );
}

/// Scroll offset that brings thumbnail [pageNumber] into the strip.
double pdfThumbStripOffset({
  required int pageNumber,
  required double stride,
  required double maxScrollExtent,
}) {
  if (pageNumber < 1 || stride <= 0) return 0;
  final raw = (pageNumber - 1) * stride;
  if (!raw.isFinite || !maxScrollExtent.isFinite) return 0;
  if (maxScrollExtent <= 0) return 0;
  return raw.clamp(0.0, maxScrollExtent);
}

int _firstPageThatMayIntersect(List<Rect> layouts, Rect visible) {
  final byY = _scrollsVertically(layouts);
  var lo = 0;
  var hi = layouts.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    final end = byY ? layouts[mid].bottom : layouts[mid].right;
    final start = byY ? visible.top : visible.left;
    if (end <= start) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo.clamp(0, layouts.length - 1);
}

bool _scrollsVertically(List<Rect> layouts) {
  if (layouts.length < 2) return true;
  final dy = (layouts.last.center.dy - layouts.first.center.dy).abs();
  final dx = (layouts.last.center.dx - layouts.first.center.dx).abs();
  return dy >= dx;
}

bool _primaryPast(List<Rect> layouts, Rect rect, Rect visible) {
  if (_scrollsVertically(layouts)) return rect.top >= visible.bottom;
  return rect.left >= visible.right;
}

int _nearestPage(List<Rect> layouts, Offset point) {
  var best = 0;
  var bestDist = double.infinity;
  final start = _firstPageThatMayIntersect(layouts, Rect.fromCircle(center: point, radius: 1));
  final from = math.max(0, start - 2);
  final to = math.min(layouts.length - 1, start + 2);
  for (var i = from; i <= to; i++) {
    final dist = (layouts[i].center - point).distanceSquared;
    if (dist < bestDist) {
      bestDist = dist;
      best = i;
    }
  }
  return best + 1;
}
