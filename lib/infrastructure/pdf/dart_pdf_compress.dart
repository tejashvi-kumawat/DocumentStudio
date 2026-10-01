import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_objects.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_parser.dart';
import 'package:document_studio/infrastructure/pdf/pdf_compress_options.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

/// An image JPEG still larger than this after the first pass gets a second
/// pass (quality about 10 points lower, longest edge about 80% of the cap).
const int kDartPdfImageSecondPassBytes = 400 * 1024;

/// Lossy images always get one JPEG pass. Returns 2 when [firstPassBytes]
/// is still over [kDartPdfImageSecondPassBytes].
int dartPdfImageCompressPasses(int firstPassBytes) =>
    firstPassBytes > kDartPdfImageSecondPassBytes ? 2 : 1;

/// Second-pass JPEG quality: 10 points below the preset (Smallest 40→30,
/// Extreme 45→35, Recommended 60→50).
int dartPdfSecondPassQuality(int jpegQuality) =>
    math.max(1, jpegQuality - 10);

/// Second-pass longest edge: 80% of the preset cap (1000→800, 1200→960,
/// 1600→1280).
int dartPdfSecondPassMaxPx(int maxSidePx) =>
    math.max(1, (maxSidePx * 0.8).round());

/// On-device PDF compression (Android, and desktop when qpdf is absent).
///
/// Lossy presets (everything except [CompressProfile.highQuality]):
/// 1. Downscale each image XObject so its longest edge is at most the preset
///    cap and re-encode JPEG, including images that are already JPEG.
/// 2. If that JPEG is still over [kDartPdfImageSecondPassBytes], run a second
///    pass at quality − 10 and 80% of the cap.
/// 3. Recompress content streams with deflate. Text-only pages (no images)
///    use the strongest deflate level and are never rasterized.
/// 4. A page is rasterized only when it is a single full-page image and the
///    XObject path could not shrink it.
/// 5. Duplicate image streams are merged and unreferenced objects are dropped.
///
/// Lossless mode only recompresses Flate streams and drops unused objects.
class DartPdfCompress {
  DartPdfCompress._();

  /// Compresses [input] to [outputPath]. Writes the smaller of the compressed
  /// bytes and the original file.
  static Future<LocalFileRef> compressToFile({
    required LocalFileRef input,
    required String outputPath,
    PdfCompressOptions options = const PdfCompressOptions(),
    String? password,
  }) async {
    final raw = await File(input.path).readAsBytes();
    final outBytes = await compressBytes(
      Uint8List.fromList(raw),
      options: options,
      password: password,
    );
    await Directory(p.dirname(outputPath)).create(recursive: true);
    await File(outputPath).writeAsBytes(outBytes, flush: true);
    final stat = await File(outputPath).stat();
    return LocalFileRef(
      path: outputPath,
      displayName: p.basename(outputPath),
      sizeBytes: stat.size,
      lastModified: stat.modified,
    );
  }

  /// Same algorithm as [compressToFile], in memory.
  ///
  /// Returns [input] unchanged when the compressed bytes are not smaller.
  static Future<Uint8List> compressBytes(
    Uint8List input, {
    PdfCompressOptions options = const PdfCompressOptions(),
    String? password,
  }) async {
    final produced = await _produce(input, options: options, password: password);
    if (produced.length < input.length) return produced;
    return input;
  }

  static Future<Uint8List> _produce(
    Uint8List input, {
    required PdfCompressOptions options,
    String? password,
  }) async {
    var working = input;
    try {
      return await _editAndMaybeRaster(working, options);
    } on PdfEditException catch (e) {
      if (e.encrypted || (password != null && password.isNotEmpty)) {
        working = await _unlockWithPdfrx(input, password);
        try {
          return await _editAndMaybeRaster(working, options);
        } on PdfEditException {
          return _pdfrxRewrite(working);
        }
      }
      return _pdfrxRewrite(working);
    } catch (_) {
      return _pdfrxRewrite(working);
    }
  }

  static Future<Uint8List> _editAndMaybeRaster(
    Uint8List input,
    PdfCompressOptions options,
  ) async {
    final edited = _editAndRewrite(input, options);
    if (!options.lossyImages || edited.raster.isEmpty) return edited.bytes;
    try {
      return await _rasterizeUnshrunkFullPageImages(
        edited.bytes,
        edited.raster,
        maxSidePx: options.downsampleMaxPx ?? 1200,
        jpegQuality: options.jpegQuality ?? 60,
      );
    } catch (_) {
      return edited.bytes;
    }
  }

