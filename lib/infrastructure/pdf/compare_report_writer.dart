import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio/domain/compare/compare_models.dart';
import 'package:document_studio/infrastructure/pdf/pdf_helvetica_metrics.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_text_builder.dart';

/// A rendered page thumbnail (baseline JPEG, RGB) with highlight marks.
class CompareReportThumb {
  const CompareReportThumb({
    required this.jpeg,
    required this.width,
    required this.height,
    required this.marks,
  });

  final Uint8List jpeg;
  final int width;
  final int height;
  final List<(NormRect, int)> marks;
}

class CompareReportRow {
  const CompareReportRow({required this.label, this.a, this.b});

  final String label;
  final CompareReportThumb? a;
  final CompareReportThumb? b;
}

const _pageW = 595.0;
const _pageH = 842.0;
const _margin = 40.0;
const _headerRgb = 0x1F2937;

/// Builds a self-contained PDF 1.4 report (standard Helvetica fonts, JPEG
/// thumbnails): summary with per-category counts, the full change list, then
/// side-by-side thumbnails of changed pages with highlight boxes.
Uint8List buildCompareReportPdf({
  required CompareResult result,
  required String oldName,
  required String newName,
  required DateTime generatedAt,
  List<CompareReportRow> thumbs = const [],
}) {
  final w = _ReportWriter();
  var page = w.newPage();

  // Header band.
  page.fillRect(0, 0, _pageW, 96, _headerRgb);
  page.text(_margin, 46, 24, 'Compare Report', bold: true, rgb: 0xFFFFFF);
  page.text(_margin, 72, 10,
      'Generated ${_fmtDate(generatedAt)} · ${result.elapsed.inMilliseconds} ms analysis',
      rgb: 0xC9CED6);

  var y = 124.0;
  page.text(_margin, y, 9, 'OLD DOCUMENT', bold: true, rgb: 0x777777);
  page.text(_pageW / 2 + 8, y, 9, 'NEW DOCUMENT', bold: true, rgb: 0x777777);
  y += 16;
  page.text(_margin, y, 12, _fit(oldName, 12, true, 240), bold: true);
  page.text(_pageW / 2 + 8, y, 12, _fit(newName, 12, true, 240), bold: true);
  y += 15;
  page.text(_margin, y, 10, '${result.oldDoc.pageCount} pages', rgb: 0x555555);
  page.text(_pageW / 2 + 8, y, 10, '${result.newDoc.pageCount} pages',
      rgb: 0x555555);

  y += 34;
  final total = result.changes.length;
  page.text(_margin, y, 30, '$total', bold: true,
      rgb: total == 0 ? compareInsertRgb : 0x1A1A1A);
  page.text(_margin + _width('$total', 30, true) + 10, y - 2, 13,
      total == 0
          ? 'No differences found — the documents match.'
          : 'change${total == 1 ? '' : 's'} found',
      rgb: 0x444444);
  y += 18;
  final affected = result.pagesAffected;
  page.text(_margin, y, 9.5,
      'Pages affected: ${affected.oldPages} of ${result.oldDoc.pageCount} old · '
      '${affected.newPages} of ${result.newDoc.pageCount} new',
      rgb: 0x555555);
  y += 18;

  // Highlight legend with per-kind totals.
  var lx = _margin;
  for (final k in CompareChangeKind.values) {
    final label = '${k.label} ${result.countOfKind(k)}';
    page.fillRect(lx, y - 8, 9, 9, compareKindRgb(k));
    page.text(lx + 13, y, 9, label, rgb: 0x333333);
    lx += 13 + _width(label, 9, false) + 16;
  }
  y += 24;

  final maxCount = math.max(
      1, CompareCategory.values.map(result.count).fold(0, math.max));
  for (final c in CompareCategory.values) {
    final n = result.count(c);
    page.text(_margin, y + 9, 10.5, c.label, bold: true);
    page.fillRect(_margin + 100, y, 300, 12, 0xF0F0F0);
    if (n > 0) {
      page.fillRect(
          _margin + 100, y, math.max(3, 300 * n / maxCount), 12, 0x4B5563);
    }
    page.text(_margin + 410, y + 9.5, 10.5, '$n', bold: true);
    final unavailable = (c == CompareCategory.formatting &&
            !result.formattingAvailable) ||
        (c == CompareCategory.images && !result.imagesAvailable);
    final kinds = unavailable
        ? 'Not detectable with this PDF backend'
        : [
            for (final k in CompareChangeKind.values)
              if (result.countKind(c, k) > 0)
                '${result.countKind(c, k)} ${k.label.toLowerCase()}',
          ].join(' · ');
    if (kinds.isNotEmpty) {
      page.text(_margin + 100, y + 23, 8.5, kinds, rgb: 0x777777);
    }
    y += 34;
  }

  // Change list.
  y += 10;
  page.text(_margin, y, 14, 'Changes', bold: true);
  y += 8;
  page.hline(_margin, _pageW - _margin, y, 0xDDDDDD);
  y += 16;
  if (result.changes.isEmpty) {
    page.text(_margin, y, 10, 'Nothing to report.', rgb: 0x777777);
  }
  for (final c in result.changes) {
    final lines = <(String, double, bool, int)>[];
    final where = [
      if (c.aPage != null) 'Old p.${c.aPage! + 1}',
      if (c.bPage != null) 'New p.${c.bPage! + 1}',
    ].join('  ·  ');
    void addWrapped(String prefix, String text, int rgb) {
      final wrapped = _wrap('$prefix$text', 9, false, _pageW - 2 * _margin - 14);
      for (final l in wrapped.take(4)) {
        lines.add((l, 9, false, rgb));
      }
      if (wrapped.length > 4) lines.add(('…', 9, false, rgb));
    }

    if (c.oldText.isNotEmpty && c.oldText != c.newText) {
      addWrapped('- ', c.oldText, compareDeleteRgb);
    }
    if (c.newText.isNotEmpty && c.oldText != c.newText) {
      addWrapped('+ ', c.newText, compareInsertRgb);
    }
    if (c.oldText.isNotEmpty && c.oldText == c.newText) {
      addWrapped('', c.oldText, 0x444444);
    }
    if (c.detail != null && c.detail!.isNotEmpty) {
      addWrapped('', c.detail!, 0x777777);
    }
    final need = 16 + lines.length * 12.0 + 8;
    if (y + need > _pageH - _margin) {
      page = w.newPage();
      y = _margin + 10;
    }
    page.fillRect(_margin, y - 9, 4, 12 + lines.length * 12.0,
        compareChangeRgb(c));
    page.text(_margin + 12, y, 9.5, '#${c.id + 1}  ${c.title}', bold: true);
    page.text(_pageW - _margin - _width(where, 8.5, false), y, 8.5, where,
        rgb: 0x777777);
    y += 13;
    for (final (text, size, bold, rgb) in lines) {
      page.text(_margin + 14, y, size, text, bold: bold, rgb: rgb);
      y += 12;
    }
    y += 8;
  }

  // Thumbnails, two rows per page.
  for (var i = 0; i < thumbs.length; i++) {
    if (i % 2 == 0) {
      page = w.newPage();
      page.text(_margin, _margin + 6, 14, 'Changed pages', bold: true);
      page.text(_pageW - _margin - 160, _margin + 6, 8.5,
          'Left: old document · Right: new document', rgb: 0x777777);
    }
    final t = thumbs[i];
    final top = _margin + 30 + (i % 2) * 380.0;
    page.text(_margin, top, 10, t.label, bold: true);
    const boxW = (_pageW - 2 * _margin - 20) / 2;
    const boxH = 340.0;
    for (final (k, thumb) in [(0, t.a), (1, t.b)]) {
      final bx = _margin + k * (boxW + 20);
      final by = top + 10;
      if (thumb == null) {
        page.fillRect(bx, by, boxW, boxH, 0xF4F4F4);
        final msg = k == 0 ? 'Not in old document' : 'Not in new document';
        page.text(bx + (boxW - _width(msg, 10, false)) / 2, by + boxH / 2, 10,
            msg, rgb: 0x999999);
        continue;
      }
      final s = math.min(boxW / thumb.width, boxH / thumb.height);
      final iw = thumb.width * s;
      final ih = thumb.height * s;
      final ix = bx + (boxW - iw) / 2;
      final iy = by;
      page.strokeRect(ix - 0.5, iy - 0.5, iw + 1, ih + 1, 0xCCCCCC, 0.6);
      page.image(w.addJpeg(thumb), ix, iy, iw, ih);
      for (final (r, rgb) in thumb.marks) {
        final rx = ix + r.l * iw;
        final ry = iy + r.t * ih;
        final rw = math.max(1.5, r.width * iw);
        final rh = math.max(1.5, r.height * ih);
        page.fillRect(rx, ry, rw, rh, rgb, alpha: true);
        page.strokeRect(rx, ry, rw, rh, rgb, 0.6);
      }
    }
  }

  return w.finish();
}

