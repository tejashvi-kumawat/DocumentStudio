import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:path/path.dart' as p;

/// Page size presets for blank PDF creation ([DS-CREATE-005]).
enum BlankPdfPagePreset { a4, letter, legal }

extension BlankPdfPagePresetX on BlankPdfPagePreset {
  String get label => switch (this) {
    BlankPdfPagePreset.a4 => 'A4',
    BlankPdfPagePreset.letter => 'US Letter',
    BlankPdfPagePreset.legal => 'US Legal',
  };

  (double widthPt, double heightPt) get mediaBox => switch (this) {
    BlankPdfPagePreset.a4 => (595.0, 842.0),
    BlankPdfPagePreset.letter => (612.0, 792.0),
    BlankPdfPagePreset.legal => (612.0, 1008.0),
  };
}

/// Creates multi-page blank PDFs locally ([DS-CREATE-005] minimal path).
class BlankPdfService {
  static const maxPages = 200;

  Future<LocalFileRef> create({
    required String outputPath,
    required int pageCount,
    BlankPdfPagePreset preset = BlankPdfPagePreset.letter,
    String title = 'Blank document',
  }) async {
    if (pageCount < 1 || pageCount > maxPages) {
      throw ArgumentError.value(pageCount, 'pageCount', 'Must be 1–$maxPages');
    }
    final bytes = _buildBlankPdf(
      pageCount: pageCount,
      preset: preset,
      title: title,
    );
    await Directory(p.dirname(outputPath)).create(recursive: true);
    await File(outputPath).writeAsBytes(bytes, flush: true);
    final stat = await File(outputPath).stat();
    return LocalFileRef(
      path: outputPath,
      displayName: p.basename(outputPath),
      sizeBytes: stat.size,
      lastModified: stat.modified,
    );
  }

  Uint8List _buildBlankPdf({
    required int pageCount,
    required BlankPdfPagePreset preset,
    required String title,
  }) {
    final (w, h) = preset.mediaBox;
    final wi = w.round();
    final hi = h.round();
    final objects = <String>[];
    objects.add('1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj');

    final pageObjectIds = <int>[];
    var nextId = 3;
    for (var i = 0; i < pageCount; i++) {
      pageObjectIds.add(nextId);
      nextId++;
    }

    final kids = pageObjectIds.map((id) => '$id 0 R').join(' ');
    objects.add(
      '2 0 obj<< /Type /Pages /Kids [$kids] /Count $pageCount >>endobj',
    );

    for (final id in pageObjectIds) {
      objects.add(
        '$id 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $wi $hi] >>endobj',
      );
    }

    final infoId = nextId;
    objects.add('$infoId 0 obj<< /Title ${_pdfTextString(title)} >>endobj');

    final header = '%PDF-1.4\n';
    var offset = header.length;
    final xrefEntries = <String>['0000000000 65535 f '];
    final rebuilt = StringBuffer(header);
    for (final obj in objects) {
      xrefEntries.add('${offset.toString().padLeft(10, '0')} 00000 n ');
      rebuilt.write('$obj\n');
      offset = rebuilt.length;
    }
    final xrefStart = rebuilt.length;
    rebuilt.write('xref\n0 ${objects.length + 1}\n');
    for (final entry in xrefEntries) {
      rebuilt.write('$entry\n');
    }
    rebuilt.write(
      'trailer<< /Size ${objects.length + 1} /Root 1 0 R '
      '/Info $infoId 0 R >>\n',
    );
    rebuilt.write('startxref\n$xrefStart\n%%EOF');
    return Uint8List.fromList(rebuilt.toString().codeUnits);
  }

  /// ASCII literal string, or UTF-16BE hex string for any other text, so the
  /// file body stays 7-bit and the xref byte offsets stay exact.
  static String _pdfTextString(String text) {
    final ascii = text.codeUnits.every((c) => c >= 0x20 && c < 0x7f);
    if (ascii) {
      final escaped = text
          .replaceAll('\\', '\\\\')
          .replaceAll('(', '\\(')
          .replaceAll(')', '\\)');
      return '($escaped)';
    }
    final hex = StringBuffer('<FEFF');
    for (final unit in text.codeUnits) {
      hex.write(unit.toRadixString(16).padLeft(4, '0').toUpperCase());
    }
    hex.write('>');
    return hex.toString();
  }
}
