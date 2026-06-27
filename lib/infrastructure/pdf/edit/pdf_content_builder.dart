import 'dart:convert';
import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:document_studio/domain/pdf_markup/pdf_page_geometry.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_objects.dart';
import 'package:image/image.dart' as img;

/// Standard-14 font families the editor writes (metric-compatible with the
/// bundled Liberation fonts used by on-screen previews).
enum PdfStdFont {
  helvetica('Helvetica'),
  helveticaBold('Helvetica-Bold'),
  helveticaOblique('Helvetica-Oblique'),
  helveticaBoldOblique('Helvetica-BoldOblique'),
  times('Times-Roman'),
  timesBold('Times-Bold'),
  timesItalic('Times-Italic'),
  timesBoldItalic('Times-BoldItalic'),
  courier('Courier'),
  courierBold('Courier-Bold'),
  courierOblique('Courier-Oblique'),
  courierBoldOblique('Courier-BoldOblique');

  const PdfStdFont(this.baseFont);
  final String baseFont;

  PdfDict toFontDict() => PdfDict({
    'Type': const PdfName('Font'),
    'Subtype': const PdfName('Type1'),
    'BaseFont': PdfName(baseFont),
    'Encoding': const PdfName('WinAnsiEncoding'),
  });
}

const Map<int, int> _winAnsiExtras = {
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

/// True when every character of [s] is representable in WinAnsiEncoding.
bool isWinAnsiEncodable(String s) {
  for (final r in s.runes) {
    if (!(_winAnsiByte(r) != null)) return false;
  }
  return true;
}

int? _winAnsiByte(int rune) {
  if (rune >= 0x20 && rune < 0x7f) return rune;
  if (rune >= 0xa0 && rune <= 0xff) return rune;
  return _winAnsiExtras[rune];
}

/// WinAnsi bytes for [s]; unsupported characters become `?`.
Uint8List encodeWinAnsi(String s) {
  final out = <int>[];
  for (final r in s.runes) {
    if (r == 0x09) {
      out.add(0x20);
      continue;
    }
    out.add(_winAnsiByte(r) ?? 0x3f);
  }
  return Uint8List.fromList(out);
}

/// Replaces characters the standard fonts can't show, so previews match.
String sanitizeForStdFont(String s) => String.fromCharCodes(
  encodeWinAnsi(s).map((b) {
    if (b < 0x80 || b >= 0xa0) return b;
    for (final e in _winAnsiExtras.entries) {
      if (e.value == b) return e.key;
    }
    return 0x3f;
  }),
);

/// Fluent builder for PDF content-stream operators.
class PdfContentBuilder {
  final StringBuffer _sb = StringBuffer();

  String n(num v) => formatPdfNum(v);

  PdfContentBuilder op(String s) {
    _sb.writeln(s);
    return this;
  }

  void save() => op('q');
  void restore() => op('Q');

  void cm(Affine2 m) =>
      op('${n(m.a)} ${n(m.b)} ${n(m.c)} ${n(m.d)} ${n(m.e)} ${n(m.f)} cm');

  void fillRgb(double r, double g, double b) =>
      op('${n(r)} ${n(g)} ${n(b)} rg');
  void strokeRgb(double r, double g, double b) =>
      op('${n(r)} ${n(g)} ${n(b)} RG');

  void fillColor(int argb) => fillRgb(
    ((argb >> 16) & 0xff) / 255,
    ((argb >> 8) & 0xff) / 255,
    (argb & 0xff) / 255,
  );
  void strokeColor(int argb) => strokeRgb(
    ((argb >> 16) & 0xff) / 255,
    ((argb >> 8) & 0xff) / 255,
    (argb & 0xff) / 255,
  );

  void lineWidth(double w) => op('${n(w)} w');
  void lineCap(int c) => op('$c J');
  void lineJoin(int j) => op('$j j');
  void dash(List<double> pattern, [double phase = 0]) =>
      op('[${pattern.map(n).join(' ')}] ${n(phase)} d');
  void gs(String name) => op('/$name gs');

  void moveTo(Offset p) => op('${n(p.dx)} ${n(p.dy)} m');
  void lineTo(Offset p) => op('${n(p.dx)} ${n(p.dy)} l');
  void curveTo(Offset c1, Offset c2, Offset p) => op(
    '${n(c1.dx)} ${n(c1.dy)} ${n(c2.dx)} ${n(c2.dy)} ${n(p.dx)} ${n(p.dy)} c',
  );
  void close() => op('h');
  void rect(double x, double y, double w, double h) =>
      op('${n(x)} ${n(y)} ${n(w)} ${n(h)} re');

  /// Rectangle with circular corners of radius [r] (y-up or y-down alike).
  void roundedRect(double x, double y, double w, double h, double r) {
    if (r <= 0) {
      rect(x, y, w, h);
      return;
    }
    const k = 0.5522847498;
    final kr = r * k;
    moveTo(Offset(x + r, y));
    lineTo(Offset(x + w - r, y));
    curveTo(
      Offset(x + w - r + kr, y),
      Offset(x + w, y + r - kr),
      Offset(x + w, y + r),
    );
    lineTo(Offset(x + w, y + h - r));
    curveTo(
      Offset(x + w, y + h - r + kr),
      Offset(x + w - r + kr, y + h),
      Offset(x + w - r, y + h),
    );
    lineTo(Offset(x + r, y + h));
    curveTo(
      Offset(x + r - kr, y + h),
      Offset(x, y + h - r + kr),
      Offset(x, y + h - r),
    );
    lineTo(Offset(x, y + r));
    curveTo(Offset(x, y + r - kr), Offset(x + r - kr, y), Offset(x + r, y));
    close();
  }

  /// Intersects the clip with the current path (and ends the path).
  void clip() => op('W n');

  void fill() => op('f');
  void stroke() => op('S');
  void fillStroke() => op('B');
  void endPath() => op('n');

  void polyline(List<Offset> pts, {bool closed = false}) {
    if (pts.isEmpty) return;
    moveTo(pts.first);
    for (final p in pts.skip(1)) {
      lineTo(p);
    }
    if (closed) close();
  }

  /// Ellipse inscribed in the axis-aligned box (4 Bézier arcs).
  void ellipse(double x, double y, double w, double h) {
    const k = 0.5522847498;
    final cx = x + w / 2, cy = y + h / 2;
    final rx = w / 2, ry = h / 2;
    moveTo(Offset(cx + rx, cy));
    curveTo(
      Offset(cx + rx, cy + ry * k),
      Offset(cx + rx * k, cy + ry),
      Offset(cx, cy + ry),
    );
    curveTo(
      Offset(cx - rx * k, cy + ry),
      Offset(cx - rx, cy + ry * k),
      Offset(cx - rx, cy),
    );
    curveTo(
      Offset(cx - rx, cy - ry * k),
      Offset(cx - rx * k, cy - ry),
      Offset(cx, cy - ry),
    );
    curveTo(
      Offset(cx + rx * k, cy - ry),
      Offset(cx + rx, cy - ry * k),
      Offset(cx + rx, cy),
    );
    close();
  }

  /// Draws [text] with the text matrix [tm] (maps text space → current space).
  ///
  /// When [invisible] is true, uses text rendering mode 3 (neither fill nor
  /// stroke) so glyphs stay selectable/searchable without covering the page.
  void text(
    String fontRes,
    double size,
    Affine2 tm,
    String text, {
    double charSpacing = 0,
    bool invisible = false,
  }) {
    final enc = encodeWinAnsi(text);
    final sb = StringBuffer('(');
    for (final b in enc) {
      if (b == 0x28 || b == 0x29 || b == 0x5c) {
        sb.write('\\');
        sb.writeCharCode(b);
      } else if (b < 0x20 || b > 0x7e) {
        sb.write('\\${b.toRadixString(8).padLeft(3, '0')}');
      } else {
        sb.writeCharCode(b);
      }
    }
    sb.write(')');
    op('BT');
    op('/$fontRes ${n(size)} Tf');
    if (invisible) op('3 Tr');
    if (charSpacing != 0) op('${n(charSpacing)} Tc');
    op('${n(tm.a)} ${n(tm.b)} ${n(tm.c)} ${n(tm.d)} ${n(tm.e)} ${n(tm.f)} Tm');
    op('$sb Tj');
    op('ET');
  }

  void doXObject(String name) => op('/$name Do');

  void beginArtifact(String subtype) =>
      op('/Artifact <</Type /Pagination /Subtype /$subtype>> BDC');
  void endMarked() => op('EMC');

  Uint8List bytes() => Uint8List.fromList(latin1.encode(_sb.toString()));
  @override
  String toString() => _sb.toString();
}

/// Flate-compressed stream helper.
PdfStream flateStream(PdfDict dict, Uint8List data) {
  final z = Uint8List.fromList(ZLibEncoder().convert(data));
  final d = dict.clone()..['Filter'] = const PdfName('FlateDecode');
  return PdfStream(d, z);
}

/// ExtGState with real transparency (never blends toward white).
PdfDict extGStateAlpha({
  double fillAlpha = 1,
  double strokeAlpha = 1,
  String? blendMode,
}) => PdfDict({
  'Type': const PdfName('ExtGState'),
  'ca': PdfNum(fillAlpha.clamp(0.0, 1.0)),
  'CA': PdfNum(strokeAlpha.clamp(0.0, 1.0)),
  if (blendMode != null) 'BM': PdfName(blendMode),
});

/// Builds an image XObject (JPEG passthrough, otherwise Flate RGB + SMask).
class PdfImageXObject {
  PdfImageXObject._(this.image, this.smask, this.widthPx, this.heightPx);

  /// Returns null when [encoded] can't be decoded.
  static PdfImageXObject? fromEncoded(Uint8List encoded) {
    final decoder = img.findDecoderForData(encoded);
    if (decoder == null) return null;
    final isJpeg = decoder is img.JpegDecoder;
    img.Image? decoded;
    try {
      decoded = decoder.decode(encoded);
    } catch (_) {
      decoded = null;
    }
    if (decoded == null) return null;
    final w = decoded.width, h = decoded.height;
    if (isJpeg && (decoded.numChannels == 3 || decoded.numChannels == 1)) {
      final gray = decoded.numChannels == 1;
      final dict = PdfDict({
        'Type': const PdfName('XObject'),
        'Subtype': const PdfName('Image'),
        'Width': PdfNum(w),
        'Height': PdfNum(h),
        'ColorSpace': PdfName(gray ? 'DeviceGray' : 'DeviceRGB'),
        'BitsPerComponent': const PdfNum(8),
        'Filter': const PdfName('DCTDecode'),
      });
      return PdfImageXObject._(PdfStream(dict, encoded), null, w, h);
    }
    final rgba = decoded.convert(numChannels: 4, format: img.Format.uint8);
    final rgb = Uint8List(w * h * 3);
    final alpha = Uint8List(w * h);
    var hasAlpha = false;
    var i = 0;
    for (final px in rgba) {
      rgb[i * 3] = px.r.toInt();
      rgb[i * 3 + 1] = px.g.toInt();
      rgb[i * 3 + 2] = px.b.toInt();
      final a = px.a.toInt();
      alpha[i] = a;
      if (a != 255) hasAlpha = true;
      i++;
    }
    PdfStream? smask;
    if (hasAlpha) {
      smask = flateStream(
        PdfDict({
          'Type': const PdfName('XObject'),
          'Subtype': const PdfName('Image'),
          'Width': PdfNum(w),
          'Height': PdfNum(h),
          'ColorSpace': const PdfName('DeviceGray'),
          'BitsPerComponent': const PdfNum(8),
        }),
        alpha,
      );
    }
    final image = flateStream(
      PdfDict({
        'Type': const PdfName('XObject'),
        'Subtype': const PdfName('Image'),
        'Width': PdfNum(w),
        'Height': PdfNum(h),
        'ColorSpace': const PdfName('DeviceRGB'),
        'BitsPerComponent': const PdfNum(8),
      }),
      rgb,
    );
    return PdfImageXObject._(image, smask, w, h);
  }

  final PdfStream image;
  final PdfStream? smask;
  final int widthPx;
  final int heightPx;
}