String _fmtDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

/// Maps characters outside WinAnsi (used by the standard fonts) to close
/// ASCII equivalents; anything else unknown becomes '?' in the encoder.
String _winAnsiSafe(String s) {
  if (s.codeUnits.every((c) => c < 0x80)) return s;
  return s
      .replaceAll('→', '->')
      .replaceAll('←', '<-')
      .replaceAll('⇄', '<->')
      .replaceAll('−', '-')
      .replaceAll('\u2010', '-')
      .replaceAll('\u2011', '-')
      .replaceAll('\u00AD', '')
      .replaceAll('\uFB01', 'fi')
      .replaceAll('\uFB02', 'fl');
}

double _width(String s, double size, bool bold) =>
    helveticaTextWidthPt(_winAnsiSafe(s), size, bold: bold);

String _fit(String s, double size, bool bold, double maxW) {
  if (_width(s, size, bold) <= maxW) return s;
  var t = s;
  while (t.isNotEmpty && _width('$t…', size, bold) > maxW) {
    t = t.substring(0, t.length - 1);
  }
  return '$t…';
}

List<String> _wrap(String text, double size, bool bold, double maxW) {
  final out = <String>[];
  for (final para in text.split('\n')) {
    var line = '';
    for (final word in para.split(' ')) {
      final cand = line.isEmpty ? word : '$line $word';
      if (_width(cand, size, bold) <= maxW) {
        line = cand;
        continue;
      }
      if (line.isNotEmpty) out.add(line);
      line = word;
      while (_width(line, size, bold) > maxW && line.length > 1) {
        var cut = line.length - 1;
        while (cut > 1 && _width(line.substring(0, cut), size, bold) > maxW) {
          cut--;
        }
        out.add(line.substring(0, cut));
        line = line.substring(cut);
      }
    }
    out.add(line);
  }
  return out;
}

