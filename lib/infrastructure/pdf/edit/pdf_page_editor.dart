import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:document_studio/infrastructure/pdf/edit/pdf_content_builder.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_content_stream.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_font_identity.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_objects.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_parser.dart';

/// An image on a page that "Edit PDF" can select, move, resize, replace or
/// delete. Rects are normalized (0..1), top-left origin, displayed
/// orientation.
enum EditableKind {
  image,
  shape,

  /// A comment, drawing, stamp, note… stored as a PDF annotation.
  annotation,
}

class EditableImage {
  const EditableImage({
    required this.page,
    required this.name,
    required this.opStart,
    required this.normRect,
    this.kind = EditableKind.image,
    this.form = 0,
  });

  /// Object number of the form XObject whose content draws it (0 = drawn by
  /// the page itself). PDFs from browsers and Office often wrap the whole
  /// page in forms, so pictures and shapes are edited where they live.
  final int form;

  /// A picture, or a painted vector path (rectangle, line, curve…).
  final EditableKind kind;

  final int page;
  final String name;

  /// Byte offset of the `Do` operation in the page's decoded content. Valid
  /// until the page content changes.
  final int opStart;
  final Rect normRect;

  /// Human label (e.g. "Ink drawing", "Highlight", "Image").
  String get label => switch (kind) {
    EditableKind.image => 'Image',
    EditableKind.shape => 'Shape',
    EditableKind.annotation => annotationLabel(name),
  };
}

/// Friendly name of an annotation /Subtype.
String annotationLabel(String subtype) => switch (subtype) {
  'Ink' => 'Drawing',
  'FreeText' => 'Text box',
  'Text' => 'Sticky note',
  'Square' => 'Rectangle',
  'Circle' => 'Ellipse',
  'Line' => 'Line',
  'Polygon' => 'Polygon',
  'PolyLine' => 'Polyline',
  'Highlight' => 'Highlight',
  'Underline' => 'Underline',
  'StrikeOut' => 'Strikethrough',
  'Squiggly' => 'Squiggly',
  'Stamp' => 'Stamp / image',
  'FileAttachment' => 'Attachment',
  'Caret' => 'Caret',
  'Sound' => 'Sound',
  'Redact' => 'Redaction mark',
  _ => subtype,
};

const _skipAnnots = {'Link', 'Widget', 'Popup'};

/// Annotations on [page1] that Edit can move, resize or delete (drawings,
/// shapes, stamps, notes, text boxes, highlights…). Links, form fields and
/// popups are left alone. [EditableImage.opStart] is the index in /Annots.
List<EditableImage> findPageAnnotations(Uint8List bytes, int page1) {
  try {
    final doc = PdfEditDocument.open(bytes);
    final items = doc.pageAnnotItems(page1);
    final out = <EditableImage>[];
    for (var i = 0; i < items.length; i++) {
      final d = doc.dictOf(items[i]);
      if (d == null) continue;
      final sub = doc.resolve(d['Subtype']);
      final name = sub is PdfName ? sub.name : '';
      if (_skipAnnots.contains(name)) continue;
      final flags = doc.numOf(d['F'])?.round() ?? 0;
      if (flags & 2 != 0) continue; // hidden
      final rect = _annotRect(doc, d);
      if (rect == null) continue;
      final n = _userToNorm(doc, page1, rect);
      if (n.width <= 0 || n.height <= 0) continue;
      out.add(
        EditableImage(
          page: page1,
          name: name,
          opStart: i,
          normRect: n,
          kind: EditableKind.annotation,
        ),
      );
    }
    return out;
  } catch (_) {
    return const [];
  }
}

List<double>? _annotRect(PdfEditDocument doc, PdfDict d) {
  final r = doc.resolve(d['Rect']);
  if (r is! PdfArray || r.items.length < 4) return null;
  final v = [for (final n in r.items.take(4)) doc.numOf(n) ?? 0.0];
  return [
    math.min(v[0], v[2]),
    math.min(v[1], v[3]),
    math.max(v[0], v[2]),
    math.max(v[1], v[3]),
  ];
}

/// Finds the annotation at [index] again, checking it is still the one the
/// user saw (same subtype); null otherwise.
(PdfObj item, PdfDict dict)? _annotAt(
  PdfEditDocument doc,
  int page1,
  int index,
  String subtype,
) {
  final items = doc.pageAnnotItems(page1);
  if (index < 0 || index >= items.length) return null;
  final d = doc.dictOf(items[index]);
  if (d == null) return null;
  final sub = doc.resolve(d['Subtype']);
  if (sub is! PdfName || sub.name != subtype) return null;
  return (items[index], d);
}

/// Removes the annotation at [index] (and its popup).
Uint8List? deletePageAnnotation(
  Uint8List bytes,
  int page1,
  int index,
  String subtype,
) {
  try {
    final doc = PdfEditDocument.open(bytes);
    final hit = _annotAt(doc, page1, index, subtype);
    if (hit == null) return null;
    final popup = hit.$2['Popup'];
    final keep = <PdfObj>[];
    final items = doc.pageAnnotItems(page1);
    for (var i = 0; i < items.length; i++) {
      if (i == index) continue;
      final it = items[i];
      if (popup is PdfRef && it is PdfRef && it.num == popup.num) continue;
      keep.add(it);
    }
    doc.setPageAnnots(page1, keep);
    return doc.save();
  } catch (_) {
    return null;
  }
}

