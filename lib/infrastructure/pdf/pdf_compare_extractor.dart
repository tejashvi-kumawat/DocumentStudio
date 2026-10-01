import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/domain/compare/compare_models.dart';
import 'package:document_studio/domain/compare/compare_runner.dart';
import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
import 'package:pdfrx/pdfrx.dart';

typedef CompareProgress = void Function(int done, int total);

/// Extracts words (with boxes, font, size, color), images and annotations for
/// Compare.
///
/// With the PDFium backend (all native platforms) extraction runs on pdfrx's
/// own PDFium worker isolate in small page chunks, so PDFium access stays
/// serialized, visible-page rendering can interleave, and the UI isolate never
/// blocks. Other backends fall back to pdfrx's portable text/link API (no font
/// or image data). Results are cached by path + modification time + size.
class PdfCompareExtractor {
  PdfCompareExtractor._();

  static final instance = PdfCompareExtractor._();

  static const _chunkPages = 8;
  static const _maxCached = 6;
  final _cache = <String, CompareDocData>{};
  var _session = 0;

  Future<CompareDocData> extract(
    String path, {
    String? password,
    CompareProgress? onProgress,
    CompareCancelToken? token,
  }) async {
    final stat = await File(path).stat();
    final key = '$path|${stat.modified.microsecondsSinceEpoch}|${stat.size}|'
        '${password ?? ''}';
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      onProgress?.call(cached.pageCount, cached.pageCount);
      return cached;
    }

    CompareDocData doc;
    if (PdfrxEntryFunctions.instance.backendType == PdfrxBackendType.pdfium) {
      try {
        doc = await _extractPdfium(path, password, onProgress, token);
      } on UnimplementedError {
        doc = await _extractPortable(path, password, onProgress, token);
      }
    } else {
      doc = await _extractPortable(path, password, onProgress, token);
    }
    while (_cache.length >= _maxCached) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = doc;
    return doc;
  }

  Future<CompareDocData> _extractPdfium(
    String path,
    String? password,
    CompareProgress? onProgress,
    CompareCancelToken? token,
  ) async {
    final session = 'compare-${identityHashCode(this)}-${_session++}';
    final pages = <ComparePageData>[];
    var total = -1;
    var start = 0;
    try {
      while (total < 0 || start < total) {
        token?.throwIfCancelled();
        final chunk = await PdfrxEntryFunctions.instance.compute(
          _extractChunk,
          (
            session: session,
            path: path,
            password: password,
            start: start,
            count: _chunkPages,
          ),
        );
        if (chunk.error != null) throw _openError(path, chunk.error!);
        total = chunk.pageCount;
        pages.addAll(chunk.pages);
        start += _chunkPages;
        onProgress?.call(math.min(start, total), total);
      }
    } finally {
      unawaited(PdfrxEntryFunctions.instance
          .compute(_closeSession, session)
          .then((_) {}, onError: (Object _) {}));
    }
    return CompareDocData(path: path, pages: pages);
  }

  Future<CompareDocData> _extractPortable(
    String path,
    String? password,
    CompareProgress? onProgress,
    CompareCancelToken? token,
  ) async {
    final PdfDocument doc;
    try {
      doc = await PdfDocument.openFile(
        path,
        passwordProvider: password == null ? null : () => password,
      );
    } on PdfPasswordException {
      throw _openError(path, 4);
    }
    try {
      final pages = <ComparePageData>[];
      final total = doc.pages.length;
      for (var i = 0; i < total; i++) {
        token?.throwIfCancelled();
        pages.add(await _portablePage(doc.pages[i], i));
        onProgress?.call(i + 1, total);
      }
      return CompareDocData(
        path: path,
        pages: pages,
        hasFontInfo: false,
        hasImageInfo: false,
      );
    } finally {
      await doc.dispose();
    }
  }

  Future<ComparePageData> _portablePage(PdfPage page, int index) async {
    final w = page.width <= 0 ? 1.0 : page.width;
    final h = page.height <= 0 ? 1.0 : page.height;
    NormRect norm(PdfRect r) {
      final rect = r.toRect(page: page);
      return NormRect(rect.left / w, rect.top / h, rect.right / w,
              rect.bottom / h)
          .clamp01();
    }

    final words = <CompareWord>[];
    final raw = await page.loadText();
    if (raw != null) {
      final text = raw.fullText;
      final rects = raw.charRects;
      final sb = StringBuffer();
      NormRect? box;
      void flush() {
        if (sb.isNotEmpty) {
          words.add(CompareWord(
            text: sb.toString(),
            rect: box ?? const NormRect(0, 0, 0, 0),
          ));
        }
        sb.clear();
        box = null;
      }

      for (var i = 0; i < text.length; i++) {
        final c = text.codeUnitAt(i);
        if (_isSpace(c)) {
          flush();
          continue;
        }
        sb.writeCharCode(c);
        if (i < rects.length && rects[i].width > 0) {
          final r = norm(rects[i]);
          box = box == null ? r : box!.union(r);
        }
      }
      flush();
    }

    final annots = <CompareAnnot>[];
    for (final link in await page.loadLinks(enableAutoLinkDetection: false)) {
      if (link.rects.isEmpty) continue;
      var r = norm(link.rects.first);
      for (final x in link.rects.skip(1)) {
        r = r.union(norm(x));
      }
      final dest = link.dest;
      annots.add(CompareAnnot(
        subtype: 2,
        rect: r,
        contents: '',
        target: link.url?.toString() ??
            (dest == null ? '' : 'page ${dest.pageNumber}'),
      ));
    }
    return ComparePageData(
      index: index,
      widthPt: w,
      heightPt: h,
      words: words,
      images: const [],
      annots: annots,
    );
  }
}

