import 'dart:convert';
import 'dart:typed_data';

/// Filled or stroked rectangle in PDF user space (bottom-left origin).
class PdfOverlayRect {
  const PdfOverlayRect({
    required this.xPt,
    required this.yPt,
    required this.widthPt,
    required this.heightPt,
    this.fillRgb,
    this.strokeRgb,
    this.strokeWidthPt = 1,
    this.fillOpacity = 1,
    this.strokeOpacity = 1,
    this.multiply = false,
  });

  final double xPt;
  final double yPt;
  final double widthPt;
  final double heightPt;
  final (double r, double g, double b)? fillRgb;
  final (double r, double g, double b)? strokeRgb;
  final double strokeWidthPt;
  final double fillOpacity;

  /// Stroke alpha (`/CA`).
  final double strokeOpacity;

  /// Paint fill and stroke with `/BM /Multiply` (highlight keeps text readable).
  final bool multiply;
}

/// Minimal multi-page overlay PDF with vector rectangles (markup burn-in).
class PdfOverlayShapeBuilder {
  Uint8List build({
    required int pageCount,
    required double Function(int pageIndex1Based) pageWidthPt,
    required double Function(int pageIndex1Based) pageHeightPt,
    required List<PdfOverlayRect> Function(int pageIndex1Based) rectsForPage,
  }) {
    if (pageCount < 1) {
      throw ArgumentError.value(pageCount, 'pageCount', 'must be >= 1');
    }

    final gStates = <String, int>{};
    final gStateDefs = <String>[];
    final pageBodies = <String>[];
    final pageGs = <Set<int>>[];
    for (var page = 1; page <= pageCount; page++) {
      final used = <int>{};
      pageBodies.add(
        _contentBody(rectsForPage(page), (fillA, strokeA, multiply) {
          final def = '/ca $fillA /CA $strokeA'
              '${multiply ? ' /BM /Multiply' : ''}';
          final idx = gStates.putIfAbsent(def, () {
            gStateDefs.add(def);
            return gStateDefs.length - 1;
          });
          used.add(idx);
          return idx;
        }),
      );
      pageGs.add(used);
    }

    // Ids: 1 catalog, 2 pages, 3.. ExtGStates, then content/page pairs.
    const firstGsId = 3;
    final firstPageObjId = firstGsId + gStateDefs.length;
    final objects = <String>[];
    objects.add('1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj');
    final pageObjectIds = <int>[
      for (var page = 0; page < pageCount; page++) firstPageObjId + page * 2 + 1,
    ];
    objects.add(
      '2 0 obj<< /Type /Pages /Kids [${pageObjectIds.map((id) => '$id 0 R').join(' ')}] '
      '/Count $pageCount >>endobj',
    );
    for (var i = 0; i < gStateDefs.length; i++) {
      objects.add(
        '${firstGsId + i} 0 obj<< /Type /ExtGState ${gStateDefs[i]} >>endobj',
      );
    }
    for (var page = 0; page < pageCount; page++) {
      final contentId = firstPageObjId + page * 2;
      final pageId = contentId + 1;
      final body = pageBodies[page];
      objects.add(
        '$contentId 0 obj << /Length ${utf8.encode(body).length} >>stream\n'
        '$body\nendstream endobj',
      );
      final w = _n(pageWidthPt(page + 1));
      final h = _n(pageHeightPt(page + 1));
      final used = pageGs[page].toList()..sort();
      final resources = used.isEmpty
          ? ''
          : '/Resources << /ExtGState << '
              '${used.map((i) => '/GS$i ${firstGsId + i} 0 R').join(' ')} >> >> ';
      objects.add(
        '$pageId 0 obj<< /Type /Page /Parent 2 0 R '
        '/MediaBox [0 0 $w $h] /Contents $contentId 0 R '
        '$resources>>endobj',
      );
    }

    final buffer = BytesBuilder(copy: false);
    buffer.add(utf8.encode('%PDF-1.4\n'));
    final offsets = <int>[0];
    for (final obj in objects) {
      offsets.add(buffer.length);
      buffer.add(utf8.encode('$obj\n'));
    }
    final xrefStart = buffer.length;
    buffer.add(utf8.encode('xref\n0 ${objects.length + 1}\n'));
    buffer.add(utf8.encode('0000000000 65535 f \n'));
    for (var i = 1; i < offsets.length; i++) {
      buffer.add(
        utf8.encode('${offsets[i].toString().padLeft(10, '0')} 00000 n \n'),
      );
    }
    buffer.add(
      utf8.encode(
        'trailer<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
        'startxref\n$xrefStart\n%%EOF\n',
      ),
    );
    return buffer.toBytes();
  }

  String _contentBody(
    List<PdfOverlayRect> rects,
    int Function(String fillAlpha, String strokeAlpha, bool multiply)
        gStateIndex,
  ) {
    final sb = StringBuffer();
    for (final r in rects) {
      if (r.fillRgb == null && r.strokeRgb == null) continue;
      sb.write('q ');
      final fa = r.fillOpacity.clamp(0.05, 1.0);
      final sa = r.strokeOpacity.clamp(0.0, 1.0);
      final needsFillAlpha = r.fillRgb != null && fa < 0.999;
      final needsStrokeAlpha = r.strokeRgb != null && sa < 0.999;
      if (needsFillAlpha || needsStrokeAlpha || r.multiply) {
        final idx = gStateIndex(
          _n(r.fillRgb != null ? fa : 1),
          _n(r.strokeRgb != null ? sa : 1),
          r.multiply,
        );
        sb.write('/GS$idx gs ');
      }
      final rect =
          '${_n(r.xPt)} ${_n(r.yPt)} ${_n(r.widthPt)} ${_n(r.heightPt)} re';
      if (r.fillRgb != null) {
        final (fr, fg, fb) = r.fillRgb!;
        sb.write('${_n(fr)} ${_n(fg)} ${_n(fb)} rg $rect f ');
      }
      if (r.strokeRgb != null) {
        final (sr, sg, sbC) = r.strokeRgb!;
        sb.write(
          '${_n(r.strokeWidthPt)} w 1 j ${_n(sr)} ${_n(sg)} ${_n(sbC)} RG '
          '$rect S ',
        );
      }
      sb.write('Q\n');
    }
    return sb.toString();
  }

  String _n(double v) => _fmt(v);
}

String _fmt(double v) {
  var s = v.toStringAsFixed(3);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  }
  if (s == '-0') s = '0';
  return s;
}
