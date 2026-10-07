import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:xml/xml.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

/// A picture from the document, kept byte-exact so saving never loses it.
class DocxImage {
  DocxImage(this.bytes, this.widthEmu, this.heightEmu, this.target);
  final Uint8List bytes;
  final int widthEmu, heightEmu;

  /// Package path (word/media/image1.png).
  final String target;
}

/// Page size and margins in twips (1/1440 inch), from `<w:sectPr>`.
class DocxPageSetup {
  DocxPageSetup({
    this.width = 11906,
    this.height = 16838,
    this.top = 1440,
    this.right = 1440,
    this.bottom = 1440,
    this.left = 1440,
  });

  int width, height, top, right, bottom, left;

  bool get landscape => width > height;

  DocxPageSetup copy() => DocxPageSetup(
    width: width,
    height: height,
    top: top,
    right: right,
    bottom: bottom,
    left: left,
  );

  @override
  bool operator ==(Object other) =>
      other is DocxPageSetup &&
      other.width == width &&
      other.height == height &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.left == left;

  @override
  int get hashCode => Object.hash(width, height, top, right, bottom, left);
}

/// The default header or footer: one or more lines of text, aligned;
/// `{PAGE}` / `{PAGES}` stand for page fields.
class DocxRunning {
  DocxRunning({this.text = '', this.align = 'center', this.part});
  String text;
  String align; // left center right
  /// Package part it came from (word/header1.xml), null when new.
  String? part;
  bool dirty = false;

  bool get isEmpty => text.trim().isEmpty;
}

/// Value of an `ins` / `del` mark (a suggested edit): author and time.
String suggestionMark(String author, DateTime? date) =>
    '$author\u0001${(date ?? DateTime.now()).toUtc().toIso8601String()}';

/// (author, date) of a suggestion mark.
(String, DateTime) suggestionInfo(String mark) {
  final i = mark.indexOf('\u0001');
  if (i < 0) return (mark, DateTime.now());
  return (
    mark.substring(0, i),
    DateTime.tryParse(mark.substring(i + 1)) ?? DateTime.now(),
  );
}

/// A reviewer comment (`word/comments.xml`), anchored to text that carries
/// `{'comment': id}` in the delta.
class DocxComment {
  DocxComment({
    required this.text,
    this.author = '',
    DateTime? date,
    this.initials = '',
  }) : date = date ?? DateTime.now();
  String text;
  String author;
  DateTime date;
  String initials;
}

/// An opened .docx: the editable text as a Quill [Delta], plus the parts we
/// keep as they are (pictures, tables, styles, headers, theme…).
class DocxDocument {
  DocxDocument({
    required this.delta,
    required this.images,
    required this.tables,
    this.original,
    DocxPageSetup? page,
    DocxRunning? header,
    DocxRunning? footer,
    Map<String, DocxComment>? comments,
    Map<String, String>? sections,
  }) : comments = comments ?? {},
       sections = sections ?? {},
       page = page ?? DocxPageSetup(),
       header = header ?? DocxRunning(),
       footer = footer ?? DocxRunning();

  /// Section breaks inside the text: embed id (`{'docsect': id}`) →
  /// `<w:sectPr>` XML, written back as it was.
  final Map<String, String> sections;

  /// Comments by id (the `comment` attribute on the text they mark).
  final Map<String, DocxComment> comments;

  /// Default header and footer (Insert → Header / Footer / Page numbers).
  final DocxRunning header, footer;

  final Delta delta;

  /// Page size and margins (Layout tab); written into `<w:sectPr>`.
  final DocxPageSetup page;

  /// Embed id → picture (`{'docimage': id}` in the delta).
  final Map<String, DocxImage> images;

  /// Embed id → `<w:tbl>` XML (`{'doctable': id}`), written back verbatim.
  final Map<String, String> tables;

  /// The source package; its other parts are carried over on save.
  final Archive? original;

  /// A blank document.
  factory DocxDocument.blank() =>
      DocxDocument(delta: Delta()..insert('\n'), images: {}, tables: {});
}

// ------------------------------------------------------------------ read

