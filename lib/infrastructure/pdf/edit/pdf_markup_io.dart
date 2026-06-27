import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:document_studio/domain/pdf_markup/markup_geometry.dart';
import 'package:document_studio/domain/pdf_markup/markup_objects.dart';
import 'package:document_studio/domain/pdf_markup/pdf_page_geometry.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_content_builder.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_objects.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_parser.dart';
import 'package:image/image.dart' as img;

/// Private annotation key holding the editable object JSON.
const String kDsMarkupKey = 'DSMarkup';
const String _dsImageKey = 'DSImage';

/// An annotation not authored by Document Studio (listed, deletable).
class ForeignAnnotation {
  const ForeignAnnotation({
    required this.page,
    required this.refNum,
    required this.subtype,
    required this.rect,
    this.contents = '',
    this.author = '',
  });

  final int page;

  /// Object number of the annotation (null for inline annotations).
  final int? refNum;
  final String subtype;

  /// Display-space rect.
  final Rect rect;
  final String contents;
  final String author;

  String get label {
    final c = contents.trim().replaceAll('\n', ' ');
    final name = switch (subtype) {
      'FreeText' => 'Text',
      'Text' => 'Note',
      'Square' => 'Rectangle',
      'Circle' => 'Ellipse',
      'Ink' => 'Drawing',
      'StrikeOut' => 'Strikethrough',
      'Widget' => 'Form field',
      _ => subtype,
    };
    if (c.isEmpty) return name;
    return '$name: ${c.length > 24 ? '${c.substring(0, 24)}…' : c}';
  }
}

/// Everything the editor needs from a PDF.
class MarkupLoadResult {
  const MarkupLoadResult({
    required this.objects,
    required this.foreign,
    required this.geometry,
    required this.adoptedRefs,
    this.error,
  });

  const MarkupLoadResult.empty([this.error])
    : objects = const [],
      foreign = const [],
      geometry = const {},
      adoptedRefs = const {};

  /// Editable objects in z-order per page.
  final List<MarkupObject> objects;
  final List<ForeignAnnotation> foreign;

  /// Page geometry keyed by 1-based page.
  final Map<int, PdfPageGeometry> geometry;

  /// Object id → foreign annotation object number that was adopted as an
  /// editable object (e.g. existing links).
  final Map<String, int> adoptedRefs;

  /// Set when the PDF couldn't be parsed (objects are then read-only).
  final String? error;
}

/// Changes to write for one save.
class MarkupSaveRequest {
  const MarkupSaveRequest({
    required this.bytes,
    required this.objectsByPage,
    this.removeRefsByPage = const {},
    this.author = '',
  });

  final Uint8List bytes;

  /// Full, ordered object list for every page that must be rewritten.
  final Map<int, List<MarkupObject>> objectsByPage;

  /// Foreign (or adopted) annotation object numbers to drop, per page.
  final Map<int, Set<int>> removeRefsByPage;
  final String author;
}

bool _isDsAnnot(PdfEditDocument doc, PdfDict d) {
  if (d.containsKey(kDsMarkupKey)) return true;
  if (d.nameOf('Subtype') == 'Popup') {
    final parent = doc.dictOf(d['Parent']);
    if (parent != null && parent.containsKey(kDsMarkupKey)) return true;
  }
  return false;
}

// =================================================================== reading

/// Reads editable Document Studio objects, adopts plain links, and lists
/// other annotations. Pure Dart; call through `Isolate.run`.
MarkupLoadResult loadMarkupFromPdf(Uint8List bytes) {
  PdfEditDocument doc;
  try {
    doc = PdfEditDocument.open(bytes);
  } on PdfEditException catch (e) {
    return MarkupLoadResult.empty(e.message);
  } catch (e) {
    return MarkupLoadResult.empty('$e');
  }
  final objects = <MarkupObject>[];
  final foreign = <ForeignAnnotation>[];
  final geometry = <int, PdfPageGeometry>{};
  final adopted = <String, int>{};
  for (var page = 1; page <= doc.pageCount; page++) {
    PdfPageGeometry geo;
    try {
      geo = doc.pageGeometry(page);
    } catch (_) {
      continue;
    }
    geometry[page] = geo;
    List<(PdfRef?, PdfDict)> annots;
    try {
      annots = doc.annotations(page);
    } catch (_) {
      continue;
    }
    var linkIdx = 0;
    for (final (ref, d) in annots) {
      final subtype = d.nameOf('Subtype') ?? 'Unknown';
      final ds = d[kDsMarkupKey];
      if (ds != null) {
        final obj = _decodeDs(doc, d, ds, page, geo);
        if (obj != null) {
          objects.add(obj);
          continue;
        }
      }
      if (_isDsAnnot(doc, d)) continue;
      if (subtype == 'Popup') continue;
      final rect = _displayRectOf(doc, d, geo);
      if (subtype == 'Link' && ref != null && rect != null) {
        final link = _adoptLink(doc, d, page, rect, ref.num, linkIdx++);
        if (link != null) {
          objects.add(link);
          adopted[link.id] = ref.num;
          continue;
        }
      }
      if (rect == null) continue;
      foreign.add(
        ForeignAnnotation(
          page: page,
          refNum: ref?.num,
          subtype: subtype,
          rect: rect,
          contents: _text(doc, d['Contents']),
          author: _text(doc, d['T']),
        ),
      );
    }
  }
  return MarkupLoadResult(
    objects: objects,
    foreign: foreign,
    geometry: geometry,
    adoptedRefs: adopted,
  );
}

