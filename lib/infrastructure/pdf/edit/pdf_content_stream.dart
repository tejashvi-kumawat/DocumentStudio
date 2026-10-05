import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio/infrastructure/pdf/edit/pdf_content_builder.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_objects.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_parser.dart';

/// One operand token of a content-stream operation (byte range in the stream).
class ContentToken {
  const ContentToken(this.start, this.end, this.text);

  final int start;
  final int end;

  /// Raw source text of the token (names keep their `/`, strings their
  /// delimiters, arrays / dictionaries the whole bracketed span).
  final String text;

  double? get number => double.tryParse(text);
  bool get isName => text.startsWith('/');
  String get name => text.substring(1);
}

/// One operator with its operands. [start]..[end] spans operands + operator.
class ContentOp {
  ContentOp(this.name, this.operands, this.start, this.end);

  final String name;
  final List<ContentToken> operands;
  final int start;
  final int end;

  double num(int i) => operands[i].number ?? 0;
}

bool _white(int c) =>
    c == 0x20 || c == 0x0a || c == 0x0d || c == 0x09 || c == 0x0c || c == 0;
bool _delim(int c) =>
    c == 0x28 ||
    c == 0x29 ||
    c == 0x3c ||
    c == 0x3e ||
    c == 0x5b ||
    c == 0x5d ||
    c == 0x7b ||
    c == 0x7d ||
    c == 0x2f ||
    c == 0x25;

/// Splits a content stream into operations. Inline images are kept as one
/// `BI` operation so their binary data is never mistaken for operators.
List<ContentOp> parseContentOps(Uint8List d) {
  final ops = <ContentOp>[];
  var operands = <ContentToken>[];
  var opStart = -1;
  var i = 0;
  final n = d.length;

  int skipString(int from) {
    var depth = 0;
    var p = from;
    while (p < n) {
      final c = d[p];
      if (c == 0x5c) {
        p += 2;
        continue;
      }
      if (c == 0x28) depth++;
      if (c == 0x29) {
        depth--;
        if (depth == 0) return p + 1;
      }
      p++;
    }
    return n;
  }

  int skipBalanced(int from, int open, int close) {
    var depth = 0;
    var p = from;
    while (p < n) {
      final c = d[p];
      if (c == 0x28) {
        p = skipString(p);
        continue;
      }
      if (c == open) depth++;
      if (c == close) {
        depth--;
        if (depth == 0) return p + 1;
      }
      p++;
    }
    return n;
  }

  while (i < n) {
    final c = d[i];
    if (_white(c)) {
      i++;
      continue;
    }
    if (c == 0x25) {
      while (i < n && d[i] != 0x0a && d[i] != 0x0d) {
        i++;
      }
      continue;
    }
    final tokStart = i;
    if (opStart < 0) opStart = i;
    if (c == 0x28) {
      i = skipString(i);
      operands.add(ContentToken(tokStart, i, latin1.decode(d.sublist(tokStart, i))));
    } else if (c == 0x5b) {
      i = skipBalanced(i, 0x5b, 0x5d);
      operands.add(ContentToken(tokStart, i, latin1.decode(d.sublist(tokStart, i))));
    } else if (c == 0x3c && i + 1 < n && d[i + 1] == 0x3c) {
      var depth = 0;
      var p = i;
      while (p + 1 < n) {
        if (d[p] == 0x3c && d[p + 1] == 0x3c) {
          depth++;
          p += 2;
        } else if (d[p] == 0x3e && d[p + 1] == 0x3e) {
          depth--;
          p += 2;
          if (depth == 0) break;
        } else {
          p++;
        }
      }
      i = p;
      operands.add(ContentToken(tokStart, i, latin1.decode(d.sublist(tokStart, i))));
    } else if (c == 0x3c) {
      while (i < n && d[i] != 0x3e) {
        i++;
      }
      i = math.min(n, i + 1);
      operands.add(ContentToken(tokStart, i, latin1.decode(d.sublist(tokStart, i))));
    } else if (c == 0x2f) {
      i++;
      while (i < n && !_white(d[i]) && !_delim(d[i])) {
        i++;
      }
      operands.add(ContentToken(tokStart, i, latin1.decode(d.sublist(tokStart, i))));
    } else if (_delim(c)) {
      i++; // stray delimiter
      opStart = -1;
      operands = [];
    } else {
      while (i < n && !_white(d[i]) && !_delim(d[i])) {
        i++;
      }
      final word = latin1.decode(d.sublist(tokStart, i));
      final isNumber = double.tryParse(word) != null;
      final isKeyword = word == 'true' || word == 'false' || word == 'null';
      if (isNumber || isKeyword) {
        operands.add(ContentToken(tokStart, i, word));
      } else if (word == 'BI') {
        // Inline image: skip to "EI" that follows image data.
        var p = i;
        var idAt = -1;
        while (p + 1 < n) {
          if (d[p] == 0x49 && d[p + 1] == 0x44 && (p == 0 || _white(d[p - 1]))) {
            idAt = p + 2;
            break;
          }
          p++;
        }
        var end = n;
        if (idAt > 0) {
          var q = idAt;
          while (q + 1 < n) {
            if (d[q] == 0x45 &&
                d[q + 1] == 0x49 &&
                _white(d[q - 1]) &&
                (q + 2 >= n || _white(d[q + 2]))) {
              end = q + 2;
              break;
            }
            q++;
          }
        }
        ops.add(ContentOp('BI', const [], opStart, end));
        i = end;
        operands = [];
        opStart = -1;
        continue;
      } else {
        ops.add(ContentOp(word, operands, opStart, i));
        operands = [];
        opStart = -1;
      }
    }
  }
  return ops;
}