String _n(double v) {
  var s = v.toStringAsFixed(2);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return s == '-0' ? '0' : s;
}

String _rgb(int rgb) =>
    '${_n(((rgb >> 16) & 0xFF) / 255)} ${_n(((rgb >> 8) & 0xFF) / 255)} ${_n((rgb & 0xFF) / 255)}';

class _ReportPage {
  final sb = StringBuffer();
  final images = <int>{};

  double _y(double top) => _pageH - top;

  void text(double x, double baselineTop, double size, String s,
      {bool bold = false, int rgb = 0x1A1A1A}) {
    sb.writeln('BT /${bold ? 'F2' : 'F1'} ${_n(size)} Tf ${_rgb(rgb)} rg '
        '${_n(x)} ${_n(_y(baselineTop))} Td '
        '(${encodeWinAnsiPdfString(_winAnsiSafe(s))}) Tj ET');
  }

  void fillRect(double x, double top, double w, double h, int rgb,
      {bool alpha = false}) {
    sb.writeln('q ${alpha ? '/GA gs ' : ''}${_rgb(rgb)} rg '
        '${_n(x)} ${_n(_y(top + h))} ${_n(w)} ${_n(h)} re f Q');
  }

  void strokeRect(double x, double top, double w, double h, int rgb,
      double lw) {
    sb.writeln('q ${_rgb(rgb)} RG ${_n(lw)} w '
        '${_n(x)} ${_n(_y(top + h))} ${_n(w)} ${_n(h)} re S Q');
  }

  void hline(double x0, double x1, double top, int rgb) {
    sb.writeln('q ${_rgb(rgb)} RG 0.6 w ${_n(x0)} ${_n(_y(top))} m '
        '${_n(x1)} ${_n(_y(top))} l S Q');
  }

