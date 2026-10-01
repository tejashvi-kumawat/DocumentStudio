import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:archive/archive.dart';
import 'package:document_studio/core/pdf/pdf_document_cache.dart';
import 'package:document_studio/infrastructure/conversion/text_to_pdf_layout.dart';
import 'package:document_studio/infrastructure/conversion/text_to_pdf_service.dart';
import 'package:path/path.dart' as p;

/// On-device Office ↔ PDF without LibreOffice (Android / fallback).
///
/// Fidelity is plain text: layout, images, and charts are not preserved.
class DartOfficeConvertService {
  DartOfficeConvertService({TextToPdfService? textToPdf})
      : _textToPdf = textToPdf ?? TextToPdfService();

  final TextToPdfService _textToPdf;

  static const fidelityNote =
      'Plain-text conversion on this device (layout and images are not kept).';

  /// Extensions this path can turn into PDF.
  static const officeToPdfExtensions = ['docx', 'txt', 'text', 'md'];

  /// True when [path] can be converted Office → PDF on-device.
  static bool canConvertOfficeToPdf(String path) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    return officeToPdfExtensions.contains(ext);
  }

  /// PDF → .docx (extracted text + simple paragraphs).
  Future<Uint8List> pdfToDocx({
    required String pdfPath,
    String? password,
    void Function(double fraction, String message)? onProgress,
  }) async {
    onProgress?.call(0.05, 'Opening PDF…');
    final lease = await PdfDocumentCache.instance.acquire(
      pdfPath,
      password: password,
    );
    try {
      final doc = lease.document;
      final pageCount = doc.pages.length;
      final paragraphs = <String>[];
      for (var i = 0; i < pageCount; i++) {
        onProgress?.call(
          0.05 + 0.85 * (i + 1) / (pageCount == 0 ? 1 : pageCount),
          'Reading page ${i + 1} of $pageCount…',
        );
        try {
          final loaded = await doc.pages[i].loadText();
          final text = loaded?.fullText.trim() ?? '';
          if (text.isEmpty) continue;
          if (paragraphs.isNotEmpty) paragraphs.add('');
          for (final block in text.split(RegExp(r'\n{2,}'))) {
            final line = block.replaceAll('\r\n', '\n').trim();
            if (line.isNotEmpty) paragraphs.add(line);
          }
        } catch (_) {}
      }
      if (paragraphs.every((e) => e.trim().isEmpty)) {
        paragraphs
          ..clear()
          ..add('(No extractable text in this PDF.)');
      }
      onProgress?.call(0.95, 'Writing Word document…');
      return buildDocxFromParagraphs(paragraphs);
    } finally {
      lease.release();
    }
  }

  /// .docx / .txt / .md → PDF via [TextToPdfService].
  Future<Uint8List> officeToPdf({
    required String inputPath,
    void Function(double fraction, String message)? onProgress,
  }) async {
    final ext = p.extension(inputPath).toLowerCase().replaceFirst('.', '');
    onProgress?.call(0.1, 'Reading document…');
    final String text;
    if (ext == 'docx') {
      text = extractTextFromDocx(await File(inputPath).readAsBytes());
    } else if (ext == 'txt' || ext == 'text' || ext == 'md') {
      text = await File(inputPath).readAsString();
    } else {
      throw UnsupportedError(
        'On-device conversion supports .docx and .txt only '
        '(not .$ext).',
      );
    }
    onProgress?.call(0.55, 'Building PDF…');
    final dir = await Directory.systemTemp.createTemp('ds_dart_office_');
    try {
      final out = p.join(dir.path, 'out.pdf');
      await _textToPdf.fromPlainText(
        text: text.isEmpty ? ' ' : text,
        outputPath: out,
        title: p.basenameWithoutExtension(inputPath),
        layout: TextToPdfLayout.letter,
      );
      onProgress?.call(0.95, 'Saving…');
      return await File(out).readAsBytes();
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }
}

/// Minimal OOXML .docx from plain paragraphs.
Uint8List buildDocxFromParagraphs(List<String> paragraphs) {
  final body = StringBuffer();
  for (final para in paragraphs) {
    final escaped = _xmlEscape(para);
    if (para.isEmpty) {
      body.writeln('<w:p/>');
    } else {
      body.writeln(
        '<w:p><w:r><w:t xml:space="preserve">$escaped</w:t></w:r></w:p>',
      );
    }
  }
  final documentXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>$body'
      '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
      '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>'
      '</w:sectPr></w:body></w:document>';

  const contentTypes =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '</Types>';

  const rels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
      'Target="word/document.xml"/>'
      '</Relationships>';

  const docRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '</Relationships>';

  final archive = Archive()
    ..addFile(_stored('[Content_Types].xml', contentTypes))
    ..addFile(_stored('_rels/.rels', rels))
    ..addFile(_stored('word/document.xml', documentXml))
    ..addFile(_stored('word/_rels/document.xml.rels', docRels));

  final encoded = ZipEncoder().encode(archive);
  return Uint8List.fromList(encoded);
}

ArchiveFile _stored(String name, String content) {
  final bytes = utf8.encode(content);
  return ArchiveFile(name, bytes.length, bytes);
}

/// Extracts visible paragraph text from a .docx (OOXML zip).
String extractTextFromDocx(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final entry = archive.findFile('word/document.xml');
  if (entry == null) {
    throw StateError('Not a valid .docx (missing word/document.xml).');
  }
  final xml = utf8.decode(entry.content as List<int>);
  final paras = <String>[];
  for (final m in RegExp(r'<w:p[\s>][\s\S]*?</w:p>').allMatches(xml)) {
    final chunk = m.group(0)!;
    final buf = StringBuffer();
    for (final t in RegExp(r'<w:t[^>]*>([^<]*)</w:t>').allMatches(chunk)) {
      buf.write(_xmlUnescape(t.group(1) ?? ''));
    }
    paras.add(buf.toString());
  }
  return paras.join('\n').trimRight();
}

String _xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _xmlUnescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'");