// ---------------------------------------------------------------- matrices

typedef Mat = List<double>;

const Mat kIdentity = [1, 0, 0, 1, 0, 0];

/// Row-vector convention: apply [m] first, then [n].
Mat matMul(Mat m, Mat n) => [
      m[0] * n[0] + m[1] * n[2],
      m[0] * n[1] + m[1] * n[3],
      m[2] * n[0] + m[3] * n[2],
      m[2] * n[1] + m[3] * n[3],
      m[4] * n[0] + m[5] * n[2] + n[4],
      m[4] * n[1] + m[5] * n[3] + n[5],
    ];

Mat? matInverse(Mat m) {
  final det = m[0] * m[3] - m[1] * m[2];
  if (det.abs() < 1e-12) return null;
  return [
    m[3] / det,
    -m[1] / det,
    -m[2] / det,
    m[0] / det,
    (m[2] * m[5] - m[3] * m[4]) / det,
    (m[1] * m[4] - m[0] * m[5]) / det,
  ];
}

(double, double) matApply(Mat m, double x, double y) =>
    (m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]);

/// Bounding box `[l, b, r, t]` of the unit square under [m].
List<double> unitSquareBounds(Mat m) {
  final pts = [
    matApply(m, 0, 0),
    matApply(m, 1, 0),
    matApply(m, 0, 1),
    matApply(m, 1, 1),
  ];
  final xs = pts.map((p) => p.$1);
  final ys = pts.map((p) => p.$2);
  return [xs.reduce(math.min), ys.reduce(math.min), xs.reduce(math.max), ys.reduce(math.max)];
}

String _fmt(double v) {
  final s = v.toStringAsFixed(4);
  return s.contains('.') ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : s;
}

String formatMatrix(Mat m) => m.map(_fmt).join(' ');

// ---------------------------------------------------------------- analysis

/// An image painted by a `Do` operator on the page (not inside a form).
class PageImagePlacement {
  PageImagePlacement({
    required this.name,
    required this.ctm,
    required this.op,
  });

  final String name;

  /// Unit square → user space at the moment of painting.
  final Mat ctm;
  final ContentOp op;

  /// `[l, b, r, t]` in user space.
  List<double> get bounds => unitSquareBounds(ctm);
}

/// A text-showing operation with its estimated origin in user space.
class PageTextShow {
  PageTextShow({
    required this.op,
    required this.x,
    required this.y,
    required this.fontSize,
    required this.renderMode,
    required this.followedByPosition,
    this.fontKey = '',
  });

  final ContentOp op;
  final double x;
  final double y;
  final double fontSize;
  final int renderMode;

  /// The next operation re-positions the text (or ends it), so removing this
  /// show op cannot shift later text.
  final bool followedByPosition;

  /// Font resource name (`/F1` → `F1`) in effect for this show op.
  final String fontKey;
}

/// A form XObject painted by a `Do` (text and images can live inside).
class FormUse {
  FormUse({required this.name, required this.ctm});

  final String name;
  final Mat ctm;
}

/// A painted vector path (line, rectangle, curve…).
class PageShape {
  PageShape({
    required this.opStart,
    required this.opEnd,
    required this.bounds,
    required this.fill,
    required this.stroke,
    required this.ctm,
  });

  /// Byte range from the first path operator to the paint operator.
  final int opStart;
  final int opEnd;

