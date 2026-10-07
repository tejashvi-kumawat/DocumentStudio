import 'dart:convert';

import 'package:document_studio/features/compose/compose_model.dart';
import 'package:document_studio/features/office/docx_io.dart';
import 'package:flutter/painting.dart' show Color;

/// The edited Word document → typeset model (for PDF export / print).
ComposeDoc docxToCompose(DocxDocument d) {
  final blocks = <CBlock>[];
  var line = <CInline>[];
  List<List<CBlock>>? listItems;
  var listOrdered = false;

  void flushList() {
    if (listItems != null && listItems!.isNotEmpty) {
      blocks.add(CList(listItems!, ordered: listOrdered));
    }
    listItems = null;
  }

  CInline inline(String text, Map<String, dynamic>? a) {
    int? color;
    final c = a?['color'];
    if (c is String && c.startsWith('#') && c.length == 7) {
      color = Color(0xFF000000 | int.parse(c.substring(1), radix: 16))
          .toARGB32();
    }
    final size = double.tryParse('${a?['size'] ?? ''}');
    return CInline(
      text,
      bold: a?['bold'] == true,
      italic: a?['italic'] == true,
      underline: a?['underline'] == true,
      strike: a?['strike'] == true,
      code: a?['code'] == true,
      link: a?['link'] as String?,
      color: color ?? (a?['link'] != null ? 0xFF0563C1 : null),
      scale: size == null ? 1 : (size / 11).clamp(0.5, 4.0),
      superscript: a?['script'] == 'super',
      subscript: a?['script'] == 'sub',
    );
  }

  void endLine(Map<String, dynamic>? la) {
    final inl = line;
    line = [];
    final list = la?['list'];
    if (list != null) {
      final ordered = list == 'ordered';
      if (listItems == null || listOrdered != ordered) {
        flushList();
        listItems = [];
        listOrdered = ordered;
      }
      listItems!.add([CPara(inl)]);
      return;
    }
    flushList();
    final header = la?['header'];
    if (header is int) {
      blocks.add(CHeading(header, inl));
      return;
    }
    final align = switch (la?['align']) {
      'center' => CAlign.center,
      'right' => CAlign.right,
      'justify' => CAlign.justify,
      _ => CAlign.left,
    };
    final para = CPara(inl, align: align);
    if (la?['blockquote'] == true) {
      blocks.add(CQuote([para]));
    } else if (la?['code-block'] == true) {
      blocks.add(CCode(inl.map((i) => i.text).join()));
    } else {
      blocks.add(inl.isEmpty ? const CSpace(6) : para);
    }
  }

  for (final op in d.delta.toList()) {
    final data = op.data;
    if (data is Map) {
      flushList();
      if (data['docsect'] != null) {
        if (line.isNotEmpty) endLine(null);
        blocks.add(const CPageBreak());
      } else if (data['dochr'] != null) {
        if (line.isNotEmpty) endLine(null);
        blocks.add(const CRule());
      } else if (data['docbreak'] != null) {
        if (line.isNotEmpty) endLine(null);
        blocks.add(const CPageBreak());
      } else if (data['docimage'] is String) {
        final img = d.images[data['docimage']];
        if (img != null) {
          blocks.add(
            CImage(
              'data:image;base64,${base64Encode(img.bytes)}',
              widthFraction: (img.widthEmu / 5943600).clamp(0.05, 1.0),
            ),
          );
        }
      } else if (data['doctable'] is String) {
        final xml = d.tables[data['doctable']];
        if (xml != null) {
          final rows = docxTableRows(xml);
          blocks.add(
            CTable([
              for (final r in rows)
                [
                  for (final c in r) [CInline(c)],
                ],
            ]),
          );
        }
      }
      continue;
    }
    final text = data as String;
    final parts = text.split('\n');
    for (var i = 0; i < parts.length; i++) {
      // Suggested deletions are not part of the exported text.
      if (parts[i].isNotEmpty && op.attributes?['del'] == null)
        line.add(inline(parts[i], op.attributes));
      if (i < parts.length - 1) endLine(op.attributes);
    }
  }
  if (line.isNotEmpty) endLine(null);
  flushList();
  final pg = d.page;
  return ComposeDoc(
    blocks: blocks,
    baseFontSize: 11,
    pageSize: '${pg.width / 20}x${pg.height / 20}',
    marginPt: pg.left / 20,
    pageHeader: d.header.isEmpty ? null : d.header.text,
    pageFooter: d.footer.isEmpty ? '' : d.footer.text,
    headerAlign: _align(d.header.align),
    footerAlign: _align(d.footer.align),
  );
}

CAlign _align(String a) => switch (a) {
  'left' => CAlign.left,
  'right' => CAlign.right,
  _ => CAlign.center,
};
