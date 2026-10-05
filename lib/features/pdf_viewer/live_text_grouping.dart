import 'dart:math' as math;
import 'dart:ui';

/// One text fragment as PDFium reports it, in normalized top-left page space.
class RawTextFragment {
  const RawTextFragment({required this.text, required this.rect});

  final String text;
  final Rect rect;
}

/// A line: fragments on one baseline joined left to right.
class TextLineGroup {
  TextLineGroup({required this.text, required this.rect});

  String text;
  Rect rect;
}

/// A paragraph-like block of consecutive lines, edited as one unit.
class TextBlockGroup {
  TextBlockGroup({required this.lines});

  final List<TextLineGroup> lines;

  String get text => lines.map((l) => l.text.trim()).join(' ');

  Rect get rect =>
      lines.map((l) => l.rect).reduce((a, b) => a.expandToInclude(b));
}

final RegExp _bulletStart = RegExp(r'^\s*([•▪◦●○■□\-–—*]|\d{1,3}[.)]|[a-zA-Z][.)])\s');

/// Groups raw PDFium fragments into lines, then lines into blocks.
///
/// PDFium splits text at font/spacing changes, so a single line often arrives
/// as several boxes and a paragraph as many lines. Acrobat edits a paragraph at
/// a time; this reproduces that with geometry only (no font data needed).
/// [pagePt] converts normalized rects to points so thresholds scale with type.
List<TextBlockGroup> groupTextFragments(
  List<RawTextFragment> fragments,
  Size pagePt,
) {
  final frags = [
    for (final f in fragments)
      if (f.text.trim().isNotEmpty) f,
  ];
  if (frags.isEmpty) return const [];

  double hPt(Rect r) => r.height * pagePt.height;
  double wPt(Rect r) => r.width * pagePt.width;
  double vOverlap(Rect a, Rect b) {
    final o = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
    final m = math.min(a.height, b.height);
    return m <= 0 ? 0 : o / m;
  }

  // 1) lines — left-to-right within a shared baseline band.
  frags.sort((a, b) {
    final dy = a.rect.center.dy - b.rect.center.dy;
    if (dy.abs() > math.min(a.rect.height, b.rect.height) * 0.5) {
      return dy < 0 ? -1 : 1;
    }
    return a.rect.left.compareTo(b.rect.left);
  });

  final lineBuckets = <List<RawTextFragment>>[];
  for (final f in frags) {
    List<RawTextFragment>? target;
    for (final bucket in lineBuckets.reversed.take(6)) {
      final last = bucket.last;
      final gap = (f.rect.left - last.rect.right) * pagePt.width;
      final h = math.max(hPt(f.rect), hPt(last.rect));
      if (vOverlap(f.rect, last.rect) > 0.5 && gap > -h * 0.5 && gap < h * 1.6) {
        target = bucket;
        break;
      }
    }
    if (target == null) {
      lineBuckets.add([f]);
    } else {
      target.add(f);
    }
  }

  final lines = <TextLineGroup>[];
  for (final bucket in lineBuckets) {
    bucket.sort((a, b) => a.rect.left.compareTo(b.rect.left));
    final sb = StringBuffer();
    var rect = bucket.first.rect;
    RawTextFragment? prev;
    for (final f in bucket) {
      if (prev != null) {
        final gap = (f.rect.left - prev.rect.right) * pagePt.width;
        final h = hPt(f.rect);
        final needsSpace = gap > h * 0.15 &&
            !prev.text.endsWith(' ') &&
            !f.text.startsWith(' ');
        if (needsSpace) sb.write(' ');
      }
      sb.write(f.text);
      rect = rect.expandToInclude(f.rect);
      prev = f;
    }
    lines.add(TextLineGroup(text: sb.toString().trimRight(), rect: rect));
  }
  lines.sort((a, b) {
    final dy = a.rect.top - b.rect.top;
    return dy.abs() < 1e-6 ? a.rect.left.compareTo(b.rect.left) : dy.sign.toInt();
  });

  // 2) blocks — same column, same type size, tight leading.
  final blocks = <TextBlockGroup>[];
  for (final line in lines) {
    TextBlockGroup? joined;
    for (final block in blocks.reversed.take(12)) {
      final last = block.lines.last;
      final h = hPt(line.rect);
      final lastH = hPt(last.rect);
      if ((h - lastH).abs() > math.max(h, lastH) * 0.22) continue;
      final gapY = (line.rect.top - last.rect.bottom) * pagePt.height;
      if (gapY < -h * 0.6 || gapY > h * 0.85) continue;
      final dLeft = (line.rect.left - last.rect.left).abs() * pagePt.width;
      final dCenter =
          (line.rect.center.dx - last.rect.center.dx).abs() * pagePt.width;
      final sameLeft = dLeft < h * 1.8;
      final sameCenter = dCenter < h * 0.8 &&
          wPt(line.rect) > h * 3 &&
          wPt(last.rect) > h * 3;
      if (!(sameLeft || sameCenter)) continue;
      // A short last line ends a paragraph; a bullet / number starts one.
      final blockRight = block.rect.right;
      if ((blockRight - last.rect.right) * pagePt.width > h * 3.5) continue;
      if (_bulletStart.hasMatch(line.text)) continue;
      joined = block;
      break;
    }
    if (joined == null) {
      blocks.add(TextBlockGroup(lines: [line]));
    } else {
      joined.lines.add(line);
    }
  }
  return blocks;
}
