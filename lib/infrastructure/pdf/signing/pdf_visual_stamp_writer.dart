
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio/core/isolate/run_isolated.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:document_studio/infrastructure/pdf/signing/pdf_cos.dart';
import 'package:image/image.dart' as img;

/// One signature / stamp / image placed on a displayed page.
///
/// The box is normalized to the displayed (rotated, cropped) page with a
/// top-left origin — the same space the on-page preview uses — so what the
/// user sees is exactly what gets written.
class PdfBurnItem {
  const PdfBurnItem({
    required this.page1Based,
    required this.png,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.rotationDegrees = 0,
    this.opacity = 1,
  });

  final int page1Based;
  final Uint8List png;
  final double left;
  final double top;
  final double width;
  final double height;

  /// Clockwise on screen, around the box center.
  final double rotationDegrees;
  final double opacity;
}

/// Adds [png] as an image XObject (RGB + SMask alpha); returns its ref.
PdfRef addPngImageXObject(PdfIncrementalWriter w, Uint8List png) {
  final decoded = img.decodeImage(png);
  if (decoded == null) throw PdfCosException('Unsupported image data');
  final rgba = decoded
      .convert(format: img.Format.uint8, numChannels: 4)
      .getBytes(order: img.ChannelOrder.rgba);
  final width = decoded.width, height = decoded.height;
  final rgb = Uint8List(width * height * 3);
  final alpha = Uint8List(width * height);
  var opaque = true;
  for (var i = 0, j = 0, k = 0; i + 3 < rgba.length; i += 4, j += 3, k++) {
    rgb[j] = rgba[i];
    rgb[j + 1] = rgba[i + 1];
    rgb[j + 2] = rgba[i + 2];
    alpha[k] = rgba[i + 3];
    if (rgba[i + 3] != 255) opaque = false;
  }
  PdfRef? smask;
  if (!opaque) {
    smask = w.add(
      PdfStream(
        PdfDict({
          'Type': const PdfName('XObject'),
          'Subtype': const PdfName('Image'),
          'Width': PdfNum(width),
          'Height': PdfNum(height),
          'ColorSpace': const PdfName('DeviceGray'),
          'BitsPerComponent': const PdfNum(8),
          'Filter': const PdfName('FlateDecode'),
        }),
        pdfDeflate(alpha),
      ),
    );
  }
  return w.add(
    PdfStream(
      PdfDict({
        'Type': const PdfName('XObject'),
        'Subtype': const PdfName('Image'),
        'Width': PdfNum(width),
        'Height': PdfNum(height),
        'ColorSpace': const PdfName('DeviceRGB'),
        'BitsPerComponent': const PdfNum(8),
        'Filter': const PdfName('FlateDecode'),
        'Interpolate': const PdfBool(true),
        'SMask': ?smask,
      }),
      pdfDeflate(rgb),
    ),
  );
}

/// Matrix mapping the image unit square onto the placed box in user space.
PdfMatrix placementMatrix(PdfCosPage page, PdfBurnItem item) {
  final pw = page.displayWidth, ph = page.displayHeight;
  final w = item.width * pw;
  final h = item.height * ph;
  final cx = (item.left + item.width / 2) * pw;
  final cy = (item.top + item.height / 2) * ph;
  return PdfMatrix(w, 0, 0, -h, -w / 2, h / 2)
      .then(PdfMatrix.rotate(item.rotationDegrees * math.pi / 180))
      .then(PdfMatrix.translate(cx, cy))
      .then(displayToUserMatrix(page));
}

/// Resolves a page's resources to a fresh, directly-embedded dictionary.
PdfDict cloneResources(PdfCosDocument doc, PdfCosPage page) {
  final res = doc.resolveDict(page.resources)?.clone() ?? PdfDict();
  for (final key in const ['XObject', 'ExtGState']) {
    final sub = doc.resolveDict(res[key]);
    if (sub != null) res[key] = sub.clone();
  }
  return res;
}

/// Content array for [page] wrapped as `q … Q` plus [extra] after it.
PdfArray wrappedContents(
  PdfCosDocument doc,
  PdfCosPage page,
  PdfIncrementalWriter w,
  List<int> extra,
) {
  final old = page.dict['Contents'];
  final items = <PdfObj>[];
  final resolved = doc.resolve(old);
  if (old is PdfRef && resolved is PdfStream) {
    items.add(old);
  } else if (resolved is PdfArray) {
    items.addAll(resolved.items);
  }
  final pre = w.add(PdfStream(PdfDict(), Uint8List.fromList('q\n'.codeUnits)));
  final post = w.add(
    PdfStream(
      PdfDict({'Filter': const PdfName('FlateDecode')}),
      pdfDeflate([...'\nQ\n'.codeUnits, ...extra]),
    ),
  );
  return PdfArray([pre, ...items, post]);
}

Uint8List burnImagesSync(Uint8List pdf, List<PdfBurnItem> items) {
  if (items.isEmpty) return pdf;
  final doc = PdfCosDocument.parse(pdf);
  if (doc.isEncrypted) throw PdfEncryptedException();
  final w = PdfIncrementalWriter(doc);
  final pages = doc.pages;
  final byPage = <int, List<PdfBurnItem>>{};
  for (final it in items) {
    if (it.page1Based < 1 || it.page1Based > pages.length) {
      throw PdfCosException('Page ${it.page1Based} does not exist');
    }
    byPage.putIfAbsent(it.page1Based, () => []).add(it);
  }
  final images = <String, PdfRef>{};
  final gstates = <int, PdfRef>{};
  for (final entry in byPage.entries) {
    final page = pages[entry.key - 1];
    final res = cloneResources(doc, page);
    final xobj = (res['XObject'] as PdfDict?) ?? PdfDict();
    final gsDict = (res['ExtGState'] as PdfDict?) ?? PdfDict();
    final ops = StringBuffer();
    for (final it in entry.value) {
      final key = crypto.sha1.convert(it.png).toString();
      final ref = images[key] ??= addPngImageXObject(w, it.png);
      final name = 'DSIm${ref.num}';
      xobj[name] = ref;
      ops.write('q\n');
      if (it.opacity < 0.999) {
        final pct = (it.opacity.clamp(0.0, 1.0) * 100).round();
        final gs = gstates[pct] ??= w.add(
          PdfDict({
            'Type': const PdfName('ExtGState'),
            'ca': PdfNum(pct / 100),
            'CA': PdfNum(pct / 100),
          }),
        );
        gsDict['DSGs$pct'] = gs;
        ops.write('/DSGs$pct gs\n');
      }
      ops.write('${placementMatrix(page, it).toPdf()} cm\n/$name Do\nQ\n');
    }
    res['XObject'] = xobj;
    if (gsDict.map.isNotEmpty) res['ExtGState'] = gsDict;
    final pageDict = page.dict.clone()
      ..['Resources'] = res
      ..['Contents'] = wrappedContents(doc, page, w, ops.toString().codeUnits);
    w.put(page.ref, pageDict);
  }
  return w.build();
}

/// Burns [items] into [pdf] off the UI isolate (pure Dart, every platform).
Future<Uint8List> burnImagesIntoPdf(Uint8List pdf, List<PdfBurnItem> items) =>
    runIsolated((a) => burnImagesSync(a.$1, a.$2), (pdf, items));