/// Reads a .docx into an editable document. Unknown content is kept where
/// possible (tables verbatim, pictures byte-exact).
DocxDocument readDocx(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  String? part(String name) {
    final f = archive.findFile(name);
    return f == null
        ? null
        : utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  final docXml = part('word/document.xml');
  if (docXml == null)
    throw const FormatException(
      'Not a Word document (word/document.xml missing)',
    );
  final doc = XmlDocument.parse(docXml);

  // Relationships: rId → target.
  final rels = <String, String>{};
  final relXml = part('word/_rels/document.xml.rels');
  if (relXml != null) {
    for (final rel in XmlDocument.parse(
      relXml,
    ).findAllElements('Relationship')) {
      rels[rel.getAttribute('Id') ?? ''] = rel.getAttribute('Target') ?? '';
    }
  }

  // Numbering: numId → (level → bullet?).
  final numIsBullet = <String, Map<String, bool>>{};
  final numXml = part('word/numbering.xml');
  if (numXml != null) {
    final n = XmlDocument.parse(numXml);
    final abs = <String, Map<String, bool>>{};
    for (final a in n.findAllElements('abstractNum', namespaceUri: _w)) {
      final id = a.getAttribute('abstractNumId', namespaceUri: _w) ?? '';
      final levels = <String, bool>{};
      for (final lvl in a.findElements('lvl', namespaceUri: _w)) {
        final ilvl = lvl.getAttribute('ilvl', namespaceUri: _w) ?? '0';
        final fmt = lvl
            .getElement('numFmt', namespaceUri: _w)
            ?.getAttribute('val', namespaceUri: _w);
        levels[ilvl] = fmt == 'bullet' || fmt == null;
      }
      abs[id] = levels;
    }
    for (final num in n.findAllElements('num', namespaceUri: _w)) {
      final id = num.getAttribute('numId', namespaceUri: _w) ?? '';
      final a = num.getElement(
        'abstractNumId',
        namespaceUri: _w,
      )?.getAttribute('val', namespaceUri: _w);
      numIsBullet[id] = abs[a] ?? const {};
    }
  }

  final delta = Delta();
  String? activeComment; // open commentRangeStart
  final images = <String, DocxImage>{};
  final tables = <String, String>{};
  var seq = 0;

  void paragraph(XmlElement p) {
    // Text since the last line break in this paragraph (embeds need their
    // own line; no empty lines may be invented around them).
    var pending = false;
    var embedEnded = false;
    final pPr = p.getElement('pPr', namespaceUri: _w);
    final style =
        pPr
            ?.getElement('pStyle', namespaceUri: _w)
            ?.getAttribute('val', namespaceUri: _w) ??
        '';
    final lineAttrs = <String, dynamic>{};
    final h = RegExp(r'^(?:Heading|heading)\s?(\d)$').firstMatch(style);
    if (h != null) lineAttrs['header'] = int.parse(h.group(1)!).clamp(1, 6);
    if (style == 'Title') lineAttrs['header'] = 1;
    if (style == 'Subtitle') lineAttrs['header'] = 2;
    if (style.toLowerCase().contains('quote')) lineAttrs['blockquote'] = true;
    switch (pPr
        ?.getElement('jc', namespaceUri: _w)
        ?.getAttribute('val', namespaceUri: _w)) {
      case 'center':
        lineAttrs['align'] = 'center';
      case 'right' || 'end':
        lineAttrs['align'] = 'right';
      case 'both' || 'distribute':
        lineAttrs['align'] = 'justify';
    }
    final line = int.tryParse(
      pPr
              ?.getElement('spacing', namespaceUri: _w)
              ?.getAttribute('line', namespaceUri: _w) ??
          '',
    );
    final rule = pPr
        ?.getElement('spacing', namespaceUri: _w)
        ?.getAttribute('lineRule', namespaceUri: _w);
    if (line != null && (rule == null || rule == 'auto')) {
      final k = line / 240;
      for (final v in const [1.0, 1.15, 1.5, 2.0]) {
        if ((k - v).abs() < 0.06 && v != 1.15) lineAttrs['line-height'] = v;
      }
    }
    final numPr = pPr?.getElement('numPr', namespaceUri: _w);
    if (numPr != null) {
      final numId =
          numPr
              .getElement('numId', namespaceUri: _w)
              ?.getAttribute('val', namespaceUri: _w) ??
          '';
      final ilvl =
          numPr
              .getElement('ilvl', namespaceUri: _w)
              ?.getAttribute('val', namespaceUri: _w) ??
          '0';
      if (numId != '0') {
        final bullet = numIsBullet[numId]?[ilvl] ?? true;
        lineAttrs['list'] = bullet ? 'bullet' : 'ordered';
        final lvl = int.tryParse(ilvl) ?? 0;
        if (lvl > 0) lineAttrs['indent'] = lvl.clamp(1, 8);
      }
    }

    void runs(
      Iterable<XmlElement> children, {
      String? link,
      Map<String, String>? track,
    }) {
      for (final c in children) {
        if (c.name.local == 'hyperlink') {
          final rid = c.getAttribute('id', namespaceUri: _r);
          runs(
            c.childElements,
            link: rid == null ? null : rels[rid],
            track: track,
          );
          continue;
        }
        // Tracked changes (suggestions): kept as `ins` / `del` marks.
        if (c.name.local == 'ins' || c.name.local == 'del') {
          final who = suggestionMark(
            c.getAttribute('author', namespaceUri: _w) ?? '',
            DateTime.tryParse(c.getAttribute('date', namespaceUri: _w) ?? ''),
          );
          runs(c.childElements, link: link, track: {c.name.local: who});
          continue;
        }
        if (c.name.local == 'smartTag' ||
            c.name.local == 'sdt' ||
            c.name.local == 'sdtContent') {
          runs(c.childElements, link: link, track: track);
          continue;
        }
        if (c.name.local == 'commentRangeStart') {
          activeComment = 'c${c.getAttribute('id', namespaceUri: _w)}';
          continue;
        }
        if (c.name.local == 'commentRangeEnd') {
          if (activeComment == 'c${c.getAttribute('id', namespaceUri: _w)}')
            activeComment = null;
          continue;
        }
        if (c.name.local != 'r') continue;
        final rPr = c.getElement('rPr', namespaceUri: _w);
        bool on(String tag) {
          final e = rPr?.getElement(tag, namespaceUri: _w);
          if (e == null) return false;
          final v = e.getAttribute('val', namespaceUri: _w);
          return v == null || (v != '0' && v != 'false' && v != 'none');
        }

        final attrs = <String, dynamic>{
          if (on('b')) 'bold': true,
          if (on('i')) 'italic': true,
          if (on('u')) 'underline': true,
          if (on('strike') || on('dstrike')) 'strike': true,
          'link': ?link,
          'comment': ?activeComment,
          ...?track,
        };
        final color = rPr
            ?.getElement('color', namespaceUri: _w)
            ?.getAttribute('val', namespaceUri: _w);
        if (color != null &&
            color != 'auto' &&
            color.length == 6 &&
            color != '000000') {
          attrs['color'] = '#$color';
        }
        final sz = rPr
            ?.getElement('sz', namespaceUri: _w)
            ?.getAttribute('val', namespaceUri: _w);
        if (sz != null) {
          final pt = (int.tryParse(sz) ?? 22) / 2;
          if ((pt - 11).abs() > 0.4 && h == null)
            attrs['size'] = pt.toStringAsFixed(pt % 1 == 0 ? 0 : 1);
        }
        final va = rPr
            ?.getElement('vertAlign', namespaceUri: _w)
            ?.getAttribute('val', namespaceUri: _w);
        if (va == 'superscript') attrs['script'] = 'super';
        if (va == 'subscript') attrs['script'] = 'sub';
        final hl = rPr
            ?.getElement('highlight', namespaceUri: _w)
            ?.getAttribute('val', namespaceUri: _w);
        final shd = rPr
            ?.getElement('shd', namespaceUri: _w)
            ?.getAttribute('fill', namespaceUri: _w);
        if (hl != null && _highlights[hl] != null) {
          attrs['background'] = _highlights[hl];
        } else if (shd != null &&
            shd.length == 6 &&
            shd.toLowerCase() != 'ffffff') {
          attrs['background'] = '#$shd';
        }
        final font = rPr
            ?.getElement('rFonts', namespaceUri: _w)
            ?.getAttribute('ascii', namespaceUri: _w);
        if (font != null && font.isNotEmpty) attrs['font'] = font;
        for (final t in c.childElements) {
          switch (t.name.local) {
            case 't' || 'delText':
              if (t.innerText.isNotEmpty) {
                delta.insert(t.innerText, attrs.isEmpty ? null : attrs);
                pending = true;
              }
            case 'tab':
              delta.insert('\t', attrs.isEmpty ? null : attrs);
              pending = true;
            case 'br' when t.getAttribute('type', namespaceUri: _w) == 'page':
              if (pending)
                delta.insert(
                  '\n',
                  lineAttrs.isEmpty ? null : Map.of(lineAttrs),
                );
              delta.insert({'docbreak': 'page'});
              delta.insert('\n');
              pending = false;
              embedEnded = true;
            case 'br' || 'cr':
              // A soft line break ends the visual line, keeping the block style.
              delta.insert('\n', lineAttrs.isEmpty ? null : Map.of(lineAttrs));
              pending = false;
            case 'drawing' || 'pict':
              final blip = t
                  .findAllElements(
                    'blip',
                    namespaceUri:
                        'http://schemas.openxmlformats.org/drawingml/2006/main',
                  )
                  .firstOrNull;
              final rid = blip?.getAttribute('embed', namespaceUri: _r);
              final target = rid == null ? null : rels[rid];
              final file = target == null
                  ? null
                  : archive.findFile(
                      'word/${target.replaceFirst(RegExp(r'^/?word/'), '')}',
                    );
              if (file != null) {
                final ext = t
                    .findAllElements(
                      'extent',
                      namespaceUri: 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing',
                    )
                    .firstOrNull;
                final id = 'img${seq++}';
                images[id] = DocxImage(
                  Uint8List.fromList(file.content as List<int>),
                  int.tryParse(ext?.getAttribute('cx') ?? '') ?? 3000000,
                  int.tryParse(ext?.getAttribute('cy') ?? '') ?? 2000000,
                  file.name,
                );
                // Block embeds sit on their own line.
                if (pending)
                  delta.insert(
                    '\n',
                    lineAttrs.isEmpty ? null : Map.of(lineAttrs),
                  );
                delta.insert({'docimage': id});
                // The picture's own line keeps the paragraph alignment.
                delta.insert(
                  '\n',
                  lineAttrs['align'] == null
                      ? null
                      : {'align': lineAttrs['align']},
                );
                pending = false;
                embedEnded = true;
              }
          }
        }
      }
    }

    final border = pPr
        ?.getElement('pBdr', namespaceUri: _w)
        ?.getElement('bottom', namespaceUri: _w);
    if (border != null &&
        p
            .findAllElements('t', namespaceUri: _w)
            .every((t) => t.innerText.trim().isEmpty) &&
        p.findAllElements('drawing', namespaceUri: _w).isEmpty) {
      delta.insert({'dochr': 'line'});
      delta.insert('\n');
      return;
    }
    runs(p.childElements);
    // A paragraph that ended with a picture already closed its line.
    if (pending || !embedEnded) {
      delta.insert('\n', lineAttrs.isEmpty ? null : lineAttrs);
    }
  }

  final sections = <String, String>{};
  void block(XmlElement el) {
    switch (el.name.local) {
      case 'p':
        paragraph(el);
        // A section break ends this paragraph's section.
        final sp = el
            .getElement('pPr', namespaceUri: _w)
            ?.getElement('sectPr', namespaceUri: _w);
        if (sp != null) {
          final id = 'sect${seq++}';
          sections[id] = sp.toXmlString();
          delta.insert({'docsect': id});
          delta.insert('\n');
        }
      case 'tbl':
        final id = 'tbl${seq++}';
        tables[id] = el.toXmlString();
        delta.insert({'doctable': id});
        delta.insert('\n');
      case 'sdt':
        // Content controls (cover page, TOC…): their blocks, tables included.
        for (final c
            in el.getElement('sdtContent', namespaceUri: _w)?.childElements ??
                const <XmlElement>[]) {
          block(c);
        }
    }
  }

  final body = doc.findAllElements('body', namespaceUri: _w).firstOrNull;
  for (final el in body?.childElements ?? const <XmlElement>[]) {
    block(el);
  }
  if (delta.isEmpty) delta.insert('\n');
  final page = DocxPageSetup();
  final sect = body?.childElements
      .where((e) => e.name.local == 'sectPr')
      .lastOrNull;
  int? tw(XmlElement? e, String a) =>
      int.tryParse(e?.getAttribute(a, namespaceUri: _w) ?? '');
  final sz = sect?.getElement('pgSz', namespaceUri: _w);
  final mar = sect?.getElement('pgMar', namespaceUri: _w);
  page
    ..width = tw(sz, 'w') ?? page.width
    ..height = tw(sz, 'h') ?? page.height
    ..top = tw(mar, 'top')?.abs() ?? page.top
    ..right = tw(mar, 'right') ?? page.right
    ..bottom = tw(mar, 'bottom')?.abs() ?? page.bottom
    ..left = tw(mar, 'left') ?? page.left;
  DocxRunning running(String kind) {
    final ref = sect
        ?.findElements('${kind}Reference', namespaceUri: _w)
        .where(
          (e) =>
              (e.getAttribute('type', namespaceUri: _w) ?? 'default') ==
              'default',
        )
        .firstOrNull;
    final target = rels[ref?.getAttribute('id', namespaceUri: _r)];
    if (target == null) return DocxRunning();
    final partName = 'word/${target.replaceFirst(RegExp(r'^/?word/'), '')}';
    final xml = part(partName);
    if (xml == null) return DocxRunning();
    final x = XmlDocument.parse(xml);
    final lines = <String>[];
    String? align;
    for (final para in x.findAllElements('p', namespaceUri: _w)) {
      align ??= para
          .getElement('pPr', namespaceUri: _w)
          ?.getElement('jc', namespaceUri: _w)
          ?.getAttribute('val', namespaceUri: _w);
      final b = StringBuffer();
      var inField = false;
      for (final e in para.descendantElements) {
        switch (e.name.local) {
          case 'fldSimple':
            final instr = (e.getAttribute('instr', namespaceUri: _w) ?? '')
                .trim()
                .toUpperCase();
            b.write(
              instr.startsWith('NUMPAGES')
                  ? '{PAGES}'
                  : (instr.startsWith('PAGE') ? '{PAGE}' : ''),
            );
          case 'instrText':
            final instr = e.innerText.trim().toUpperCase();
            if (instr.startsWith('NUMPAGES')) b.write('{PAGES}');
            if (instr.startsWith('PAGE')) b.write('{PAGE}');
          case 'fldChar':
            final t = e.getAttribute('fldCharType', namespaceUri: _w);
            if (t == 'begin') inField = true;
            if (t == 'end') inField = false;
          case 't':
            // Cached field results and fldSimple contents are not text.
            final inSimple = e.ancestorElements.any(
              (a) => a.name.local == 'fldSimple',
            );
            if (!inField && !inSimple) b.write(e.innerText);
          case 'tab':
            b.write('\t');
        }
      }
      lines.add(b.toString());
    }
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    return DocxRunning(
      text: lines.join('\n'),
      align: switch (align) {
        'right' || 'end' => 'right',
        'left' || 'start' => 'left',
        _ => 'center',
      },
      part: partName,
    );
  }

  final comments = <String, DocxComment>{};
  final commentsXml = part('word/comments.xml');
  if (commentsXml != null) {
    for (final c in XmlDocument.parse(
      commentsXml,
    ).findAllElements('comment', namespaceUri: _w)) {
      final id = c.getAttribute('id', namespaceUri: _w);
      if (id == null) continue;
      comments['c$id'] = DocxComment(
        text: c
            .findAllElements('p', namespaceUri: _w)
            .map(
              (p) => p
                  .findAllElements('t', namespaceUri: _w)
                  .map((t) => t.innerText)
                  .join(),
            )
            .join('\n'),
        author: c.getAttribute('author', namespaceUri: _w) ?? '',
        initials: c.getAttribute('initials', namespaceUri: _w) ?? '',
        date: DateTime.tryParse(c.getAttribute('date', namespaceUri: _w) ?? ''),
      );
    }
  }

  return DocxDocument(
    delta: _normalize(delta),
    images: images,
    tables: tables,
    original: archive,
    page: page,
    header: running('header'),
    footer: running('footer'),
    comments: comments,
    sections: sections,
  );
}

/// Quill wants the document to end with a newline and embeds alone on
/// their line; drop an empty leading line created by an embed.
Delta _normalize(Delta d) {
  final ops = d.toList();
  if (ops.isEmpty ||
      !(ops.last.data is String && (ops.last.data as String).endsWith('\n'))) {
    ops.add(Operation.insert('\n'));
  }
  final out = Delta();
  for (final o in ops) {
    out.push(o);
  }
  return out;
}

/// Text of a `<w:tbl>` as rows of cells (for previews / PDF export).
List<List<String>> docxTableRows(String tblXml) {
  final t = XmlDocument.parse(_tblNs(tblXml));
  return [
    for (final tr in t.findAllElements('tr', namespaceUri: _w))
      [
        for (final tc in tr.findElements('tc', namespaceUri: _w))
          tc
              .findAllElements('p', namespaceUri: _w)
              .map(
                (p) => p
                    .findAllElements('t', namespaceUri: _w)
                    .map((x) => x.innerText)
                    .join(),
              )
              .join('\n'),
      ],
  ];
}

/// A `<w:tbl>` cut out of document.xml has no namespace declaration of its
/// own; give it one so it parses on its own.
String _tblNs(String xml) => xml.contains('xmlns:w=')
    ? xml
    : xml.replaceFirst(RegExp(r'^<w:tbl\b'), '<w:tbl xmlns:w="$_w"');

/// A new bordered table with [cells] (rows of cell text), Word's "Table Grid"
/// look; [header] makes the first row bold.
String docxNewTable(List<List<String>> cells, {bool header = true}) {
  final cols = cells.fold<int>(1, (m, r) => r.length > m ? r.length : m);
  final colW = (9026 / cols).floor();
  const border = 'w:val="single" w:sz="4" w:space="0" w:color="auto"';
  final b = StringBuffer(
    '<w:tbl xmlns:w="$_w"><w:tblPr><w:tblW w:w="0" w:type="auto"/>'
    '<w:tblBorders><w:top $border/><w:left $border/><w:bottom $border/><w:right $border/>'
    '<w:insideH $border/><w:insideV $border/></w:tblBorders>'
    '<w:tblLook w:val="04A0" w:firstRow="1" w:lastRow="0" w:firstColumn="1" w:lastColumn="0" w:noHBand="0" w:noVBand="1"/></w:tblPr><w:tblGrid>',
  );
  for (var c = 0; c < cols; c++) {
    b.write('<w:gridCol w:w="$colW"/>');
  }
  b.write('</w:tblGrid>');
  for (var r = 0; r < cells.length; r++) {
    b.write('<w:tr>');
    for (var c = 0; c < cols; c++) {
      final text = c < cells[r].length ? cells[r][c] : '';
      final rPr = header && r == 0 ? '<w:rPr><w:b/></w:rPr>' : '';
      b.write('<w:tc><w:tcPr><w:tcW w:w="$colW" w:type="dxa"/></w:tcPr>');
      for (final line in text.split('\n')) {
        b.write(
          '<w:p><w:pPr><w:spacing w:after="0"/></w:pPr><w:r>$rPr<w:t xml:space="preserve">${_esc(line)}</w:t></w:r></w:p>',
        );
      }
      b.write('</w:tc>');
    }
    b.write('</w:tr>');
  }
  b.write('</w:tbl>');
  return b.toString();
}

/// [tblXml] with its cell text replaced by [cells]. Rows and columns are
/// added by copying the last one (keeping borders, shading and fonts) or
/// removed from the end; the formatting of the kept cells stays as it is.
String docxTableWithCells(String tblXml, List<List<String>> cells) {
  final doc = XmlDocument.parse(_tblNs(tblXml));
  final tbl = doc.rootElement;
  final cols = cells.fold<int>(1, (m, r) => r.length > m ? r.length : m);
  var rows = tbl.findElements('tr', namespaceUri: _w).toList();
  if (rows.isEmpty) return docxNewTable(cells);
  while (rows.length < cells.length) {
    final copy = rows.last.copy();
    tbl.children.insert(tbl.children.indexOf(rows.last) + 1, copy);
    rows.add(copy);
  }
  while (rows.length > cells.length && rows.length > 1) {
    tbl.children.remove(rows.removeLast());
  }
  final grid = tbl.getElement('tblGrid', namespaceUri: _w);
  if (grid != null) {
    final gc = grid.findElements('gridCol', namespaceUri: _w).toList();
    while (gc.length < cols && gc.isNotEmpty) {
      final c = gc.last.copy();
      grid.children.add(c);
      gc.add(c);
    }
    while (gc.length > cols && gc.length > 1) {
      grid.children.remove(gc.removeLast());
    }
  }
  for (var r = 0; r < rows.length; r++) {
    final tr = rows[r];
    final tcs = tr.findElements('tc', namespaceUri: _w).toList();
    while (tcs.length < cols && tcs.isNotEmpty) {
      final c = tcs.last.copy();
      tr.children.insert(tr.children.indexOf(tcs.last) + 1, c);
      tcs.add(c);
    }
    while (tcs.length > cols && tcs.length > 1) {
      tr.children.remove(tcs.removeLast());
    }
    for (var c = 0; c < tcs.length; c++) {
      final text = c < cells[r].length ? cells[r][c] : '';
      _setCellText(tcs[c], text);
    }
  }
  return doc.rootElement.toXmlString();
}

void _setCellText(XmlElement tc, String text) {
  final ps = tc.findElements('p', namespaceUri: _w).toList();
  final XmlElement first;
  if (ps.isEmpty) {
    first = XmlDocument.parse('<w:p xmlns:w="$_w"/>').rootElement.copy();
    tc.children.add(first);
  } else {
    first = ps.first;
    for (final extra in ps.skip(1)) {
      tc.children.remove(extra);
    }
  }
  final rPr = first
      .findAllElements('rPr', namespaceUri: _w)
      .where((e) => e.parentElement?.name.local == 'r')
      .firstOrNull
      ?.copy();
  first.children.removeWhere((n) => n is XmlElement && n.name.local != 'pPr');
  final lines = text.split('\n');
  XmlElement run(String t) => XmlDocument.parse(
    '<w:r xmlns:w="$_w">${rPr?.toXmlString() ?? ''}<w:t xml:space="preserve">${_esc(t)}</w:t></w:r>',
  ).rootElement.copy();
  if (lines.first.isNotEmpty) first.children.add(run(lines.first));
  var at = tc.children.indexOf(first);
  for (final l in lines.skip(1)) {
    final p = first.copy();
    p.children.removeWhere((n) => n is XmlElement && n.name.local != 'pPr');
    if (l.isNotEmpty) p.children.add(run(l));
    tc.children.insert(++at, p);
  }
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Word highlight names → colours.
const _highlights = {
  'yellow': '#FFFF00',
  'green': '#00FF00',
  'cyan': '#00FFFF',
  'magenta': '#FF00FF',
  'blue': '#0000FF',
  'red': '#FF0000',
  'darkBlue': '#000080',
  'darkCyan': '#008080',
  'darkGreen': '#008000',
  'darkMagenta': '#800080',
  'darkRed': '#800000',
  'darkYellow': '#808000',
  'darkGray': '#808080',
  'lightGray': '#C0C0C0',
  'black': '#000000',
};

// ----------------------------------------------------------------- write

/// Writes the document back to .docx. Styles, theme, headers, footers and
/// settings of the original package are kept; the body is regenerated from
/// the editor; pictures and tables are written back untouched.
Uint8List writeDocx(DocxDocument d) {
  final body = StringBuffer();
  final mediaRels = <String, String>{}; // target → rId
  var relSeq = 900;
  String relFor(String target) =>
      mediaRels.putIfAbsent(target, () => 'rIdDs${relSeq++}');

  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  var picId = 1;
  String drawing(DocxImage img) {
    final rid = relFor(img.target.replaceFirst('word/', ''));
    final id = picId++;
    return '<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="${img.widthEmu}" cy="${img.heightEmu}"/><wp:docPr id="$id" name="Picture $id"/>'
        '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
        '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:nvPicPr><pic:cNvPr id="$id" name="image$id"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="$rid"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="${img.widthEmu}" cy="${img.heightEmu}"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic>'
        '</wp:inline></w:drawing></w:r>';
  }

  final linkRels = <String, String>{}; // url → rId
  String runXml(String text, Map<String, dynamic>? a) {
    final rPr = StringBuffer();
    if (a != null) {
      if (a['font'] is String) {
        final f = esc(a['font'] as String);
        rPr.write('<w:rFonts w:ascii="$f" w:hAnsi="$f" w:cs="$f"/>');
      }
      if (a['bold'] == true) rPr.write('<w:b/>');
      if (a['italic'] == true) rPr.write('<w:i/>');
      if (a['strike'] == true) rPr.write('<w:strike/>');
      if (a['color'] is String) {
        rPr.write(
          '<w:color w:val="${(a['color'] as String).replaceFirst('#', '').toUpperCase()}"/>',
        );
      } else if (a['link'] != null) {
        rPr.write('<w:color w:val="0563C1"/>');
      }
      final size = double.tryParse('${a['size'] ?? ''}');
      if (size != null)
        rPr.write(
          '<w:sz w:val="${(size * 2).round()}"/><w:szCs w:val="${(size * 2).round()}"/>',
        );
      // Schema order: … sz, szCs, u, shd, vertAlign.
      if (a['underline'] == true || a['link'] != null)
        rPr.write('<w:u w:val="single"/>');
      final bg = a['background'];
      if (bg is String && bg.startsWith('#') && bg.length == 7) {
        rPr.write(
          '<w:shd w:val="clear" w:color="auto" w:fill="${bg.substring(1).toUpperCase()}"/>',
        );
      }
      if (a['script'] == 'super')
        rPr.write('<w:vertAlign w:val="superscript"/>');
      if (a['script'] == 'sub') rPr.write('<w:vertAlign w:val="subscript"/>');
    }
    final parts = text.split('\t');
    final r = StringBuffer('<w:r>${rPr.isEmpty ? '' : '<w:rPr>$rPr</w:rPr>'}');
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) r.write('<w:tab/>');
      if (parts[i].isNotEmpty)
        r.write('<w:t xml:space="preserve">${esc(parts[i])}</w:t>');
    }
    r.write('</w:r>');
    final link = a?['link'];
    if (link is String && link.isNotEmpty) {
      final rid = linkRels.putIfAbsent(link, () => 'rIdDsL${linkRels.length}');
      return '<w:hyperlink r:id="$rid">$r</w:hyperlink>';
    }
    return r.toString();
  }

  // Walk the delta line by line.
  var line = StringBuffer();
  void endLine(Map<String, dynamic>? la) {
    // Children in schema order: pStyle, numPr, spacing, ind, jc.
    final pPr = StringBuffer();
    final header = la?['header'];
    if (header is int) {
      pPr.write('<w:pStyle w:val="Heading$header"/>');
    } else if (la?['blockquote'] == true) {
      pPr.write('<w:pStyle w:val="Quote"/>');
    }
    final list = la?['list'];
    final isList =
        list == 'bullet' ||
        list == 'ordered' ||
        list == 'checked' ||
        list == 'unchecked';
    if (isList) {
      final lvl = (la?['indent'] as int?) ?? 0;
      pPr.write(
        '<w:numPr><w:ilvl w:val="$lvl"/><w:numId w:val="${list == 'ordered' ? _numOrdered : _numBullet}"/></w:numPr>',
      );
    }
    final lh = la?['line-height'];
    if (lh is num)
      pPr.write(
        '<w:spacing w:line="${(lh * 240).round()}" w:lineRule="auto"/>',
      );
    if (!isList && la?['indent'] is int) {
      pPr.write('<w:ind w:left="${(la!['indent'] as int) * 720}"/>');
    }
    final align = switch (la?['align']) {
      'center' => 'center',
      'right' => 'right',
      'justify' => 'both',
      _ => null,
    };
    if (align != null) pPr.write('<w:jc w:val="$align"/>');
    body.write('<w:p>${pPr.isEmpty ? '' : '<w:pPr>$pPr</w:pPr>'}$line</w:p>');
    line = StringBuffer();
  }

  // Suggestions: <w:ins> / <w:del> around runs (deleted text as delText).
  var revision = 100000; // apart from comment ids
  String trackedRun(String run, Map<String, dynamic>? a) {
    final ins = a?['ins'], del = a?['del'];
    final mark = (del ?? ins) as String?;
    if (mark == null) return run;
    final (author, date) = suggestionInfo(mark);
    final when = '${date.toUtc().toIso8601String().split('.').first}Z';
    final tag = del != null ? 'del' : 'ins';
    final body = del != null
        ? run
              .replaceAll(
                '<w:t xml:space="preserve">',
                '<w:delText xml:space="preserve">',
              )
              .replaceAll('</w:t>', '</w:delText>')
        : run;
    return '<w:$tag w:id="${revision++}" w:author="${esc(author)}" w:date="$when">$body</w:$tag>';
  }

  // Comment ranges: markers around the commented runs, numbered 0, 1, …
  final commentIds = <String, int>{};
  String? openComment;
  void closeComment() {
    final c = openComment;
    if (c == null) return;
    final n = commentIds[c]!;
    line.write(
      '<w:commentRangeEnd w:id="$n"/><w:r><w:rPr><w:rStyle w:val="CommentReference"/></w:rPr><w:commentReference w:id="$n"/></w:r>',
    );
    openComment = null;
  }

  void commentFor(Map<String, dynamic>? attrs) {
    final c = attrs?['comment'] as String?;
    final known = c != null && d.comments.containsKey(c);
    if (openComment != null && openComment != (known ? c : null))
      closeComment();
    if (known && openComment != c) {
      final n = commentIds.putIfAbsent(c, () => commentIds.length);
      line.write('<w:commentRangeStart w:id="$n"/>');
      openComment = c;
    }
  }

  // A block embed's own line end must not become an extra empty paragraph.
  var swallowNewline = false;
  var endsWithTable = false;
  for (final op in d.delta.toList()) {
    final data = op.data;
    final attrs = op.attributes;
    if (data is Map) {
      closeComment();
      if (data['docsect'] is String) {
        final xml = d.sections[data['docsect']];
        if (line.isNotEmpty) endLine(null);
        if (xml != null)
          body.write('<w:p><w:pPr>${_stripNs(xml)}</w:pPr></w:p>');
        swallowNewline = true;
        continue;
      }
      if (data['dochr'] != null) {
        if (line.isNotEmpty) endLine(null);
        body.write(
          '<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="auto"/></w:pBdr></w:pPr></w:p>',
        );
        swallowNewline = true;
        continue;
      }
      if (data['docbreak'] != null) {
        if (line.isNotEmpty) endLine(null);
        line.write('<w:r><w:br w:type="page"/></w:r>');
        continue;
      }
      if (data['docimage'] is String) {
        final img = d.images[data['docimage']];
        if (img != null) line.write(drawing(img));
      } else if (data['doctable'] is String) {
        final xml = d.tables[data['doctable']];
        if (xml != null) {
          if (line.isNotEmpty) endLine(null);
          body.write(_stripNs(xml));
          swallowNewline = true;
          endsWithTable = true;
        }
      }
      continue;
    }
    final text = data as String;
    final pieces = text.split('\n');
    for (var i = 0; i < pieces.length; i++) {
      if (pieces[i].isNotEmpty) {
        commentFor(attrs);
        line.write(trackedRun(runXml(pieces[i], attrs), attrs));
        swallowNewline = false;
        endsWithTable = false;
      }
      if (i < pieces.length - 1) {
        if (swallowNewline && line.isEmpty) {
          swallowNewline = false;
          continue;
        }
        endLine(attrs);
        endsWithTable = false;
      }
    }
  }
  closeComment();
  if (line.isNotEmpty) endLine(null);
  // Word needs a paragraph after a table that ends the body.
  if (endsWithTable) body.write('<w:p/>');

  // Header / footer parts (rewritten only when edited).
  final runningParts = <String, List<int>>{};
  final runningRefs = <(String, String)>[]; // (kind, rId)
  for (final (kind, r) in [('header', d.header), ('footer', d.footer)]) {
    if (!r.dirty) continue;
    if (r.isEmpty && r.part == null) continue;
    var partName = r.part;
    if (partName == null) {
      var n = 1;
      while (d.original?.findFile('word/$kind$n.xml') != null) {
        n++;
      }
      partName = 'word/${kind}Ds$n.xml';
      final rid = 'rIdDs${kind == 'header' ? 'H' : 'F'}';
      runningRefs.add((kind, rid));
      mediaRels[partName.replaceFirst('word/', '')] =
          rid; // written as relationship below
    }
    final jc = r.align == 'center'
        ? 'center'
        : (r.align == 'right' ? 'right' : 'left');
    final paras = StringBuffer();
    for (final l in r.text.split('\n')) {
      paras.write('<w:p><w:pPr><w:jc w:val="$jc"/></w:pPr>');
      final parts = l.split(RegExp(r'(\{PAGE\}|\{PAGES\})'));
      final fields = RegExp(r'\{PAGES?\}')
          .allMatches(l)
          .map((m) => m.group(0))
          .toList();
      for (var i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) paras.write(runXml(parts[i], null));
        if (i < fields.length) {
          final instr = fields[i] == '{PAGES}' ? 'NUMPAGES' : 'PAGE';
          paras.write(
            '<w:fldSimple w:instr=" $instr "><w:r><w:t>1</w:t></w:r></w:fldSimple>',
          );
        }
      }
      paras.write('</w:p>');
    }
    final root = kind == 'header' ? 'hdr' : 'ftr';
    runningParts[partName] = utf8.encode(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:$root xmlns:w="$_w" xmlns:r="$_r">$paras</w:$root>',
    );
  }
  var sectPr = _sectPrWith(_originalSectPr(d.original), d.page);
  if (runningRefs.isNotEmpty) {
    // References come first in sectPr.
    final refs = runningRefs
        .map((e) => '<w:${e.$1}Reference w:type="default" r:id="${e.$2}"/>')
        .join();
    sectPr = sectPr.replaceFirstMapped(
      RegExp(r'<w:sectPr[^>]*>'),
      (m) => '${m.group(0)}$refs',
    );
  }
  final documentXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="$_w" xmlns:r="$_r" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture" '
      'xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml" '
      'xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" mc:Ignorable="${_ignorable(d.original)}"${_extraNamespaces(d.original)}>'
      '<w:body>$body$sectPr</w:body></w:document>';

  // Package: originals first, then our parts on top.
  final files = <String, List<int>>{};
  final orig = d.original;
  if (orig != null) {
    for (final f in orig.files) {
      if (f.isFile) files[f.name] = f.content as List<int>;
    }
  }
  for (final img in d.images.values) {
    files.putIfAbsent(img.target, () => img.bytes);
  }
  files['word/document.xml'] = utf8.encode(documentXml);
  files.addAll(runningParts);
  // Comments: ours replace the original part; Word's companion parts
  // (extended / ids / extensible) describe the old set, so they go.
  const commentCompanions = {
    'commentsExtended',
    'commentsIds',
    'commentsExtensible',
  };
  final hadComments = files.containsKey('word/comments.xml');
  if (commentIds.isNotEmpty || hadComments) {
    for (final n in [
      'word/commentsExtended.xml',
      'word/commentsIds.xml',
      'word/commentsExtensible.xml',
    ]) {
      files.remove(n);
    }
    final b = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:comments xmlns:w="$_w">',
    );
    commentIds.forEach((key, n) {
      final c = d.comments[key]!;
      final ini = c.initials.isNotEmpty
          ? c.initials
          : c.author
                .split(RegExp(r'\s+'))
                .where((w) => w.isNotEmpty)
                .map((w) => w[0].toUpperCase())
                .take(2)
                .join();
      b.write(
        '<w:comment w:id="$n" w:author="${esc(c.author)}" w:date="${c.date.toUtc().toIso8601String().split('.').first}Z" w:initials="${esc(ini)}">',
      );
      for (final l in c.text.split('\n')) {
        b.write(
          '<w:p><w:r><w:t xml:space="preserve">${esc(l)}</w:t></w:r></w:p>',
        );
      }
      b.write('</w:comment>');
    });
    b.write('</w:comments>');
    files['word/comments.xml'] = utf8.encode(b.toString());
  }
  files['word/numbering.xml'] = utf8.encode(
    _numberingWith(files['word/numbering.xml']),
  );
  if (!files.containsKey('word/styles.xml'))
    files['word/styles.xml'] = utf8.encode(_stylesXml);

  // Relationships: keep the originals and add ours (unique ids).
  final rel = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
  );
  final keptTypes = <String>{};
  if (orig != null && files['word/_rels/document.xml.rels'] != null) {
    final x = XmlDocument.parse(
      utf8.decode(files['word/_rels/document.xml.rels']!),
    );
    for (final r in x.findAllElements('Relationship')) {
      final type = r.getAttribute('Type') ?? '';
      if (commentCompanions.contains(type.split('/').last) &&
          !files.containsKey('word/${r.getAttribute('Target') ?? ''}'))
        continue;
      // Kept as-is: tables, headers and footers may still point at them.
      keptTypes.add(type.split('/').last);
      rel.write(r.toXmlString());
    }
  }
  if (!keptTypes.contains('styles')) {
    rel.write(
      '<Relationship Id="rIdDsS" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>',
    );
  }
  if (files.containsKey('word/comments.xml') &&
      !keptTypes.contains('comments')) {
    rel.write(
      '<Relationship Id="rIdDsC" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments" Target="comments.xml"/>',
    );
  }
  if (!keptTypes.contains('numbering')) {
    rel.write(
      '<Relationship Id="rIdDsN" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>',
    );
  }
  mediaRels.forEach((target, id) {
    final type = target.startsWith('headerDs')
        ? 'header'
        : (target.startsWith('footerDs') ? 'footer' : 'image');
    rel.write(
      '<Relationship Id="$id" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/$type" Target="$target"/>',
    );
  });
  linkRels.forEach((url, id) {
    rel.write(
      '<Relationship Id="$id" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="${esc(url)}" TargetMode="External"/>',
    );
  });
  rel.write('</Relationships>');
  files['word/_rels/document.xml.rels'] = utf8.encode(rel.toString());
  files.putIfAbsent(
    '_rels/.rels',
    () => utf8.encode(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '</Relationships>',
    ),
  );
  files['[Content_Types].xml'] = utf8.encode(
    _contentTypes(files.keys, files['[Content_Types].xml']),
  );

  final out = Archive();
  for (final e in files.entries) {
    out.addFile(ArchiveFile(e.key, e.value.length, e.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(out));
}

String? _originalSectPr(Archive? a) {
  final f = a?.findFile('word/document.xml');
  if (f == null) return null;
  try {
    final x = XmlDocument.parse(utf8.decode(f.content as List<int>));
    final body = x.findAllElements('body', namespaceUri: _w).firstOrNull;
    final s = body?.childElements
        .where((e) => e.name.local == 'sectPr')
        .lastOrNull;
    return s == null ? null : _stripNs(s.toXmlString());
  } catch (_) {
    return null;
  }
}

/// The section properties with [page]'s size and margins (headers, footers
/// and columns of the original kept).
String _sectPrWith(String? original, DocxPageSetup page) {
  final x = XmlDocument.parse(
    original == null
        ? '<w:sectPr xmlns:w="$_w"><w:pgSz/><w:pgMar w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>'
        : original.replaceFirst('<w:sectPr', '<w:sectPr xmlns:w="$_w"'),
  );
  final root = x.rootElement;
  XmlElement child(String name) {
    final e = root.getElement(name, namespaceUri: _w);
    if (e != null) return e;
    final n = XmlDocument.parse('<w:$name xmlns:w="$_w"/>').rootElement.copy();
    root.children.add(n);
    return n;
  }

  void set(XmlElement e, String a, int v) {
    e.removeAttribute(a, namespaceUri: _w);
    e.attributes.add(XmlAttribute(XmlName.parts(a, prefix: 'w'), '$v'));
  }

  final sz = child('pgSz');
  set(sz, 'w', page.width);
  set(sz, 'h', page.height);
  sz.removeAttribute('orient', namespaceUri: _w);
  if (page.landscape)
    sz.attributes.add(
      XmlAttribute(XmlName.parts('orient', prefix: 'w'), 'landscape'),
    );
  final mar = child('pgMar');
  set(mar, 'top', page.top);
  set(mar, 'right', page.right);
  set(mar, 'bottom', page.bottom);
  set(mar, 'left', page.left);
  return _stripNs(root.toXmlString());
}

/// Element XML copied from another document: drop repeated xmlns
/// declarations (the root declares them).
String _stripNs(String xml) =>
    xml.replaceAll(RegExp(r'\s+xmlns:(w|r|wp|a|pic|w14|mc)="[^"]*"'), '');

/// Namespace declarations of the original document root that ours lacks,
/// so copied tables / section XML (w15, wp14, v, o, m…) stay valid.
String _extraNamespaces(Archive? a) {
  final root = _originalRoot(a);
  if (root == null) return '';
  const ours = {'w', 'r', 'wp', 'a', 'pic', 'w14', 'mc'};
  final b = StringBuffer();
  for (final at in root.attributes) {
    if (at.name.prefix == 'xmlns' && !ours.contains(at.name.local)) {
      b.write(' xmlns:${at.name.local}="${at.value}"');
    }
  }
  return b.toString();
}

/// mc:Ignorable of the original (only prefixes we declare), plus w14.
String _ignorable(Archive? a) {
  final root = _originalRoot(a);
  final declared = {
    'w14',
    for (final at in root?.attributes ?? const <XmlAttribute>[])
      if (at.name.prefix == 'xmlns') at.name.local,
  };
  final orig =
      root?.attributes
          .where((at) => at.name.local == 'Ignorable')
          .firstOrNull
          ?.value
          .split(RegExp(r'\s+')) ??
      const <String>[];
  return {'w14', ...orig.where(declared.contains)}.join(' ');
}

XmlElement? _originalRoot(Archive? a) {
  final f = a?.findFile('word/document.xml');
  if (f == null) return null;
  try {
    // Only the root start tag is needed.
    final text = utf8.decode(f.content as List<int>, allowMalformed: true);
    final start = text.indexOf('<w:document');
    final end = start < 0 ? -1 : text.indexOf('>', start);
    if (end < 0) return null;
    return XmlDocument.parse(
      '${text.substring(start, end).replaceFirst(RegExp(r'/$'), '')}/>',
    ).rootElement;
  } catch (_) {
    return null;
  }
}

const _numBullet = 9001, _numOrdered = 9002;

/// Our two list definitions added to the original numbering part (tables,
/// headers and styles keep using their own numIds).
String _numberingWith(List<int>? original) {
  if (original == null) return _numberingXml;
  try {
    final doc = XmlDocument.parse(utf8.decode(original, allowMalformed: true));
    final root = doc.rootElement;
    final ours = XmlDocument.parse(_numberingXml).rootElement;
    for (final id in [_numBullet, _numOrdered]) {
      root.children.removeWhere(
        (n) =>
            n is XmlElement &&
            ((n.name.local == 'num' &&
                    n.getAttribute('numId', namespaceUri: _w) == '$id') ||
                (n.name.local == 'abstractNum' &&
                    n.getAttribute('abstractNumId', namespaceUri: _w) ==
                        '$id')),
      );
    }
    // All abstractNum elements come before the first num.
    final firstNum = root.childElements
        .where((e) => e.name.local == 'num')
        .firstOrNull;
    var at = firstNum == null
        ? root.children.length
        : root.children.indexOf(firstNum);
    for (final a in ours.findElements('abstractNum', namespaceUri: _w)) {
      root.children.insert(at++, a.copy());
    }
    for (final n in ours.findElements('num', namespaceUri: _w)) {
      root.children.add(n.copy());
    }
    return doc.toXmlString();
  } catch (_) {
    return _numberingXml;
  }
}

String _contentTypes(Iterable<String> names, List<int>? original) {
  final have = names.toSet();
  final kept = StringBuffer();
  final keptDefaults = <String>{}, keptOverrides = <String>{};
  if (original != null) {
    try {
      for (final e in XmlDocument.parse(
        utf8.decode(original, allowMalformed: true),
      ).rootElement.childElements) {
        if (e.name.local == 'Default') {
          final ext = (e.getAttribute('Extension') ?? '').toLowerCase();
          if (keptDefaults.add(ext))
            kept.write(
              '<Default Extension="$ext" ContentType="${e.getAttribute('ContentType')}"/>',
            );
        } else if (e.name.local == 'Override') {
          final part = (e.getAttribute('PartName') ?? '').replaceFirst('/', '');
          if (have.contains(part) && keptOverrides.add(part)) {
            kept.write(
              '<Override PartName="/$part" ContentType="${e.getAttribute('ContentType')}"/>',
            );
          }
        }
      }
    } catch (_) {}
  }
  return _contentTypesFrom(names, kept.toString(), keptDefaults, keptOverrides);
}

String _contentTypesFrom(
  Iterable<String> names,
  String kept,
  Set<String> keptDefaults,
  Set<String> keptOverrides,
) {
  final b = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">$kept',
  );
  const defaults = {
    'rels': 'application/vnd.openxmlformats-package.relationships+xml',
    'xml': 'application/xml',
    'png': 'image/png',
    'jpeg': 'image/jpeg',
    'jpg': 'image/jpeg',
    'gif': 'image/gif',
    'bmp': 'image/bmp',
    'emf': 'image/x-emf',
    'wmf': 'image/x-wmf',
    'svg': 'image/svg+xml',
  };
  defaults.forEach((ext, type) {
    if (!keptDefaults.contains(ext))
      b.write('<Default Extension="$ext" ContentType="$type"/>');
  });
  const overrides = {
    'word/document.xml': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml',
    'word/styles.xml': 'application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml',
    'word/numbering.xml': 'application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml',
    'word/settings.xml': 'application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml',
    'word/fontTable.xml': 'application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml',
    'word/webSettings.xml': 'application/vnd.openxmlformats-officedocument.wordprocessingml.webSettings+xml',
    'word/theme/theme1.xml':
        'application/vnd.openxmlformats-officedocument.theme+xml',
    'word/footnotes.xml': 'application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml',
    'word/endnotes.xml': 'application/vnd.openxmlformats-officedocument.wordprocessingml.endnotes+xml',
    'word/comments.xml': 'application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml',
    'docProps/core.xml':
        'application/vnd.openxmlformats-package.core-properties+xml',
    'docProps/app.xml':
        'application/vnd.openxmlformats-officedocument.extended-properties+xml',
  };
  for (final n in names) {
    if (keptOverrides.contains(n)) continue;
    final t =
        overrides[n] ??
        (RegExp(r'^word/header(Ds)?\d+\.xml$').hasMatch(n)
            ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml'
            : RegExp(r'^word/footer(Ds)?\d+\.xml$').hasMatch(n)
            ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml'
            : null);
    if (t != null) b.write('<Override PartName="/$n" ContentType="$t"/>');
  }
  b.write('</Types>');
  return b.toString();
}

