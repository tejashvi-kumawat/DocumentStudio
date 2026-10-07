import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:document_studio/core/pdf/large_doc_policy.dart';
import 'package:document_studio/core/pdf/page_loader.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/live_page_text_loader.dart';
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_page_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

/// PDF → Word that keeps the look of each page: paragraphs (grouped the same
/// way Edit groups them) with their font, size, weight, colour, alignment,
/// indent and spacing; headings marked for Word's navigation pane; pictures
/// placed inline at their size; one Word page per PDF page; two-column pages
/// read column by column.
///
/// Runs on-device (no LibreOffice), one page at a time, so memory stays flat.
Future<Uint8List> pdfToDocxWithLayout({
  required LocalFileRef file,
  String? password,
  void Function(double fraction, String message)? onProgress,
}) async {
  onProgress?.call(0.02, 'Opening PDF…');
  final doc = await openPdfLazily(file.path, password: password);
  try {
    final pageCount = doc.pages.length;
    final pages = [for (var i = 1; i <= pageCount; i++) i];

    // Fonts and picture positions from the page content (pure Dart, off the
    // UI isolate). Skipped for very large files.
    var hints = <int, List<TextFontHint>>{};
    var pictures = <int, List<EditableImage>>{};
    final size = file.sizeBytes ?? await File(file.path).length();
    if (size <= LargeDocPolicy.analysisByteLimit) {
      onProgress?.call(0.05, 'Reading fonts and pictures…');
      try {
        final r = await compute(_scanFontsAndImages, (file.path, pages));
        hints = r.$1;
        pictures = r.$2;
      } catch (_) {}
    }

    final w = _DocxWriter();
    for (final n in pages) {
      onProgress?.call(
        0.1 + 0.8 * n / math.max(1, pageCount),
        'Converting page $n of $pageCount…',
      );
      final page = await loadPageOnDemand(doc, n);
      if (page == null) continue;
      final blocks =
          (await loadEditableTextBlocksFromDoc(doc, [n]))[n] ??
          const <LiveTextEditTarget>[];
      if (n == 1) w.setPage(page.width, page.height, blocks);
      if (n > 1) w.pageBreak();
      final objects = pictures[n] ?? const <EditableImage>[];
      final figures = _figureRegions([
        for (final o in objects)
          if (o.kind == EditableKind.shape) o,
      ], blocks);
      bool inFigure(Rect r) =>
          figures.any((f) => f.inflate(0.005).contains(r.center));
      final items = <_Item>[
        for (final b in blocks)
          if (!inFigure(b.normRect))
            _Item.text(b, _fontFor(b, hints[n] ?? const [])),
      ];
      for (final f in figures) {
        final png = await _renderCrop(page, f.inflate(0.004));
        if (png != null) items.add(_Item.picture(f, png));
      }
      for (final pic in objects) {
        if (pic.kind != EditableKind.image) continue;
        if (inFigure(pic.normRect)) continue;
        final area = pic.normRect.width * pic.normRect.height;
        if (area < 0.0015) continue; // specks, rules
        if (area > 0.85 && blocks.isNotEmpty) continue; // page background
        final jpg = await _renderCrop(page, pic.normRect, photo: true);
        if (jpg != null)
          items.add(_Item.picture(pic.normRect, jpg, jpeg: true));
      }
      w.addPage(_readingOrder(items), page.width, page.height);
    }
    onProgress?.call(0.95, 'Writing Word document…');
    return w.build();
  } finally {
    await doc.dispose();
  }
}

(Map<int, List<TextFontHint>>, Map<int, List<EditableImage>>)
_scanFontsAndImages((String, List<int>) args) {
  final (path, pages) = args;
  final bytes = File(path).readAsBytesSync();
  return (
    {for (final p in pages) p: findPageTextFonts(bytes, p)},
    {
      for (final p in pages)
        p: [...findPageImages(bytes, p), ...findPageShapes(bytes, p)],
    },
  );
}

