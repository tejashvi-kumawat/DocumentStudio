import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio/infrastructure/pdf/pdf_helvetica_metrics.dart';

/// One line of Helvetica text on a PDF page (points, origin bottom-left).
class PdfOverlayTextLine {
  const PdfOverlayTextLine({
    required this.text,
    required this.xPt,
    required this.yPt,
    this.fontSizePt = 10,
    this.opacity = 1,
    this.rotationDegrees = 0,
    this.centerAtAnchor = false,
    this.invisible = false,
    this.bold = false,
    this.fillRgb,
    this.fillAlpha = 1,
  });

  final String text;
  final double xPt;
  final double yPt;
  final double fontSizePt;

  /// 0–1 fill gray level (1 = black). Values below 1 simulate lighter watermarks.
  /// Ignored when [fillRgb] is set.
  final double opacity;

  final double rotationDegrees;

  /// When true with rotation, [xPt]/[yPt] is the rotation anchor and text is centered there.
  final bool centerAtAnchor;

  /// PDF text rendering mode 3 — invisible but selectable/searchable.
  final bool invisible;

  /// Use Helvetica-Bold when true.
  final bool bold;

  /// Optional RGB fill (0–1). When set, overrides gray [opacity].
  final (double r, double g, double b)? fillRgb;

  /// True fill transparency (`/ca`), independent of the gray [opacity] level.
  final double fillAlpha;
}

/// Builds minimal multi-page PDFs with text overlays (headers, footers, numbers).
class PdfOverlayTextBuilder {
  Uint8List build({
    required int pageCount,
    double Function(int pageIndex1Based)? pageWidthPt,
    double Function(int pageIndex1Based)? pageHeightPt,
    required List<PdfOverlayTextLine> Function(int pageIndex1Based) linesForPage,
  }) {
    if (pageCount < 1) {
      throw ArgumentError.value(pageCount, 'pageCount', 'must be >= 1');
    }

    final gStates = <String, int>{};
    final pageBodies = <String>[];
    final pageGs = <Set<int>>[];
    for (var page = 1; page <= pageCount; page++) {
      final used = <int>{};
      pageBodies.add(
        _contentBody(linesForPage(page), (alpha) {
          final idx = gStates.putIfAbsent(alpha, () => gStates.length);
          used.add(idx);
          return idx;
        }),
      );
      pageGs.add(used);
    }

    final fontRegularId = 3 + pageCount * 2;
    final fontBoldId = fontRegularId + 1;
    final firstGsId = fontBoldId + 1;
    final objects = <String>[];

    objects.add('1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj');
    final kids = [
      for (var page = 0; page < pageCount; page++) '${3 + page * 2 + 1} 0 R',
    ].join(' ');
    objects.add(
      '2 0 obj<< /Type /Pages /Kids [$kids] /Count $pageCount >>endobj',
    );

    for (var page = 0; page < pageCount; page++) {
      final contentId = 3 + page * 2;
      final pageId = contentId + 1;
      final content = pageBodies[page];
      objects.add(
        '$contentId 0 obj<< /Length ${content.length} >>\n'
        'stream\n$content\nendstream endobj',
      );
      final w = _n(pageWidthPt?.call(page + 1) ?? 612);
      final h = _n(pageHeightPt?.call(page + 1) ?? 792);
      final used = pageGs[page].toList()..sort();
      final gs = used.isEmpty
          ? ''
          : '/ExtGState<< '
              '${used.map((i) => '/GS$i ${firstGsId + i} 0 R').join(' ')} >> ';
      objects.add(
        '$pageId 0 obj<< /Type /Page /Parent 2 0 R '
        '/MediaBox [0 0 $w $h] /Contents $contentId 0 R '
        '/Resources<< /Font<< /F1 $fontRegularId 0 R /F2 $fontBoldId 0 R >> '
        '$gs>> >>endobj',
      );
    }

    objects.add(
      '$fontRegularId 0 obj<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
      '/Encoding /WinAnsiEncoding >>endobj',
    );
    objects.add(
      '$fontBoldId 0 obj<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold '
      '/Encoding /WinAnsiEncoding >>endobj',
    );
    final gsByIndex = gStates.map((alpha, idx) => MapEntry(idx, alpha));
    for (var i = 0; i < gStates.length; i++) {
      objects.add(
        '${firstGsId + i} 0 obj<< /Type /ExtGState /ca ${gsByIndex[i]} >>endobj',
      );
    }

    // Everything is pure ASCII (text bytes >= 0x80 are octal-escaped).
    const header = '%PDF-1.4\n';
    final body = objects.join('\n');
    final offsets = <int>[0];
    var pos = header.length;
    for (final obj in objects) {
      offsets.add(pos);
      pos += obj.length + 1;
    }
    final xrefStart = pos;
    final xref = StringBuffer('xref\n0 ${offsets.length}\n')
      ..writeln('0000000000 65535 f ')
      ..writeln(
        offsets
            .skip(1)
            .map((o) => o.toString().padLeft(10, '0'))
            .map((o) => '$o 00000 n ')
            .join('\n'),
      );
    final trailer =
        'trailer<< /Size ${offsets.length} /Root 1 0 R >>\nstartxref\n$xrefStart\n%%EOF';
    return Uint8List.fromList(
      ascii.encode('$header$body\n$xref$trailer'),
    );
  }

