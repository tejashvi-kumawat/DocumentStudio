import 'package:document_studio/core/pdf/page_loader.dart';

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/live_text_grouping.dart';
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/infrastructure/pdf/pdf_helvetica_metrics.dart';
import 'package:pdfrx/pdfrx.dart';

/// Text / link geometry of one page in normalized, top-left, *displayed*
/// coordinates (page rotation and crop box applied — same space as overlays).
class LivePageText {
  const LivePageText({
    required this.page1Based,
    required this.pageSizePt,
    required this.charRects,
    required this.runs,
    required this.links,
  });

  final int page1Based;
  final Size pageSizePt;
  final List<Rect> charRects;
  final List<LiveTextEditTarget> runs;
  final List<LiveLinkHit> links;
}

Rect _norm(PdfRect r, PdfPage page) {
  final px = r.toRect(page: page);
  return Rect.fromLTRB(
    px.left / page.width,
    px.top / page.height,
    px.right / page.width,
    px.bottom / page.height,
  );
}

final RegExp _ascenders = RegExp(r'[A-Z0-9bdfhiklt!?&%#@$/\\|()\[\]{}]');
final RegExp _descenders = RegExp(r'[gjpqyQ,;()\[\]{}|]');

/// Editor box for an existing run: estimates font size and baseline from the
/// tight glyph bounds so replacement text sits on the original baseline.
LiveTextEditTarget _runTarget(String text, Rect coverNorm, Size pagePt) {
  final hPt = coverNorm.height * pagePt.height;
  final hasAsc = _ascenders.hasMatch(text);
  final hasDesc = _descenders.hasMatch(text);
  final emFraction = switch ((hasAsc, hasDesc)) {
    (true, true) => 0.93,
    (true, false) => 0.72,
    (false, true) => 0.74,
    (false, false) => 0.53,
  };
  final fs = (hPt / emFraction).clamp(4.0, 96.0);
  final topPt = coverNorm.top * pagePt.height;
  final baselinePt = topPt + (hasAsc ? 0.72 : 0.53) * fs;
  final lineTopPt = baselinePt - kHelveticaBaselineFromLineTopEm * fs;
  final leftPt = coverNorm.left * pagePt.width;
  final widthPt = math.max(
    coverNorm.width * pagePt.width + fs * 0.6,
    helveticaTextWidthPt(text, fs) + fs * 0.6,
  );
  final box = Rect.fromLTWH(
    leftPt / pagePt.width,
    lineTopPt / pagePt.height,
    math.min(widthPt / pagePt.width, 1 - leftPt / pagePt.width),
    fs * kTextLineHeightEm / pagePt.height,
  );
  return LiveTextEditTarget(
    normRect: box,
    originalText: text,
    fontSizePt: fs,
    coverNorm: coverNorm.inflate(0.6 / pagePt.height),
  );
}

/// Loads text runs, character boxes and link annotations for [page1Based].
Future<LivePageText?> loadLivePageText({
  required LocalFileRef file,
  required String? password,
  required int page1Based,
  bool withRuns = true,
  bool withChars = true,
  bool withLinks = false,
}) async {
  PdfDocument? doc;
  try {
    doc = await openPdfLazily(file.path, password: password);
    if (doc.pages.isEmpty) return null;
    final page = await loadPageOnDemand(
      doc,
      page1Based.clamp(1, doc.pages.length),
    );
    if (page == null) return null;
    final size = Size(page.width, page.height);
    final chars = <Rect>[];
    final runs = <LiveTextEditTarget>[];
    if (withRuns || withChars) {
      final text = await page.loadStructuredText();
      if (withChars) {
        for (final r in text.charRects) {
          chars.add(_norm(r, page));
        }
      }
      if (withRuns) {
        runs.addAll(await _blocksFor(page, text, size));
      }
    }
    final links = <LiveLinkHit>[];
    if (withLinks) {
      final raw = await page.loadLinks(enableAutoLinkDetection: false);
      for (final l in raw) {
        if (l.rects.isEmpty) continue;
        var r = _norm(l.rects.first, page);
        for (final extra in l.rects.skip(1)) {
          r = r.expandToInclude(_norm(extra, page));
        }
        links.add(
          LiveLinkHit(
            normRect: r,
            uri: l.url?.toString(),
            destPage1Based: l.dest?.pageNumber,
          ),
        );
      }
    }
    return LivePageText(
      page1Based: page.pageNumber,
      pageSizePt: size,
      charRects: chars,
      runs: runs,
      links: links,
    );
  } catch (_) {
    return null;
  } finally {
    await doc?.dispose();
  }
}

