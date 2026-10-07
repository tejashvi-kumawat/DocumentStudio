import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// One JPEG image drawn on a PDF page (points, origin bottom-left).
class PdfOverlayImageLine {
  const PdfOverlayImageLine({
    required this.jpegBytes,
    required this.imageWidthPx,
    required this.imageHeightPx,
    required this.xPt,
    required this.yPt,
    required this.widthPt,
    required this.heightPt,
    this.opacity = 1,
    this.rotationDegrees = 0,
    this.smaskBytes,
    this.rgbIsFlate = false,
  });

  final Uint8List jpegBytes;
  final int imageWidthPx;
  final int imageHeightPx;
  final double xPt;
  final double yPt;
  final double widthPt;
  final double heightPt;

  /// Non-stroking alpha applied via ExtGState (`/ca`).
  final double opacity;

  /// Counter-clockwise rotation around the stamp box center (PDF degrees).
  final double rotationDegrees;

  /// Zlib (Flate) compressed 8-bit DeviceGray alpha plane,
  /// [imageWidthPx] x [imageHeightPx]; written as the image `/SMask`.
  final Uint8List? smaskBytes;

  /// When true, [jpegBytes] holds zlib-compressed raw RGB (8 bpc) instead of JPEG.
  final bool rgbIsFlate;
}

/// Builds multi-page overlay PDFs with optional JPEG stamps per page.
class PdfOverlayImageBuilder {
  Uint8List build({
    required int pageCount,
    required double Function(int pageIndex1Based) pageWidthPt,
    required double Function(int pageIndex1Based) pageHeightPt,
    required List<PdfOverlayImageLine> Function(int pageIndex1Based)
    imagesForPage,
  }) {
    if (pageCount < 1) {
      throw ArgumentError.value(pageCount, 'pageCount', 'must be >= 1');
    }

    final buffer = BytesBuilder(copy: false);
    final objectOffsets = <int, int>{};

    void writeObj(int id, String text) {
      objectOffsets[id] = buffer.length;
      buffer.add(utf8.encode(text));
    }

    void writeObjWithBinary(
      int id,
      String head,
      Uint8List binary,
      String tail,
    ) {
      objectOffsets[id] = buffer.length;
      buffer.add(utf8.encode(head));
      buffer.add(binary);
      buffer.add(utf8.encode(tail));
    }

    buffer.add(utf8.encode('%PDF-1.4\n'));

    const catalogId = 1;
    const pagesId = 2;
    var nextId = 3;

    final pagePlan =
        <
          ({
            int pageId,
            int contentId,
            List<int> imageIds,
            List<int?> smaskIds,
            List<int?> gStateIds,
            List<PdfOverlayImageLine> images,
            String w,
            String h,
          })
        >[];

    for (var page = 1; page <= pageCount; page++) {
      final contentId = nextId++;
      final pageId = nextId++;
      final images = imagesForPage(page);
      final imageIds = <int>[for (var i = 0; i < images.length; i++) nextId++];
      final smaskIds = <int?>[
        for (final img in images) img.smaskBytes != null ? nextId++ : null,
      ];
      final gStateIds = <int?>[
        for (final img in images)
          img.opacity.clamp(0.05, 1.0) < 0.999 ? nextId++ : null,
      ];
      pagePlan.add((
        pageId: pageId,
        contentId: contentId,
        imageIds: imageIds,
        smaskIds: smaskIds,
        gStateIds: gStateIds,
        images: images,
        w: _n(pageWidthPt(page)),
        h: _n(pageHeightPt(page)),
      ));
    }

    writeObj(
      catalogId,
      '$catalogId 0 obj<< /Type /Catalog /Pages $pagesId 0 R >>endobj\n',
    );

    final kids = pagePlan.map((e) => '${e.pageId} 0 R').join(' ');
    writeObj(
      pagesId,
      '$pagesId 0 obj<< /Type /Pages /Kids [$kids] /Count $pageCount >>endobj\n',
    );

    for (final plan in pagePlan) {
      final content = _contentStream(plan.images, plan.gStateIds);
      writeObj(
        plan.contentId,
        '${plan.contentId} 0 obj<< /Length ${utf8.encode(content).length} >>'
        'stream\n$content\nendstream\nendobj\n',
      );

      final resources = StringBuffer();
      final hasG = plan.gStateIds.any((id) => id != null);
      if (plan.imageIds.isNotEmpty || hasG) {
        resources.write('/Resources<< ');
        if (hasG) {
          resources.write('/ExtGState<< ');
          for (var i = 0; i < plan.gStateIds.length; i++) {
            final id = plan.gStateIds[i];
            if (id != null) {
              resources.write('/GS${i + 1} $id 0 R ');
            }
          }
          resources.write('>> ');
        }
        if (plan.imageIds.isNotEmpty) {
          resources.write('/XObject<< ');
          for (var i = 0; i < plan.imageIds.length; i++) {
            resources.write('/Im${i + 1} ${plan.imageIds[i]} 0 R ');
          }
          resources.write('>> ');
        }
        resources.write('>> ');
      }

      writeObj(
        plan.pageId,
        '${plan.pageId} 0 obj<< /Type /Page /Parent $pagesId 0 R '
        '/MediaBox [0 0 ${plan.w} ${plan.h}] /Contents ${plan.contentId} 0 R '
        '$resources>>endobj\n',
      );

      for (var i = 0; i < plan.images.length; i++) {
        final img = plan.images[i];
        final id = plan.imageIds[i];
        final smaskId = plan.smaskIds[i];
        final filter = img.rgbIsFlate ? '/FlateDecode' : '/DCTDecode';
        writeObjWithBinary(
          id,
          '$id 0 obj<< /Type /XObject /Subtype /Image '
              '/Width ${img.imageWidthPx} /Height ${img.imageHeightPx} '
              '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter $filter '
              '${smaskId != null ? '/SMask $smaskId 0 R ' : ''}'
              '/Length ${img.jpegBytes.length} >>stream\n',
          img.jpegBytes,
          '\nendstream\nendobj\n',
        );
      }

      for (var i = 0; i < plan.images.length; i++) {
        final smaskId = plan.smaskIds[i];
        if (smaskId == null) continue;
        final img = plan.images[i];
        final smask = img.smaskBytes!;
        writeObjWithBinary(
          smaskId,
          '$smaskId 0 obj<< /Type /XObject /Subtype /Image '
              '/Width ${img.imageWidthPx} /Height ${img.imageHeightPx} '
              '/ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode '
              '/Length ${smask.length} >>stream\n',
          smask,
          '\nendstream\nendobj\n',
        );
      }

      for (var i = 0; i < plan.images.length; i++) {
        final gId = plan.gStateIds[i];
        if (gId == null) continue;
        final a = plan.images[i].opacity.clamp(0.05, 1.0);
        writeObj(
          gId,
          '$gId 0 obj<< /Type /ExtGState '
          '/ca ${a.toStringAsFixed(3)} '
          '/CA ${a.toStringAsFixed(3)} >>endobj\n',
        );
      }
    }

    final xrefStart = buffer.length;
    final xrefCount = nextId;
    final xref = StringBuffer('xref\n0 $xrefCount\n0000000000 65535 f \n');
    for (var id = 1; id < xrefCount; id++) {
      final off = objectOffsets[id];
      if (off == null) {
        xref.writeln('0000000000 65535 f ');
      } else {
        xref.writeln('${off.toString().padLeft(10, '0')} 00000 n ');
      }
    }
    buffer.add(
      utf8.encode(
        '$xref'
        'trailer<< /Size $xrefCount /Root $catalogId 0 R >>\n'
        'startxref\n$xrefStart\n%%EOF',
      ),
    );

    return buffer.toBytes();
  }