DocumentStudioError _openError(String path, int code) => DocumentStudioError(
      code: code == 4
          ? DocumentStudioErrorCode.passwordRequired
          : DocumentStudioErrorCode.invalidFile,
      message: code == 4
          ? '${path.split(Platform.pathSeparator).last} is password protected.'
          : 'Could not read ${path.split(Platform.pathSeparator).last} '
              '(PDFium error $code).',
    );

// ---------------------------------------------------------------------------
// PDFium worker side. Everything below runs inside pdfrx's worker isolate;
// top-level state is therefore private to that isolate.
// ---------------------------------------------------------------------------

typedef _ChunkRequest = ({
  String session,
  String path,
  String? password,
  int start,
  int count,
});
typedef _ChunkResult = ({
  int pageCount,
  List<ComparePageData> pages,
  int? error,
});

pdfium_bindings.PDFium? _pdfiumCache;
pdfium_bindings.PDFium get _pdfium =>
    _pdfiumCache ??= pdfium_bindings.getPdfium(modulePath: Pdfrx.pdfiumModulePath);

/// Documents kept open between chunks of one extraction run.
final _sessionDocs = <String, int>{};

void _closeSession(String session) {
  final addr = _sessionDocs.remove(session);
  if (addr != null) {
    _pdfium.FPDF_CloseDocument(pdfium_bindings.FPDF_DOCUMENT.fromAddress(addr));
  }
}

_ChunkResult _extractChunk(_ChunkRequest r) {
  final pdfium = _pdfium;
  return using((arena) {
    pdfium_bindings.FPDF_DOCUMENT doc;
    final addr = _sessionDocs[r.session];
    if (addr != null) {
      doc = pdfium_bindings.FPDF_DOCUMENT.fromAddress(addr);
    } else {
      doc = pdfium.FPDF_LoadDocument(
        r.path.toNativeUtf8(allocator: arena).cast(),
        r.password == null
            ? nullptr
            : r.password!.toNativeUtf8(allocator: arena).cast(),
      );
      if (doc.address == 0) {
        return (
          pageCount: 0,
          pages: const <ComparePageData>[],
          error: pdfium.FPDF_GetLastError(),
        );
      }
      _sessionDocs[r.session] = doc.address;
    }
    final count = pdfium.FPDF_GetPageCount(doc);
    final end = math.min(count, r.start + r.count);
    final pages = <ComparePageData>[
      for (var i = r.start; i < end; i++) _extractPage(pdfium, doc, i),
    ];
    if (end >= count) _closeSession(r.session);
    return (pageCount: count, pages: pages, error: null);
  });
}