/// Keeps hyperlinks with an edited text block: every link whose centre lies
/// in [fromNorm] is mapped onto [toNorm] (same affine as the block). Returns
/// null when nothing needed to move.
Uint8List? moveLinksWithBlock(
  Uint8List bytes,
  int page1,
  Rect fromNorm,
  Rect toNorm,
) {
  try {
    final doc = PdfEditDocument.open(bytes);
    final items = doc.pageAnnotItems(page1);
    final from = _normToUser(doc, page1, fromNorm);
    final to = _normToUser(doc, page1, toNorm);
    final f = [
      math.min(from[0], from[2]),
      math.min(from[1], from[3]),
      math.max(from[0], from[2]),
      math.max(from[1], from[3]),
    ];
    final t = [
      math.min(to[0], to[2]),
      math.min(to[1], to[3]),
      math.max(to[0], to[2]),
      math.max(to[1], to[3]),
    ];
    final sx = f[2] - f[0] <= 0 ? 1.0 : (t[2] - t[0]) / (f[2] - f[0]);
    final sy = f[3] - f[1] <= 0 ? 1.0 : (t[3] - t[1]) / (f[3] - f[1]);
    var changed = false;
    for (var i = 0; i < items.length; i++) {
      final d = doc.dictOf(items[i]);
      if (d == null) continue;
      final sub = doc.resolve(d['Subtype']);
      if (sub is! PdfName || sub.name != 'Link') continue;
      final r = _annotRect(doc, d);
      if (r == null) continue;
      final cx = (r[0] + r[2]) / 2, cy = (r[1] + r[3]) / 2;
      if (cx < f[0] || cx > f[2] || cy < f[1] || cy > f[3]) continue;
      // Links keep their size; the anchor follows the block.
      final nx = t[0] + (r[0] - f[0]) * sx;
      final ny = t[1] + (r[1] - f[1]) * sy;
      final next = d.clone()
        ..['Rect'] = PdfArray.nums([
          nx,
          ny,
          nx + r[2] - r[0],
          ny + r[3] - r[1],
        ]);
      next.remove('QuadPoints');
      final item = items[i];
      if (item is PdfRef) {
        doc.setObject(item, next);
      } else {
        items[i] = next;
        doc.setPageAnnots(page1, items);
      }
      changed = true;
    }
    return changed ? doc.save() : null;
  } catch (_) {
    return null;
  }
}

/// Same place on the page: overlap of at least half, or the same centre
/// and size.
bool _sameLinkRect(Rect a, Rect b) {
  final inter = a.intersect(b);
  if (inter.width > 0 && inter.height > 0) {
    final area = inter.width * inter.height;
    final union = a.width * a.height + b.width * b.height - area;
    if (union > 0 && area / union >= 0.5) return true;
  }
  return (a.center.dx - b.center.dx).abs() <= 0.01 &&
      (a.center.dy - b.center.dy).abs() <= 0.01 &&
      (a.width - b.width).abs() <= 0.02 &&
      (a.height - b.height).abs() <= 0.02;
}

/// Link annotations on [page1] whose place matches [norm] are dropped from
/// the list; returns how many.
int _dropLinksAt(
  PdfEditDocument doc,
  int page1,
  Rect norm,
  List<PdfObj> items,
) {
  var removed = 0;
  items.removeWhere((it) {
    final d = doc.dictOf(it);
    final sub = d == null ? null : doc.resolve(d['Subtype']);
    if (d == null || sub is! PdfName || sub.name != 'Link') return false;
    final r = _annotRect(doc, d);
    if (r == null) return false;
    if (_sameLinkRect(_userToNorm(doc, page1, r), norm)) {
      removed++;
      return true;
    }
    return false;
  });
  return removed;
}

/// Adds a Link annotation (web address, or jump to [destPage1]) at [rect]
/// (normalized display space), replacing the link at [replaceNorm] when
/// given. Null when the page cannot be edited or the link to replace is
/// gone.
Uint8List? addPageLink(
  Uint8List bytes,
  int page1, {
  required Rect rect,
  String? uri,
  int? destPage1,
  bool visibleBorder = false,
  Rect? replaceNorm,
}) {
  try {
    final doc = PdfEditDocument.open(bytes);
    final items = doc.pageAnnotItems(page1);
    if (replaceNorm != null &&
        _dropLinksAt(doc, page1, replaceNorm, items) == 0)
      return null;
    final PdfDict action;
    if (uri != null) {
      var u = uri.trim();
      if (!u.contains('://') && !u.startsWith('mailto:') && !u.startsWith('#'))
        u = 'https://$u';
      action = PdfDict({
        'S': const PdfName('URI'),
        'URI': PdfString(Uint8List.fromList(u.codeUnits)),
      });
    } else if (destPage1 != null &&
        destPage1 >= 1 &&
        destPage1 <= doc.pageCount) {
      action = PdfDict({
        'S': const PdfName('GoTo'),
        'D': PdfArray([doc.pageRef(destPage1), const PdfName('Fit')]),
      });
    } else {
      return null;
    }
    final u = _normToUser(doc, page1, rect);
    final box = [
      math.min(u[0], u[2]),
      math.min(u[1], u[3]),
      math.max(u[0], u[2]),
      math.max(u[1], u[3]),
    ];
    final annot = doc.addObject(
      PdfDict({
        'Type': const PdfName('Annot'),
        'Subtype': const PdfName('Link'),
        'Rect': PdfArray.nums(box),
        'P': doc.pageRef(page1),
        'F': const PdfNum(4),
        'H': const PdfName('I'),
        'Border': PdfArray.nums(visibleBorder ? [0, 0, 1] : [0, 0, 0]),
        if (visibleBorder) 'C': PdfArray.nums([0, 0, 1]),
        'A': action,
      }),
    );
    items.add(annot);
    doc.setPageAnnots(page1, items);
    return doc.save();
  } catch (_) {
    return null;
  }
}