  String _contentBody(
    List<PdfOverlayTextLine> lines,
    int Function(String alpha) gStateIndex,
  ) {
    if (lines.isEmpty) return ' ';
    final buf = StringBuffer();
    for (final line in lines) {
      final encoded = encodeWinAnsiPdfString(line.text);
      final size = _n(line.fontSizePt);
      final x = _n(line.xPt);
      final y = _n(line.yPt);
      final font = line.bold ? '/F2' : '/F1';
      final gray = line.opacity.clamp(0.01, 1.0);
      buf.write('q ');
      final alpha = line.fillAlpha.clamp(0.0, 1.0);
      if (!line.invisible && alpha < 0.999) {
        buf.write('/GS${gStateIndex(_n(alpha))} gs ');
      }
      if (!line.invisible) {
        if (line.fillRgb != null) {
          final (r, g, b) = line.fillRgb!;
          buf.write(
            '${r.toStringAsFixed(3)} ${g.toStringAsFixed(3)} '
            '${b.toStringAsFixed(3)} rg ',
          );
        } else if (gray < 1) {
          buf.write('${gray.toStringAsFixed(2)} g ');
        }
      }
      if (line.rotationDegrees != 0) {
        final rad = line.rotationDegrees * math.pi / 180;
        final cos = math.cos(rad).toStringAsFixed(4);
        final sin = math.sin(rad).toStringAsFixed(4);
        buf.write('1 0 0 1 $x $y cm ');
        buf.write('$cos $sin ${(-math.sin(rad)).toStringAsFixed(4)} $cos 0 0 cm ');
        var tx = 0.0;
        var ty = 0.0;
        if (line.centerAtAnchor) {
          final estWidth = helveticaTextWidthPt(
            line.text.replaceAll('\t', ' '),
            line.fontSizePt,
            bold: line.bold,
          );
          tx = -estWidth / 2;
          ty = -line.fontSizePt / 2;
        }
        buf.write('BT $font $size Tf ');
        if (line.invisible) buf.write('3 Tr ');
        buf.write('${_n(tx)} ${_n(ty)} Td ($encoded) Tj ET ');
      } else {
        buf.write('BT $font $size Tf ');
        if (line.invisible) buf.write('3 Tr ');
        buf.write('$x $y Td ($encoded) Tj ET ');
      }
      buf.write('Q ');
    }
    return buf.toString();
  }

  String _n(double v) => _fmt(v);
}

const Map<int, int> _winAnsiExtras = <int, int>{
  0x20AC: 0x80,
  0x201A: 0x82,
  0x0192: 0x83,
  0x201E: 0x84,
  0x2026: 0x85,
  0x2020: 0x86,
  0x2021: 0x87,
  0x02C6: 0x88,
  0x2030: 0x89,
  0x0160: 0x8A,
  0x2039: 0x8B,
  0x0152: 0x8C,
  0x017D: 0x8E,
  0x2018: 0x91,
  0x2019: 0x92,
  0x201C: 0x93,
  0x201D: 0x94,
  0x2022: 0x95,
  0x2013: 0x96,
  0x2014: 0x97,
  0x02DC: 0x98,
  0x2122: 0x99,
  0x0161: 0x9A,
  0x203A: 0x9B,
  0x0153: 0x9C,
  0x017E: 0x9E,
  0x0178: 0x9F,
};

/// Encodes [text] as the body of a PDF literal string in WinAnsiEncoding.
///
/// The result is pure ASCII: `\`, `(`, `)` are escaped, bytes >= 0x80 are
/// written as octal escapes, unmappable characters become `?`.
String encodeWinAnsiPdfString(String text) {
  final sb = StringBuffer();
  for (final cp in text.runes) {
    int byte;
    if (cp == 0x09) {
      byte = 0x20;
    } else if (cp >= 0x20 && cp <= 0x7E) {
      byte = cp;
    } else if (cp >= 0xA0 && cp <= 0xFF) {
      byte = cp;
    } else {
      byte = _winAnsiExtras[cp] ?? 0x3F;
    }
    if (byte == 0x5C || byte == 0x28 || byte == 0x29) {
      sb.write('\\');
      sb.writeCharCode(byte);
    } else if (byte >= 0x80) {
      sb.write('\\${byte.toRadixString(8).padLeft(3, '0')}');
    } else {
      sb.writeCharCode(byte);
    }
  }
  return sb.toString();
}

String _fmt(double v) {
  var s = v.toStringAsFixed(3);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  }
  if (s == '-0') s = '0';
  return s;
}