  /// `[l, b, r, t]` in user space.
  final List<double> bounds;
  final bool fill;
  final bool stroke;
  final Mat ctm;
}

class PageContentAnalysis {
  PageContentAnalysis(
    this.bytes,
    this.ops,
    this.images,
    this.texts, [
    this.forms = const [],
    this.shapes = const [],
  ]);

  final List<FormUse> forms;
  final List<PageShape> shapes;

  final Uint8List bytes;
  final List<ContentOp> ops;
  final List<PageImagePlacement> images;
  final List<PageTextShow> texts;
}

const _showOps = {'Tj', 'TJ', "'", '"'};
const _positionOps = {'Td', 'TD', 'Tm', 'T*', 'ET', 'BT'};

/// Walks [ops], tracking the CTM and text matrices.
///
/// [imageNames] are the page's image XObject names; only those `Do` calls are
/// reported (forms are skipped).
PageContentAnalysis analyzeContent(
  Uint8List bytes, {
  required Set<String> imageNames,
  Set<String> formNames = const {},
  Mat initialCtm = kIdentity,
}) {
  final ops = parseContentOps(bytes);
  final images = <PageImagePlacement>[];
  final texts = <PageTextShow>[];
  final forms = <FormUse>[];
  final shapes = <PageShape>[];
  // Path under construction.
  int pathStart = -1;
  double pMinX = 0, pMinY = 0, pMaxX = 0, pMaxY = 0;
  var pathHasPoints = false;
  var clipPending = false;

  var ctm = initialCtm;
  final stack = <Mat>[];

  void addPoint(double x, double y) {
    final u = matApply(ctm, x, y);
    if (!pathHasPoints) {
      pMinX = pMaxX = u.$1;
      pMinY = pMaxY = u.$2;
      pathHasPoints = true;
    } else {
      pMinX = math.min(pMinX, u.$1);
      pMaxX = math.max(pMaxX, u.$1);
      pMinY = math.min(pMinY, u.$2);
      pMaxY = math.max(pMaxY, u.$2);
    }
  }
  var tm = kIdentity;
  var tlm = kIdentity;
  var fontSize = 12.0;
  var fontKey = '';
  var leading = 0.0;
  var charSpace = 0.0;
  var wordSpace = 0.0;
  var hScale = 1.0;
  var rise = 0.0;
  var renderMode = 0;

  double advanceFor(ContentOp op) {
    var chars = 0;
    var spaces = 0;
    for (final t in op.operands) {
      final s = t.text;
      if (s.startsWith('(') || s.startsWith('[') || s.startsWith('<')) {
        chars += s.length;
        spaces += ' '.allMatches(s).length;
      }
    }
    return (chars * 0.5 * fontSize + chars * charSpace + spaces * wordSpace) * hScale;
  }

  for (var i = 0; i < ops.length; i++) {
    final op = ops[i];
    switch (op.name) {
      case 'm':
      case 'l':
        if (op.operands.length >= 2) {
          if (pathStart < 0) pathStart = op.start;
          addPoint(op.num(0), op.num(1));
        }
      case 'c':
        if (op.operands.length >= 6) {
          if (pathStart < 0) pathStart = op.start;
          addPoint(op.num(0), op.num(1));
          addPoint(op.num(2), op.num(3));
          addPoint(op.num(4), op.num(5));
        }
      case 'v':
      case 'y':
        if (op.operands.length >= 4) {
          if (pathStart < 0) pathStart = op.start;
          addPoint(op.num(0), op.num(1));
          addPoint(op.num(2), op.num(3));
        }
      case 're':
        if (op.operands.length >= 4) {
          if (pathStart < 0) pathStart = op.start;
          final x = op.num(0), y = op.num(1), w = op.num(2), h = op.num(3);
          addPoint(x, y);
          addPoint(x + w, y + h);
        }
      case 'W':
      case 'W*':
        clipPending = true;
      case 'S':
      case 's':
      case 'f':
      case 'F':
      case 'f*':
      case 'B':
      case 'B*':
      case 'b':
      case 'b*':
      case 'n':
        if (pathStart >= 0 && pathHasPoints && !clipPending && op.name != 'n') {
          final fill = op.name != 'S' && op.name != 's';
          final stroke = op.name == 'S' ||
              op.name == 's' ||
              op.name.startsWith('B') ||
              op.name.startsWith('b');
          shapes.add(
            PageShape(
              opStart: pathStart,
              opEnd: op.end,
              bounds: [pMinX, pMinY, pMaxX, pMaxY],
              fill: fill,
              stroke: stroke,
              ctm: ctm,
            ),
          );
        }
        pathStart = -1;
        pathHasPoints = false;
        clipPending = false;
      case 'q':
        stack.add(ctm);
      case 'Q':
        if (stack.isNotEmpty) ctm = stack.removeLast();
      case 'cm':
        if (op.operands.length >= 6) {
          ctm = matMul([for (var k = 0; k < 6; k++) op.num(k)], ctm);
        }
      case 'BT':
        tm = kIdentity;
        tlm = kIdentity;
      case 'Tf':
        if (op.operands.length >= 2) {
          fontSize = op.num(1).abs();
          if (op.operands.first.isName) fontKey = op.operands.first.name;
        }
      case 'TL':
        if (op.operands.isNotEmpty) leading = op.num(0);
      case 'Tc':
        if (op.operands.isNotEmpty) charSpace = op.num(0);
      case 'Tw':
        if (op.operands.isNotEmpty) wordSpace = op.num(0);
      case 'Tz':
        if (op.operands.isNotEmpty) hScale = op.num(0) / 100;
      case 'Ts':
        if (op.operands.isNotEmpty) rise = op.num(0);
      case 'Tr':
        if (op.operands.isNotEmpty) renderMode = op.num(0).round();
      case 'Td':
        if (op.operands.length >= 2) {
          tlm = matMul([1, 0, 0, 1, op.num(0), op.num(1)], tlm);
          tm = tlm;
        }
      case 'TD':
        if (op.operands.length >= 2) {
          leading = -op.num(1);
          tlm = matMul([1, 0, 0, 1, op.num(0), op.num(1)], tlm);
          tm = tlm;
        }
      case 'Tm':
        if (op.operands.length >= 6) {
          tlm = [for (var k = 0; k < 6; k++) op.num(k)];
          tm = tlm;
        }
      case 'T*':
        tlm = matMul([1, 0, 0, 1, 0, -leading], tlm);
        tm = tlm;
      case 'Do':
        if (op.operands.isNotEmpty &&
            op.operands.first.isName &&
            formNames.contains(op.operands.first.name)) {
          forms.add(FormUse(name: op.operands.first.name, ctm: ctm));
        }
        if (op.operands.isNotEmpty &&
            op.operands.first.isName &&
            imageNames.contains(op.operands.first.name)) {
          images.add(
            PageImagePlacement(
              name: op.operands.first.name,
              ctm: ctm,
              op: op,
            ),
          );
        }
      default:
        if (_showOps.contains(op.name)) {
          if (op.name == "'" || op.name == '"') {
            tlm = matMul([1, 0, 0, 1, 0, -leading], tlm);
            tm = tlm;
          }
          final full = matMul(tm, ctm);
          final o = matApply(full, 0, rise);
          // Next significant op decides whether removal is shift-safe.
          var follow = true;
          for (var j = i + 1; j < ops.length; j++) {
            final nx = ops[j].name;
            if (_showOps.contains(nx)) {
              follow = false;
              break;
            }
            if (_positionOps.contains(nx)) break;
          }
          final scale = math.sqrt(full[0] * full[0] + full[1] * full[1]);
          texts.add(
            PageTextShow(
              op: op,
              x: o.$1,
              y: o.$2,
              fontSize: fontSize * (scale == 0 ? 1 : scale),
              renderMode: renderMode,
              followedByPosition: follow,
              fontKey: fontKey,
            ),
          );
          tm = matMul([1, 0, 0, 1, advanceFor(op), 0], tm);
        }
    }
  }
  return PageContentAnalysis(bytes, ops, images, texts, forms, shapes);
}

