import 'dart:math' as math;

/// Rectangle in normalized page space: 0..1, top-left origin, visual
/// (rotation-applied) orientation. Normalized coordinates let two pages of
/// different sizes be overlaid and painted at any zoom.
class NormRect {
  const NormRect(this.l, this.t, this.r, this.b);

  final double l;
  final double t;
  final double r;
  final double b;

  double get width => r - l;
  double get height => b - t;
  double get area => math.max(0, width) * math.max(0, height);
  double get cx => (l + r) / 2;
  double get cy => (t + b) / 2;

  NormRect union(NormRect o) => NormRect(
    math.min(l, o.l),
    math.min(t, o.t),
    math.max(r, o.r),
    math.max(b, o.b),
  );

  NormRect inflate(double d) => NormRect(l - d, t - d, r + d, b + d);

  NormRect clamp01() => NormRect(
    l.clamp(0.0, 1.0),
    t.clamp(0.0, 1.0),
    r.clamp(0.0, 1.0),
    b.clamp(0.0, 1.0),
  );

  double iou(NormRect o) {
    final il = math.max(l, o.l);
    final it = math.max(t, o.t);
    final ir = math.min(r, o.r);
    final ib = math.min(b, o.b);
    if (ir <= il || ib <= it) return 0;
    final inter = (ir - il) * (ib - it);
    final u = area + o.area - inter;
    return u <= 0 ? 0 : inter / u;
  }

  @override
  String toString() =>
      'NormRect(${l.toStringAsFixed(3)}, ${t.toStringAsFixed(3)}, '
      '${r.toStringAsFixed(3)}, ${b.toStringAsFixed(3)})';
}

// ---------------------------------------------------------------------------
// Extracted page content
// ---------------------------------------------------------------------------

class CompareWord {
  const CompareWord({
    required this.text,
    required this.rect,
    this.font = '',
    this.size = 0,
    this.color = 0,
  });

  final String text;
  final NormRect rect;

  /// Base font name without the subset tag (`ABCDEF+`). Empty when unknown.
  final String font;
  final double size;

  /// 0xRRGGBB fill color.
  final int color;
}

class CompareImageObj {
  const CompareImageObj({
    required this.rect,
    required this.pixelWidth,
    required this.pixelHeight,
    this.hash = 0,
  });

  final NormRect rect;
  final int pixelWidth;
  final int pixelHeight;

  /// Hash of the raw (encoded) image stream; 0 when unavailable. Two images
  /// with equal size but different hashes have different content.
  final int hash;
}

class CompareAnnot {
  const CompareAnnot({
    required this.subtype,
    required this.rect,
    required this.contents,
    this.target = '',
  });

  final int subtype;
  final NormRect rect;
  final String contents;

  /// Link target (URI or `page N`) for link annotations.
  final String target;

  String get subtypeLabel => pdfAnnotSubtypeLabel(subtype);
}

class ComparePageData {
  const ComparePageData({
    required this.index,
    required this.widthPt,
    required this.heightPt,
    required this.words,
    required this.images,
    required this.annots,
  });

  /// 0-based page index.
  final int index;

  /// Visual page size (rotation applied).
  final double widthPt;
  final double heightPt;
  final List<CompareWord> words;
  final List<CompareImageObj> images;
  final List<CompareAnnot> annots;
}

class CompareDocData {
  const CompareDocData({
    required this.path,
    required this.pages,
    this.hasFontInfo = true,
    this.hasImageInfo = true,
  });

  final String path;
  final List<ComparePageData> pages;

  /// False when the text backend exposes no font / size / color data, so
  /// formatting changes cannot be detected.
  final bool hasFontInfo;

  /// False when image objects could not be enumerated.
  final bool hasImageInfo;

  int get pageCount => pages.length;
}

String pdfAnnotSubtypeLabel(int subtype) => switch (subtype) {
  1 => 'Note',
  2 => 'Link',
  3 => 'Text box',
  4 => 'Line',
  5 => 'Rectangle',
  6 => 'Ellipse',
  7 => 'Polygon',
  8 => 'Polyline',
  9 => 'Highlight',
  10 => 'Underline',
  11 => 'Squiggly',
  12 => 'Strikeout',
  13 => 'Stamp',
  14 => 'Caret',
  15 => 'Ink',
  16 => 'Popup',
  17 => 'File attachment',
  18 => 'Sound',
  19 => 'Movie',
  20 => 'Form field',
  21 => 'Screen',
  22 => 'Printer mark',
  23 => 'Trap net',
  24 => 'Watermark',
  25 => '3D',
  26 => 'Rich media',
  27 => 'XFA widget',
  28 => 'Redaction',
  _ => 'Annotation',
};

/// Thrown when a compare run is cancelled (new run, screen closed, user).
class CompareCancelled implements Exception {
  const CompareCancelled();

  @override
  String toString() => 'Compare cancelled';
}

// ---------------------------------------------------------------------------
// Compare result
// ---------------------------------------------------------------------------

enum CompareCategory {
  text('Text', 'Words inserted, deleted or replaced'),
  formatting('Formatting', 'Font, size, color and page size changes'),
  images('Images', 'Images added, removed, replaced or resized'),
  annotations('Annotations', 'Comments, markup and links'),
  pages('Pages', 'Pages inserted, deleted or moved');