String _text(PdfEditDocument doc, PdfObj? o) {
  final r = doc.resolve(o);
  return r is PdfString ? r.text : '';
}

Rect? _displayRectOf(PdfEditDocument doc, PdfDict d, PdfPageGeometry geo) {
  final r = doc.resolve(d['Rect']);
  if (r is! PdfArray || r.length < 4) return null;
  final n = [for (final e in r.items.take(4)) doc.numOf(e) ?? 0.0];
  return geo.userRectToDisplay([
    math.min(n[0], n[2]),
    math.min(n[1], n[3]),
    math.max(n[0], n[2]),
    math.max(n[1], n[3]),
  ]);
}

MarkupObject? _decodeDs(
  PdfEditDocument doc,
  PdfDict d,
  PdfObj ds,
  int page,
  PdfPageGeometry geo,
) {
  final s = doc.resolve(ds);
  if (s is! PdfString) return null;
  Map<String, dynamic> json;
  try {
    json = Map<String, dynamic>.from(jsonDecode(s.text) as Map);
  } catch (_) {
    return null;
  }
  Uint8List? imageBytes;
  if (json['type'] == 'image') {
    imageBytes = _decodeImageXObject(doc, d[_dsImageKey]);
    if (imageBytes == null) return null;
  }
  final saved = json['geom'] is Map
      ? PdfPageGeometry.fromJson(Map<String, dynamic>.from(json['geom'] as Map))
      : null;
  var obj = MarkupObject.fromJson(json, imageBytes: imageBytes);
  if (obj == null) return null;
  if (saved != null && !saved.sameAs(geo)) obj = obj.remapped(saved, geo);
  return obj.withCommon(page: page);
}

Uint8List? _decodeImageXObject(PdfEditDocument doc, PdfObj? ref) {
  final s = doc.resolve(ref);
  if (s is! PdfStream) return null;
  final filter = s.dict['Filter'];
  final isDct =
      (filter is PdfName && filter.name == 'DCTDecode') ||
      (filter is PdfArray &&
          filter.items.any((f) => f is PdfName && f.name == 'DCTDecode'));
  if (isDct) return Uint8List.fromList(s.data);
  try {
    final w = doc.numOf(s.dict['Width'])!.round();
    final h = doc.numOf(s.dict['Height'])!.round();
    final rgb = decodeStreamData(s.dict, s.data);
    Uint8List? alpha;
    final sm = doc.resolve(s.dict['SMask']);
    if (sm is PdfStream) alpha = decodeStreamData(sm.dict, sm.data);
    final image = img.Image(width: w, height: h, numChannels: 4);
    var i = 0;
    for (final px in image) {
      px
        ..r = rgb[i * 3]
        ..g = rgb[i * 3 + 1]
        ..b = rgb[i * 3 + 2]
        ..a = alpha != null && i < alpha.length ? alpha[i] : 255;
      i++;
    }
    return Uint8List.fromList(img.encodePng(image));
  } catch (_) {
    return null;
  }
}

LinkMarkup? _adoptLink(
  PdfEditDocument doc,
  PdfDict d,
  int page,
  Rect rect,
  int refNum,
  int idx,
) {
  String? uri;
  int? dest;
  final a = doc.dictOf(d['A']);
  if (a != null) {
    final s = a.nameOf('S');
    if (s == 'URI') {
      uri = _text(doc, a['URI']);
    } else if (s == 'GoTo') {
      dest = _destPage(doc, a['D']);
    }
  }
  dest ??= _destPage(doc, d['Dest']);
  if (uri == null && dest == null) return null;
  final border = doc.resolve(d['Border']);
  var showBorder = false;
  if (border is PdfArray && border.length >= 3) {
    showBorder = (doc.numOf(border[2]) ?? 0) > 0;
  }
  return LinkMarkup(
    id: 'pdflink-$refNum',
    page: page,
    linkFrame: rect,
    text: _text(doc, d['Contents']),
    uri: uri,
    destPage: dest,
    showBorder: showBorder,
  );
}