// ---------------------------------------------------------------- page I/O

/// Decoded, concatenated content of [page1] — null when a stream uses a
/// filter the editor cannot decode.
Uint8List? readPageContent(PdfEditDocument doc, int page1) {
  final page = doc.pageDict(page1);
  final c = doc.resolve(page['Contents']);
  final out = BytesBuilder();
  void add(PdfObj? o) {
    final r = doc.resolve(o);
    if (r is PdfStream) {
      out.add(decodeStreamData(r.dict, r.data));
      out.addByte(0x0a);
    }
  }

  try {
    if (c is PdfArray) {
      for (final item in c.items) {
        add(item);
      }
    } else {
      add(page['Contents']);
    }
  } catch (_) {
    return null;
  }
  return out.toBytes();
}

/// Image XObject names visible to the page's own content.
Set<String> pageImageNames(PdfEditDocument doc, int page1) {
  final page = doc.pageDict(page1);
  final res = doc.dictOf(doc.inherited(page, 'Resources'));
  final xo = doc.dictOf(res?['XObject']);
  if (xo == null) return const {};
  final out = <String>{};
  for (final e in xo.entries.entries) {
    final o = doc.resolve(e.value);
    final d = o is PdfStream ? o.dict : (o is PdfDict ? o : null);
    if (d != null && d.nameOf('Subtype') == 'Image') out.add(e.key);
  }
  return out;
}