/// Removes the Link annotations at [norm] on [page1]; null when none match.
Uint8List? removePageLinks(Uint8List bytes, int page1, Rect norm) {
  try {
    final doc = PdfEditDocument.open(bytes);
    final items = doc.pageAnnotItems(page1);
    if (_dropLinksAt(doc, page1, norm, items) == 0) return null;
    doc.setPageAnnots(page1, items);
    return doc.save();
  } catch (_) {
    return null;
  }
}

/// Moves / resizes the annotation at [index] to [newRect] (normalized). The
/// appearance follows /Rect; point lists (ink, quads, vertices, line ends)
/// are mapped too so other readers redraw it in the same place.
Uint8List? transformPageAnnotation(
  Uint8List bytes,
  int page1,
  int index,
  String subtype,
  Rect newRect,
) {
  try {
    final doc = PdfEditDocument.open(bytes);
    final hit = _annotAt(doc, page1, index, subtype);
    if (hit == null) return null;
    final (item, dict) = hit;
    final from = _annotRect(doc, dict);
    if (from == null) return null;
    final to = _normToUser(doc, page1, newRect);
    final t = [
      math.min(to[0], to[2]),
      math.min(to[1], to[3]),
      math.max(to[0], to[2]),
      math.max(to[1], to[3]),
    ];
    final fw = from[2] - from[0];
    final fh = from[3] - from[1];
    final sx = fw <= 0 ? 1.0 : (t[2] - t[0]) / fw;
    final sy = fh <= 0 ? 1.0 : (t[3] - t[1]) / fh;
    double mx(double x) => t[0] + (x - from[0]) * sx;
    double my(double y) => t[1] + (y - from[1]) * sy;
    PdfArray mapPoints(PdfArray a) {
      final out = <PdfObj>[];
      for (var i = 0; i < a.items.length; i++) {
        final v = doc.numOf(a.items[i]) ?? 0.0;
        out.add(PdfNum(i.isEven ? mx(v) : my(v)));
      }
      return PdfArray(out);
    }

    final next = dict.clone();
    next['Rect'] = PdfArray.nums(t);
    for (final key in ['QuadPoints', 'Vertices', 'L', 'CL']) {
      final a = doc.resolve(next[key]);
      if (a is PdfArray) next[key] = mapPoints(a);
    }
    final ink = doc.resolve(next['InkList']);
    if (ink is PdfArray) {
      next['InkList'] = PdfArray([
        for (final s in ink.items)
          if (doc.resolve(s) case final PdfArray path) mapPoints(path),
      ]);
    }
    // Text markup and drawings are best redrawn by readers from their points;
    // the stored appearance still scales with /Rect.
    if (item is PdfRef) {
      doc.setObject(item, next);
    } else {
      final items = doc.pageAnnotItems(page1);
      items[index] = next;
      doc.setPageAnnots(page1, items);
    }
    return doc.save();
  } catch (_) {
    return null;
  }
}

Rect _userToNorm(PdfEditDocument doc, int page1, List<double> b) {
  final g = doc.pageGeometry(page1);
  final r = g.userRectToDisplay(b);
  return Rect.fromLTRB(
    r.left / g.displayWidth,
    r.top / g.displayHeight,
    r.right / g.displayWidth,
    r.bottom / g.displayHeight,
  );
}

List<double> _normToUser(PdfEditDocument doc, int page1, Rect n) {
  final g = doc.pageGeometry(page1);
  return g.displayRectToUser(
    Rect.fromLTRB(
      n.left * g.displayWidth,
      n.top * g.displayHeight,
      n.right * g.displayWidth,
      n.bottom * g.displayHeight,
    ),
  );
}

PageContentAnalysis? _analyze(PdfEditDocument doc, int page1) {
  final content = readPageContent(doc, page1);
  if (content == null) return null;
  return analyzeContent(content, imageNames: pageImageNames(doc, page1));
}

/// One content stream that paints on the page: the page itself (form 0) or
/// a form XObject it draws, analysed in page user space.
class _Unit {
  _Unit(this.form, this.ref, this.stream, this.resources, this.a);

  final int form;
  final PdfRef? ref;
  final PdfStream? stream;
  final PdfDict? resources;
  final PageContentAnalysis a;
}

