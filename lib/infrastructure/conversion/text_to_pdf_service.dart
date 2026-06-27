import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/infrastructure/conversion/text_to_pdf_layout.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:pdf/pdf.dart';
// ignore: depend_on_referenced_packages
import 'package:pdf/widgets.dart' as pw;

const _kRegularFont = 'assets/fonts/text/LiberationSans-Regular.ttf';

/// Creates a text PDF with wrapping and as many pages as the text needs.
///
/// Uses the bundled Liberation Sans (Latin, Greek, Cyrillic) so accented and
/// non-English text renders; layout runs on a background isolate.
class TextToPdfService {
  Uint8List? _font;

  Future<Uint8List> _fontBytes() async {
    final cached = _font;
    if (cached != null) return cached;
    try {
      final data = await rootBundle.load(_kRegularFont);
      return _font = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      // Asset bundle unavailable (e.g. pure-Dart contexts): Helvetica fallback.
      return _font = Uint8List(0);
    }
  }

  Future<LocalFileRef> fromPlainText({
    required String text,
    required String outputPath,
    String title = 'Document',
    TextToPdfLayout layout = TextToPdfLayout.letter,
  }) async {
    final font = await _fontBytes();
    final job = _TextPdfJob(
      text: text,
      title: title,
      widthPt: layout.pageWidthPt,
      heightPt: layout.pageHeightPt,
      fontSizePt: layout.fontSizePt,
      marginPt: layout.marginPt,
      leadingPt: layout.lineLeadingPt,
      font: font,
    );
    final bytes = await Isolate.run(() => _buildTextPdf(job));
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
}

class _TextPdfJob {
  const _TextPdfJob({
    required this.text,
    required this.title,
    required this.widthPt,
    required this.heightPt,
    required this.fontSizePt,
    required this.marginPt,
    required this.leadingPt,
    required this.font,
  });

  final String text;
  final String title;
  final double widthPt;
  final double heightPt;
  final double fontSizePt;
  final double marginPt;
  final double leadingPt;
  final Uint8List font;
}

Future<Uint8List> _buildTextPdf(_TextPdfJob job) async {
  final font = job.font.isEmpty
      ? pw.Font.helvetica()
      : pw.Font.ttf(ByteData.sublistView(job.font));
  final doc = pw.Document(title: job.title, creator: 'Document Studio');
  final style = pw.TextStyle(
    font: font,
    fontSize: job.fontSizePt,
    lineSpacing: (job.leadingPt - job.fontSizePt).clamp(0, job.fontSizePt),
  );
  final paragraphs = job.text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat(
        job.widthPt,
        job.heightPt,
        marginAll: job.marginPt,
      ),
      maxPages: 2000,
      build: (_) => [
        for (final para in paragraphs)
          para.isEmpty
              ? pw.SizedBox(height: job.leadingPt)
              : pw.Paragraph(
                  text: para,
                  style: style,
                  margin: pw.EdgeInsets.zero,
                ),
      ],
    ),
  );
  return doc.save();
}