/// Editable paragraph blocks of [page], with sampled background / ink colour.
Future<List<LiveTextEditTarget>> _blocksFor(
  PdfPage page,
  PdfPageText text,
  Size size,
) async {
  final raw = <RawTextFragment>[];
  for (final f in text.fragments) {
    if (f.text.trim().isEmpty) continue;
    final n = _norm(f.bounds, page);
    if (n.width < 0.002 || n.height < 0.002) continue;
    raw.add(RawTextFragment(text: f.text, rect: n));
  }
  final blocks = groupTextFragments(raw, size);
  if (blocks.isEmpty) return const [];

  _PagePixels? pixels;
  try {
    pixels = await _renderForSampling(page);
  } catch (_) {}

  final out = <LiveTextEditTarget>[];
  for (final b in blocks) {
    final first = b.lines.first;
    final base = _runTarget(first.text.trimRight(), first.rect, size);
    final union = b.rect;
    final covers = [for (final l in b.lines) l.rect.inflate(0.6 / size.height)];
    final fs = base.fontSizePt;
    // Original line spacing (centre to centre of the first two lines).
    var leading = kTextLineHeightEm;
    if (b.lines.length >= 2) {
      final pitch =
          (b.lines[1].rect.center.dy - b.lines[0].rect.center.dy) * size.height;
      leading = (pitch / fs).clamp(1.0, 2.6);
    }
    final leftPt = union.left * size.width;
    final textW = [
      for (final l in b.lines) helveticaTextWidthPt(l.text.trim(), fs),
    ].reduce(math.max);
    final widthPt = math.max(
      union.width * size.width + fs * 0.6,
      textW + fs * 0.6,
    );
    final box = Rect.fromLTWH(
      leftPt / size.width,
      base.normRect.top - (leading - kTextLineHeightEm) / 2 * fs / size.height,
      math.min(widthPt / size.width, 1 - leftPt / size.width),
      b.lines.length * fs * leading / size.height,
    );
    Color? bg;
    Color? ink;
    if (pixels != null) {
      bg = pixels.backgroundAround(union);
      ink = pixels.inkWithin(union, bg);
    }
    out.add(
      LiveTextEditTarget(
        normRect: box,
        originalText: b.text,
        fontSizePt: fs,
        coverNorm: union.inflate(0.6 / size.height),
        coverRects: covers,
        coverColor: bg,
        textColor: ink,
        lineCount: b.lines.length,
        leadingEm: leading,
      ),
    );
  }
  return out;
}

/// Loads editable text blocks for [pages] from one open document.
Future<Map<int, List<LiveTextEditTarget>>> loadEditableTextBlocks({
  required LocalFileRef file,
  required String? password,
  required List<int> pages,
}) async {
  try {
    final doc = await _EditDocCache.open(file.path, password);
    return await _EditDocCache.run(
      () => loadEditableTextBlocksFromDoc(doc, pages),
    );
  } catch (_) {
    return const {};
  }
}

/// Picture of [norm] (normalized rect) on [page1], [widthPx] wide — the
/// "ghost" Edit drags around before the change is written. Uses the cached
/// Edit copy, so it costs one small render.
Future<Image?> renderPageRegion({
  required String path,
  required String? password,
  required int page1,
  required Rect norm,
  required double widthPx,
}) async {
  try {
    final doc = await _EditDocCache.open(path, password);
    return await _EditDocCache.run(() async {
      final page = await loadPageOnDemand(doc, page1);
      if (page == null) return null;
      final n = norm.intersect(const Rect.fromLTWH(0, 0, 1, 1));
      if (n.width <= 0 || n.height <= 0) return null;
      final scale = (widthPx / math.max(1, n.width * page.width)).clamp(
        0.2,
        4.0,
      );
      final fullW = page.width * scale, fullH = page.height * scale;
      final w = math.max(1, (n.width * fullW).round());
      final h = math.max(1, (n.height * fullH).round());
      if (w * h > 4000 * 4000) return null;
      final img = await page.render(
        x: (n.left * fullW).round(),
        y: (n.top * fullH).round(),
        width: w,
        height: h,
        fullWidth: fullW,
        fullHeight: fullH,
        annotationRenderingMode: PdfAnnotationRenderingMode.annotationAndForms,
        flags: PdfPageRenderFlags.limitedImageCache,
      );
      if (img == null) return null;
      try {
        final c = Completer<Image>();
        decodeImageFromPixels(
          Uint8List.fromList(img.pixels),
          img.width,
          img.height,
          PixelFormat.bgra8888,
          c.complete,
        );
        return await c.future;
      } finally {
        img.dispose();
      }
    });
  } catch (_) {
    return null;
  }
}

/// Closes the cached Edit copy (before the file is rewritten: Windows cannot
/// replace a file that is open).
Future<void> releaseEditDocCache() => _EditDocCache.release();

/// Edit mode asks for blocks on every page change. Opening the PDF each time
/// cost 0.3–1.5 s on big books, so one lazily loaded copy is kept while the
/// file is unchanged (path + size + mtime) and closed after a minute idle.
abstract final class _EditDocCache {
  static String? _key;
  static Future<PdfDocument>? _doc;
  static Timer? _idle;
  static int _busy = 0;

