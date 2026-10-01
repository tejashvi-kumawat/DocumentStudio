import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio/domain/pdf_stamp/stamp_label_layout.dart';
import 'package:document_studio/domain/pdf_stamp/watermark_layout.dart';
import 'package:image/image.dart' as img;

/// Text run drawn with Helvetica-Bold (WinAnsi), centered on a rotated frame.
class PdfMarkText {
  const PdfMarkText({
    required this.text,
    required this.fontSizePt,
    required this.centerXPt,
    required this.centerYPt,
    required this.baselineStartXPt,
    required this.baselineYDownPt,
    required this.rgb,
    this.rotationDegrees = 0,
    this.opacity = 1,
  });

  /// Latin-1 text (already sanitized).
  final String text;
  final double fontSizePt;

  /// Frame origin in PDF user space (bottom-left origin).
  final double centerXPt;
  final double centerYPt;

  /// Baseline start relative to the frame origin; y measured downward.
  final double baselineStartXPt;
  final double baselineYDownPt;
  final (double, double, double) rgb;

  /// Counter-clockwise, degrees.
  final double rotationDegrees;
  final double opacity;
}

/// The shared watermark image drawn centered on a rotated frame.
class PdfMarkImage {
  const PdfMarkImage({
    required this.centerXPt,
    required this.centerYPt,
    required this.widthPt,
    required this.heightPt,
    this.rotationDegrees = 0,
    this.opacity = 1,
  });

  final double centerXPt;
  final double centerYPt;
  final double widthPt;
  final double heightPt;
  final double rotationDegrees;
  final double opacity;
}

/// Filled and/or stroked rectangle (bottom-left origin).
class PdfMarkRect {
  const PdfMarkRect({
    required this.xPt,
    required this.yPt,
    required this.widthPt,
    required this.heightPt,
    this.fillRgb,
    this.fillOpacity = 1,
    this.strokeRgb,
    this.strokeOpacity = 1,
    this.strokeWidthPt = 1,
  });

  final double xPt;
  final double yPt;
  final double widthPt;
  final double heightPt;
  final (double, double, double)? fillRgb;
  final double fillOpacity;
  final (double, double, double)? strokeRgb;
  final double strokeOpacity;
  final double strokeWidthPt;
}

class PdfMarkPage {
  const PdfMarkPage({
    this.rects = const [],
    this.images = const [],
    this.texts = const [],
  });

  final List<PdfMarkRect> rects;
  final List<PdfMarkImage> images;
  final List<PdfMarkText> texts;

  bool get isEmpty => rects.isEmpty && images.isEmpty && texts.isEmpty;
}

/// Pre-encoded image for [PdfWatermarkOverlayBuilder] (encoded once, shared
/// by every page and tile).
class PdfMarkImageData {
  PdfMarkImageData._({
    required this.widthPx,
    required this.heightPx,
    required this.data,
    required this.filter,
    this.alphaFlate,
  });

  final int widthPx;
  final int heightPx;
  final Uint8List data;
  final String filter;
  final Uint8List? alphaFlate;

  double get aspect => widthPx / math.max(1, heightPx);