/// Vector drawings: clusters of many shapes. A cluster that holds little
/// text (labels) is a figure and is placed as one picture; one full of text
/// is a table or a boxed layout and keeps its text editable.
List<Rect> _figureRegions(
  List<EditableImage> shapes,
  List<LiveTextEditTarget> blocks,
) {
  final clusters = <(Rect, int)>[];
  for (final s in shapes) {
    var r = s.normRect;
    var count = 1;
    for (var i = clusters.length - 1; i >= 0; i--) {
      final (cr, cc) = clusters[i];
      if (cr.inflate(0.012).overlaps(r)) {
        r = r.expandToInclude(cr);
        count += cc;
        clusters.removeAt(i);
      }
    }
    clusters.add((r, count));
  }
  final out = <Rect>[];
  for (final (r, count) in clusters) {
    final area = r.width * r.height;
    if (count < 6 || area < 0.02 || area > 0.8) continue;
    var chars = 0;
    var inside = 0;
    for (final b in blocks) {
      if (r.inflate(0.005).contains(b.normRect.center)) {
        chars += b.originalText.length;
        inside++;
      }
    }
    // Labels are short and few next to the strokes; a table's cells carry
    // more text than it has border lines.
    final labelsOnly = inside == 0 || chars / inside <= 30;
    if (chars <= 160 || (labelsOnly && count >= inside * 2)) {
      out.add(_fitFigure(r, blocks));
    }
  }
  return out;
}

FontMatch? _fontFor(LiveTextEditTarget b, List<TextFontHint> hints) {
  final box = (b.coverNorm ?? b.normRect).inflate(0.004);
  for (final h in hints) {
    if (box.contains(h.origin)) return classifyBaseFont(h.baseFont);
  }
  return b.fontMatch;
}

/// Pulls nearby short labels into a figure and pushes real paragraphs that
/// touch its top or bottom edge out of it, so they stay editable text.
Rect _fitFigure(Rect r, List<LiveTextEditTarget> blocks) {
  var f = r;
  for (final b in blocks) {
    final t = b.originalText.trim();
    final c = b.normRect.center;
    if (t.length <= 14 && f.inflate(0.025).contains(c) && !f.contains(c)) {
      f = f.expandToInclude(b.coverNorm ?? b.normRect);
    }
  }
  for (final b in blocks) {
    if (b.originalText.trim().length <= 40) continue;
    final br = b.coverNorm ?? b.normRect;
    if (!f.contains(br.center)) continue;
    if (br.center.dy < f.top + f.height * 0.25) {
      f = Rect.fromLTRB(f.left, br.bottom, f.right, f.bottom);
    } else if (br.center.dy > f.bottom - f.height * 0.25) {
      f = Rect.fromLTRB(f.left, f.top, f.right, br.top);
    }
  }
  return f;
}

Future<Uint8List?> _renderCrop(
  PdfPage page,
  Rect area, {
  bool photo = false,
}) async {
  final n = area.intersect(const Rect.fromLTWH(0, 0, 1, 1));
  if (n.width <= 0 || n.height <= 0) return null;
  // 150 dpi, at most 2000 px on a side.
  var scale = 150 / 72;
  final longPx = math.max(n.width * page.width, n.height * page.height) * scale;
  if (longPx > 2000) scale *= 2000 / longPx;
  final fullW = page.width * scale;
  final fullH = page.height * scale;
  final x = (n.left * fullW).round();
  final y = (n.top * fullH).round();
  final cw = math.max(1, (n.width * fullW).round());
  final ch = math.max(1, (n.height * fullH).round());
  final image = await page.render(
    x: x,
    y: y,
    width: cw,
    height: ch,
    fullWidth: fullW,
    fullHeight: fullH,
    backgroundColor: 0xffffffff,
    annotationRenderingMode: PdfAnnotationRenderingMode.none,
    flags: PdfPageRenderFlags.limitedImageCache,
  );
  if (image == null) return null;
  try {
    final pixels = Uint8List.fromList(image.pixels);
    return await compute(_encode, (pixels, image.width, image.height, photo));
  } finally {
    image.dispose();
  }
}

