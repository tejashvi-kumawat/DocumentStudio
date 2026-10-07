import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:document_studio/domain/compare/compare_models.dart';
import 'package:pdfrx/pdfrx.dart';

/// Both pages rendered to the same pixel grid plus a difference heatmap.
class CompareVisualFrame {
  CompareVisualFrame({
    required this.a,
    required this.b,
    required this.heat,
    required this.boxes,
    required this.changedRatio,
  });

  final ui.Image? a;
  final ui.Image? b;
  final ui.Image? heat;
  final List<NormRect> boxes;

  /// Fraction of pixels that differ noticeably.
  final double changedRatio;

  void dispose() {
    a?.dispose();
    b?.dispose();
    heat?.dispose();
  }
}

/// Renders aligned page pairs at a moderate resolution and diffs them in a
/// background isolate. Frames are cached (LRU) per aligned row.
class CompareVisualDiffer {
  CompareVisualDiffer(this.oldDoc, this.newDoc, {this.targetWidth = 1000});

  final PdfDocument oldDoc;
  final PdfDocument newDoc;
  final int targetWidth;

  final _cache = <int, Future<CompareVisualFrame?>>{};
  var _disposed = false;

  Future<CompareVisualFrame?> frame(int row, ComparePagePair pair) {
    final hit = _cache.remove(row);
    if (hit != null) {
      _cache[row] = hit;
      return hit;
    }
    final f = _build(pair)
        .then<CompareVisualFrame?>((v) => v, onError: (Object _) => null);
    _cache[row] = f;
    while (_cache.length > 10) {
      final oldest = _cache.keys.first;
      unawaited(_cache.remove(oldest)!.then((v) => v?.dispose()));
    }
    return f;
  }

  Future<CompareVisualFrame?> _build(ComparePagePair pair) async {
    final pa = pair.a == null ? null : oldDoc.pages[pair.a!];
    final pb = pair.b == null ? null : newDoc.pages[pair.b!];
    final ref = pa ?? pb;
    if (ref == null) return null;
    final w = targetWidth;
    final h = math.max(1, (w * ref.height / ref.width).round());

    Future<Uint8List?> render(PdfPage? p) async {
      if (p == null) return null;
      final img = await p.render(
        width: w,
        height: h,
        fullWidth: w.toDouble(),
        fullHeight: h.toDouble(),
        backgroundColor: 0xFFFFFFFF,
      );
      if (img == null) return null;
      try {
        return Uint8List.fromList(img.pixels);
      } finally {
        img.dispose();
      }
    }

    final a = await render(pa);
    final b = await render(pb);
    if (_disposed) return null;
    final diff = (a != null && b != null)
        ? await _diffOffThread(a, b, w, h)
        : null;
    if (_disposed) return null;

    final images = await Future.wait([
      if (a != null)
        _decode(a, w, h, ui.PixelFormat.bgra8888)
      else
        Future.value(null),
      if (b != null)
        _decode(b, w, h, ui.PixelFormat.bgra8888)
      else
        Future.value(null),
      if (diff != null)
        _decode(diff.heat, w, h, ui.PixelFormat.rgba8888)
      else
        Future.value(null),
    ]);
    return CompareVisualFrame(
      a: images[0],
      b: images[1],
      heat: images[2],
      boxes: diff?.boxes ?? const [],
      changedRatio: diff?.ratio ?? (a == null || b == null ? 1 : 0),
    );
  }

  void dispose() {
    _disposed = true;
    for (final f in _cache.values) {
      unawaited(f.then((v) => v?.dispose()));
    }
    _cache.clear();
  }
}

Future<ui.Image?> _decode(Uint8List px, int w, int h, ui.PixelFormat format) {
  final c = Completer<ui.Image?>();
  ui.decodeImageFromPixels(px, w, h, format, c.complete);
  return c.future;
}

typedef _Diff = ({Uint8List heat, List<NormRect> boxes, double ratio});

/// Top-level so the isolate closure captures only the pixel buffers.
Future<_Diff> _diffOffThread(Uint8List a, Uint8List b, int w, int h) =>
    Isolate.run(() => _pixelDiff(a, b, w, h), debugName: 'compare-heatmap');

_Diff _pixelDiff(Uint8List a, Uint8List b, int w, int h) {
  const threshold = 36;
  const cell = 12;
  final cw = (w + cell - 1) ~/ cell;
  final ch = (h + cell - 1) ~/ cell;
  final cells = Uint16List(cw * ch);
  final heat = Uint8List(w * h * 4);
  var changed = 0;
  for (var y = 0; y < h; y++) {
    final row = y * w;
    final cy = (y ~/ cell) * cw;
    for (var x = 0; x < w; x++) {
      final i = (row + x) * 4;
      final d = math.max(
        (a[i] - b[i]).abs(),
        math.max((a[i + 1] - b[i + 1]).abs(), (a[i + 2] - b[i + 2]).abs()),
      );
      if (d < threshold) continue;
      changed++;
      cells[cy + x ~/ cell]++;
      // Yellow (small) -> red (strong) ramp.
      final t = (d - threshold) / (255 - threshold);
      heat[i] = 255;
      heat[i + 1] = (210 * (1 - t)).round();
      heat[i + 2] = 0;
      heat[i + 3] = (150 + 100 * t).round();
    }
  }

  // Connected changed cells (8-neighbourhood, 1-cell tolerance) -> boxes.
  final mark = Uint8List(cw * ch);
  for (var k = 0; k < cells.length; k++) {
    if (cells[k] >= 3) mark[k] = 1;
  }
  final boxes = <NormRect>[];
  final stack = <int>[];
  for (var k = 0; k < mark.length; k++) {
    if (mark[k] != 1) continue;
    var x0 = cw, y0 = ch, x1 = -1, y1 = -1;
    stack.add(k);
    mark[k] = 2;
    while (stack.isNotEmpty) {
      final c = stack.removeLast();
      final cx = c % cw;
      final cy = c ~/ cw;
      x0 = math.min(x0, cx);
      y0 = math.min(y0, cy);
      x1 = math.max(x1, cx);
      y1 = math.max(y1, cy);
      for (var dy = -2; dy <= 2; dy++) {
        for (var dx = -2; dx <= 2; dx++) {
          final nx = cx + dx;
          final ny = cy + dy;
          if (nx < 0 || ny < 0 || nx >= cw || ny >= ch) continue;
          final n = ny * cw + nx;
          if (mark[n] == 1) {
            mark[n] = 2;
            stack.add(n);
          }
        }
      }
    }
    boxes.add(
      NormRect(
        x0 * cell / w,
        y0 * cell / h,
        math.min(1, (x1 + 1) * cell / w),
        math.min(1, (y1 + 1) * cell / h),
      ),
    );
    if (boxes.length > 300) break;
  }
  return (heat: heat, boxes: boxes, ratio: changed / (w * h));
}