bool _isSpace(int c) =>
    c <= 32 ||
    c == 0xA0 ||
    (c >= 0x2000 && c <= 0x200B) ||
    c == 0x3000 ||
    c == 0xFEFF ||
    c == 0xFFFE;

String _stripSubset(String font) {
  final plus = font.indexOf('+');
  return plus == 6 ? font.substring(7) : font;
}

/// 2D affine matrix `[a b c d e f]` as used by PDF (x' = ax + cy + e).
typedef _Mat = (double, double, double, double, double, double);

const _Mat _identity = (1, 0, 0, 1, 0, 0);

(double, double) _apply(_Mat m, double x, double y) =>
    (m.$1 * x + m.$3 * y + m.$5, m.$2 * x + m.$4 * y + m.$6);

/// `outer ∘ inner`: applies [inner] first.
_Mat _concat(_Mat inner, _Mat outer) => (
      inner.$1 * outer.$1 + inner.$2 * outer.$3,
      inner.$1 * outer.$2 + inner.$2 * outer.$4,
      inner.$3 * outer.$1 + inner.$4 * outer.$3,
      inner.$3 * outer.$2 + inner.$4 * outer.$4,
      inner.$5 * outer.$1 + inner.$6 * outer.$3 + outer.$5,
      inner.$5 * outer.$2 + inner.$6 * outer.$4 + outer.$6,
    );

int _hashBytes(Uint8List data) {
  // FNV-1a over at most ~256K evenly spaced bytes plus the length.
  var h = 0x811C9DC5 ^ data.length;
  final step = math.max(1, data.length ~/ 262144);
  for (var i = 0; i < data.length; i += step) {
    h = ((h ^ data[i]) * 0x01000193) & 0xFFFFFFFF;
  }
  return h == 0 ? 1 : h;
}

ComparePageData _extractPage(
  pdfium_bindings.PDFium pdfium,
  pdfium_bindings.FPDF_DOCUMENT doc,
  int index,
) {
  final page = pdfium.FPDF_LoadPage(doc, index);
  if (page.address == 0) {
    return ComparePageData(
      index: index,
      widthPt: 612,
      heightPt: 792,
      words: const [],
      images: const [],
      annots: const [],
    );
  }
  return using((arena) {
    try {
      final wPt = pdfium.FPDF_GetPageWidthF(page);
      final hPt = pdfium.FPDF_GetPageHeightF(page);

      // Page user space -> normalized visual space (top-left origin), derived
      // from PDFium's own display matrix so crop-box offsets and /Rotate are
      // honoured exactly as the renderer does.
      final sw = math.max(1, (wPt * 10).round());
      final sh = math.max(1, (hPt * 10).round());
      final dx = arena<Int>();
      final dy = arena<Int>();
      (double, double) dev(double x, double y) {
        pdfium.FPDF_PageToDevice(page, 0, 0, sw, sh, 0, x, y, dx, dy);
        return (dx.value / sw, dy.value / sh);
      }

      final o = dev(0, 0);
      final ex = dev(1000, 0);
      final ey = dev(0, 1000);
      final axx = (ex.$1 - o.$1) / 1000, axy = (ex.$2 - o.$2) / 1000;
      final ayx = (ey.$1 - o.$1) / 1000, ayy = (ey.$2 - o.$2) / 1000;
      NormRect norm(double l, double b, double r, double t) {
        var x0 = double.infinity, y0 = double.infinity;
        var x1 = -double.infinity, y1 = -double.infinity;
        for (final (px, py) in [(l, b), (r, b), (l, t), (r, t)]) {
          final x = o.$1 + axx * px + ayx * py;
          final y = o.$2 + axy * px + ayy * py;
          x0 = math.min(x0, x);
          y0 = math.min(y0, y);
          x1 = math.max(x1, x);
          y1 = math.max(y1, y);
        }
        return NormRect(x0, y0, x1, y1);
      }

      return ComparePageData(
        index: index,
        widthPt: wPt,
        heightPt: hPt,
        words: _words(pdfium, page, arena, norm),
        images: _images(pdfium, page, arena, norm),
        annots: _annots(pdfium, doc, page, arena, norm),
      );
    } finally {
      pdfium.FPDF_ClosePage(page);
    }
  });
}