/// PNG for line art (sharp, small), JPEG for photos (much smaller).
Uint8List _encode((Uint8List, int, int, bool) a) {
  final (bgra, w, h, photo) = a;
  final im = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: bgra.buffer,
    numChannels: 4,
    order: img.ChannelOrder.bgra,
  );
  return photo ? img.encodeJpg(im, quality: 85) : img.encodePng(im, level: 6);
}

class _Item {
  _Item.text(LiveTextEditTarget this.block, this.font)
    : rect = block.coverNorm ?? block.normRect,
      png = null,
      jpeg = false;
  _Item.picture(this.rect, Uint8List this.png, {this.jpeg = false})
    : block = null,
      font = null;

  final bool jpeg;

  final Rect rect;
  final LiveTextEditTarget? block;
  final FontMatch? font;
  final Uint8List? png;
}

/// Top-to-bottom, but a two-column page is read left column first.
List<_Item> _readingOrder(List<_Item> items) {
  if (items.length < 4) {
    return items..sort((a, b) => a.rect.top.compareTo(b.rect.top));
  }
  final left = items.where((i) => i.rect.right <= 0.53).length;
  final right = items.where((i) => i.rect.left >= 0.47).length;
  final twoColumns = left >= items.length * 0.3 && right >= items.length * 0.3;
  int col(_Item i) {
    if (!twoColumns) return 0;
    if (i.rect.right <= 0.53) return 1;
    if (i.rect.left >= 0.47) return 2;
    return 0; // spans both: headers / full-width figures
  }

  items.sort((a, b) {
    if (twoColumns) {
      // Full-width items keep their vertical slot; columns read in order.
      final ca = col(a), cb = col(b);
      if (ca != 0 && cb != 0 && ca != cb) return ca.compareTo(cb);
    }
    return a.rect.top.compareTo(b.rect.top);
  });
  return items;
}

class _DocxWriter {
  final _body = StringBuffer();
  final _media = <String, Uint8List>{};
  double _pageW = 612, _pageH = 792;
  double _marginL = 72, _marginR = 72, _marginT = 72, _marginB = 72;
  double _bodySize = 11;
  var _picId = 0;

  /// Page size, margins and body text size from the first page.
  void setPage(double w, double h, List<LiveTextEditTarget> blocks) {
    _pageW = w;
    _pageH = h;
    if (blocks.isEmpty) return;
    final left = blocks.map((b) => b.normRect.left).reduce(math.min) * w;
    final right = blocks.map((b) => b.normRect.right).reduce(math.max) * w;
    final top = blocks.map((b) => b.normRect.top).reduce(math.min) * h;
    final bottom = blocks.map((b) => b.normRect.bottom).reduce(math.max) * h;
    _marginL = left.clamp(18.0, 108.0);
    _marginR = (w - right).clamp(18.0, 108.0);
    _marginT = top.clamp(18.0, 90.0);
    _marginB = (h - bottom).clamp(18.0, 90.0);
    final sizes = [for (final b in blocks) b.fontSizePt]..sort();
    _bodySize = sizes[sizes.length ~/ 2];
  }

  void pageBreak() =>
      _body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');

  void addPage(List<_Item> items, double pageW, double pageH) {
    var lastBottomPt = _marginT;
    final contentW = _pageW - _marginL - _marginR;
    for (final it in items) {
      final topPt = it.rect.top * pageH;
      final before = ((topPt - lastBottomPt) * 20).round().clamp(0, 1440);
      final indent = ((it.rect.left * pageW - _marginL) * 20).round().clamp(
        0,
        7200,
      );
      if (it.png != null) {
        final wPt = math.min(it.rect.width * pageW, contentW);
        final hPt = it.rect.height * pageH * (wPt / (it.rect.width * pageW));
        _picture(it.png!, wPt, hPt, before, indent, jpeg: it.jpeg);
      } else {
        _paragraphs(it.block!, it.font, before, indent, it.rect, pageW);
      }
      lastBottomPt = it.rect.bottom * pageH;
    }
  }