  String _contentStream(
    List<PdfOverlayImageLine> images,
    List<int?> gStateIds,
  ) {
    if (images.isEmpty) {
      return ' ';
    }
    final buf = StringBuffer();
    for (var i = 0; i < images.length; i++) {
      final line = images[i];
      final name = '/Im${i + 1}';
      final w = line.widthPt;
      final h = line.heightPt;
      final cx = line.xPt + w / 2;
      final cy = line.yPt + h / 2;
      final rot = line.rotationDegrees;
      buf.write('q ');
      if (gStateIds[i] != null) {
        buf.write('/GS${i + 1} gs ');
      }
      if (rot.abs() > 0.01) {
        final rad = rot * math.pi / 180;
        final c = math.cos(rad);
        final s = math.sin(rad);
        buf.write('1 0 0 1 ${_n(cx)} ${_n(cy)} cm ');
        buf.write(
          '${c.toStringAsFixed(5)} ${s.toStringAsFixed(5)} '
          '${(-s).toStringAsFixed(5)} ${c.toStringAsFixed(5)} 0 0 cm ',
        );
        buf.write('${_n(w)} 0 0 ${_n(h)} ${_n(-w / 2)} ${_n(-h / 2)} cm ');
      } else {
        buf.write('${_n(w)} 0 0 ${_n(h)} ${_n(line.xPt)} ${_n(line.yPt)} cm ');
      }
      buf.write('$name Do Q ');
    }
    return buf.toString();
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
