import 'dart:math' as math;
import 'dart:ui';

import 'package:document_studio/domain/models/local_file_ref.dart';
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
    doc = await PdfDocument.openFile(
      file.path,
      passwordProvider: password == null ? null : () async => password,
    );
    if (doc.pages.isEmpty) return null;
    final page = doc.pages[(page1Based - 1).clamp(0, doc.pages.length - 1)];
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
        for (final f in text.fragments) {
          final t = f.text.trim();
          if (t.isEmpty) continue;
          final n = _norm(f.bounds, page);
          if (n.width < 0.002 || n.height < 0.002) continue;
          runs.add(_runTarget(f.text.trimRight(), n, size));
        }
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