int? _destPage(PdfEditDocument doc, PdfObj? raw) {
  var dest = doc.resolve(raw);
  if (dest is PdfString || dest is PdfName) {
    // Named destinations: look up /Dests or /Names /Dests tree (flat only).
    final name = dest is PdfString ? dest.text : (dest as PdfName).name;
    final dests = doc.dictOf(doc.catalog['Dests']);
    dest = doc.resolve(dests?[name]);
    if (dest == null) {
      final names = doc.dictOf(doc.catalog['Names']);
      final tree = doc.dictOf(names?['Dests']);
      final arr = doc.resolve(tree?['Names']);
      if (arr is PdfArray) {
        for (var i = 0; i + 1 < arr.length; i += 2) {
          final k = doc.resolve(arr[i]);
          if (k is PdfString && k.text == name) {
            dest = doc.resolve(arr[i + 1]);
            break;
          }
        }
      }
    }
    if (dest is PdfDict) dest = doc.resolve(dest['D']);
  }
  if (dest is! PdfArray || dest.length == 0) return null;
  final first = dest[0];
  if (first is PdfRef) {
    final idx = doc.pageRefs.indexWhere((r) => r.num == first.num);
    return idx >= 0 ? idx + 1 : null;
  }
  if (first is PdfNum) return first.i + 1;
  return null;
}

String? _imageHashFromJson(String text) {
  try {
    final j = jsonDecode(text);
    return j is Map && j['ih'] is String ? j['ih'] as String : null;
  } catch (_) {
    return null;
  }
}

/// Cheap content hash (FNV-1a, sampled for large images) used to reuse an
/// image XObject across saves instead of appending a new copy each time.
String imageBytesHash(Uint8List bytes) {
  var h = 0x811c9dc5;
  final step = bytes.length > 1 << 20 ? 7 : 1;
  for (var i = 0; i < bytes.length; i += step) {
    h ^= bytes[i];
    h = (h * 0x01000193) & 0xffffffff;
  }
  return '${bytes.length.toRadixString(16)}-${h.toRadixString(16)}';
}

// ================================================================== display

/// Removes Document Studio annotations (and adopted links) so the rendered
/// page doesn't duplicate what the editor overlay draws. Returns [bytes]
/// unchanged when there is nothing to strip or the file can't be parsed.
Uint8List stripEditableAnnotsForDisplay(Uint8List bytes) {
  PdfEditDocument doc;
  try {
    doc = PdfEditDocument.open(bytes);
  } catch (_) {
    return bytes;
  }
  for (var page = 1; page <= doc.pageCount; page++) {
    List<PdfObj> items;
    try {
      items = doc.pageAnnotItems(page);
    } catch (_) {
      continue;
    }
    if (items.isEmpty) continue;
    final kept = <PdfObj>[];
    var removed = false;
    for (final e in items) {
      final d = doc.dictOf(e);
      if (d == null) {
        kept.add(e);
        continue;
      }
      final isLink = d.nameOf('Subtype') == 'Link' && e is PdfRef;
      if (_isDsAnnot(doc, d) || isLink) {
        removed = true;
        continue;
      }
      kept.add(e);
    }
    if (removed) doc.setPageAnnots(page, kept);
  }
  return doc.hasChanges ? doc.save() : bytes;
}

/// Cheap check before running the full parser.
///
/// Only Document Studio's own `/DSMarkup` key. Ordinary PDFs almost always
/// contain `/Link` and `/ObjStm`; treating those as a hit forced a full
/// parse/rewrite on every open.
bool pdfMayContainEditableAnnots(Uint8List bytes) {
  return indexOfBytes(bytes, latin1.encode('/$kDsMarkupKey')) >= 0;
}

// =================================================================== writing

/// Applies a save request and returns the new PDF bytes (incremental update).
/// Throws [PdfEditException] (e.g. encrypted input).
Uint8List applyMarkupToPdf(MarkupSaveRequest req) {
  final doc = PdfEditDocument.open(req.bytes);
  final w = _AnnotWriter(doc, req.author);
  final pages = {...req.objectsByPage.keys, ...req.removeRefsByPage.keys};
  for (final page in pages) {
    if (page < 1 || page > doc.pageCount) continue;
    final remove = req.removeRefsByPage[page] ?? const <int>{};
    final rewrite = req.objectsByPage.containsKey(page);
    final kept = <PdfObj>[];
    for (final e in doc.pageAnnotItems(page)) {
      if (e is PdfRef && remove.contains(e.num)) continue;
      final d = doc.dictOf(e);
      if (rewrite && d != null && _isDsAnnot(doc, d)) {
        final img = d[_dsImageKey];
        final nm = doc.resolve(d['NM']);
        if (img is PdfRef && nm is PdfString) {
          final json = doc.resolve(d[kDsMarkupKey]);
          final hash = json is PdfString ? _imageHashFromJson(json.text) : null;
          if (hash != null) w.reusableImages['${nm.text}|$hash'] = img;
        }
        continue;
      }
      kept.add(e);
    }
    if (rewrite) {
      for (final obj in req.objectsByPage[page]!) {
        kept.addAll(w.write(page, obj));
      }
    }
    doc.setPageAnnots(page, kept);
  }
  return doc.save();
}