  static Future<PdfDocument> open(String path, String? password) async {
    final st = await File(path).stat();
    final key = '$path|${st.size}|${st.modified.microsecondsSinceEpoch}';
    if (_key != key || _doc == null) {
      final old = _doc;
      _key = key;
      _doc = openPdfLazily(path, password: password);
      if (old != null) unawaited(_disposeWhenFree(old));
    }
    _armIdle();
    return _doc!;
  }

  static Future<void> release() async {
    final d = _doc;
    _doc = null;
    _key = null;
    _idle?.cancel();
    if (d != null) await _disposeWhenFree(d);
  }

  static Future<T> run<T>(Future<T> Function() task) async {
    _busy++;
    try {
      return await task();
    } finally {
      _busy--;
      _armIdle();
    }
  }

  static Future<void> _disposeWhenFree(Future<PdfDocument> doc) async {
    while (_busy > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    try {
      await (await doc).dispose();
    } catch (_) {}
  }

  static void _armIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 60), () {
      final d = _doc;
      if (d == null || _busy > 0) return;
      _doc = null;
      _key = null;
      unawaited(_disposeWhenFree(d));
    });
  }
}

/// Same as [loadEditableTextBlocks] on an already open document (so a
/// whole-document pass opens the file once).
Future<Map<int, List<LiveTextEditTarget>>> loadEditableTextBlocksFromDoc(
  PdfDocument doc,
  List<int> pages,
) async {
  final result = <int, List<LiveTextEditTarget>>{};
  for (final n in pages) {
    try {
      final page = await loadPageOnDemand(doc, n);
      if (page == null) continue;
      final text = await page.loadStructuredText();
      result[n] = await _blocksFor(page, text, Size(page.width, page.height));
    } catch (_) {
      // Pages that failed stay absent so a later call retries them.
    }
  }
  return result;
}

class _PagePixels {
  _PagePixels(this.bgra, this.w, this.h);

  final Uint8List bgra;
  final int w;
  final int h;

  Color _px(int x, int y) {
    final i = (y.clamp(0, h - 1) * w + x.clamp(0, w - 1)) * 4;
    return Color.fromARGB(255, bgra[i + 2], bgra[i + 1], bgra[i]);
  }

  /// Median colour of a ring just outside [norm] — the page behind the text.
  Color backgroundAround(Rect norm) {
    final l = (norm.left * w).floor() - 2;
    final r = (norm.right * w).ceil() + 2;
    final t = (norm.top * h).floor() - 2;
    final b = (norm.bottom * h).ceil() + 2;
    final rs = <int>[], gs = <int>[], bs = <int>[];
    void add(int x, int y) {
      final c = _px(x, y);
      rs.add((c.r * 255).round());
      gs.add((c.g * 255).round());
      bs.add((c.b * 255).round());
    }

    final stepX = math.max(1, (r - l) ~/ 24);
    for (var x = l; x <= r; x += stepX) {
      add(x, t);
      add(x, b);
    }
    final stepY = math.max(1, (b - t) ~/ 12);
    for (var y = t; y <= b; y += stepY) {
      add(l, y);
      add(r, y);
    }
    int med(List<int> v) {
      v.sort();
      return v[v.length ~/ 2];
    }

    return Color.fromARGB(255, med(rs), med(gs), med(bs));
  }

  /// The pixel inside [norm] farthest from [bg]: the glyph ink.
  Color? inkWithin(Rect norm, Color bg) {
    final l = (norm.left * w).floor().clamp(0, w - 1);
    final r = (norm.right * w).ceil().clamp(0, w);
    final t = (norm.top * h).floor().clamp(0, h - 1);
    final b = (norm.bottom * h).ceil().clamp(0, h);
    var best = 0.0;
    Color? ink;
    for (var y = t; y < b; y++) {
      for (var x = l; x < r; x++) {
        final c = _px(x, y);
        final dr = c.r - bg.r, dg = c.g - bg.g, db = c.b - bg.b;
        final d = dr * dr + dg * dg + db * db;
        if (d > best) {
          best = d;
          ink = c;
        }
      }
    }
    return best < 0.12 ? null : ink;
  }
}

Future<_PagePixels?> _renderForSampling(PdfPage page) async {
  // ~1 px per point is enough to find a background and the ink colour.
  final scale = 1.0;
  final w = (page.width * scale).round().clamp(64, 2400);
  final h = (page.height * scale).round().clamp(64, 3200);
  final img = await page.render(
    fullWidth: w.toDouble(),
    fullHeight: h.toDouble(),
    backgroundColor: 0xffffffff,
    flags: PdfPageRenderFlags.limitedImageCache,
  );
  if (img == null) return null;
  try {
    return _PagePixels(Uint8List.fromList(img.pixels), img.width, img.height);
  } finally {
    img.dispose();
  }
}