  void _paragraphs(
    LiveTextEditTarget b,
    FontMatch? font,
    int before,
    int indent,
    Rect r,
    double pageW,
  ) {
    final size = b.fontSizePt;
    final heading = size >= _bodySize * 1.35 && b.lineCount <= 3
        ? (size >= _bodySize * 1.8 ? 0 : 1)
        : null;
    final centre = (r.center.dx - 0.5).abs() < 0.04 && r.width < 0.75;
    final rightAligned = !centre && r.left > 0.5 && r.right > 0.85;
    final jc = centre ? 'center' : (rightAligned ? 'right' : null);
    final line = (b.leadingEm / 1.17 * 240).round().clamp(240, 720);
    final runProps = _runProps(font, size, b.textColor, heading != null);
    var first = true;
    for (final para in _splitParagraphs(b.originalText)) {
      _body
        ..write('<w:p><w:pPr>')
        ..write(
          '<w:spacing w:before="${first ? before : 0}" w:after="0" '
          'w:line="$line" w:lineRule="auto"/>',
        );
      if (indent > 0 && jc == null) _body.write('<w:ind w:left="$indent"/>');
      if (jc != null) _body.write('<w:jc w:val="$jc"/>');
      if (heading != null) _body.write('<w:outlineLvl w:val="$heading"/>');
      _body
        ..write('</w:pPr><w:r>$runProps<w:t xml:space="preserve">')
        ..write(_esc(para))
        ..write('</w:t></w:r></w:p>');
      first = false;
    }
  }

  /// PDF lines → Word paragraphs: wrapped lines are joined (Word reflows
  /// them); list items and blank lines start new paragraphs.
  static List<String> _splitParagraphs(String text) {
    final out = <String>[];
    var cur = '';
    final listStart = RegExp(r'^\s*([•▪●◦‣\-–*]|\d{1,3}[.)]|[a-z][.)])\s');
    for (final raw in text.replaceAll('\r', '').split('\n')) {
      final l = raw.trimRight();
      if (l.trim().isEmpty) {
        if (cur.isNotEmpty) out.add(cur);
        cur = '';
        continue;
      }
      if (cur.isEmpty) {
        cur = l.trimLeft();
      } else if (listStart.hasMatch(l)) {
        out.add(cur);
        cur = l.trimLeft();
      } else if (cur.endsWith('-') && !cur.endsWith(' -')) {
        cur = cur.substring(0, cur.length - 1) + l.trimLeft();
      } else {
        cur = '$cur ${l.trimLeft()}';
      }
    }
    if (cur.isNotEmpty) out.add(cur);
    return out.isEmpty ? [''] : out;
  }