  /// Decodes [source]; keeps transparency via a soft mask so PNG logos do not
  /// get an opaque box around them.
  static PdfMarkImageData? fromEncoded(
    Uint8List source, {
    int maxSidePx = 2000,
  }) {
    var decoded = img.decodeImage(source);
    if (decoded == null) return null;
    decoded = img.bakeOrientation(decoded);
    final longest = math.max(decoded.width, decoded.height);
    if (longest > maxSidePx) {
      decoded = decoded.width >= decoded.height
          ? img.copyResize(decoded, width: maxSidePx)
          : img.copyResize(decoded, height: maxSidePx);
    }
    var hasAlpha = false;
    if (decoded.hasAlpha) {
      for (final p in decoded) {
        if (p.aNormalized < 0.999) {
          hasAlpha = true;
          break;
        }
      }
    }
    if (!hasAlpha) {
      return PdfMarkImageData._(
        widthPx: decoded.width,
        heightPx: decoded.height,
        data: Uint8List.fromList(img.encodeJpg(decoded, quality: 90)),
        filter: '/DCTDecode',
      );
    }
    final rgb = Uint8List(decoded.width * decoded.height * 3);
    final alpha = Uint8List(decoded.width * decoded.height);
    var i = 0;
    for (final p in decoded) {
      rgb[i * 3] = (p.rNormalized * 255).round().clamp(0, 255);
      rgb[i * 3 + 1] = (p.gNormalized * 255).round().clamp(0, 255);
      rgb[i * 3 + 2] = (p.bNormalized * 255).round().clamp(0, 255);
      alpha[i] = (p.aNormalized * 255).round().clamp(0, 255);
      i++;
    }
    final z = ZLibCodec(level: 6);
    return PdfMarkImageData._(
      widthPx: decoded.width,
      heightPx: decoded.height,
      data: Uint8List.fromList(z.encode(rgb)),
      filter: '/FlateDecode',
      alphaFlate: Uint8List.fromList(z.encode(alpha)),
    );
  }
}

/// Converts shared-layout watermark marks (normalized, top-left origin) into
/// PDF user-space marks (points, bottom-left origin).
PdfMarkPage watermarkMarksToPdf(
  List<WatermarkMark> marks, {
  required WatermarkSpec spec,
  required double pageWidthPt,
  required double pageHeightPt,
}) {
  final opacity = spec.clampedOpacity;
  if (spec.isImage) {
    return PdfMarkPage(
      images: [
        for (final m in marks)
          PdfMarkImage(
            centerXPt: m.centerXNorm * pageWidthPt,
            centerYPt: (1 - m.centerYNorm) * pageHeightPt,
            widthPt: m.widthPt,
            heightPt: m.heightPt,
            rotationDegrees: m.rotationDegrees,
            opacity: opacity,
          ),
      ],
    );
  }
  return PdfMarkPage(
    texts: [
      for (final m in marks)
        PdfMarkText(
          text: m.text,
          fontSizePt: m.fontSizePt,
          centerXPt: m.centerXNorm * pageWidthPt,
          centerYPt: (1 - m.centerYNorm) * pageHeightPt,
          baselineStartXPt: m.baselineStartXPt,
          baselineYDownPt: m.baselineYDownPt,
          rgb: spec.colorRgb,
          rotationDegrees: m.rotationDegrees,
          opacity: opacity,
        ),
    ],
  );
}

/// Converts a shared-layout stamp label into PDF user-space marks.
PdfMarkPage stampLabelToPdf(
  StampLabelLayout s, {
  required (double, double, double) rgb,
  required double pageWidthPt,
  required double pageHeightPt,
}) {
  final x = s.leftNorm * pageWidthPt;
  final y = (1 - s.topNorm - s.heightNorm) * pageHeightPt;
  return PdfMarkPage(
    rects: [
      PdfMarkRect(
        xPt: x,
        yPt: y,
        widthPt: s.widthPt,
        heightPt: s.heightPt,
        fillRgb: rgb,
        fillOpacity: StampLabelLayout.fillOpacity,
        strokeRgb: rgb,
        strokeWidthPt: StampLabelLayout.strokeWidthPt,
      ),
    ],
    texts: [
      PdfMarkText(
        text: s.text,
        fontSizePt: s.fontSizePt,
        centerXPt: s.centerXNorm * pageWidthPt,
        centerYPt: (1 - s.centerYNorm) * pageHeightPt,
        baselineStartXPt: -s.textWidthPt / 2,
        baselineYDownPt: s.baselineBelowCenterPt,
        rgb: rgb,
      ),
    ],
  );
}

