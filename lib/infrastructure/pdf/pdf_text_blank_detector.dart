import 'dart:math' as math;
import 'dart:ui';

import 'package:document_studio/infrastructure/pdf/pdf_form_spot_detector.dart';

/// Id prefix for blanks found in the page text layer (not AcroForm widgets).
const String textBlankSpotIdPrefix = 'textblank_';

/// Shown when a page was checked and no type-in blank could be placed.
const String noFillInBlanksOnPageMessage = 'No fill-in blanks on this page';

/// True when the smaller rect is mostly covered by the intersection.
bool formNormOverlap(Rect a, Rect b, {double ratio = 0.45}) {
  if (a.width <= 0 || a.height <= 0 || b.width <= 0 || b.height <= 0) {
    return false;
  }
  if (!a.overlaps(b)) return false;
  final i = a.intersect(b);
  if (i.width <= 0 || i.height <= 0) return false;
  final denom = math.min(a.width * a.height, b.width * b.height);
  if (denom < 1e-12) return false;
  return (i.width * i.height) / denom >= ratio;
}

/// Finds underline-style blanks in one page's text layer.
///
/// Looks for runs of underscores, dotted leaders, and wide sequences of
/// spaces on a text line. Does not treat vector strokes or handwriting as
/// fields — if nothing in the text can be placed, the list is empty.
List<PdfFormSpot> detectTextLayerBlanks({
  required String text,
  required List<Rect> normRects,
  required int pageIndex1Based,
  required double pageWidthPt,
  required double pageHeightPt,
}) {
  final pageW = pageWidthPt.isFinite && pageWidthPt > 1 ? pageWidthPt : 612.0;
  final pageH = pageHeightPt.isFinite && pageHeightPt > 1 ? pageHeightPt : 792.0;
  final n = math.min(text.length, normRects.length);
  if (n == 0) return const [];

  final glyphs = <_Glyph>[];
  for (var i = 0; i < n; i++) {
    final ch = text[i];
    if (ch == '\n' || ch == '\r') continue;
    glyphs.add(_Glyph(ch, normRects[i], pageW, pageH));
  }
  if (glyphs.isEmpty) return const [];

  final heights = [
    for (final g in glyphs)
      if (g.ink) g.norm.height,
  ]..sort();
  final medianH = heights.isEmpty ? 12 / pageH : heights[heights.length ~/ 2];
  final lineThresh = math.max(medianH * 0.85, 6 / pageH);

  glyphs.sort((a, b) {
    final dy = a.cy.compareTo(b.cy);
    if (dy != 0) return dy;
    return a.norm.left.compareTo(b.norm.left);
  });

  final lines = <List<_Glyph>>[];
  for (final g in glyphs) {
    if (lines.isEmpty) {
      lines.add([g]);
      continue;
    }
    final line = lines.last;
    var anchor = 0.0;
    for (final e in line) {
      anchor += e.cy;
    }
    anchor /= line.length;
    if ((g.cy - anchor).abs() <= lineThresh) {
      line.add(g);
    } else {
      lines.add([g]);
    }
  }

  final found = <_Candidate>[];
  for (final line in lines) {
    line.sort((a, b) => a.norm.left.compareTo(b.norm.left));
    var i = 0;
    while (i < line.length) {
      if (!line[i].blank) {
        i++;
        continue;
      }
      var j = i + 1;
      while (j < line.length && line[j].blank) {
        j++;
      }
      final candidate = _candidateFor(line, i, j, pageW, pageH, medianH);
      if (candidate != null) found.add(candidate);
      i = j;
    }
  }

  found.sort((a, b) {
    final dy = a.norm.top.compareTo(b.norm.top);
    if (dy != 0) return dy;
    return a.norm.left.compareTo(b.norm.left);
  });

  final kept = <_Candidate>[];
  for (final c in found) {
    final hit = kept.indexWhere(
      (o) => formNormOverlap(o.norm, c.norm, ratio: 0.5),
    );
    if (hit < 0) {
      kept.add(c);
      continue;
    }
    final other = kept[hit];
    if (c.rank > other.rank ||
        (c.rank == other.rank && c.norm.width > other.norm.width)) {
      kept[hit] = c;
    }
  }

  final spots = <PdfFormSpot>[];
  var nLine = 0;
  var nDots = 0;
  var nBlank = 0;
  for (final c in kept) {
    if (spots.length >= 80) break;
    final String name;
    switch (c.kind) {
      case _BlankKind.line:
        nLine++;
        name = 'Line $nLine';
      case _BlankKind.dots:
        nDots++;
        name = 'Dots $nDots';
      case _BlankKind.spaces:
        nBlank++;
        name = 'Blank $nBlank';
    }
    final norm = c.norm;
    spots.add(
      PdfFormSpot(
        id: '$textBlankSpotIdPrefix${pageIndex1Based}_${spots.length}',
        name: name,
        kind: PdfFormSpotKind.text,
        pdfRect: Rect.fromLTRB(
          norm.left * pageW,
          (1 - norm.bottom) * pageH,
          norm.right * pageW,
          (1 - norm.top) * pageH,
        ),
        normRect: norm,
        pageIndex1Based: pageIndex1Based,
      ),
    );
  }
  return spots;
}

