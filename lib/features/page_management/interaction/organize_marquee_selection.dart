import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Layout inputs matching [SliverGridDelegateWithFixedCrossAxisCount] on the page grid.
class OrganizeGridLayoutMetrics {
  const OrganizeGridLayoutMetrics({
    required this.crossAxisCount,
    required this.crossAxisSpacing,
    required this.mainAxisSpacing,
    required this.childAspectRatio,
    required this.padding,
    required this.viewportWidth,
    required this.itemCount,
  });

  final int crossAxisCount;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double childAspectRatio;
  final EdgeInsets padding;
  final double viewportWidth;
  final int itemCount;

  double get _tileWidth {
    final inner =
        viewportWidth - padding.horizontal - (crossAxisCount - 1) * crossAxisSpacing;
    return inner / crossAxisCount;
  }

  double get tileHeight => _tileWidth / childAspectRatio;

  Rect tileRectInContent(int index, double scrollOffset) {
    if (index < 0 || index >= itemCount) return Rect.zero;
    final row = index ~/ crossAxisCount;
    final col = index % crossAxisCount;
    final left = padding.left + col * (_tileWidth + crossAxisSpacing);
    final top = padding.top + row * (tileHeight + mainAxisSpacing) - scrollOffset;
    return Rect.fromLTWH(left, top, _tileWidth, tileHeight);
  }

  /// [localInViewport] is in the scroll view's viewport coordinates (0 at visible top).
  Rect contentRectFromViewportDrag(Offset start, Offset end, double scrollOffset) {
    final top = math.min(start.dy, end.dy) + scrollOffset;
    final bottom = math.max(start.dy, end.dy) + scrollOffset;
    final left = math.min(start.dx, end.dx);
    final right = math.max(start.dx, end.dx);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  bool viewportPointHitsTile(Offset localInViewport, int index, double scrollOffset) {
    return tileRectInContent(index, scrollOffset).contains(
      Offset(localInViewport.dx, localInViewport.dy + scrollOffset),
    );
  }

  Set<int> indicesIntersectingContentRect(Rect contentRect) {
    if (itemCount == 0) return {};
    final result = <int>{};
    for (var i = 0; i < itemCount; i++) {
      final tile = tileRectInContent(i, 0);
      if (contentRect.overlaps(tile)) result.add(i);
    }
    return result;
  }
}

/// Rubber-band rectangle in viewport coordinates (for painting).
class OrganizeMarqueeBand {
  const OrganizeMarqueeBand(this.start, this.end);

  final Offset start;
  final Offset end;

  Rect get rect {
    return Rect.fromPoints(start, end);
  }

  bool get isEmpty => rect.width < 2 && rect.height < 2;
}

class OrganizeMarqueeOverlayPainter extends CustomPainter {
  OrganizeMarqueeOverlayPainter({
    required this.band,
    required this.color,
  });

  final OrganizeMarqueeBand? band;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final b = band;
    if (b == null || b.isEmpty) return;
    final r = b.rect;
    final fill = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(r, fill);
    canvas.drawRect(r, stroke);
  }

  @override
  bool shouldRepaint(covariant OrganizeMarqueeOverlayPainter oldDelegate) {
    return oldDelegate.band != band || oldDelegate.color != color;
  }
}

/// Scrolls a [ScrollController] while the pointer is near the top/bottom edge.
class OrganizeGridEdgeAutoScroller {
  OrganizeGridEdgeAutoScroller({
    required this.scrollController,
    this.edgeExtent = 56,
    this.maxStep = 14,
  });

  final ScrollController scrollController;
  final double edgeExtent;
  final double maxStep;

  double _velocity = 0;
  bool _frameScheduled = false;

  void updateFromViewportLocal(Offset localInViewport, double viewportHeight) {
    if (!scrollController.hasClients || viewportHeight <= 0) {
      _velocity = 0;
      return;
    }
    final y = localInViewport.dy;
    if (y < edgeExtent) {
      final t = 1 - (y / edgeExtent).clamp(0.0, 1.0);
      _velocity = -maxStep * t;
    } else if (y > viewportHeight - edgeExtent) {
      final dist = viewportHeight - y;
      final t = 1 - (dist / edgeExtent).clamp(0.0, 1.0);
      _velocity = maxStep * t;
    } else {
      _velocity = 0;
    }
  }

  /// Horizontal filmstrip: scroll while the pointer is near the left/right edge.
  void updateFromViewportLocalHorizontal(
    Offset localInViewport,
    double viewportWidth,
  ) {
    if (!scrollController.hasClients || viewportWidth <= 0) {
      _velocity = 0;
      return;
    }
    final x = localInViewport.dx;
    if (x < edgeExtent) {
      final t = 1 - (x / edgeExtent).clamp(0.0, 1.0);
      _velocity = -maxStep * t;
    } else if (x > viewportWidth - edgeExtent) {
      final dist = viewportWidth - x;
      final t = 1 - (dist / edgeExtent).clamp(0.0, 1.0);
      _velocity = maxStep * t;
    } else {
      _velocity = 0;
    }
  }

  void stop() {
    _velocity = 0;
  }

  bool get isActive => _velocity != 0;

  void ensureTicking(VoidCallback onTick) {
    if (_velocity == 0 || _frameScheduled) return;
    _frameScheduled = true;
    WidgetsBinding.instance.scheduleFrameCallback((_) {
      _frameScheduled = false;
      onTick();
    });
  }

  void tick() {
    if (_velocity == 0 || !scrollController.hasClients) return;
    final pos = scrollController.position;
    final next = (pos.pixels + _velocity).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if (next != pos.pixels) {
      scrollController.jumpTo(next);
    }
  }
}