class _AnnotWriter {
  _AnnotWriter(this.doc, this.author);

  final PdfEditDocument doc;
  final String author;

  /// `id|hash` → image XObject from the previous save of the same object.
  final Map<String, PdfRef> reusableImages = {};
  final Map<String, PdfRef> _fonts = {};
  final Map<String, PdfRef> _gstates = {};

  PdfRef _font(String baseFont) => _fonts.putIfAbsent(
    baseFont,
    () => doc.addObject(
      PdfStdFont.values
          .firstWhere(
            (f) => f.baseFont == baseFont,
            orElse: () => PdfStdFont.helvetica,
          )
          .toFontDict(),
    ),
  );

  PdfRef _gs(double alpha, {bool multiply = false, double? fillAlpha}) {
    final fa = fillAlpha ?? alpha;
    final key =
        '${alpha.toStringAsFixed(3)}-${fa.toStringAsFixed(3)}-$multiply';
    return _gstates.putIfAbsent(
      key,
      () => doc.addObject(
        extGStateAlpha(
          fillAlpha: fa,
          strokeAlpha: alpha,
          blendMode: multiply ? 'Multiply' : null,
        ),
      ),
    );
  }

  static String _date(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'D:${t.year}${two(t.month)}${two(t.day)}'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  static PdfArray _rgb(int argb) => PdfArray.nums([
    ((argb >> 16) & 0xff) / 255,
    ((argb >> 8) & 0xff) / 255,
    (argb & 0xff) / 255,
  ]);

  /// Writes [obj]; returns the annotation refs to append to `/Annots`.
  List<PdfObj> write(int page, MarkupObject obj) {
    final geo = doc.pageGeometry(page);
    final pageRef = doc.pageRef(page);
    final json = obj.toJson()..['geom'] = geo.toJson();
    if (obj is ImageMarkup) json['ih'] = imageBytesHash(obj.bytes);
    final base = PdfDict({
      'Type': const PdfName('Annot'),
      'P': pageRef,
      'NM': PdfString.text(obj.id),
      'M': PdfString.text(_date(DateTime.now())),
      'F': PdfNum(obj.hidden ? 2 : 4),
      kDsMarkupKey: PdfString.text(jsonEncode(json)),
    });
    if (obj.opacity < 1) base['CA'] = PdfNum(obj.opacity);
    if (author.isNotEmpty) base['T'] = PdfString.text(author);
    switch (obj) {
      case TextBoxMarkup():
        return [_textBox(obj, geo, base)];
      case ImageMarkup():
        final r = _image(obj, geo, base);
        return r == null ? const [] : [r];
      case InkMarkup():
        return [_ink(obj, geo, base)];
      case ShapeMarkup():
        return [_shape(obj, geo, base)];
      case TextMarkupMarkup():
        return [_textMarkup(obj, geo, base)];
      case NoteMarkup():
        return _note(obj, geo, base, pageRef);
      case LinkMarkup():
        return [_link(obj, geo, base)];
    }
  }

  /// Creates the appearance form for [displayBounds] and sets `/Rect`/`/AP`.
  PdfRef _finish(
    PdfDict annot,
    PdfPageGeometry geo,
    Rect displayBounds,
    PdfContentBuilder content,
    PdfDict resources,
  ) {
    final h = geo.displayHeight;
    final b = displayBounds.inflate(0.5);
    final bbox = [b.left, h - b.bottom, b.right, h - b.top];
    final form = flateStream(
      PdfDict({
        'Type': const PdfName('XObject'),
        'Subtype': const PdfName('Form'),
        'BBox': PdfArray.nums(bbox),
        'Matrix': PdfArray.nums(geo.displayUpToUserMatrix),
        'Resources': resources,
      }),
      content.bytes(),
    );
    annot['Rect'] = PdfArray.nums(geo.displayRectToUser(b));
    annot['AP'] = PdfDict({'N': doc.addObject(form)});
    return doc.addObject(annot);
  }

  /// Display → display-up.
  static Affine2 _up(PdfPageGeometry geo) =>
      Affine2(1, 0, 0, -1, 0, geo.displayHeight);

  Offset _u(PdfPageGeometry geo, Offset d) => geo.displayToUp(d);

  List<double> _userPts(PdfPageGeometry geo, Iterable<Offset> pts) => [
    for (final p in pts) ...[geo.displayToUser(p).dx, geo.displayToUser(p).dy],
  ];

  void _applyAlpha(
    PdfContentBuilder c,
    PdfDict res,
    double alpha, {
    bool multiply = false,
    double fillAlpha = 1,
    String name = 'G0',
  }) {
    if (alpha >= 1 && fillAlpha >= 1 && !multiply) return;
    final gs = res['ExtGState'] as PdfDict? ?? PdfDict();
    gs[name] = _gs(alpha, multiply: multiply, fillAlpha: alpha * fillAlpha);
    res['ExtGState'] = gs;
    c.gs(name);
  }

  static double _alphaOf(int argb) => ((argb >> 24) & 0xff) / 255;

  // ------------------------------------------------------------- text box

  PdfRef _textBox(TextBoxMarkup t, PdfPageGeometry geo, PdfDict annot) {
    final c = PdfContentBuilder();
    final res = PdfDict();
    final baseFont = t.fontFamily.pdfBaseFont(bold: t.bold, italic: t.italic);
    res['Font'] = PdfDict({'F0': _font(baseFont)});
    _applyAlpha(c, res, t.opacity);
    final up = _up(geo);
    final f = t.frame;
    if (t.isCallout) {
      final target = t.calloutPoints[0], knee = t.calloutPoints[1];
      final attach = t.calloutAttachPoint();
      final lineColor = t.borderColor ?? t.textColor;
      c
        ..save()
        ..strokeColor(lineColor)
        ..lineWidth(math.max(0.75, t.borderWidth))
        ..lineCap(1)
        ..lineJoin(1)
        ..polyline([_u(geo, target), _u(geo, knee), _u(geo, attach)])
        ..stroke()
        ..fillColor(lineColor)
        ..polyline(
          arrowHead(
            knee,
            target,
            math.max(0.75, t.borderWidth),
          ).map((p) => _u(geo, p)).toList(),
          closed: true,
        )
        ..fill()
        ..restore();
    }
    // frame-local (y down) → display → up; then flip local y to draw y-up.
    final m = up
        .multiply(frameToDisplay(f, t.rotation))
        .multiply(Affine2(1, 0, 0, -1, 0, f.height));
    c
      ..save()
      ..cm(m);
    if (t.fillColor != null) {
      c.save();
      _applyAlpha(
        c,
        res,
        t.opacity,
        fillAlpha: _alphaOf(t.fillColor!),
        name: 'G1',
      );
      c
        ..fillColor(t.fillColor!)
        ..rect(0, 0, f.width, f.height)
        ..fill()
        ..restore();
    }
    if (t.borderColor != null && t.borderWidth > 0) {
      final bw = t.borderWidth;
      c
        ..strokeColor(t.borderColor!)
        ..lineWidth(bw)
        ..rect(bw / 2, bw / 2, f.width - bw, f.height - bw)
        ..stroke();
    }
    c.fillColor(t.textColor);
    for (final line in t.lines) {
      if (line.text.isEmpty) continue;
      c.text(
        'F0',
        t.fontSize,
        Affine2(1, 0, 0, 1, line.left, f.height - line.baseline),
        line.text,
        charSpacing: t.letterSpacing,
      );
    }
    for (final r in textDecorationRects(t)) {
      c.rect(r.left, f.height - r.bottom, r.width, r.height);
    }
    if (t.underline || t.strike) c.fill();
    c.restore();
    annot['Subtype'] = const PdfName('FreeText');
    annot['Contents'] = PdfString.text(t.text);
    final rgb = [
      16,
      8,
      0,
    ].map((s) => formatPdfNum(((t.textColor >> s) & 0xff) / 255)).join(' ');
    annot['DA'] = PdfString.text(
      '/${_daFontName(baseFont)} ${formatPdfNum(t.fontSize)} Tf $rgb rg',
    );
    annot['Q'] = PdfNum(switch (t.align) {
      MarkupTextAlign.left => 0,
      MarkupTextAlign.center => 1,
      MarkupTextAlign.right => 2,
    });
    if (t.isCallout) {
      annot['IT'] = const PdfName('FreeTextCallout');
      annot['CL'] = PdfArray.nums(
        _userPts(geo, [
          t.calloutPoints[0],
          t.calloutPoints[1],
          t.calloutAttachPoint(),
        ]),
      );
      annot['LE'] = const PdfName('ClosedArrow');
    }
    if (t.fillColor != null) annot['C'] = _rgb(t.fillColor!);
    annot['BS'] = PdfDict({
      'W': PdfNum(t.borderColor == null ? 0 : t.borderWidth),
    });
    return _finish(annot, geo, t.bounds, c, res);
  }

  static String _daFontName(String base) => switch (base) {
    'Times-Roman' ||
    'Times-Bold' ||
    'Times-Italic' ||
    'Times-BoldItalic' => 'TiRo',
    'Courier' ||
    'Courier-Bold' ||
    'Courier-Oblique' ||
    'Courier-BoldOblique' => 'Cour',
    _ => 'Helv',
  };

  // ---------------------------------------------------------------- image

  PdfRef? _image(ImageMarkup im, PdfPageGeometry geo, PdfDict annot) {
    var imgRef = reusableImages['${im.id}|${imageBytesHash(im.bytes)}'];
    if (imgRef == null) {
      final x = PdfImageXObject.fromEncoded(im.bytes);
      if (x == null) return null;
      final dict = x.image.dict.clone();
      if (x.smask != null) dict['SMask'] = doc.addObject(x.smask!);
      imgRef = doc.addObject(PdfStream(dict, x.image.data));
    }
    final c = PdfContentBuilder();
    final res = PdfDict({
      'XObject': PdfDict({'Im0': imgRef}),
    });
    _applyAlpha(c, res, im.opacity);
    final f = im.frame;
    final radius = effectiveCornerRadius(im.cornerRadius, f.width, f.height);
    // Frame-local, y flipped up (origin bottom-left of the frame).
    final frameUp = _up(geo)
        .multiply(
          frameToDisplay(f, im.rotation, flipH: im.flipH, flipV: im.flipV),
        )
        .multiply(Affine2(1, 0, 0, -1, 0, f.height));
    // The crop window fills the frame; the full image extends beyond it.
    final cr = im.crop;
    final cw = math.max(1e-6, cr.width), ch = math.max(1e-6, cr.height);
    final fullW = f.width / cw, fullH = f.height / ch;
    final imageToFrameUp = Affine2(
      fullW,
      0,
      0,
      fullH,
      -cr.left * fullW,
      f.height - (1 - cr.top) * fullH,
    );
    c
      ..save()
      ..cm(frameUp);
    if (im.isCropped || radius > 0) {
      c
        ..roundedRect(0, 0, f.width, f.height, radius)
        ..clip();
    }
    c
      ..save()
      ..cm(imageToFrameUp)
      ..doXObject('Im0')
      ..restore();
    if (im.hasBorder) {
      final bw = im.borderWidth;
      c.save();
      _applyAlpha(c, res, im.opacity * _alphaOf(im.borderColor!), name: 'G1');
      c
        ..strokeColor(im.borderColor!)
        ..lineWidth(bw)
        ..roundedRect(
          bw / 2,
          bw / 2,
          f.width - bw,
          f.height - bw,
          math.max(0, radius - bw / 2),
        )
        ..stroke()
        ..restore();
    }
    c.restore();
    annot['Subtype'] = const PdfName('Stamp');
    annot['Name'] = const PdfName('DSImage');
    annot[_dsImageKey] = imgRef;
    return _finish(annot, geo, im.bounds, c, res);
  }

  // ------------------------------------------------------------------ ink

  PdfRef _ink(InkMarkup ink, PdfPageGeometry geo, PdfDict annot) {
    final c = PdfContentBuilder();
    final res = PdfDict();
    _applyAlpha(c, res, ink.opacity, multiply: ink.highlighter);
    c
      ..strokeColor(ink.strokeColor)
      ..fillColor(ink.strokeColor)
      ..lineWidth(ink.strokeWidth)
      ..lineCap(1)
      ..lineJoin(1);
    for (final s in ink.strokes) {
      if (s.isEmpty) continue;
      if (s.length == 1) {
        final p = _u(geo, s.first);
        final r = ink.strokeWidth / 2;
        c
          ..ellipse(p.dx - r, p.dy - r, r * 2, r * 2)
          ..fill();
        continue;
      }
      c
        ..polyline([for (final p in s) _u(geo, p)])
        ..stroke();
    }
    annot['Subtype'] = const PdfName('Ink');
    annot['InkList'] = PdfArray([
      for (final s in ink.strokes) PdfArray.nums(_userPts(geo, s)),
    ]);
    annot['C'] = _rgb(ink.strokeColor);
    annot['BS'] = PdfDict({'W': PdfNum(ink.strokeWidth)});
    if (ink.highlighter) annot['IT'] = const PdfName('InkHighlight');
    return _finish(annot, geo, ink.bounds, c, res);
  }

  // ---------------------------------------------------------------- shape

  PdfRef _shape(ShapeMarkup s, PdfPageGeometry geo, PdfDict annot) {
    final c = PdfContentBuilder();
    final res = PdfDict();
    _applyAlpha(
      c,
      res,
      s.opacity,
      fillAlpha: s.fillColor == null ? 1 : _alphaOf(s.fillColor!),
    );
    c
      ..strokeColor(s.strokeColor)
      ..lineWidth(s.strokeWidth)
      ..lineJoin(s.kind == ShapeKind.rectangle ? 0 : 1)
      ..lineCap(s.dash == StrokeDash.dotted ? 1 : 0);
    final dash = dashPatternFor(s.dash, s.strokeWidth);
    if (dash != null) c.dash(dash);
    if (s.fillColor != null) c.fillColor(s.fillColor!);
    final paint = s.fillColor != null && s.isClosed;
    void finishPath() => paint ? c.fillStroke() : c.stroke();

    final bs = PdfDict({'W': PdfNum(s.strokeWidth)});
    if (dash != null) {
      bs['S'] = const PdfName('D');
      bs['D'] = PdfArray.nums(dash);
    }
    annot['BS'] = bs;
    annot['C'] = _rgb(s.strokeColor);
    if (s.fillColor != null) annot['IC'] = _rgb(s.fillColor!);

    switch (s.kind) {
      case ShapeKind.rectangle:
      case ShapeKind.ellipse:
        final f = s.shapeFrame!;
        final m = _up(geo)
            .multiply(frameToDisplay(f, s.rotation))
            .multiply(Affine2(1, 0, 0, -1, 0, f.height));
        c
          ..save()
          ..cm(m);
        if (s.kind == ShapeKind.rectangle) {
          c.rect(0, 0, f.width, f.height);
        } else {
          c.ellipse(0, 0, f.width, f.height);
        }
        finishPath();
        c.restore();
        annot['Subtype'] = PdfName(
          s.kind == ShapeKind.rectangle ? 'Square' : 'Circle',
        );
      case ShapeKind.line:
      case ShapeKind.arrow:
        final a = s.points.first, b = s.points.last;
        c
          ..polyline([_u(geo, a), _u(geo, b)])
          ..stroke();
        if (s.kind == ShapeKind.arrow) {
          final head = arrowHead(a, b, s.strokeWidth);
          c
            ..save()
            ..op('[] 0 d')
            ..fillColor(s.strokeColor)
            ..polyline([for (final p in head) _u(geo, p)], closed: true)
            ..fill()
            ..restore();
          annot['LE'] = PdfArray([
            const PdfName('None'),
            const PdfName('ClosedArrow'),
          ]);
          annot['IC'] = _rgb(s.strokeColor);
        }
        annot['Subtype'] = const PdfName('Line');
        annot['L'] = PdfArray.nums(_userPts(geo, [a, b]));
      case ShapeKind.polygon:
        c.polyline([for (final p in s.points) _u(geo, p)], closed: true);
        finishPath();
        annot['Subtype'] = const PdfName('Polygon');
        annot['Vertices'] = PdfArray.nums(_userPts(geo, s.points));
      case ShapeKind.cloud:
        final arcs = cloudArcs(s.points, s.cloudRadius());
        if (arcs.isNotEmpty) {
          c.moveTo(_u(geo, arcs.first.$1));
          for (final (st, ctl, en) in arcs) {
            // Quadratic → cubic.
            final c1 = st + (ctl - st) * (2 / 3);
            final c2 = en + (ctl - en) * (2 / 3);
            c.curveTo(_u(geo, c1), _u(geo, c2), _u(geo, en));
          }
          c.close();
          finishPath();
        }
        annot['Subtype'] = const PdfName('Polygon');
        annot['Vertices'] = PdfArray.nums(_userPts(geo, s.points));
        annot['BE'] = PdfDict({'S': const PdfName('C'), 'I': const PdfNum(1)});
    }
    return _finish(annot, geo, s.bounds, c, res);
  }

  // ---------------------------------------------------------- text markup

  PdfRef _textMarkup(TextMarkupMarkup t, PdfPageGeometry geo, PdfDict annot) {
    final c = PdfContentBuilder();
    final res = PdfDict();
    final highlight = t.kind == TextMarkupKind.highlight;
    _applyAlpha(c, res, t.opacity, multiply: highlight);
    if (highlight) {
      c.fillColor(t.markupColor);
      for (final r in t.rects) {
        final p = _u(geo, r.bottomLeft);
        c.rect(p.dx, p.dy, r.width, r.height);
      }
      c.fill();
    } else {
      c
        ..strokeColor(t.markupColor)
        ..lineCap(0)
        ..lineJoin(1);
      for (final r in t.rects) {
        final st = textMarkupStroke(t.kind, r);
        if (st == null) continue;
        c
          ..lineWidth(st.width)
          ..polyline([for (final p in st.points) _u(geo, p)])
          ..stroke();
      }
    }
    annot['Subtype'] = PdfName(switch (t.kind) {
      TextMarkupKind.highlight => 'Highlight',
      TextMarkupKind.underline => 'Underline',
      TextMarkupKind.strikeout => 'StrikeOut',
      TextMarkupKind.squiggly => 'Squiggly',
    });
    annot['C'] = _rgb(t.markupColor);
    annot['QuadPoints'] = PdfArray.nums([
      for (final r in t.rects)
        ..._userPts(geo, [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]),
    ]);
    if (t.text.isNotEmpty) annot['Contents'] = PdfString.text(t.text);
    return _finish(annot, geo, t.bounds, c, res);
  }

  // ----------------------------------------------------------------- note

  List<PdfObj> _note(
    NoteMarkup n,
    PdfPageGeometry geo,
    PdfDict annot,
    PdfRef pageRef,
  ) {
    final c = PdfContentBuilder();
    final res = PdfDict();
    _applyAlpha(c, res, n.opacity);
    final g = NoteIconGeometry(kNoteIconSize);
    Offset at(Offset local) => _u(geo, n.anchor + local);
    final body = g.body;
    c
      ..fillColor(n.noteColor)
      ..strokeColor(0xFF5D4B1F)
      ..lineWidth(0.8)
      ..lineJoin(1)
      ..polyline([
        at(body.topLeft),
        at(body.topRight),
        at(body.bottomRight),
        at(g.tail[2]),
        at(g.tail[1]),
        at(g.tail[0]),
        at(body.bottomLeft),
      ], closed: true)
      ..fillStroke()
      ..lineWidth(1);
    for (final (a, b) in g.lines) {
      c
        ..polyline([at(a), at(b)])
        ..stroke();
    }
    annot['Subtype'] = const PdfName('Text');
    annot['Name'] = const PdfName('Comment');
    annot['Contents'] = PdfString.text(n.text);
    annot['C'] = _rgb(n.noteColor);
    annot['Open'] = PdfBool(n.open);
    final noteRef = _finish(annot, geo, n.bounds, c, res);
    final popupRect = notePopupRect(
      n.anchor,
      geo.displayWidth,
      geo.displayHeight,
    );
    final popup = PdfDict({
      'Type': const PdfName('Annot'),
      'Subtype': const PdfName('Popup'),
      'Parent': noteRef,
      'P': pageRef,
      'Rect': PdfArray.nums(geo.displayRectToUser(popupRect)),
      'Open': PdfBool(n.open),
      'F': PdfNum(n.hidden ? 2 : 0),
    });
    final popupRef = doc.addObject(popup);
    final withPopup = (doc.getObject(noteRef.num) as PdfDict).clone()
      ..['Popup'] = popupRef;
    doc.setObject(noteRef, withPopup);
    return [noteRef, popupRef];
  }

  // ----------------------------------------------------------------- link

  PdfRef _link(LinkMarkup l, PdfPageGeometry geo, PdfDict annot) {
    annot['Subtype'] = const PdfName('Link');
    annot['H'] = const PdfName('I');
    if (l.showBorder) {
      annot['Border'] = PdfArray.nums([0, 0, 1]);
      annot['C'] = PdfArray.nums([0.12, 0.44, 0.85]);
    } else {
      annot['Border'] = PdfArray.nums([0, 0, 0]);
    }
    final uri = l.normalizedUri;
    if (uri != null) {
      annot['A'] = PdfDict({
        'S': const PdfName('URI'),
        'URI': PdfString(Uint8List.fromList(latin1.encode(_asciiUri(uri)))),
      });
    } else if (l.destPage != null &&
        l.destPage! >= 1 &&
        l.destPage! <= doc.pageCount) {
      annot['A'] = PdfDict({
        'S': const PdfName('GoTo'),
        'D': PdfArray([
          doc.pageRef(l.destPage!),
          const PdfName('XYZ'),
          PdfNull.instance,
          PdfNull.instance,
          PdfNull.instance,
        ]),
      });
    }
    final label = l.text.trim();
    if (label.isNotEmpty) {
      annot['Contents'] = PdfString.text(label);
    }

    // Invisible hit-area (adopted PDF links with no drawn text / border).
    if (label.isEmpty && !l.showBorder) {
      annot['Rect'] = PdfArray.nums(geo.displayRectToUser(l.linkFrame));
      return doc.addObject(annot);
    }

    final c = PdfContentBuilder();
    final res = PdfDict();
    res['Font'] = PdfDict({'F0': _font('Helvetica')});
    _applyAlpha(c, res, l.opacity);
    final f = l.linkFrame;
    final up = _up(geo);
    final m = up
        .multiply(frameToDisplay(f, 0))
        .multiply(Affine2(1, 0, 0, -1, 0, f.height));
    c
      ..save()
      ..cm(m);
    if (l.showBorder) {
      c
        ..strokeColor(l.color)
        ..lineWidth(1)
        ..rect(0.5, 0.5, f.width - 1, f.height - 1)
        ..stroke();
    }
    if (label.isNotEmpty) {
      final size = LinkMarkup.textFontSize;
      final baseline = f.height - math.max(2.0, (f.height - size) / 2);
      c
        ..fillColor(l.color)
        ..text('F0', size, Affine2(1, 0, 0, 1, 1, baseline), label);
      // Underline under the visible glyphs (approx. WinAnsi width).
      final underlineY = baseline - 1.5;
      final textW = _approxHelvWidth(label, size);
      c
        ..rect(1, underlineY - 0.6, math.min(textW, f.width - 2), 0.75)
        ..fill();
    }
    c.restore();
    return _finish(annot, geo, l.bounds, c, res);
  }

  /// Rough Helvetica width for underlines in link appearances.
  static double _approxHelvWidth(String s, double size) {
    var w = 0.0;
    for (final r in s.runes) {
      w += (r == 0x20 || r == 0x69 || r == 0x6c || r == 0x74) ? 0.28 : 0.55;
    }
    return w * size;
  }

  static String _asciiUri(String s) {
    final sb = StringBuffer();
    for (final b in utf8.encode(s)) {
      if (b < 0x21 || b > 0x7e) {
        sb.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      } else {
        sb.writeCharCode(b);
      }
    }
    return sb.toString();
  }
}