  void image(int objId, double x, double top, double w, double h) {
    images.add(objId);
    sb.writeln('q ${_n(w)} 0 0 ${_n(h)} ${_n(x)} ${_n(_y(top + h))} cm '
        '/Im$objId Do Q');
  }
}

class _ReportWriter {
  final _objects = <int, List<int>>{};
  final _pages = <_ReportPage>[];
  var _next = 7; // 1 catalog, 2 pages, 3 F1, 4 F2, 5 GA, 6 info

  _ReportPage newPage() {
    final p = _ReportPage();
    _pages.add(p);
    return p;
  }

  int addJpeg(CompareReportThumb t) {
    final id = _next++;
    final head = ascii.encode('<< /Type /XObject /Subtype /Image '
        '/Width ${t.width} /Height ${t.height} /ColorSpace /DeviceRGB '
        '/BitsPerComponent 8 /Filter /DCTDecode /Length ${t.jpeg.length} >>\n'
        'stream\n');
    _objects[id] = (BytesBuilder(copy: false)
          ..add(head)
          ..add(t.jpeg)
          ..add(ascii.encode('\nendstream')))
        .toBytes();
    return id;
  }

  Uint8List finish() {
    _objects[3] = ascii.encode('<< /Type /Font /Subtype /Type1 '
        '/BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
    _objects[4] = ascii.encode('<< /Type /Font /Subtype /Type1 '
        '/BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>');
    _objects[5] = ascii.encode('<< /Type /ExtGState /ca 0.28 /CA 1 >>');
    _objects[6] = ascii.encode(
        '<< /Title (Compare Report) /Producer (Document Studio) >>');
    final kids = <int>[];
    for (final p in _pages) {
      final contentId = _next++;
      final pageId = _next++;
      final data = latin1.encode(p.sb.toString());
      _objects[contentId] = [
        ...ascii.encode('<< /Length ${data.length} >>\nstream\n'),
        ...data,
        ...ascii.encode('\nendstream'),
      ];
      final xobj = p.images.isEmpty
          ? ''
          : '/XObject << ${p.images.map((i) => '/Im$i $i 0 R').join(' ')} >> ';
      _objects[pageId] = ascii.encode('<< /Type /Page /Parent 2 0 R '
          '/MediaBox [0 0 ${_n(_pageW)} ${_n(_pageH)}] '
          '/Resources << /Font << /F1 3 0 R /F2 4 0 R >> '
          '/ExtGState << /GA 5 0 R >> $xobj>> '
          '/Contents $contentId 0 R >>');
      kids.add(pageId);
    }
    _objects[2] = ascii.encode('<< /Type /Pages /Count ${kids.length} '
        '/Kids [${kids.map((k) => '$k 0 R').join(' ')}] >>');
    _objects[1] = ascii.encode('<< /Type /Catalog /Pages 2 0 R >>');

    final out = BytesBuilder(copy: false);
    // Header plus the customary binary-marker comment line.
    out.add(ascii.encode('%PDF-1.4\n'));
    out.add(const [0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);
    final maxId = _next - 1;
    final offsets = List<int>.filled(maxId + 1, 0);
    for (var id = 1; id <= maxId; id++) {
      final body = _objects[id];
      if (body == null) continue;
      offsets[id] = out.length;
      out.add(ascii.encode('$id 0 obj\n'));
      out.add(body);
      out.add(ascii.encode('\nendobj\n'));
    }
    final xref = out.length;
    final sb = StringBuffer('xref\n0 ${maxId + 1}\n0000000000 65535 f \n');
    for (var id = 1; id <= maxId; id++) {
      if (_objects[id] == null) {
        sb.write('0000000000 65535 f \n');
      } else {
        sb.write('${offsets[id].toString().padLeft(10, '0')} 00000 n \n');
      }
    }
    sb.write('trailer\n<< /Size ${maxId + 1} /Root 1 0 R /Info 6 0 R >>\n'
        'startxref\n$xref\n%%EOF\n');
    out.add(ascii.encode(sb.toString()));
    return out.toBytes();
  }
}