Set<String> _imageNamesIn(PdfEditDocument doc, PdfDict? res) {
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

/// The page content plus every form it draws (up to 4 levels deep), each
/// with its own analysis. Forms drawn more than once on the page are
/// skipped: editing one would change every copy.
List<_Unit> _units(PdfEditDocument doc, int page1) {
  final content = readPageContent(doc, page1);
  if (content == null) return const [];
  final page = doc.pageDict(page1);
  final pageRes = doc.dictOf(doc.inherited(page, 'Resources'));
  final pa = analyzeContent(
    content,
    imageNames: _imageNamesIn(doc, pageRes),
    formNames: formRefsIn(doc, pageRes).keys.toSet(),
  );
  final out = <_Unit>[_Unit(0, null, null, pageRes, pa)];
  void walk(PdfDict? res, PageContentAnalysis a, int depth) {
    if (depth > 4) return;
    final refs = formRefsIn(doc, res);
    final uses = <String, int>{};
    for (final f in a.forms) {
      uses[f.name] = (uses[f.name] ?? 0) + 1;
    }
    for (final use in a.forms) {
      final ref = refs[use.name];
      if (ref == null || uses[use.name]! > 1) continue;
      if (out.any((u) => u.form == ref.num)) continue;
      final form = doc.resolve(ref);
      if (form is! PdfStream) continue;
      final m = doc.resolve(form.dict['Matrix']);
      Mat fm = kIdentity;
      if (m is PdfArray && m.length >= 6) {
        fm = [for (var i = 0; i < 6; i++) doc.numOf(m[i]) ?? 0];
      }
      Uint8List data;
      try {
        data = decodeStreamData(form.dict, form.data);
      } catch (_) {
        continue;
      }
      final fres = doc.dictOf(form.dict['Resources']) ?? res;
      final fa = analyzeContent(
        data,
        imageNames: _imageNamesIn(doc, fres),
        formNames: formRefsIn(doc, fres).keys.toSet(),
        initialCtm: matMul(fm, use.ctm),
      );
      out.add(_Unit(ref.num, ref, form, fres, fa));
      walk(fres, fa, depth + 1);
    }
  }

  walk(pageRes, pa, 0);
  return out;
}

_Unit? _unit(PdfEditDocument doc, int page1, int form) {
  for (final u in _units(doc, page1)) {
    if (u.form == form) return u;
  }
  return null;
}

/// Writes [content] back to where [u] came from.
Uint8List _saveUnit(
  PdfEditDocument doc,
  int page1,
  _Unit u,
  Uint8List content,
) {
  if (u.form == 0) return _save(doc, page1, content);
  final d = u.stream!.dict.clone()
    ..remove('DecodeParms')
    ..remove('Length');
  doc.setObject(u.ref!, flateStream(d, content));
  return doc.save();
}

/// Images on [page1], including those inside form XObjects. Never throws.
List<EditableImage> findPageImages(Uint8List bytes, int page1) {
  try {
    final doc = PdfEditDocument.open(bytes);
    return [
      for (final u in _units(doc, page1))
        for (final img in u.a.images)
          EditableImage(
            page: page1,
            name: img.name,
            opStart: img.op.start,
            normRect: _userToNorm(doc, page1, img.bounds),
            form: u.form,
          ),
    ];
  } catch (_) {
    return const [];
  }
}

PageImagePlacement? _imageAt(PageContentAnalysis a, int opStart) {
  for (final i in a.images) {
    if (i.op.start == opStart) return i;
  }
  return null;
}

Uint8List _save(PdfEditDocument doc, int page1, Uint8List content) {
  writePageContent(doc, page1, content);
  return doc.save();
}

/// Removes the image painted at [opStart]. Null when it cannot be found.
Uint8List? deletePageImage(
  Uint8List bytes,
  int page1,
  int opStart, {
  int form = 0,
}) {
  try {
    final doc = PdfEditDocument.open(bytes);
    final u = _unit(doc, page1, form);
    final img = u == null ? null : _imageAt(u.a, opStart);
    if (u == null || img == null) return null;
    final out = applyRangeEdits(u.a.bytes, [
      (start: img.op.start, end: img.op.end, text: ''),
    ]);
    return _saveUnit(doc, page1, u, out);
  } catch (_) {
    return null;
  }
}

/// [S] mapping user bounds [from] onto [to], as `T = C·S·C⁻¹` in the space
/// the object is drawn in (C = its CTM).
Mat? _relocate(Mat ctm, List<double> from, List<double> to) {
  final fw = from[2] - from[0];
  final fh = from[3] - from[1];
  final sx = fw <= 1e-6 ? 1.0 : (to[2] - to[0]) / fw;
  final sy = fh <= 1e-6 ? 1.0 : (to[3] - to[1]) / fh;
  final s = <double>[sx, 0, 0, sy, to[0] - from[0] * sx, to[1] - from[1] * sy];
  final cInv = matInverse(ctm);
  if (cInv == null) return null;
  return matMul(matMul(ctm, s), cInv);
}

List<double> _sorted(List<double> r) => [
  math.min(r[0], r[2]),
  math.min(r[1], r[3]),
  math.max(r[0], r[2]),
  math.max(r[1], r[3]),
];

/// Moves / resizes the image at [opStart] to [newRect] (normalized).
Uint8List? transformPageImage(
  Uint8List bytes,
  int page1,
  int opStart,
  Rect newRect, {
  int form = 0,
}) {
  try {
    final doc = PdfEditDocument.open(bytes);
    final u = _unit(doc, page1, form);
    final img = u == null ? null : _imageAt(u.a, opStart);
    if (u == null || img == null) return null;
    final t = _relocate(
      img.ctm,
      img.bounds,
      _sorted(_normToUser(doc, page1, newRect)),
    );
    if (t == null) return null;
    final out = applyRangeEdits(u.a.bytes, [
      (
        start: img.op.start,
        end: img.op.end,
        text: 'q ${formatMatrix(t)} cm /${img.name} Do Q',
      ),
    ]);
    return _saveUnit(doc, page1, u, out);
  } catch (_) {
    return null;
  }
}

/// Swaps the picture at [opStart] for [encoded] (same rectangle).
Uint8List? replacePageImage(
  Uint8List bytes,
  int page1,
  int opStart,
  Uint8List encoded, {
  int form = 0,
}) {
  try {
    final doc = PdfEditDocument.open(bytes);
    final u = _unit(doc, page1, form);
    final img = u == null ? null : _imageAt(u.a, opStart);
    if (u == null || img == null) return null;
    final x = PdfImageXObject.fromEncoded(encoded);
    if (x == null) return null;
    final dict = x.image.dict.clone();
    if (x.smask != null) dict['SMask'] = doc.addObject(x.smask!);
    final ref = doc.addObject(PdfStream(dict, x.image.data));
    final name = 'DsImg${ref.num}';
    if (u.form == 0) {
      final pageRef = doc.pageRef(page1);
      final page = doc.pageDict(page1).clone();
      final res = (doc.dictOf(doc.inherited(page, 'Resources')) ?? PdfDict())
          .clone();
      final xo = (doc.dictOf(res['XObject']) ?? PdfDict()).clone();
      xo[name] = ref;
      res['XObject'] = xo;
      page['Resources'] = res;
      doc.setObject(pageRef, page);
    } else {
      // The form's own resources get the new picture.
      final fdict = u.stream!.dict.clone();
      final res = (doc.dictOf(fdict['Resources']) ?? PdfDict()).clone();
      final xo = (doc.dictOf(res['XObject']) ?? PdfDict()).clone();
      xo[name] = ref;
      res['XObject'] = xo;
      fdict['Resources'] = res;
      final unit = _Unit(
        u.form,
        u.ref,
        PdfStream(fdict, u.stream!.data),
        res,
        u.a,
      );
      final out = applyRangeEdits(u.a.bytes, [
        (start: img.op.start, end: img.op.end, text: '/$name Do'),
      ]);
      return _saveUnit(doc, page1, unit, out);
    }
    final out = applyRangeEdits(u.a.bytes, [
      (start: img.op.start, end: img.op.end, text: '/$name Do'),
    ]);
    return _saveUnit(doc, page1, u, out);
  } catch (_) {
    return null;
  }
}

/// Removes text-show operations in form XObjects reachable from the page whose
/// origin lies in [pageUserRects] (page user space). Returns true when any
/// form stream changed (the document is modified in place).
bool _stripTextInForms(
  PdfEditDocument doc,
  PdfDict pageResources,
  PageContentAnalysis pageAnalysis,
  List<List<double>> pageUserRects, {
  required bool blank,
}) {
  var changed = false;

  void walk(
    PdfDict resources,
    PageContentAnalysis analysis,
    Mat toUser,
    int depth,
  ) {
    if (depth > 3) return;
    final refs = formRefsIn(doc, resources);
    final seen = <int>{};
    for (final use in analysis.forms) {
      final ref = refs[use.name];
      if (ref == null) continue;
      final form = doc.resolve(ref);
      if (form is! PdfStream) continue;
      final matrixObj = doc.resolve(form.dict['Matrix']);
      Mat fm = kIdentity;
      if (matrixObj is PdfArray && matrixObj.length >= 6) {
        fm = [for (var i = 0; i < 6; i++) doc.numOf(matrixObj[i]) ?? 0];
      }
      // form space → page user space
      final formToUser = matMul(matMul(fm, use.ctm), toUser);
      final inv = matInverse(formToUser);
      if (inv == null) continue;
      // Rects into form space (bounding box of the mapped corners).
      final rects = <List<double>>[];
      for (final r in pageUserRects) {
        final pts = [
          matApply(inv, r[0], r[1]),
          matApply(inv, r[2], r[1]),
          matApply(inv, r[0], r[3]),
          matApply(inv, r[2], r[3]),
        ];
        rects.add([
          pts.map((p) => p.$1).reduce(math.min),
          pts.map((p) => p.$2).reduce(math.min),
          pts.map((p) => p.$1).reduce(math.max),
          pts.map((p) => p.$2).reduce(math.max),
        ]);
      }
      Uint8List content;
      try {
        content = decodeStreamData(form.dict, form.data);
      } catch (_) {
        continue;
      }
      final fres = doc.dictOf(form.dict['Resources']) ?? resources;
      final fa = analyzeContent(
        content,
        imageNames: const {},
        formNames: formRefsIn(doc, fres).keys.toSet(),
      );
      final edits = <({int start, int end, String text})>[];
      for (final t in fa.texts) {
        final tol = t.fontSize * 0.2;
        final hit = rects.any(
          (r) =>
              t.x >= r[0] - tol &&
              t.x <= r[2] + tol &&
              t.y >= r[1] - tol &&
              t.y <= r[3] + tol,
        );
        if (!hit) continue;
        edits.add(_textEdit(t, blank: blank, bytes: content));
      }
      if (edits.isNotEmpty && seen.add(ref.num)) {
        final out = applyRangeEdits(content, edits);
        final d = form.dict.clone();
        final packed = flateStream(d, out);
        doc.setObject(ref, packed);
        changed = true;
      }
      walk(fres, fa, formToUser, depth + 1);
    }
  }

  walk(pageResources, pageAnalysis, kIdentity, 0);
  return changed;
}

/// One text-show removal edit (delete, keep-advance invisible, or blank).
({int start, int end, String text}) _textEdit(
  PageTextShow t, {
  required bool blank,
  required Uint8List bytes,
}) {
  final op = t.op;
  final isMove = op.name == "'" || op.name == '"';
  if (t.followedByPosition) {
    return (start: op.start, end: op.end, text: isMove ? 'T*' : '');
  }
  if (!blank) {
    final src = String.fromCharCodes(bytes.sublist(op.start, op.end));
    return (start: op.start, end: op.end, text: '3 Tr $src ${t.renderMode} Tr');
  }
  var chars = 0;
  for (final tok in op.operands) {
    final s = tok.text;
    if (s.startsWith('(') || s.startsWith('<') || s.startsWith('[')) {
      chars += s.length;
    }
  }
  final b = '(${' ' * chars.clamp(1, 400)})';
  final prefix = op.name == '"'
      ? '${op.operands.take(2).map((o) => o.text).join(' ')} '
      : '';
  final show = op.name == 'TJ' ? '[$b] TJ' : '$b ${op.name}';
  return (start: op.start, end: op.end, text: '$prefix$show');
}

/// Removes text-show operations whose origin lies in any of [normRects]
/// (normalized, top-left) so edited text no longer needs a cover box.
///
/// Returns null when nothing was removed (text may live in a form XObject —
/// the caller then falls back to covering it).
Uint8List? removeTextInRects(Uint8List bytes, int page1, List<Rect> normRects) {
  try {
    final doc = PdfEditDocument.open(bytes);
    final a = _analyze(doc, page1);
    if (a == null) return null;
    final rects = [for (final r in normRects) _normToUser(doc, page1, r)];
    final edits = <({int start, int end, String text})>[];
    for (final t in a.texts) {
      final tol = t.fontSize * 0.2;
      final hit = rects.any(
        (r) =>
            t.x >= r[0] - tol &&
            t.x <= r[2] + tol &&
            t.y >= r[1] - tol &&
            t.y <= r[3] + tol,
      );
      if (!hit) continue;
      final op = t.op;
      final isMove = op.name == "'" || op.name == '"';
      if (t.followedByPosition) {
        edits.add((start: op.start, end: op.end, text: isMove ? 'T*' : ''));
      } else {
        // Later text relies on this advance: keep it, but invisible.
        final src = String.fromCharCodes(a.bytes.sublist(op.start, op.end));
        edits.add((
          start: op.start,
          end: op.end,
          text: '3 Tr $src ${t.renderMode} Tr',
        ));
      }
    }
    final page = doc.pageDict(page1);
    final res = doc.dictOf(doc.inherited(page, 'Resources')) ?? PdfDict();
    final fa = analyzeContent(
      a.bytes,
      imageNames: pageImageNames(doc, page1),
      formNames: formRefsIn(doc, res).keys.toSet(),
    );
    final formsChanged = _stripTextInForms(doc, res, fa, rects, blank: false);
    if (edits.isEmpty && !formsChanged) return null;
    return _save(
      doc,
      page1,
      edits.isEmpty ? a.bytes : applyRangeEdits(a.bytes, edits),
    );
  } catch (_) {
    return null;
  }
}

/// Font of one text-show operation on a page (for font recognition).
class TextFontHint {
  const TextFontHint({
    required this.origin,
    required this.baseFont,
    required this.sizePt,
    this.evidence,
    this.weight = 1,
  });

  /// Origin in normalized display space (0..1, top-left).
  final Offset origin;
  final String baseFont;
  final double sizePt;

  /// Name, embedded family, flags and widths of the font (see
  /// FontIdentifier).
  final PdfFontEvidence? evidence;

  /// How much text the operation shows (bytes); a block takes the font of
  /// most of its text.
  final int weight;
}

/// Fonts used by the text on [page1] — including text inside form
/// XObjects — with where each run starts. Never throws.
List<TextFontHint> findPageTextFonts(Uint8List bytes, int page1) {
  try {
    final doc = PdfEditDocument.open(bytes);
    final g = doc.pageGeometry(page1);
    final out = <TextFontHint>[];
    for (final u in _units(doc, page1)) {
      final fonts = readFontEvidence(doc, u.resources);
      for (final t in u.a.texts) {
        final ev = fonts[t.fontKey];
        if (ev == null || t.renderMode == 3) continue; // invisible (OCR) text
        final d = g.userToDisplay(Offset(t.x, t.y));
        out.add(
          TextFontHint(
            origin: Offset(d.dx / g.displayWidth, d.dy / g.displayHeight),
            baseFont: ev.name,
            sizePt: t.fontSize,
            evidence: ev,
            weight: t.op.end - t.op.start,
          ),
        );
      }
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// How a PDF BaseFont maps onto the families the editor can write.
class FontMatch {
  const FontMatch({
    required this.family,
    required this.bold,
    required this.italic,
    required this.original,
    this.libraryFamily,
    this.how,
  });

  /// Bundled family that reproduces the font (font recognition), if any.
  final String? libraryFamily;

  /// How it was recognised (name, embedded, metrics, class).
  final String? how;

  /// `sans`, `serif` or `mono` (see MarkupFontFamily).
  final String family;
  final bool bold;
  final bool italic;
  final String original;

  String get label {
    final f = switch (family) {
      'serif' => 'Serif',
      'mono' => 'Mono',
      _ => 'Sans',
    };
    final style = [if (bold) 'Bold', if (italic) 'Italic'].join(' ');
    return style.isEmpty ? f : '$f $style';
  }
}

/// Best standard-14 match for [baseFont] (e.g. `Calibri-BoldItalic`).
FontMatch classifyBaseFont(String baseFont) {
  final n = baseFont.toLowerCase().replaceAll(RegExp(r'[\s_]'), '');
  final bold = RegExp(r'bold|black|heavy|semibold|demi|extrabold').hasMatch(n);
  final italic = RegExp(r'italic|oblique|ital\b|-it\b|slanted').hasMatch(n);
  final mono = RegExp(
    r'courier|mono|consolas|menlo|lucidaconsole|typewriter|cousine|firacode|sourcecode',
  ).hasMatch(n);
  final serif =
      RegExp(
        r'times|serif|georgia|garamond|cambria|palatino|minion|bookman|century|'
        r'baskerville|didot|caslon|charter|merriweather|lora|playfair|cormorant|'
        r'tinos|liberationserif|nimbusrom|utopia|sabon|bodoni',
      ).hasMatch(n) &&
      !RegExp(r'sans').hasMatch(n);
  return FontMatch(
    family: mono ? 'mono' : (serif ? 'serif' : 'sans'),
    bold: bold,
    italic: italic,
    original: baseFont,
  );
}

/// Comments, stamps, form fields … under a redaction box would still expose
/// the covered content (text of a note, field value), so they are removed.
/// Links stay.
void _dropAnnotationsUnder(
  PdfEditDocument doc,
  int page1,
  List<List<double>> rects,
) {
  final items = doc.pageAnnotItems(page1);
  if (items.isEmpty) return;
  final keep = <PdfObj>[];
  var changed = false;
  for (final item in items) {
    final d = doc.dictOf(item);
    final rect = d == null ? null : doc.resolve(d['Rect']);
    final sub = d == null ? null : doc.resolve(d['Subtype']);
    if (d == null ||
        rect is! PdfArray ||
        rect.items.length < 4 ||
        (sub is PdfName && sub.name == 'Link')) {
      keep.add(item);
      continue;
    }
    final v = [for (final n in rect.items) doc.numOf(n) ?? 0.0];
    final x1 = v[0] < v[2] ? v[0] : v[2], x2 = v[0] < v[2] ? v[2] : v[0];
    final y1 = v[1] < v[3] ? v[1] : v[3], y2 = v[1] < v[3] ? v[3] : v[1];
    final hit = rects.any(
      (r) => x1 < r[2] && x2 > r[0] && y1 < r[3] && y2 > r[1],
    );
    if (hit) {
      changed = true;
    } else {
      keep.add(item);
    }
  }
  if (changed) doc.setPageAnnots(page1, keep);
}

/// Result of [redactPageVector].
class VectorRedaction {
  const VectorRedaction(this.bytes, {required this.imagesTouched});

  /// Redacted PDF, or the unchanged input when [imagesTouched].
  final Uint8List bytes;

  /// A picture lies under a redaction box. Content-stream redaction cannot
  /// blank part of a picture, so the caller should flatten that page.
  final bool imagesTouched;
}

/// True redaction without rasterizing the page: deletes the text under each
/// box from the content stream (it cannot be extracted afterwards) and paints
/// opaque black over the area. Everything else on the page stays vector.
VectorRedaction? redactPageVector(
  Uint8List bytes,
  int page1,
  List<Rect> normRects,
) {
  try {
    final doc = PdfEditDocument.open(bytes);
    final a = _analyze(doc, page1);
    if (a == null) return null;
    final rects = [for (final r in normRects) _normToUser(doc, page1, r)];
    bool hits(double x, double y, double tol) => rects.any(
      (r) =>
          x >= r[0] - tol &&
          x <= r[2] + tol &&
          y >= r[1] - tol &&
          y <= r[3] + tol,
    );
    for (final img in a.images) {
      final b = img.bounds;
      final touch = rects.any(
        (r) => b[0] < r[2] && b[2] > r[0] && b[1] < r[3] && b[3] > r[1],
      );
      if (touch) return VectorRedaction(bytes, imagesTouched: true);
    }
    final edits = <({int start, int end, String text})>[];
    for (final t in a.texts) {
      if (!hits(t.x, t.y, t.fontSize * 0.2)) continue;
      final op = t.op;
      if (t.followedByPosition) {
        edits.add((
          start: op.start,
          end: op.end,
          text: op.name == "'" || op.name == '"' ? 'T*' : '',
        ));
      } else {
        // Keep the advance for the text that follows, never the characters.
        var chars = 0;
        for (final tok in op.operands) {
          final s = tok.text;
          if (s.startsWith('(') || s.startsWith('<') || s.startsWith('[')) {
            chars += s.length;
          }
        }
        final blank = '(${' ' * chars.clamp(1, 400)})';
        final prefix = op.name == '"'
            ? '${op.operands.take(2).map((o) => o.text).join(' ')} '
            : '';
        final show = op.name == 'TJ' ? '[$blank] TJ' : '$blank ${op.name}';
        edits.add((start: op.start, end: op.end, text: '$prefix$show'));
      }
    }
    final pageDict = doc.pageDict(page1);
    final pageRes =
        doc.dictOf(doc.inherited(pageDict, 'Resources')) ?? PdfDict();
    final fa = analyzeContent(
      a.bytes,
      imageNames: pageImageNames(doc, page1),
      formNames: formRefsIn(doc, pageRes).keys.toSet(),
    );
    _stripTextInForms(doc, pageRes, fa, rects, blank: true);
    var content = edits.isEmpty ? a.bytes : applyRangeEdits(a.bytes, edits);
    final boxes = StringBuffer('\nq 0 g\n');
    for (final r in rects) {
      boxes.write(
        '${formatMatrix([r[0], r[1], r[2] - r[0], r[3] - r[1]])} re f\n',
      );
    }
    boxes.write('Q\n');
    content = Uint8List.fromList([...content, ...boxes.toString().codeUnits]);
    _dropAnnotationsUnder(doc, page1, rects);
    return VectorRedaction(_save(doc, page1, content), imagesTouched: false);
  } catch (_) {
    return null;
  }
}

/// Painted vector paths on [page1] (filled / stroked shapes and lines),
/// including those inside form XObjects. Page-sized backgrounds and specks
/// are left out. Never throws.
List<EditableImage> findPageShapes(Uint8List bytes, int page1) {
  try {
    final doc = PdfEditDocument.open(bytes);
    final g = doc.pageGeometry(page1);
    final pageArea = g.displayWidth * g.displayHeight;
    final out = <EditableImage>[];
    for (final u in _units(doc, page1)) {
      for (final sh in u.a.shapes) {
        final w = sh.bounds[2] - sh.bounds[0];
        final h = sh.bounds[3] - sh.bounds[1];
        if (w < 0.5 && h < 0.5) continue;
        if (w * h > pageArea * 0.85) continue;
        out.add(
          EditableImage(
            page: page1,
            name: '',
            opStart: sh.opStart,
            normRect: _userToNorm(doc, page1, sh.bounds),
            kind: EditableKind.shape,
            form: u.form,
          ),
        );
        if (out.length >= 400) return out;
      }
    }
    return out;
  } catch (_) {
    return const [];
  }
}

PageShape? _shapeAt(PageContentAnalysis a, int opStart) {
  for (final s in a.shapes) {
    if (s.opStart == opStart) return s;
  }
  return null;
}

Uint8List? deletePageShape(
  Uint8List bytes,
  int page1,
  int opStart, {
  int form = 0,
}) {
  try {
    final doc = PdfEditDocument.open(bytes);
    final u = _unit(doc, page1, form);
    final sh = u == null ? null : _shapeAt(u.a, opStart);
    if (u == null || sh == null) return null;
    return _saveUnit(
      doc,
      page1,
      u,
      applyRangeEdits(u.a.bytes, [
        (start: sh.opStart, end: sh.opEnd, text: ''),
      ]),
    );
  } catch (_) {
    return null;
  }
}

/// Recolors a shape's fill and stroke to [r],[g],[b] (0..1) without leaking
/// the colour to later objects (wrapped in q … Q).
Uint8List? recolorPageShape(
  Uint8List bytes,
  int page1,
  int opStart,
  double r,
  double g,
  double b, {
  int form = 0,
}) {
  try {
    final doc = PdfEditDocument.open(bytes);
    final u = _unit(doc, page1, form);
    final sh = u == null ? null : _shapeAt(u.a, opStart);
    if (u == null || sh == null) return null;
    final c = formatMatrix([r, g, b]);
    return _saveUnit(
      doc,
      page1,
      u,
      applyRangeEdits(u.a.bytes, [
        (start: sh.opStart, end: sh.opStart, text: 'q $c rg $c RG '),
        (start: sh.opEnd, end: sh.opEnd, text: ' Q'),
      ]),
    );
  } catch (_) {
    return null;
  }
}

/// Moves / resizes a shape to [newRect] (normalized).
Uint8List? transformPageShape(
  Uint8List bytes,
  int page1,
  int opStart,
  Rect newRect, {
  int form = 0,
}) {
  try {
    final doc = PdfEditDocument.open(bytes);
    final u = _unit(doc, page1, form);
    final sh = u == null ? null : _shapeAt(u.a, opStart);
    if (u == null || sh == null) return null;
    final t = _relocate(
      sh.ctm,
      sh.bounds,
      _sorted(_normToUser(doc, page1, newRect)),
    );
    if (t == null) return null;
    return _saveUnit(
      doc,
      page1,
      u,
      applyRangeEdits(u.a.bytes, [
        (start: sh.opStart, end: sh.opStart, text: 'q ${formatMatrix(t)} cm '),
        (start: sh.opEnd, end: sh.opEnd, text: ' Q'),
      ]),
    );
  } catch (_) {
    return null;
  }
}