/// Replaces the page's content with [content] (single Flate stream).
void writePageContent(PdfEditDocument doc, int page1, Uint8List content) {
  final ref = doc.addObject(flateStream(PdfDict(), content));
  final pageRef = doc.pageRef(page1);
  final page = doc.pageDict(page1).clone();
  page['Contents'] = ref;
  doc.setObject(pageRef, page);
}

/// Applies byte-range edits (`start`, `end`, replacement) to [src].
Uint8List applyRangeEdits(
  Uint8List src,
  List<({int start, int end, String text})> edits,
) {
  final sorted = [...edits]..sort((a, b) => a.start.compareTo(b.start));
  final out = BytesBuilder();
  var pos = 0;
  for (final e in sorted) {
    if (e.start < pos) continue;
    out.add(src.sublist(pos, e.start));
    out.add(latin1.encode(e.text));
    pos = e.end;
  }
  out.add(src.sublist(pos));
  return out.toBytes();
}


/// Page font resource name → BaseFont (subset prefix `ABCDEF+` removed).
Map<String, String> pageFontBaseNames(PdfEditDocument doc, int page1) {
  final page = doc.pageDict(page1);
  final res = doc.dictOf(doc.inherited(page, 'Resources'));
  final fonts = doc.dictOf(res?['Font']);
  if (fonts == null) return const {};
  final out = <String, String>{};
  for (final e in fonts.entries.entries) {
    final f = doc.dictOf(e.value);
    var base = f?.nameOf('BaseFont');
    if (base == null) continue;
    final plus = base.indexOf('+');
    if (plus == 6) base = base.substring(7);
    out[e.key] = base;
  }
  return out;
}


/// Image XObject name → object number for the page's own resources.
Map<String, int> pageImageRefs(PdfEditDocument doc, int page1) {
  final page = doc.pageDict(page1);
  final res = doc.dictOf(doc.inherited(page, 'Resources'));
  final xo = doc.dictOf(res?['XObject']);
  if (xo == null) return const {};
  final out = <String, int>{};
  for (final e in xo.entries.entries) {
    final v = e.value;
    if (v is! PdfRef) continue;
    final o = doc.resolve(v);
    final d = o is PdfStream ? o.dict : (o is PdfDict ? o : null);
    if (d != null && d.nameOf('Subtype') == 'Image') out[e.key] = v.num;
  }
  return out;
}

/// For every image on every page: the pixel size (longest edge) needed to
/// show it at [dpi] where it is actually drawn. An image drawn at 2 inches
/// does not need more than `2 × dpi` pixels, however large the file is.
/// Images drawn more than once keep the largest requirement.
Map<int, int> imageNeededPixels(PdfEditDocument doc, double dpi) {
  final needed = <int, double>{};
  for (var p = 1; p <= doc.pageCount; p++) {
    try {
      final refs = pageImageRefs(doc, p);
      if (refs.isEmpty) continue;
      final content = readPageContent(doc, p);
      if (content == null) continue;
      final a = analyzeContent(content, imageNames: refs.keys.toSet());
      for (final img in a.images) {
        final obj = refs[img.name];
        if (obj == null) continue;
        final b = img.bounds;
        final pts = math.max(b[2] - b[0], b[3] - b[1]);
        final px = pts * dpi / 72;
        needed[obj] = math.max(needed[obj] ?? 0, px);
      }
    } catch (_) {}
  }
  return {for (final e in needed.entries) e.key: e.value.ceil()};
}


/// Form XObject name → reference, from a resources dictionary.
Map<String, PdfRef> formRefsIn(PdfEditDocument doc, PdfDict? resources) {
  final xo = doc.dictOf(resources?['XObject']);
  if (xo == null) return const {};
  final out = <String, PdfRef>{};
  for (final e in xo.entries.entries) {
    final v = e.value;
    if (v is! PdfRef) continue;
    final o = doc.resolve(v);
    if (o is PdfStream && o.dict.nameOf('Subtype') == 'Form') out[e.key] = v;
  }
  return out;
}