  static _EditedPdf _editAndRewrite(
    Uint8List input,
    PdfCompressOptions options,
  ) {
    final doc = PdfEditDocument.open(input);
    final lossy = options.lossyImages;
    final maxPx = options.downsampleMaxPx;
    final quality = (options.jpegQuality ?? 60).clamp(1, 100);
    final pages = _inspectPages(doc);
    final smasks = _softMaskObjectNumbers(doc);

    final shrunk = <int>{};
    for (final num in doc.liveObjectNumbers) {
      final obj = doc.getObject(num);
      if (obj is! PdfStream) continue;
      final type = obj.dict.nameOf('Type');
      if (type == 'ObjStm' || type == 'XRef') continue;

      if (obj.dict.nameOf('Subtype') == 'Image') {
        if (lossy && !smasks.contains(num)) {
          final next = _compressImageStream(
            obj,
            maxSidePx: maxPx,
            jpegQuality: quality,
          );
          if (next != null && next.data.length < obj.data.length) {
            doc.setObject(PdfRef(num, doc.generationOf(num)), next);
            shrunk.add(num);
          } else if (options.recompressFlate) {
            final flate = _recompressFlateStream(obj, level: ZLibOption.maxLevel);
            if (flate != null) {
              doc.setObject(PdfRef(num, doc.generationOf(num)), flate);
            }
          }
        } else if (options.recompressFlate) {
          final next = _recompressFlateStream(obj, level: ZLibOption.maxLevel);
          if (next != null) {
            doc.setObject(PdfRef(num, doc.generationOf(num)), next);
          }
        }
        continue;
      }

      if (!options.recompressFlate) continue;
      final textOnly = pages.textOnlyStreams.contains(num);
      final level = textOnly ? ZLibOption.maxLevel : ZLibOption.defaultLevel;
      final next = _recompressFlateStream(obj, level: level) ??
          (pages.contentStreams.contains(num) || textOnly
              ? _deflateRawStream(obj, level: level)
              : null);
      if (next != null) {
        doc.setObject(PdfRef(num, doc.generationOf(num)), next);
      }
    }

    _dedupeImageStreams(doc);
    final raster = <_RasterTarget>[];
    if (lossy) {
      for (final page in _unshrunkFullPageImages(doc, shrunk)) {
        raster.add(page);
      }
    }
    final bytes = _writeFullPdf(doc);
    if (!_rewriteKeepsPages(input, bytes)) {
      return _EditedPdf(input, const []);
    }
    return _EditedPdf(bytes, raster);
  }