/// Builds a multi-page overlay PDF for qpdf `--overlay` / `--underlay`.
///
/// Pages use the viewer's visual size (after `/Rotate`); qpdf inverts the
/// destination rotation so the overlay lands upright as previewed.
class PdfWatermarkOverlayBuilder {
  Uint8List build({
    required int pageCount,
    required (double, double) Function(int pageIndex1Based) pageSizePt,
    required PdfMarkPage Function(int pageIndex1Based) marksForPage,
    PdfMarkImageData? image,
  }) {
    if (pageCount < 1) {
      throw ArgumentError.value(pageCount, 'pageCount', 'must be >= 1');
    }

    final pages = [for (var p = 1; p <= pageCount; p++) marksForPage(p)];

    final alphas = <String>{};
    String key(double fill, double stroke) =>
        '${_n(fill.clamp(0.0, 1.0))}_${_n(stroke.clamp(0.0, 1.0))}';
    for (final page in pages) {
      for (final r in page.rects) {
        alphas.add(key(r.fillOpacity, 1));
        alphas.add(key(1, r.strokeOpacity));
      }
      for (final m in page.images) {
        alphas.add(key(m.opacity, m.opacity));
      }
      for (final t in page.texts) {
        alphas.add(key(t.opacity, t.opacity));
      }
    }
    final gsNames = <String, String>{};
    for (final k in alphas) {
      gsNames[k] = '/GS${gsNames.length + 1}';
    }

    final out = BytesBuilder(copy: false);
    final offsets = <int, int>{};
    out.add(latin1.encode('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n'));

    void obj(int id, List<int> body) {
      offsets[id] = out.length;
      out.add(latin1.encode('$id 0 obj\n'));
      out.add(body);
      out.add(latin1.encode('\nendobj\n'));
    }

    void streamObj(int id, String dict, List<int> data) {
      offsets[id] = out.length;
      out.add(latin1.encode('$id 0 obj\n<< $dict /Length ${data.length} >>\nstream\n'));
      out.add(data);
      out.add(latin1.encode('\nendstream\nendobj\n'));
    }

    const catalogId = 1;
    const pagesId = 2;
    const fontId = 3;
    var next = 4;
    final imageId = image != null ? next++ : null;
    final smaskId = image?.alphaFlate != null ? next++ : null;
    final gsIds = <String, int>{for (final k in gsNames.keys) k: next++};
    final pageIds = <int>[];
    final contentIds = <int>[];
    for (var i = 0; i < pageCount; i++) {
      contentIds.add(next++);
      pageIds.add(next++);
    }

    obj(catalogId, latin1.encode('<< /Type /Catalog /Pages $pagesId 0 R >>'));
    obj(
      pagesId,
      latin1.encode(
        '<< /Type /Pages /Kids [${pageIds.map((id) => '$id 0 R').join(' ')}] '
        '/Count $pageCount >>',
      ),
    );
    obj(
      fontId,
      latin1.encode(
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold '
        '/Encoding /WinAnsiEncoding >>',
      ),
    );
    if (image != null && imageId != null) {
      final smask = smaskId != null ? '/SMask $smaskId 0 R ' : '';
      streamObj(
        imageId,
        '/Type /XObject /Subtype /Image /Width ${image.widthPx} '
        '/Height ${image.heightPx} /ColorSpace /DeviceRGB '
        '/BitsPerComponent 8 /Filter ${image.filter} $smask',
        image.data,
      );
      if (smaskId != null) {
        streamObj(
          smaskId,
          '/Type /XObject /Subtype /Image /Width ${image.widthPx} '
          '/Height ${image.heightPx} /ColorSpace /DeviceGray '
          '/BitsPerComponent 8 /Filter /FlateDecode',
          image.alphaFlate!,
        );
      }
    }
    for (final entry in gsIds.entries) {
      final parts = entry.key.split('_');
      obj(
        entry.value,
        latin1.encode(
          '<< /Type /ExtGState /ca ${parts[0]} /CA ${parts[1]} >>',
        ),
      );
    }

    final gsRes = gsIds.entries
        .map((e) => '${gsNames[e.key]} ${e.value} 0 R')
        .join(' ');
    final xRes = imageId != null ? '/XObject << /Im1 $imageId 0 R >> ' : '';
    final resources = '/Resources << /Font << /F1 $fontId 0 R >> '
        '${gsRes.isEmpty ? '' : '/ExtGState << $gsRes >> '}$xRes>>';

    for (var i = 0; i < pageCount; i++) {
      final content = _content(pages[i], gsNames, key);
      streamObj(contentIds[i], '', content);
      final (w, h) = pageSizePt(i + 1);
      obj(
        pageIds[i],
        latin1.encode(
          '<< /Type /Page /Parent $pagesId 0 R '
          '/MediaBox [0 0 ${_n(math.max(w, 1))} ${_n(math.max(h, 1))}] '
          '/Contents ${contentIds[i]} 0 R $resources >>',
        ),
      );
    }

    final size = next;
    final xrefStart = out.length;
    final xref = StringBuffer('xref\n0 $size\n0000000000 65535 f \n');
    for (var id = 1; id < size; id++) {
      xref.write('${(offsets[id] ?? 0).toString().padLeft(10, '0')} 00000 n \n');
    }
    xref.write(
      'trailer\n<< /Size $size /Root $catalogId 0 R >>\n'
      'startxref\n$xrefStart\n%%EOF\n',
    );
    out.add(latin1.encode(xref.toString()));
    return out.toBytes();
  }

