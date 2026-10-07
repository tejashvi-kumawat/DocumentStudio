import 'dart:typed_data';
import 'package:xml/xml.dart';
import 'package:archive/archive.dart';
import 'dart:convert';
import 'dart:io';

import 'package:document_studio/features/office/docx_io.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('blank → write → read round trip keeps styles', () {
    final d = DocxDocument.blank();
    final delta = Delta()
      ..insert('Title')
      ..insert('\n', {'header': 1})
      ..insert('Bold', {'bold': true})
      ..insert(' and ')
      ..insert('red', {'color': '#D32F2F', 'italic': true})
      ..insert('\n', {'align': 'center'})
      ..insert('one')
      ..insert('\n', {'list': 'bullet'})
      ..insert('two')
      ..insert('\n', {'list': 'ordered'})
      ..insert('link', {'link': 'https://example.com'})
      ..insert('\n');
    final bytes = writeDocx(DocxDocument(delta: delta, images: d.images, tables: d.tables));
    final back = readDocx(bytes);
    final ops = back.delta.toList();
    final text = ops.where((o) => o.data is String).map((o) => o.data).join();
    expect(text, 'Title\nBold and red\none\ntwo\nlink\n');
    expect(ops.firstWhere((o) => o.data == 'Bold').attributes?['bold'], true);
    expect(ops.firstWhere((o) => o.data == 'red').attributes?['color'], '#D32F2F');
    final nl = ops.where((o) => o.data == '\n').toList();
    expect(nl[0].attributes?['header'], 1);
    expect(nl[1].attributes?['align'], 'center');
    expect(nl[2].attributes?['list'], 'bullet');
    expect(nl[3].attributes?['list'], 'ordered');
    expect(ops.firstWhere((o) => o.data == 'link').attributes?['link'], 'https://example.com');
  });

  test('real document reads and rewrites without losing pictures or tables', () {
    final f = File('/home/tejashvi-sprix/Downloads/lab5 sp.docx');
    if (!f.existsSync()) return;
    final d = readDocx(f.readAsBytesSync());
    final out = writeDocx(d);
    final again = readDocx(out);
    expect(again.images.length, d.images.length);
    expect(again.tables.length, d.tables.length);
    final t1 = d.delta.toList().where((o) => o.data is String).map((o) => o.data).join();
    final t2 = again.delta.toList().where((o) => o.data is String).map((o) => o.data).join();
    expect(t2, t1);
    final p = Platform.environment['DS_DOCX_OUT'];
    if (p != null) File(p).writeAsBytesSync(out);
  });

  test('page setup, page breaks, line spacing, highlight and tables round-trip', () {
    final cells = [
      ['Item', 'Qty'],
      ['Pens', '4'],
    ];
    final delta = Delta()
      ..insert('Spaced', {'background': '#FFFF00'})
      ..insert('\n', {'line-height': 1.5})
      ..insert({'docbreak': 'page'})
      ..insert('\n')
      ..insert({'doctable': 't'})
      ..insert('\n')
      ..insert('After\n');
    final page = DocxPageSetup(width: 16838, height: 11906, top: 720, right: 720, bottom: 720, left: 720);
    final bytes = writeDocx(DocxDocument(
      delta: delta,
      images: {},
      tables: {'t': docxNewTable(cells)},
      page: page,
    ));
    final back = readDocx(bytes);
    expect(back.page, page);
    expect(back.page.landscape, isTrue);
    final ops = back.delta.toList();
    expect(ops.firstWhere((o) => o.data == 'Spaced').attributes?['background'], '#FFFF00');
    expect(ops.where((o) => o.data is Map && (o.data as Map)['docbreak'] != null), hasLength(1));
    expect(back.tables, hasLength(1));
    expect(docxTableRows(back.tables.values.first), cells);
    final nl = ops.firstWhere((o) => o.data is String && (o.data as String).startsWith('\n'));
    expect(nl.attributes?['line-height'], 1.5);
    // Writing again does not grow empty paragraphs around the table.
    final again = readDocx(writeDocx(back));
    String plain(DocxDocument d) => d.delta.toList().map((o) => o.data is String ? o.data : '#').join();
    expect(plain(again), plain(back));
  });

  test('editing table cells keeps the table and adds/removes rows and columns', () {
    final xml = docxNewTable([
      ['a', 'b'],
      ['c', 'd'],
    ]);
    final grown = docxTableWithCells(xml, [
      ['A', 'B', 'X'],
      ['C', 'D', 'Y'],
      ['E', 'F', 'Z'],
    ]);
    expect(docxTableRows(grown), [
      ['A', 'B', 'X'],
      ['C', 'D', 'Y'],
      ['E', 'F', 'Z'],
    ]);
    expect(grown, contains('<w:b/>')); // header row formatting kept
    final shrunk = docxTableWithCells(grown, [
      ['only'],
    ]);
    expect(docxTableRows(shrunk), [
      ['only'],
    ]);
  });

  test('header, footer with page fields and horizontal lines round-trip', () {
    final d = DocxDocument(
      delta: Delta()
        ..insert('Above\n')
        ..insert({'dochr': 'line'})
        ..insert('\nBelow\n'),
      images: {},
      tables: {},
    );
    d.header
      ..text = 'Quarterly report'
      ..align = 'right'
      ..dirty = true;
    d.footer
      ..text = 'Page {PAGE} of {PAGES}'
      ..dirty = true;
    final bytes = writeDocx(d);
    final back = readDocx(bytes);
    expect(back.header.text, 'Quarterly report');
    expect(back.header.align, 'right');
    expect(back.footer.text, 'Page {PAGE} of {PAGES}');
    expect(back.footer.align, 'center');
    expect(back.delta.toList().where((o) => o.data is Map && (o.data as Map)['dochr'] != null), hasLength(1));
    // Editing an existing footer rewrites its part.
    back.footer
      ..text = '{PAGE}'
      ..align = 'right'
      ..dirty = true;
    final again = readDocx(writeDocx(back));
    expect(again.footer.text, '{PAGE}');
    expect(again.footer.align, 'right');
    expect(again.header.text, 'Quarterly report');
  });

  test('comments round-trip as Word comments anchored to their text', () {
    final d = DocxDocument(
      delta: Delta()
        ..insert('Plain ')
        ..insert('reviewed words', {'comment': 'k1', 'bold': true})
        ..insert(' tail\nNext line ')
        ..insert('second', {'comment': 'k2'})
        ..insert('\n'),
      images: {},
      tables: {},
      comments: {
        'k1': DocxComment(text: 'Please check this', author: 'Tejashvi Kumawat'),
        'k2': DocxComment(text: 'Two\nlines', author: 'Reviewer'),
      },
    );
    final bytes = writeDocx(d);
    final back = readDocx(bytes);
    expect(back.comments.values.map((c) => c.text), ['Please check this', 'Two\nlines']);
    expect(back.comments.values.first.author, 'Tejashvi Kumawat');
    final ops = back.delta.toList();
    final marked = ops.where((o) => o.attributes?['comment'] != null).map((o) => o.data).toList();
    expect(marked, ['reviewed words', 'second']);
    expect(ops.firstWhere((o) => o.data == 'reviewed words').attributes?['bold'], true);
    // Text outside the ranges is not commented.
    expect(ops.firstWhere((o) => o.data is String && (o.data as String).contains('tail')).attributes?['comment'], isNull);
  });

  test('save keeps numbering, content types, namespaces, content controls and sections', () {
    const w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
    final docXml = '<?xml version="1.0" encoding="UTF-8"?>'
        '<w:document xmlns:w="$w" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:w15="http://schemas.microsoft.com/office/word/2012/wordml" '
        'xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" mc:Ignorable="w15"><w:body>'
        '<w:p><w:r><w:t>Intro</w:t></w:r></w:p>'
        '<w:tbl><w:tr><w:tc><w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="5"/></w:numPr><w15:collapsed/></w:pPr><w:r><w:t>cell</w:t></w:r></w:p></w:tc></w:tr></w:tbl>'
        '<w:sdt><w:sdtContent><w:p><w:r><w:t>In control</w:t></w:r></w:p>'
        '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>sdt cell</w:t></w:r></w:p></w:tc></w:tr></w:tbl></w:sdtContent></w:sdt>'
        '<w:p><w:pPr><w:sectPr><w:pgSz w:w="11906" w:h="16838"/></w:sectPr></w:pPr><w:r><w:t>End of section 1</w:t></w:r></w:p>'
        '<w:p><w:r><w:t>Section 2</w:t></w:r></w:p>'
        '<w:sectPr><w:pgSz w:w="16838" w:h="11906" w:orient="landscape"/></w:sectPr></w:body></w:document>';
    final numbering = '<?xml version="1.0"?><w:numbering xmlns:w="$w">'
        '<w:abstractNum w:abstractNumId="3"><w:lvl w:ilvl="0"><w:numFmt w:val="decimal"/></w:lvl></w:abstractNum>'
        '<w:num w:numId="5"><w:abstractNumId w:val="3"/></w:num></w:numbering>';
    final types = '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Default Extension="tif" ContentType="image/tiff"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/customXml/itemProps1.xml" ContentType="application/vnd.openxmlformats-officedocument.customXmlProperties+xml"/>'
        '</Types>';
    final a = Archive();
    void add(String n, String t) {
      final b = utf8.encode(t);
      a.addFile(ArchiveFile(n, b.length, b));
    }

    add('[Content_Types].xml', types);
    add('word/document.xml', docXml);
    add('word/numbering.xml', numbering);
    add('customXml/itemProps1.xml', '<ds:datastoreItem xmlns:ds="http://schemas.openxmlformats.org/officeDocument/2006/customXml"/>');
    add('_rels/.rels', '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>');
    final d = readDocx(Uint8List.fromList(ZipEncoder().encode(a)));
    expect(d.tables, hasLength(2), reason: 'the table inside the content control is kept');
    expect(d.sections, hasLength(1));
    final out = ZipDecoder().decodeBytes(writeDocx(d));
    String part(String n) => utf8.decode(out.findFile(n)!.content as List<int>);
    // Valid XML, with w15 declared for the copied table.
    final saved = XmlDocument.parse(part('word/document.xml'));
    expect(part('word/document.xml'), contains('xmlns:w15='));
    expect(saved.findAllElements('sectPr', namespaceUri: w), hasLength(2));
    // The table's numId 5 still exists; ours were added beside it.
    final num = part('word/numbering.xml');
    expect(num, contains('w:numId="5"'));
    expect(num, contains('w:numId="9001"'));
    // Custom part keeps its content type; tif default kept.
    final ct = part('[Content_Types].xml');
    expect(ct, contains('/customXml/itemProps1.xml'));
    expect(ct, contains('Extension="tif"'));
    final again = readDocx(writeDocx(d));
    expect(again.sections, hasLength(1));
    expect(again.page.landscape, isTrue);
  });

  test('suggestions are Word tracked changes (w:ins / w:del)', () {
    final mark = suggestionMark('Reviewer', DateTime.utc(2026, 10, 7, 9, 30));
    final d = DocxDocument(
      delta: Delta()
        ..insert('Keep ')
        ..insert('old', {'del': mark})
        ..insert('new', {'ins': mark})
        ..insert(' end\n'),
      images: {},
      tables: {},
    );
    final bytes = writeDocx(d);
    final xml = utf8.decode(ZipDecoder().decodeBytes(bytes).findFile('word/document.xml')!.content as List<int>);
    expect(xml, contains('<w:del '));
    expect(xml, contains('<w:delText xml:space="preserve">old</w:delText>'));
    expect(xml, contains('<w:ins '));
    expect(xml, contains('w:author="Reviewer"'));
    final back = readDocx(bytes);
    final ops = back.delta.toList();
    expect(ops.firstWhere((o) => o.data == 'old').attributes?['del'], isNotNull);
    expect(ops.firstWhere((o) => o.data == 'new').attributes?['ins'], isNotNull);
    expect(suggestionInfo(ops.firstWhere((o) => o.data == 'new').attributes!['ins'] as String).$1, 'Reviewer');
  });
}
