import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio/domain/compare/compare_models.dart';
import 'package:document_studio/infrastructure/pdf/compare_report_writer.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

const _maxThumbRows = 24;
const _thumbWidth = 520;

/// Renders changed-page thumbnails and builds the compare report PDF. Heavy
/// work (JPEG encoding, PDF assembly) runs off the UI isolate.
Future<Uint8List> buildCompareReport({
  required CompareResult result,
  required PdfDocument oldPdf,
  required PdfDocument newPdf,
  required String oldName,
  required String newName,
  void Function(double progress)? onProgress,
}) async {
  final rowsWithChanges = <int>{
    for (final c in result.changes) c.row,
  }.toList()
    ..sort();
  final rows = rowsWithChanges.take(_maxThumbRows).toList();

  final thumbs = <CompareReportRow>[];
  for (var k = 0; k < rows.length; k++) {
    final row = rows[k];
    final pair = result.rows[row];
    List<(NormRect, int)> marks(bool oldSide) {
      final page = oldSide ? pair.a : pair.b;
      if (page == null) return const [];
      return [
        for (final c in result.changes)
          for (final r in (oldSide ? c.aRects : c.bRects)[page] ?? const <NormRect>[])
            (r, compareChangeRgb(c)),
      ];
    }

    final a = pair.a == null
        ? null
        : await _thumb(oldPdf.pages[pair.a!], marks(true));
    final b = pair.b == null
        ? null
        : await _thumb(newPdf.pages[pair.b!], marks(false));
    final label = [
      pair.a == null ? 'Inserted page' : 'Old page ${pair.a! + 1}',
      pair.b == null ? 'Deleted page' : 'New page ${pair.b! + 1}',
    ].join('  ·  ');
    thumbs.add(CompareReportRow(label: label, a: a, b: b));
    onProgress?.call((k + 1) / math.max(1, rows.length) * 0.9);
  }

  final now = DateTime.now();
  final bytes = await _assemble(result, oldName, newName, now, thumbs);
  onProgress?.call(1);
  return bytes;
}

Future<Uint8List> _assemble(
  CompareResult result,
  String oldName,
  String newName,
  DateTime now,
  List<CompareReportRow> thumbs,
) =>
    Isolate.run(() => buildCompareReportPdf(
          result: result,
          oldName: oldName,
          newName: newName,
          generatedAt: now,
          thumbs: thumbs,
        ));

Future<CompareReportThumb?> _thumb(
  PdfPage page,
  List<(NormRect, int)> marks,
) async {
  final w = _thumbWidth;
  final h = math.max(1, (w * page.height / page.width).round());
  final image = await page.render(
    width: w,
    height: h,
    fullWidth: w.toDouble(),
    fullHeight: h.toDouble(),
    backgroundColor: 0xFFFFFFFF,
  );
  if (image == null) return null;
  final Uint8List bgra;
  try {
    bgra = Uint8List.fromList(image.pixels);
  } finally {
    image.dispose();
  }
  final jpeg = await _encodeJpeg(bgra, w, h);
  return CompareReportThumb(jpeg: jpeg, width: w, height: h, marks: marks);
}

Future<Uint8List> _encodeJpeg(Uint8List bgra, int w, int h) =>
    Isolate.run(() {
      final im = img.Image.fromBytes(
        width: w,
        height: h,
        bytes: bgra.buffer,
        numChannels: 4,
        order: img.ChannelOrder.bgra,
      );
      final rgb = im.convert(numChannels: 3);
      return Uint8List.fromList(img.encodeJpg(rgb, quality: 80));
    });
