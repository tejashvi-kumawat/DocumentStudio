import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:pdfrx/pdfrx.dart';

/// Character boxes of one page in display points (top-left origin).
class MarkupPageText {
  MarkupPageText(this.text, this.rects);

  final String text;
  final List<Rect> rects;

  bool get isEmpty => rects.every((r) => r.isEmpty);

  static final Expando<Future<MarkupPageText?>> _cache =
      Expando<Future<MarkupPageText?>>('markupPageText');

  /// Loads (and caches per page instance) the text layer of [page].
  static Future<MarkupPageText?> of(PdfPage page) {
    return _cache[page] ??= () async {
      try {
        final raw = await page.loadText();
        if (raw == null) return null;
        final rects = [
          for (final r in raw.charRects) r.toRect(page: page),
        ];
        return MarkupPageText(raw.fullText, rects);
      } catch (_) {
        return null;
      }
    }();
  }

  int? _indexNear(Offset p) {
    int? best;
    var bestScore = double.infinity;
    for (var i = 0; i < rects.length; i++) {
      final r = rects[i];
      if (r.isEmpty || r.width <= 0 || r.height <= 0) continue;
      if (r.contains(p)) return i;
      final dy = p.dy < r.top
          ? r.top - p.dy
          : (p.dy > r.bottom ? p.dy - r.bottom : 0.0);
      final dx = p.dx < r.left
          ? r.left - p.dx
          : (p.dx > r.right ? p.dx - r.right : 0.0);
      // Strongly prefer the same line.
      final score = dy * 6 + dx;
      if (score < bestScore) {
        bestScore = score;
        best = i;
      }
    }
    if (bestScore > 60) return null;
    return best;
  }

  /// Line rects covering characters [start, end) — for markup applied to an
  /// existing text selection.
  List<Rect> linesForRange(int start, int end) {
    final lines = <Rect>[];
    Rect? cur;
    for (var i = math.max(0, start); i < math.min(end, rects.length); i++) {
      final r = rects[i];
      if (r.isEmpty || r.width <= 0 || r.height <= 0) continue;
      final c = cur;
      if (c == null) {
        cur = r;
        continue;
      }
      final overlap = math.min(c.bottom, r.bottom) - math.max(c.top, r.top);
      final sameLine = overlap > math.min(c.height, r.height) * 0.5 &&
          r.left >= c.left - r.height;
      if (sameLine) {
        cur = c.expandToInclude(r);
      } else {
        lines.add(c);
        cur = r;
      }
    }
    if (cur != null) lines.add(cur);
    return lines;
  }

  /// Line rects + text covered by a drag from [a] to [b] (reading order).
  (List<Rect>, String)? selection(Offset a, Offset b) {
    final i0 = _indexNear(a);
    final i1 = _indexNear(b);
    if (i0 == null || i1 == null) return null;
    var s = math.min(i0, i1), e = math.max(i0, i1);
    // Snap the far end to the character side the pointer is on.
    final lines = <Rect>[];
    Rect? cur;
    for (var i = s; i <= e; i++) {
      final r = rects[i];
      if (r.isEmpty || r.width <= 0 || r.height <= 0) continue;
      final c = cur;
      if (c == null) {
        cur = r;
        continue;
      }
      final overlap =
          math.min(c.bottom, r.bottom) - math.max(c.top, r.top);
      final sameLine = overlap > math.min(c.height, r.height) * 0.5 &&
          r.left >= c.left - r.height;
      if (sameLine) {
        cur = c.expandToInclude(r);
      } else {
        lines.add(c);
        cur = r;
      }
    }
    if (cur != null) lines.add(cur);
    if (lines.isEmpty) return null;
    e = math.min(e, text.length - 1);
    s = math.min(s, e);
    final t = text.isEmpty ? '' : text.substring(s, e + 1);
    return (lines, t.replaceAll(RegExp(r'\s+'), ' ').trim());
  }
}