enum _BlankKind { line, dots, spaces }

class _Candidate {
  _Candidate({required this.kind, required this.norm});

  final _BlankKind kind;
  final Rect norm;

  int get rank => switch (kind) {
        _BlankKind.line => 3,
        _BlankKind.dots => 2,
        _BlankKind.spaces => 1,
      };
}

class _Glyph {
  _Glyph(this.char, this.norm, this.pageW, this.pageH);

  final String char;
  final Rect norm;
  final double pageW;
  final double pageH;

  double get cx => (norm.left + norm.right) / 2;
  double get cy => (norm.top + norm.bottom) / 2;

  bool get ink =>
      norm.width * pageW >= 0.2 && norm.height * pageH >= 0.2;

  bool get underscore =>
      char == '_' ||
      char == '＿' ||
      char == '‗' ||
      char == '‾' ||
      char == '⎯' ||
      char == '─' ||
      char == '━';

  int get dotWeight => switch (char) {
        '.' || '·' || '∙' || '•' || '․' || '‧' => 1,
        '‥' => 2,
        '…' => 3,
        _ => 0,
      };

  bool get dot => dotWeight > 0;

  bool get space {
    if (underscore || dot) return false;
    if (char.isEmpty) return false;
    return char.trim().isEmpty;
  }

  bool get blank => underscore || dot || space;
}

_Candidate? _candidateFor(
  List<_Glyph> line,
  int start,
  int end,
  double pageW,
  double pageH,
  double medianH,
) {
  final run = line.sublist(start, end);
  var underCount = 0;
  var dotCount = 0;
  var spaceCount = 0;
  for (final g in run) {
    if (g.underscore) {
      underCount++;
    } else if (g.dot) {
      dotCount += g.dotWeight;
    } else if (g.space) {
      spaceCount++;
    }
  }

  Rect? union;
  for (final g in run) {
    if (!g.ink) continue;
    final current = union;
    union = current == null ? g.norm : current.expandToInclude(g.norm);
  }

  double? gapLeft;
  double? gapRight;
  for (var i = start - 1; i >= 0; i--) {
    if (line[i].ink && !line[i].blank) {
      gapLeft = line[i].norm.right;
      break;
    }
  }
  for (var i = end; i < line.length; i++) {
    if (line[i].ink && !line[i].blank) {
      gapRight = line[i].norm.left;
      break;
    }
  }

  final unionW = union == null ? 0.0 : union.width * pageW;
  final gapW = (gapLeft != null && gapRight != null && gapRight > gapLeft)
      ? (gapRight - gapLeft) * pageW
      : 0.0;
  final widthPt = math.max(unionW, gapW);

  final _BlankKind? kind;
  if (underCount >= 3 ||
      (underCount >= 2 && widthPt >= 18) ||
      (underCount >= 1 && widthPt >= 28)) {
    kind = _BlankKind.line;
  } else if (dotCount >= 4 || (dotCount >= 3 && widthPt >= 28)) {
    kind = _BlankKind.dots;
  } else if (spaceCount >= 3 && widthPt >= 36) {
    kind = _BlankKind.spaces;
  } else {
    kind = null;
  }
  if (kind == null || widthPt < 8) return null;

  final double left;
  final double right;
  if (kind == _BlankKind.spaces && gapW >= 36 && gapLeft != null && gapRight != null) {
    left = gapLeft;
    right = gapRight;
  } else if (union != null && (gapW < unionW + 8 || gapLeft == null || gapRight == null)) {
    left = union.left;
    right = union.right;
  } else if (gapLeft != null && gapRight != null) {
    left = gapLeft;
    right = gapRight;
  } else if (union != null) {
    left = union.left;
    right = union.right;
  } else {
    return null;
  }
  if ((right - left) * pageW < 8) return null;

  final bandBottom = union?.bottom ??
      (line.map((g) => g.norm.bottom).reduce(math.max));
  final minH = math.max(medianH, 14 / pageH);
  final maxH = math.max(minH, 18 / pageH);
  final bottom = bandBottom.clamp(0.0, 1.0);
  final top = (bottom - maxH).clamp(0.0, 1.0);
  final height = math.max(minH, bottom - top);
  final placedTop = (bottom - height).clamp(0.0, 1.0);
  final placedBottom = math.min(1.0, placedTop + height);
  if (placedBottom - placedTop < 8 / pageH) return null;

  return _Candidate(
    kind: kind,
    norm: Rect.fromLTRB(
      left.clamp(0.0, 1.0),
      placedTop,
      right.clamp(0.0, 1.0),
      placedBottom,
    ),
  );
}