const _numberingXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:numbering xmlns:w="$_w">'
    '<w:abstractNum w:abstractNumId="9001"><w:multiLevelType w:val="hybridMultilevel"/>'
    '<w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="•"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl>'
    '<w:lvl w:ilvl="1"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="◦"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="1440" w:hanging="360"/></w:pPr></w:lvl>'
    '<w:lvl w:ilvl="2"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="▪"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="2160" w:hanging="360"/></w:pPr></w:lvl>'
    '</w:abstractNum>'
    '<w:abstractNum w:abstractNumId="9002"><w:multiLevelType w:val="hybridMultilevel"/>'
    '<w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl>'
    '<w:lvl w:ilvl="1"><w:start w:val="1"/><w:numFmt w:val="lowerLetter"/><w:lvlText w:val="%2."/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="1440" w:hanging="360"/></w:pPr></w:lvl>'
    '<w:lvl w:ilvl="2"><w:start w:val="1"/><w:numFmt w:val="lowerRoman"/><w:lvlText w:val="%3."/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="2160" w:hanging="360"/></w:pPr></w:lvl>'
    '</w:abstractNum>'
    '<w:num w:numId="9001"><w:abstractNumId w:val="9001"/></w:num>'
    '<w:num w:numId="9002"><w:abstractNumId w:val="9002"/></w:num>'
    '</w:numbering>';

const _stylesXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:styles xmlns:w="$_w">'
    '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/><w:sz w:val="22"/></w:rPr></w:rPrDefault>'
    '<w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="259" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
    '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="240" w:after="80"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="36"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="200" w:after="60"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:sz w:val="30"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/><w:sz w:val="26"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading4"><w:name w:val="heading 4"/><w:basedOn w:val="Normal"/><w:rPr><w:b/><w:i/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading5"><w:name w:val="heading 5"/><w:basedOn w:val="Normal"/><w:rPr><w:b/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading6"><w:name w:val="heading 6"/><w:basedOn w:val="Normal"/><w:rPr><w:i/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="720"/></w:pPr><w:rPr><w:i/><w:color w:val="555555"/></w:rPr></w:style>'
    '</w:styles>';