  List<int> _content(
    PdfMarkPage page,
    Map<String, String> gsNames,
    String Function(double, double) key,
  ) {
    final b = StringBuffer();
    String rgb((double, double, double) c) =>
        '${_n(c.$1)} ${_n(c.$2)} ${_n(c.$3)}';
    String rotate(double cx, double cy, double deg) {
      final rad = deg * math.pi / 180;
      final c = math.cos(rad);
      final s = math.sin(rad);
      return '${_t(c)} ${_t(s)} ${_t(-s)} ${_t(c)} ${_n(cx)} ${_n(cy)} cm ';
    }

    for (final r in page.rects) {
      final re =
          '${_n(r.xPt)} ${_n(r.yPt)} ${_n(r.widthPt)} ${_n(r.heightPt)} re ';
      final fill = r.fillRgb;
      if (fill != null) {
        b.write('q ${gsNames[key(r.fillOpacity, 1)]} gs ${rgb(fill)} rg ${re}f Q\n');
      }
      final stroke = r.strokeRgb;
      if (stroke != null && r.strokeWidthPt > 0) {
        b.write(
          'q ${gsNames[key(1, r.strokeOpacity)]} gs ${rgb(stroke)} RG '
          '${_n(r.strokeWidthPt)} w 0 j ${re}S Q\n',
        );
      }
    }
    for (final m in page.images) {
      b.write(
        'q ${gsNames[key(m.opacity, m.opacity)]} gs '
        '${rotate(m.centerXPt, m.centerYPt, m.rotationDegrees)}'
        '${_n(m.widthPt)} 0 0 ${_n(m.heightPt)} '
        '${_n(-m.widthPt / 2)} ${_n(-m.heightPt / 2)} cm /Im1 Do Q\n',
      );
    }
    for (final t in page.texts) {
      final escaped = t.text
          .replaceAll(r'\', r'\\')
          .replaceAll('(', r'\(')
          .replaceAll(')', r'\)');
      b.write(
        'q ${gsNames[key(t.opacity, t.opacity)]} gs ${rgb(t.rgb)} rg '
        '${rotate(t.centerXPt, t.centerYPt, t.rotationDegrees)}'
        'BT /F1 ${_n(t.fontSizePt)} Tf '
        '${_n(t.baselineStartXPt)} ${_n(-t.baselineYDownPt)} Td '
        '($escaped) Tj ET Q\n',
      );
    }
    if (b.isEmpty) b.write(' ');
    return latin1.encode(b.toString());
  }

  static String _n(num v) {
    final s = v.toStringAsFixed(3);
    return s.contains('.')
        ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : s;
  }

  static String _t(double v) => v.toStringAsFixed(5);
}