  const CompareCategory(this.label, this.description);

  final String label;
  final String description;
}

enum CompareChangeKind {
  inserted('Inserted'),
  deleted('Deleted'),
  replaced('Replaced'),
  changed('Changed'),
  moved('Moved');

  const CompareChangeKind(this.label);

  final String label;
}

/// Highlight palette shared by in-page highlights, the change list, the
/// legend and the PDF report (0xRRGGBB).
const compareInsertRgb = 0x1E9E4A;
const compareDeleteRgb = 0xE0342F;
const compareReplaceRgb = 0xE59A0C;
const compareChangedRgb = 0x2F6FDE;

int compareKindRgb(CompareChangeKind k) => switch (k) {
  CompareChangeKind.inserted => compareInsertRgb,
  CompareChangeKind.deleted => compareDeleteRgb,
  CompareChangeKind.replaced => compareReplaceRgb,
  CompareChangeKind.changed || CompareChangeKind.moved => compareChangedRgb,
};

int compareChangeRgb(CompareChange c) => compareKindRgb(c.kind);

/// One aligned row of the side-by-side view. A null side is a page that only
/// exists in the other document.
class ComparePagePair {
  const ComparePagePair(this.a, this.b);

  final int? a;
  final int? b;

  bool get isInserted => a == null;
  bool get isDeleted => b == null;
}

class CompareChange {
  const CompareChange({
    required this.id,
    required this.category,
    required this.kind,
    required this.row,
    this.oldText = '',
    this.newText = '',
    this.detail,
    this.aRects = const {},
    this.bRects = const {},
    this.aPage,
    this.bPage,
  });

  final int id;
  final CompareCategory category;
  final CompareChangeKind kind;

  /// Index into [CompareResult.rows] where this change starts.
  final int row;
  final String oldText;
  final String newText;
  final String? detail;

  /// Highlight rectangles by 0-based page index of the old / new document.
  final Map<int, List<NormRect>> aRects;
  final Map<int, List<NormRect>> bRects;

  /// Anchor pages for navigation (0-based).
  final int? aPage;
  final int? bPage;

  String get title {
    switch (category) {
      case CompareCategory.text:
        return switch (kind) {
          CompareChangeKind.inserted => 'Inserted text',
          CompareChangeKind.deleted => 'Deleted text',
          _ => 'Replaced text',
        };
      case CompareCategory.formatting:
        return 'Formatting changed';
      case CompareCategory.images:
        return switch (kind) {
          CompareChangeKind.inserted => 'Image added',
          CompareChangeKind.deleted => 'Image removed',
          CompareChangeKind.replaced => 'Image replaced',
          _ => 'Image moved or resized',
        };
      case CompareCategory.annotations:
        return switch (kind) {
          CompareChangeKind.inserted => 'Annotation added',
          CompareChangeKind.deleted => 'Annotation removed',
          _ => 'Annotation changed',
        };
      case CompareCategory.pages:
        return switch (kind) {
          CompareChangeKind.inserted => 'Page inserted',
          CompareChangeKind.deleted => 'Page deleted',
          CompareChangeKind.moved => 'Page moved',
          _ => 'Page changed',
        };
    }
  }
}

class CompareResult {
  CompareResult({
    required this.oldDoc,
    required this.newDoc,
    required this.rows,
    required this.changes,
    required this.elapsed,
    this.movedAtoB = const {},
  }) : rowOfA = {
         for (var i = 0; i < rows.length; i++)
           if (rows[i].a != null) rows[i].a!: i,
       },
       rowOfB = {
         for (var i = 0; i < rows.length; i++)
           if (rows[i].b != null) rows[i].b!: i,
       },
       movedBtoA = {for (final e in movedAtoB.entries) e.value: e.key};

  final CompareDocData oldDoc;
  final CompareDocData newDoc;
  final List<ComparePagePair> rows;
  final List<CompareChange> changes;
  final Duration elapsed;
  final Map<int, int> rowOfA;
  final Map<int, int> rowOfB;

  /// Pages that exist in both documents at different positions.
  final Map<int, int> movedAtoB;
  final Map<int, int> movedBtoA;

  bool get formattingAvailable => oldDoc.hasFontInfo && newDoc.hasFontInfo;
  bool get imagesAvailable => oldDoc.hasImageInfo && newDoc.hasImageInfo;

  int count(CompareCategory c) => changes.where((e) => e.category == c).length;

  int countKind(CompareCategory c, CompareChangeKind k) =>
      changes.where((e) => e.category == c && e.kind == k).length;

  int countOfKind(CompareChangeKind k) =>
      changes.where((e) => e.kind == k).length;

  /// Distinct old / new pages touched by at least one change.
  ({int oldPages, int newPages}) get pagesAffected {
    final a = <int>{};
    final b = <int>{};
    for (final c in changes) {
      a.addAll(c.aRects.keys);
      b.addAll(c.bRects.keys);
    }
    return (oldPages: a.length, newPages: b.length);
  }

  bool get identical => changes.isEmpty;
}