  String _runProps(FontMatch? f, double size, Color? color, bool heading) {
    final name = _fontName(f);
    final sz = (size * 2).round().clamp(8, 288);
    final b = StringBuffer('<w:rPr>')
      ..write('<w:rFonts w:ascii="$name" w:hAnsi="$name" w:cs="$name"/>');
    if ((f?.bold ?? false) || (heading && f == null)) b.write('<w:b/>');
    if (f?.italic ?? false) b.write('<w:i/>');
    if (color != null) {
      final hex = [color.r, color.g, color.b]
          .map((c) => (c * 255).round().toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();
      if (hex != '000000') b.write('<w:color w:val="$hex"/>');
    }
    b.write('<w:sz w:val="$sz"/><w:szCs w:val="$sz"/></w:rPr>');
    return b.toString();
  }

  /// Font family Word should use: the PDF font's own family when it names
  /// one (subset tag and style suffix removed), else a common equivalent.
  static String _fontName(FontMatch? f) {
    final fallback = switch (f?.family) {
      'serif' => 'Times New Roman',
      'mono' => 'Courier New',
      _ => 'Arial',
    };
    final orig = f?.original;
    if (orig == null || orig.isEmpty) return fallback;
    var n = orig.contains('+') ? orig.substring(orig.indexOf('+') + 1) : orig;
    n = n.split(RegExp(r'[-,]')).first;
    n = n.replaceAll(
      RegExp(r'(MT|PS|PSMT|Bold|Italic|Oblique|Regular|Light|Medium)+$'),
      '',
    );
    // "TimesNewRoman" → "Times New Roman".
    n = n.replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
    n = n.trim();
    if (n.isEmpty || n.length > 40) return fallback;
    const std = {
      'Helvetica': 'Arial',
      'Times': 'Times New Roman',
      'Times Roman': 'Times New Roman',
      'Courier': 'Courier New',
    };
    return _esc(std[n] ?? n);
  }

  void _picture(
    Uint8List png,
    double wPt,
    double hPt,
    int before,
    int indent, {
    bool jpeg = false,
  }) {
    final id = ++_picId;
    final name = 'image$id.${jpeg ? 'jpeg' : 'png'}';
    _media[name] = png;
    final cx = (wPt * 12700).round();
    final cy = (hPt * 12700).round();
    _body.write(
      '<w:p><w:pPr><w:spacing w:before="$before" w:after="0"/>'
      '${indent > 0 ? '<w:ind w:left="$indent"/>' : ''}</w:pPr><w:r><w:drawing>'
      '<wp:inline distT="0" distB="0" distL="0" distR="0">'
      '<wp:extent cx="$cx" cy="$cy"/><wp:docPr id="$id" name="Picture $id"/>'
      '<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/>'
      '</wp:cNvGraphicFramePr><a:graphic><a:graphicData '
      'uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '<pic:pic><pic:nvPicPr><pic:cNvPr id="$id" name="$name"/><pic:cNvPicPr/>'
      '</pic:nvPicPr><pic:blipFill><a:blip r:embed="rImg$id"/><a:stretch>'
      '<a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm>'
      '<a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
      '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
      '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>',
    );
  }

  Uint8List build() {
    if (_body.isEmpty) {
      _body.write('<w:p><w:r><w:t>(No text in this PDF.)</w:t></w:r></w:p>');
    }
    int tw(double pt) => (pt * 20).round();
    final document =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document '
        'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<w:body>$_body<w:sectPr>'
        '<w:pgSz w:w="${tw(_pageW)}" w:h="${tw(_pageH)}"'
        '${_pageW > _pageH ? ' w:orient="landscape"' : ''}/>'
        '<w:pgMar w:top="${tw(_marginT)}" w:right="${tw(_marginR)}" '
        'w:bottom="${tw(_marginB)}" w:left="${tw(_marginL)}" '
        'w:header="0" w:footer="0" w:gutter="0"/>'
        '</w:sectPr></w:body></w:document>';
    const contentTypes =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Default Extension="png" ContentType="image/png"/>'
        '<Default Extension="jpeg" ContentType="image/jpeg"/>'
        '<Override PartName="/word/document.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '</Types>';
    const rels =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
        'Target="word/document.xml"/></Relationships>';
    final docRels = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
    );
    for (final name in _media.keys) {
      final id = name.split('.').first.replaceAll(RegExp(r'\D'), '');
      docRels.write(
        '<Relationship Id="rImg$id" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
        'Target="media/$name"/>',
      );
    }
    docRels.write('</Relationships>');
    ArchiveFile text(String name, String s) {
      final b = utf8.encode(s);
      return ArchiveFile(name, b.length, b);
    }

    final archive = Archive()
      ..addFile(text('[Content_Types].xml', contentTypes))
      ..addFile(text('_rels/.rels', rels))
      ..addFile(text('word/document.xml', document))
      ..addFile(text('word/_rels/document.xml.rels', docRels.toString()));
    for (final e in _media.entries) {
      archive.addFile(
        ArchiveFile('word/media/${e.key}', e.value.length, e.value),
      );
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
}