  /// Reject a rewrite that no longer opens or lost pages.
  static bool _rewriteKeepsPages(Uint8List original, Uint8List rewritten) {
    try {
      final before = PdfEditDocument.open(original);
      final after = PdfEditDocument.open(rewritten);
      return after.pageCount == before.pageCount && after.pageCount > 0;
    } on PdfEditException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Re-encodes an image XObject as JPEG. Already-JPEG images are included.
  /// Returns null when the new stream is not smaller.
  static PdfStream? _compressImageStream(
    PdfStream src, {
    required int? maxSidePx,
    required int jpegQuality,
  }) {
    final dict = src.dict;
    if (dict['ImageMask'] is PdfBool && (dict['ImageMask'] as PdfBool).value) {
      return null;
    }
    if (dict.containsKey('Decode') || dict.containsKey('Mask')) return null;
    if (dict.containsKey('SMask')) return null;
    final bpc = (dict['BitsPerComponent'] as PdfNum?)?.i ?? 8;
    if (bpc != 8) return null;

    final w = (dict['Width'] as PdfNum?)?.i;
    final h = (dict['Height'] as PdfNum?)?.i;
    if (w == null || h == null || w < 1 || h < 1) return null;
    if (w * h > 80000000) return null;

    final frame = _decodeImage(src, w, h);
    if (frame == null) return null;

    final first = _jpegPass(frame, maxSidePx: _capPx(maxSidePx), quality: jpegQuality);
    if (first == null) return null;
    var best = first;
    if (dartPdfImageCompressPasses(first.bytes.length) == 2) {
      final cap = (maxSidePx != null && maxSidePx > 0)
          ? maxSidePx
          : math.max(frame.width, frame.height);
      final second = _jpegPass(
        frame,
        maxSidePx: dartPdfSecondPassMaxPx(cap),
        quality: dartPdfSecondPassQuality(jpegQuality),
      );
      if (second != null && second.bytes.length < best.bytes.length) {
        best = second;
      }
    }
    if (best.bytes.length >= src.data.length) return null;

    final gray = best.channels == 1;
    final nextDict = dict.clone()
      ..['Width'] = PdfNum(best.width)
      ..['Height'] = PdfNum(best.height)
      ..['BitsPerComponent'] = const PdfNum(8)
      ..['ColorSpace'] = PdfName(gray ? 'DeviceGray' : 'DeviceRGB')
      ..['Filter'] = const PdfName('DCTDecode')
      ..remove('DecodeParms')
      ..remove('SMask')
      ..remove('Mask')
      ..remove('Length');
    return PdfStream(nextDict, best.bytes);
  }

  static int? _capPx(int? maxSidePx) =>
      (maxSidePx != null && maxSidePx > 0) ? maxSidePx : null;

  static img.Image? _decodeImage(PdfStream src, int w, int h) {
    final filters = _filterNames(src.dict);
    if (filters.length == 1 &&
        (filters.first == 'DCTDecode' || filters.first == 'DCT')) {
      try {
        return img.decodeJpg(src.data);
      } catch (_) {
        return null;
      }
    }
    if (filters.isNotEmpty &&
        !(filters.length == 1 &&
            (filters.first == 'FlateDecode' || filters.first == 'Fl'))) {
      return null;
    }
    final cs = _colorSpaceName(src.dict['ColorSpace']);
    if (cs != 'DeviceRGB' && cs != 'DeviceGray') return null;
    late final Uint8List decoded;
    try {
      decoded = filters.isEmpty ? src.data : decodeStreamData(src.dict, src.data);
    } catch (_) {
      return null;
    }
    final channels = cs == 'DeviceGray' ? 1 : 3;
    if (decoded.length < w * h * channels) return null;
    return img.Image.fromBytes(
      width: w,
      height: h,
      bytes: decoded.buffer,
      bytesOffset: decoded.offsetInBytes,
      order: channels == 1 ? img.ChannelOrder.red : img.ChannelOrder.rgb,
      numChannels: channels,
    );
  }

  static _JpegPass? _jpegPass(
    img.Image frame, {
    required int? maxSidePx,
    required int quality,
  }) {
    var out = frame;
    if (maxSidePx != null) {
      final longest = math.max(out.width, out.height);
      if (longest > maxSidePx) {
        final scale = maxSidePx / longest;
        out = img.copyResize(
          out,
          width: math.max(1, (out.width * scale).round()),
          height: math.max(1, (out.height * scale).round()),
          interpolation: img.Interpolation.average,
        );
      }
    }
    final gray = out.numChannels == 1;
    final encoded = gray ? out : out.convert(numChannels: 3);
    Uint8List jpeg;
    try {
      jpeg = Uint8List.fromList(
        img.encodeJpg(encoded, quality: quality.clamp(1, 100)),
      );
    } catch (_) {
      return null;
    }
    return _JpegPass(
      bytes: jpeg,
      width: out.width,
      height: out.height,
      channels: gray ? 1 : 3,
    );
  }

  static PdfStream? _recompressFlateStream(PdfStream src, {required int level}) {
    final filters = _filterNames(src.dict);
    if (filters.length != 1) return null;
    if (filters.first != 'FlateDecode' && filters.first != 'Fl') return null;
    final type = src.dict.nameOf('Type');
    if (type == 'ObjStm' || type == 'XRef') return null;
    late final Uint8List decoded;
    try {
      decoded = decodeStreamData(src.dict, src.data);
    } catch (_) {
      return null;
    }
    return _deflateBytes(src.dict, decoded, level: level, original: src.data.length);
  }

  static PdfStream? _deflateRawStream(PdfStream src, {required int level}) {
    if (_filterNames(src.dict).isNotEmpty) return null;
    if (src.dict.nameOf('Subtype') == 'Image') return null;
    final type = src.dict.nameOf('Type');
    if (type == 'ObjStm' || type == 'XRef' || type == 'Metadata') return null;
    return _deflateBytes(src.dict, src.data, level: level, original: src.data.length);
  }

  static PdfStream? _deflateBytes(
    PdfDict dict,
    Uint8List decoded, {
    required int level,
    required int original,
  }) {
    final encoded = Uint8List.fromList(
      ZLibEncoder(level: level.clamp(0, 9)).convert(decoded),
    );
    if (encoded.length >= original) return null;
    final nextDict = dict.clone()
      ..['Filter'] = const PdfName('FlateDecode')
      ..remove('DecodeParms')
      ..remove('Length');
    return PdfStream(nextDict, encoded);
  }

  static Set<int> _softMaskObjectNumbers(PdfEditDocument doc) {
    final out = <int>{};
    for (final n in doc.liveObjectNumbers) {
      final obj = doc.getObject(n);
      if (obj is! PdfStream) continue;
      if (obj.dict.nameOf('Subtype') != 'Image') continue;
      final mask = obj.dict['SMask'];
      if (mask is PdfRef) out.add(mask.num);
    }
    return out;
  }

  static _PageFacts _inspectPages(PdfEditDocument doc) {
    final textOnly = <int>{};
    final content = <int>{};
    try {
      for (var page1 = 1; page1 <= doc.pageCount; page1++) {
        final page = doc.pageDict(page1);
        final streams = _contentObjectNumbers(doc, page);
        content.addAll(streams);
        final hasImage = _resourcesHaveImage(
          doc,
          doc.dictOf(doc.inherited(page, 'Resources')),
          {},
        );
        if (!hasImage) {
          textOnly.addAll(streams);
          textOnly.addAll(_formStreamNumbers(doc, page));
        }
      }
    } on PdfEditException {
      // Damaged page tree: still compress image objects, skip page policy.
    }
    return _PageFacts(
      textOnlyStreams: textOnly,
      contentStreams: content,
    );
  }

  static List<_RasterTarget> _unshrunkFullPageImages(
    PdfEditDocument doc,
    Set<int> shrunk,
  ) {
    final out = <_RasterTarget>[];
    try {
      for (var page1 = 1; page1 <= doc.pageCount; page1++) {
        final page = doc.pageDict(page1);
        final target = _fullPageImageTarget(doc, page1, page);
        if (target == null || shrunk.contains(target.imageObject)) continue;
        out.add(target);
      }
    } on PdfEditException {
      return const [];
    }
    return out;
  }

  static List<int> _contentObjectNumbers(PdfEditDocument doc, PdfDict page) {
    final raw = page['Contents'];
    final resolved = doc.resolve(raw);
    final items = resolved is PdfArray ? resolved.items : <PdfObj>[?raw];
    return [
      for (final item in items)
        if (item is PdfRef) item.num,
    ];
  }

  static List<int> _formStreamNumbers(PdfEditDocument doc, PdfDict page) {
    final out = <int>[];
    void walk(PdfDict? res, Set<int> seen) {
      if (res == null) return;
      final xo = doc.dictOf(res['XObject']);
      if (xo == null) return;
      for (final v in xo.entries.values) {
        if (v is! PdfRef || !seen.add(v.num)) continue;
        final obj = doc.getObject(v.num);
        if (obj is! PdfStream) continue;
        if (obj.dict.nameOf('Subtype') != 'Form') continue;
        out.add(v.num);
        walk(doc.dictOf(obj.dict['Resources']), seen);
      }
    }

    walk(doc.dictOf(doc.inherited(page, 'Resources')), {});
    return out;
  }

  static bool _resourcesHaveImage(
    PdfEditDocument doc,
    PdfDict? res,
    Set<int> seen,
  ) {
    if (res == null) return false;
    final xo = doc.dictOf(res['XObject']);
    if (xo == null) return false;
    for (final v in xo.entries.values) {
      final refNum = v is PdfRef ? v.num : null;
      if (refNum != null && !seen.add(refNum)) continue;
      final obj = doc.resolve(v);
      if (obj is! PdfStream) continue;
      final subtype = obj.dict.nameOf('Subtype');
      if (subtype == 'Image') return true;
      if (subtype == 'Form' &&
          _resourcesHaveImage(doc, doc.dictOf(obj.dict['Resources']), seen)) {
        return true;
      }
    }
    return false;
  }

  /// A page whose only paint is one image XObject covering the page.
  static _RasterTarget? _fullPageImageTarget(
    PdfEditDocument doc,
    int page1,
    PdfDict page,
  ) {
    final raw = _decodePageContent(doc, page);
    if (raw == null) return null;
    final scan = _scanContent(raw);
    if (scan.hasText || scan.unsafe || scan.doNames.length != 1) return null;
    final name = scan.doNames.single;
    final ref = _imageRefNamed(doc, page, name);
    if (ref == null) return null;
    final stream = doc.getObject(ref.num);
    if (stream is! PdfStream) return null;
    final geo = doc.pageGeometry(page1);
    final matrixFull = scan.cmWidth != null &&
        scan.cmHeight != null &&
        scan.cmWidth! >= geo.cropWidth * 0.75 &&
        scan.cmHeight! >= geo.cropHeight * 0.75;
    final w = (stream.dict['Width'] as PdfNum?)?.i ?? 0;
    final h = (stream.dict['Height'] as PdfNum?)?.i ?? 0;
    final large = math.max(w, h) >= 800 || stream.data.length > kDartPdfImageSecondPassBytes;
    if (!matrixFull && !large) return null;
    return _RasterTarget(page1 - 1, ref.num);
  }

  static String? _decodePageContent(PdfEditDocument doc, PdfDict page) {
    final raw = page['Contents'];
    final resolved = doc.resolve(raw);
    final items = resolved is PdfArray ? resolved.items : <PdfObj>[?raw];
    final buf = StringBuffer();
    for (final item in items) {
      final stream = doc.resolve(item);
      if (stream is! PdfStream) return null;
      Uint8List data;
      try {
        data = _filterNames(stream.dict).isEmpty
            ? stream.data
            : decodeStreamData(stream.dict, stream.data);
      } catch (_) {
        return null;
      }
      buf.writeln(latin1.decode(data));
    }
    return buf.toString();
  }

  static PdfRef? _imageRefNamed(PdfEditDocument doc, PdfDict page, String name) {
    final res = doc.dictOf(doc.inherited(page, 'Resources'));
    final xo = doc.dictOf(res?['XObject']);
    final v = xo?[name];
    if (v is! PdfRef) return null;
    final obj = doc.getObject(v.num);
    if (obj is PdfStream && obj.dict.nameOf('Subtype') == 'Image') return v;
    return null;
  }

  static void _dedupeImageStreams(PdfEditDocument doc) {
    final buckets = <int, List<int>>{};
    final meta = <int, (String, Uint8List)>{};
    for (final n in doc.liveObjectNumbers) {
      final obj = doc.getObject(n);
      if (obj is! PdfStream || obj.dict.nameOf('Subtype') != 'Image') continue;
      final key = _imageMeta(doc, obj);
      final hash = Object.hash(key, obj.data.length, _fnv(obj.data));
      meta[n] = (key, obj.data);
      buckets.putIfAbsent(hash, () => []).add(n);
    }
    final redirect = <int, int>{};
    for (final group in buckets.values) {
      if (group.length < 2) continue;
      final canon = group.first;
      final canonBytes = meta[canon]!.$2;
      final canonKey = meta[canon]!.$1;
      for (final n in group.skip(1)) {
        final other = meta[n]!;
        if (other.$1 != canonKey) continue;
        if (!_sameBytes(canonBytes, other.$2)) continue;
        redirect[n] = canon;
      }
    }
    if (redirect.isEmpty) return;
    final nums = doc.liveObjectNumbers.toList();
    for (final n in nums) {
      if (redirect.containsKey(n)) continue;
      final obj = doc.getObject(n);
      if (obj == null) continue;
      final next = _rewriteRefs(doc, obj, redirect);
      if (next != null) {
        doc.setObject(PdfRef(n, doc.generationOf(n)), next);
      }
    }
  }

  static String _imageMeta(PdfEditDocument doc, PdfStream stream) {
    final w = (stream.dict['Width'] as PdfNum?)?.i ?? 0;
    final h = (stream.dict['Height'] as PdfNum?)?.i ?? 0;
    final cs = _colorSpaceName(stream.dict['ColorSpace']) ?? '';
    final filter = _filterNames(stream.dict).join(',');
    final mask = stream.dict['SMask'];
    var maskHash = 0;
    if (mask is PdfRef) {
      final m = doc.getObject(mask.num);
      if (m is PdfStream) maskHash = _fnv(m.data);
    }
    return '$w,$h,$cs,$filter,$maskHash';
  }

  static PdfObj? _rewriteRefs(
    PdfEditDocument doc,
    PdfObj obj,
    Map<int, int> redirect,
  ) {
    switch (obj) {
      case PdfRef(:final num):
        final to = redirect[num];
        if (to == null) return null;
        return PdfRef(to, doc.generationOf(to));
      case PdfArray(:final items):
        var changed = false;
        final next = <PdfObj>[];
        for (final item in items) {
          final rewritten = _rewriteRefs(doc, item, redirect);
          if (rewritten != null) {
            changed = true;
            next.add(rewritten);
          } else {
            next.add(item);
          }
        }
        return changed ? PdfArray(next) : null;
      case PdfDict(:final entries):
        var changed = false;
        final next = <String, PdfObj>{};
        for (final e in entries.entries) {
          final rewritten = _rewriteRefs(doc, e.value, redirect);
          if (rewritten != null) {
            changed = true;
            next[e.key] = rewritten;
          } else {
            next[e.key] = e.value;
          }
        }
        return changed ? PdfDict(next) : null;
      case PdfStream(:final dict, :final data):
        final rewritten = _rewriteRefs(doc, dict, redirect);
        if (rewritten is! PdfDict) return null;
        return PdfStream(rewritten, data);
      default:
        return null;
    }
  }

  static Future<Uint8List> _rasterizeUnshrunkFullPageImages(
    Uint8List pdf,
    List<_RasterTarget> targets, {
    required int maxSidePx,
    required int jpegQuality,
  }) async {
    final opened = await PdfDocument.openData(pdf);
    try {
      final replacements = <int, PdfStream>{};
      for (final target in targets) {
        if (target.pageIndex < 0 || target.pageIndex >= opened.pages.length) {
          continue;
        }
        try {
        final page = opened.pages[target.pageIndex];
        final loaded = await page.loadText();
        final text = loaded?.fullText.trim() ?? '';
        if (text.isNotEmpty) continue;
        final longest = math.max(page.width, page.height);
        final scale = longest <= 0
            ? 1.0
            : (maxSidePx / longest).clamp(0.15, 4.0).toDouble();
        final rendered = await page.render(
          fullWidth: math.max(1.0, page.width * scale),
          fullHeight: math.max(1.0, page.height * scale),
        );
        if (rendered == null) continue;
        Uint8List jpeg;
        var width = rendered.width;
        var height = rendered.height;
        try {
          final frame = img.Image.fromBytes(
            width: rendered.width,
            height: rendered.height,
            bytes: rendered.pixels.buffer,
            bytesOffset: rendered.pixels.offsetInBytes,
            order: img.ChannelOrder.bgra,
            numChannels: 4,
          ).convert(numChannels: 3);
          var current = frame;
          jpeg = Uint8List.fromList(
            img.encodeJpg(current, quality: jpegQuality.clamp(1, 100)),
          );
          if (jpeg.length > kDartPdfImageSecondPassBytes) {
            final edge = dartPdfSecondPassMaxPx(maxSidePx);
            final side = math.max(current.width, current.height);
            if (side > edge) {
              final s = edge / side;
              current = img.copyResize(
                current,
                width: math.max(1, (current.width * s).round()),
                height: math.max(1, (current.height * s).round()),
                interpolation: img.Interpolation.average,
              );
            }
            final second = Uint8List.fromList(
              img.encodeJpg(
                current,
                quality: dartPdfSecondPassQuality(jpegQuality),
              ),
            );
            if (second.length < jpeg.length) {
              jpeg = second;
              width = current.width;
              height = current.height;
            }
          }
        } finally {
          rendered.dispose();
        }
        replacements[target.imageObject] = PdfStream(
          PdfDict({
            'Type': const PdfName('XObject'),
            'Subtype': const PdfName('Image'),
            'Width': PdfNum(width),
            'Height': PdfNum(height),
            'ColorSpace': const PdfName('DeviceRGB'),
            'BitsPerComponent': const PdfNum(8),
            'Filter': const PdfName('DCTDecode'),
          }),
          jpeg,
        );
        } catch (_) {
          continue;
        }
      }
      if (replacements.isEmpty) return pdf;
      final doc = PdfEditDocument.open(pdf);
      var changed = false;
      for (final e in replacements.entries) {
        final current = doc.getObject(e.key);
        if (current is! PdfStream) continue;
        if (e.value.data.length >= current.data.length) continue;
        doc.setObject(PdfRef(e.key, doc.generationOf(e.key)), e.value);
        changed = true;
      }
      if (!changed) return pdf;
      final rewritten = _writeFullPdf(doc);
      if (rewritten.length >= pdf.length) return pdf;
      if (!_rewriteKeepsPages(pdf, rewritten)) return pdf;
      return rewritten;
    } finally {
      await opened.dispose();
    }
  }

  static List<String> _filterNames(PdfDict dict) {
    final filter = dict['Filter'];
    if (filter is PdfName) return [filter.name];
    if (filter is PdfArray) {
      return [
        for (final f in filter.items)
          if (f is PdfName) f.name,
      ];
    }
    return const [];
  }

  static String? _colorSpaceName(PdfObj? cs) {
    if (cs is PdfName) return cs.name;
    if (cs is PdfArray && cs.items.isNotEmpty && cs.items.first is PdfName) {
      return (cs.items.first as PdfName).name;
    }
    return null;
  }

  static Set<int> _reachableNums(PdfEditDocument doc) {
    final seen = <int>{};
    var steps = 0;
    void walk(PdfObj? o) {
      if (o == null || steps++ > 2000000) return;
      if (o is PdfRef) {
        if (!seen.add(o.num)) return;
        walk(doc.getObject(o.num));
        return;
      }
      if (o is PdfArray) {
        for (final i in o.items) {
          walk(i);
        }
      } else if (o is PdfDict) {
        for (final v in o.entries.values) {
          walk(v);
        }
      } else if (o is PdfStream) {
        walk(o.dict);
      }
    }

    walk(doc.trailer['Root']);
    walk(doc.trailer['Info']);
    return seen;
  }

  /// Classic xref rewrite of reachable objects. Unreferenced objects are omitted.
  static Uint8List _writeFullPdf(PdfEditDocument doc) {
    final reachable = _reachableNums(doc);
    final sink = PdfWriterSink();
    sink.raw('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n');
    final offsets = <int, int>{};
    final gens = <int, int>{};
    final maxNum = math.max(0, doc.nextObjectNumber - 1);
    var highest = 0;
    for (var n = 1; n <= maxNum; n++) {
      if (!reachable.contains(n)) continue;
      final obj = doc.getObject(n);
      if (obj == null) continue;
      if (obj is PdfStream) {
        final t = obj.dict.nameOf('Type');
        if (t == 'ObjStm' || t == 'XRef') continue;
      }
      highest = math.max(highest, n);
      final gen = doc.generationOf(n);
      gens[n] = gen;
      offsets[n] = sink.length;
      sink.raw('$n $gen obj\n');
      sink.obj(obj);
      sink.raw('\nendobj\n');
    }
    final trailer = doc.trailer.clone()
      ..['Size'] = PdfNum(highest + 1)
      ..remove('Prev')
      ..remove('XRefStm')
      ..remove('Encrypt');
    final xrefStart = sink.length;
    sink.raw('xref\n0 ${highest + 1}\n');
    sink.raw('0000000000 65535 f \n');
    for (var i = 1; i <= highest; i++) {
      final off = offsets[i];
      if (off == null) {
        sink.raw('0000000000 65535 f \n');
      } else {
        final gen = (gens[i] ?? 0).toString().padLeft(5, '0');
        sink.raw('${off.toString().padLeft(10, '0')} $gen n \n');
      }
    }
    sink.raw('trailer\n');
    sink.obj(trailer);
    sink.raw('\nstartxref\n$xrefStart\n%%EOF\n');
    return sink.take();
  }

  static Future<Uint8List> _unlockWithPdfrx(
    Uint8List input,
    String? password,
  ) async {
    final doc = await PdfDocument.openData(
      input,
      passwordProvider: password == null || password.isEmpty
          ? null
          : () async => password,
    );
    try {
      return await doc.encodePdf(removeSecurity: true);
    } finally {
      await doc.dispose();
    }
  }

  /// Structural rewrite when the editor cannot open the file.
  ///
  /// Does not rasterize pages. Turning text pages into images makes them
  /// larger and destroys selection.
  static Future<Uint8List> _pdfrxRewrite(Uint8List input) async {
    final doc = await PdfDocument.openData(input);
    try {
      final pages = List<PdfPage>.of(doc.pages);
      final out = await PdfDocument.createNew(
        sourceName:
            'document_studio://compress-fallback/${DateTime.now().microsecondsSinceEpoch}',
      );
      try {
        out.pages = pages;
        await out.assemble();
        return await out.encodePdf();
      } finally {
        await out.dispose();
      }
    } finally {
      await doc.dispose();
    }
  }
}

class _EditedPdf {
  const _EditedPdf(this.bytes, this.raster);
  final Uint8List bytes;
  final List<_RasterTarget> raster;
}

class _RasterTarget {
  const _RasterTarget(this.pageIndex, this.imageObject);
  final int pageIndex;
  final int imageObject;
}

class _PageFacts {
  const _PageFacts({
    required this.textOnlyStreams,
    required this.contentStreams,
  });