typedef _Norm = NormRect Function(double l, double b, double r, double t);

List<CompareWord> _words(
  pdfium_bindings.PDFium pdfium,
  pdfium_bindings.FPDF_PAGE page,
  Arena arena,
  _Norm norm,
) {
  final words = <CompareWord>[];
  final tp = pdfium.FPDFText_LoadPage(page);
  if (tp.address == 0) return words;
  try {
    final n = pdfium.FPDFText_CountChars(tp);
    final loose = arena<pdfium_bindings.FS_RECTF>();
    final l = arena<Double>(), r = arena<Double>();
    final b = arena<Double>(), t = arena<Double>();
    final cr = arena<UnsignedInt>(), cg = arena<UnsignedInt>();
    final cb = arena<UnsignedInt>(), ca = arena<UnsignedInt>();
    final flags = arena<Int>();
    final fontBuf = arena<Uint8>(256);

    final text = StringBuffer();
    double wl = 0, wb = 0, wr = 0, wt = 0;
    double pl = 0, pb = 0, pr = 0, pt = 0;
    var hasBox = false;
    var font = '';
    var size = 0.0;
    var color = 0;

    void flush() {
      if (text.isNotEmpty) {
        words.add(CompareWord(
          text: text.toString(),
          rect: hasBox ? norm(wl, wb, wr, wt) : const NormRect(0, 0, 0, 0),
          font: font,
          size: size,
          color: color,
        ));
      }
      text.clear();
      hasBox = false;
    }

    for (var i = 0; i < n; i++) {
      final code = pdfium.FPDFText_GetUnicode(tp, i);
      if (_isSpace(code) || code == 0xFFFD && text.isEmpty) {
        flush();
        continue;
      }
      var boxed = false;
      double cl = 0, cbm = 0, crt = 0, ctp = 0;
      if (pdfium.FPDFText_GetLooseCharBox(tp, i, loose) != 0 &&
          loose.ref.right > loose.ref.left) {
        cl = loose.ref.left;
        crt = loose.ref.right;
        cbm = math.min(loose.ref.bottom, loose.ref.top);
        ctp = math.max(loose.ref.bottom, loose.ref.top);
        boxed = true;
      } else if (pdfium.FPDFText_GetCharBox(tp, i, l, r, b, t) != 0 &&
          r.value > l.value) {
        cl = l.value;
        crt = r.value;
        cbm = b.value;
        ctp = t.value;
        boxed = true;
      }
      if (boxed && text.isNotEmpty && hasBox) {
        // Words positioned without an explicit space, or a jump to another
        // line / column, still split.
        final em = math.max(size, 4.0);
        final gapX = math.max(0.0, math.max(cl - pr, pl - crt));
        final gapY = math.max(0.0, math.max(cbm - pt, pb - ctp));
        if (gapX > em * 0.3 || gapY > em * 0.6) flush();
      }
      if (text.isEmpty) {
        final len =
            pdfium.FPDFText_GetFontInfo(tp, i, fontBuf.cast(), 256, flags);
        font = len > 1
            ? _stripSubset(String.fromCharCodes(
                fontBuf.asTypedList(math.min(len - 1, 255))))
            : '';
        size = pdfium.FPDFText_GetFontSize(tp, i);
        color = pdfium.FPDFText_GetFillColor(tp, i, cr, cg, cb, ca) != 0
            ? (cr.value << 16) | (cg.value << 8) | cb.value
            : 0;
      }
      text.writeCharCode(code);
      if (boxed) {
        if (!hasBox) {
          wl = cl;
          wr = crt;
          wb = cbm;
          wt = ctp;
          hasBox = true;
        } else {
          wl = math.min(wl, cl);
          wr = math.max(wr, crt);
          wb = math.min(wb, cbm);
          wt = math.max(wt, ctp);
        }
        pl = cl;
        pr = crt;
        pb = cbm;
        pt = ctp;
      }
    }
    flush();
  } finally {
    pdfium.FPDFText_ClosePage(tp);
  }
  return words;
}

List<CompareImageObj> _images(
  pdfium_bindings.PDFium pdfium,
  pdfium_bindings.FPDF_PAGE page,
  Arena arena,
  _Norm norm,
) {
  final images = <CompareImageObj>[];
  final fl = arena<Float>(), fb = arena<Float>();
  final fr = arena<Float>(), ft = arena<Float>();
  final pw = arena<UnsignedInt>(), ph = arena<UnsignedInt>();
  final mat = arena<pdfium_bindings.FS_MATRIX>();

  void visit(pdfium_bindings.FPDF_PAGEOBJECT obj, _Mat m, int depth) {
    if (obj.address == 0 || images.length >= 400) return;
    final type = pdfium.FPDFPageObj_GetType(obj);
    if (type == pdfium_bindings.FPDF_PAGEOBJ_FORM && depth < 4) {
      // Children of a form XObject are positioned in form space.
      var inner = m;
      if (pdfium.FPDFPageObj_GetMatrix(obj, mat) != 0) {
        final f = mat.ref;
        inner = _concat((f.a, f.b, f.c, f.d, f.e, f.f), m);
      }
      final n = pdfium.FPDFFormObj_CountObjects(obj);
      for (var k = 0; k < n; k++) {
        visit(pdfium.FPDFFormObj_GetObject(obj, k), inner, depth + 1);
      }
      return;
    }
    if (type != pdfium_bindings.FPDF_PAGEOBJ_IMAGE) return;
    if (pdfium.FPDFPageObj_GetBounds(obj, fl, fb, fr, ft) == 0) return;
    var x0 = double.infinity, y0 = double.infinity;
    var x1 = -double.infinity, y1 = -double.infinity;
    for (final (px, py) in [
      (fl.value, fb.value),
      (fr.value, fb.value),
      (fl.value, ft.value),
      (fr.value, ft.value),
    ]) {
      final (x, y) = _apply(m, px, py);
      x0 = math.min(x0, x);
      y0 = math.min(y0, y);
      x1 = math.max(x1, x);
      y1 = math.max(y1, y);
    }
    final rect = norm(x0, y0, x1, y1).clamp01();
    if (rect.area < 0.00005) return;
    final ok = pdfium.FPDFImageObj_GetImagePixelSize(obj, pw, ph) != 0;
    images.add(CompareImageObj(
      rect: rect,
      pixelWidth: ok ? pw.value : 0,
      pixelHeight: ok ? ph.value : 0,
      hash: _imageHash(pdfium, obj),
    ));
  }

  final objCount = pdfium.FPDFPage_CountObjects(page);
  for (var k = 0; k < objCount && images.length < 400; k++) {
    visit(pdfium.FPDFPage_GetObject(page, k), _identity, 0);
  }
  return images;
}