  final Set<int> textOnlyStreams;
  final Set<int> contentStreams;
}

class _JpegPass {
  const _JpegPass({
    required this.bytes,
    required this.width,
    required this.height,
    required this.channels,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int channels;
}

class _ContentScan {
  bool hasText = false;
  bool unsafe = false;
  final List<String> doNames = [];
  double? cmWidth;
  double? cmHeight;
}

const _textOps = {'Tj', 'TJ', "'", '"', 'BT'};
const _paintOps = {
  'm', 'l', 'c', 'v', 'y', 'h', 're',
  'S', 's', 'f', 'F', 'f*', 'B', 'B*', 'b', 'b*', 'sh',
};

_ContentScan _scanContent(String s) {
  final scan = _ContentScan();
  final nums = <double>[];
  String? pendingName;
  final n = s.length;
  var i = 0;

  void applyOp(String op) {
    if (op == 'cm' && nums.length >= 6) {
      final a = nums[nums.length - 6];
      final b = nums[nums.length - 5];
      final c = nums[nums.length - 4];
      final d = nums[nums.length - 3];
      scan.cmWidth = math.sqrt(a * a + b * b);
      scan.cmHeight = math.sqrt(c * c + d * d);
    }
    if (op == 'Do' && pendingName != null) scan.doNames.add(pendingName!);
    if (_textOps.contains(op)) scan.hasText = true;
    if (_paintOps.contains(op) || op == 'BI') scan.unsafe = true;
    nums.clear();
    pendingName = null;
  }

  while (i < n && !scan.unsafe) {
    final c = s.codeUnitAt(i);
    if (c == 0x25) {
      while (i < n && s.codeUnitAt(i) != 0x0a && s.codeUnitAt(i) != 0x0d) {
        i++;
      }
      continue;
    }
    if (c == 0x28) {
      i = _skipLiteralString(s, i);
      nums.clear();
      continue;
    }
    if (c == 0x3c) {
      if (i + 1 < n && s.codeUnitAt(i + 1) == 0x3c) {
        i = _skipAngleDict(s, i);
      } else {
        i = _skipHexString(s, i);
      }
      nums.clear();
      continue;
    }
    if (c == 0x2f) {
      i++;
      final start = i;
      while (i < n && !_isPdfDelim(s.codeUnitAt(i))) {
        i++;
      }
      pendingName = s.substring(start, i);
      continue;
    }
    if (_isPdfSpace(c) || c == 0x5b || c == 0x5d || c == 0x7b || c == 0x7d) {
      i++;
      continue;
    }
    final start = i;
    while (i < n && !_isPdfDelim(s.codeUnitAt(i))) {
      i++;
    }
    final tok = s.substring(start, i);
    if (tok.isEmpty) {
      i++;
      continue;
    }
    final numVal = double.tryParse(tok);
    if (numVal != null) {
      nums.add(numVal);
    } else {
      applyOp(tok);
    }
  }
  return scan;
}

int _skipLiteralString(String s, int i) {
  var depth = 0;
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    if (c == 0x5c) {
      i += 2;
      continue;
    }
    if (c == 0x28) depth++;
    if (c == 0x29) {
      depth--;
      i++;
      if (depth == 0) return i;
      continue;
    }
    i++;
  }
  return i;
}

int _skipHexString(String s, int i) {
  final end = s.indexOf('>', i + 1);
  return end < 0 ? s.length : end + 1;
}

int _skipAngleDict(String s, int i) {
  var depth = 0;
  while (i + 1 < s.length) {
    if (s.codeUnitAt(i) == 0x3c && s.codeUnitAt(i + 1) == 0x3c) {
      depth++;
      i += 2;
      continue;
    }
    if (s.codeUnitAt(i) == 0x3e && s.codeUnitAt(i + 1) == 0x3e) {
      depth--;
      i += 2;
      if (depth == 0) return i;
      continue;
    }
    i++;
  }
  return s.length;
}

bool _isPdfSpace(int c) =>
    c == 0x00 ||
    c == 0x09 ||
    c == 0x0a ||
    c == 0x0c ||
    c == 0x0d ||
    c == 0x20;

bool _isPdfDelim(int c) =>
    _isPdfSpace(c) ||
    c == 0x28 ||
    c == 0x29 ||
    c == 0x3c ||
    c == 0x3e ||
    c == 0x5b ||
    c == 0x5d ||
    c == 0x7b ||
    c == 0x7d ||
    c == 0x2f ||
    c == 0x25;

int _fnv(Uint8List data) {
  var h = 0x811c9dc5;
  for (final b in data) {
    h = (h ^ b) * 0x01000193;
  }
  return h & 0x7fffffff;
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