int _imageHash(
  pdfium_bindings.PDFium pdfium,
  pdfium_bindings.FPDF_PAGEOBJECT obj,
) {
  const maxBytes = 16 * 1024 * 1024;
  final len = pdfium.FPDFImageObj_GetImageDataRaw(obj, nullptr, 0);
  if (len <= 0) return 0;
  if (len > maxBytes) return 0x9E3779B1 ^ len;
  final buf = malloc<Uint8>(len);
  try {
    final got = pdfium.FPDFImageObj_GetImageDataRaw(obj, buf.cast(), len);
    if (got <= 0 || got > len) return 0;
    return _hashBytes(buf.asTypedList(got));
  } finally {
    malloc.free(buf);
  }
}

List<CompareAnnot> _annots(
  pdfium_bindings.PDFium pdfium,
  pdfium_bindings.FPDF_DOCUMENT doc,
  pdfium_bindings.FPDF_PAGE page,
  Arena arena,
  _Norm norm,
) {
  final annots = <CompareAnnot>[];
  final annotCount = pdfium.FPDFPage_GetAnnotCount(page);
  final rectF = arena<pdfium_bindings.FS_RECTF>();
  final contentsKey = 'Contents'.toNativeUtf8(allocator: arena).cast<Char>();
  for (var k = 0; k < annotCount && annots.length < 400; k++) {
    final annot = pdfium.FPDFPage_GetAnnot(page, k);
    if (annot.address == 0) continue;
    try {
      final subtype = pdfium.FPDFAnnot_GetSubtype(annot);
      if (subtype == 16) continue; // popups mirror their parent note
      if (pdfium.FPDFAnnot_GetRect(annot, rectF) == 0) continue;
      final rf = rectF.ref;
      final rect = norm(
        math.min(rf.left, rf.right),
        math.min(rf.bottom, rf.top),
        math.max(rf.left, rf.right),
        math.max(rf.bottom, rf.top),
      ).clamp01();
      var contents = '';
      final need =
          pdfium.FPDFAnnot_GetStringValue(annot, contentsKey, nullptr, 0);
      if (need > 2) {
        final buf = arena<Uint16>(need ~/ 2 + 1);
        pdfium.FPDFAnnot_GetStringValue(annot, contentsKey, buf.cast(), need);
        contents = String.fromCharCodes(buf.asTypedList(need ~/ 2 - 1));
      }
      final target = subtype == 2 ? _linkTarget(pdfium, doc, annot, arena) : '';
      annots.add(CompareAnnot(
        subtype: subtype,
        rect: rect,
        contents: contents,
        target: target,
      ));
    } finally {
      pdfium.FPDFPage_CloseAnnot(annot);
    }
  }
  return annots;
}

String _linkTarget(
  pdfium_bindings.PDFium pdfium,
  pdfium_bindings.FPDF_DOCUMENT doc,
  pdfium_bindings.FPDF_ANNOTATION annot,
  Arena arena,
) {
  final link = pdfium.FPDFAnnot_GetLink(annot);
  if (link.address == 0) return '';
  final dest = pdfium.FPDFLink_GetDest(doc, link);
  if (dest.address != 0) {
    final p = pdfium.FPDFDest_GetDestPageIndex(doc, dest);
    return p >= 0 ? 'page ${p + 1}' : '';
  }
  final action = pdfium.FPDFLink_GetAction(link);
  if (action.address == 0) return '';
  final type = pdfium.FPDFAction_GetType(action);
  if (type == pdfium_bindings.PDFACTION_URI) {
    final need = pdfium.FPDFAction_GetURIPath(doc, action, nullptr, 0);
    if (need <= 1) return '';
    final buf = arena<Uint8>(need);
    pdfium.FPDFAction_GetURIPath(doc, action, buf.cast(), need);
    return String.fromCharCodes(buf.asTypedList(need - 1));
  }
  if (type == pdfium_bindings.PDFACTION_GOTO) {
    final d = pdfium.FPDFAction_GetDest(doc, action);
    if (d.address != 0) {
      final p = pdfium.FPDFDest_GetDestPageIndex(doc, d);
      if (p >= 0) return 'page ${p + 1}';
    }
  }
  return '';
}
