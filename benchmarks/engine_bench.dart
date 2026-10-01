// Engine-only timing for Document Studio's production open.
//
// PdfDocumentCache.acquire() calls PdfDocument.openFile with
// useProgressiveLoading: true and does not load every page unless
// loadAllPages is set. This process makes that same open. It is not a
// Flutter frame and it does not start the app UI.
//
// Usage:
//   dart benchmarks/engine_bench.dart <pdf> [--search]
//
// Prints one JSON object on stdout. Progress goes to stderr.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:pdfrx_engine/pdfrx_engine.dart';

const _longEdgePx = 800.0;

Future<void> main(List<String> args) async {
  final search = args.contains('--search');
  final paths = args.where((a) => !a.startsWith('--')).toList();
  if (paths.length != 1) {
    stderr.writeln('Usage: dart benchmarks/engine_bench.dart <pdf> [--search]');
    exitCode = 64;
    return;
  }
  final path = paths.single;
  final file = File(path);
  if (!file.existsSync()) {
    _emit({'file': path, 'error': 'PDF not found'});
    exitCode = 66;
    return;
  }

  final result = <String, Object?>{
    'file': path,
    'bytes': file.lengthSync(),
    'engine':
        'pdfrx PdfDocument.openFile(useProgressiveLoading: true); loadAllPages false',
  };

  try {
    await pdfrxInitialize();
    result['initNote'] =
        'pdfrxInitialize is outside the open timer (the app initializes pdfrx at startup).';

    stderr.writeln('cold open $path');
    final cold = await _open(path);
    result['coldOpenMs'] = cold.ms;
    result['pages'] = cold.pages;
    result['pagesLoadedAfterColdOpen'] = cold.loaded;
    await cold.document.dispose();

    stderr.writeln('warm open $path');
    final warm = await _open(path);
    result['warmOpenMs'] = warm.ms;
    result['pagesLoadedAfterWarmOpen'] = warm.loaded;
    if (warm.pages != cold.pages) {
      result['pageCountMismatch'] = '${cold.pages} vs ${warm.pages}';
    }

    final doc = warm.document;
    final pageCount = doc.pages.length;

    if (search) {
      stderr.writeln('search income (before extra page renders)');
      final found = await _searchIncome(doc);
      result.addAll(found);
    }

    final renderCount = math.min(6, pageCount);
    if (renderCount == 0) {
      result['renderError'] = 'document has no pages';
    } else {
      stderr.writeln('render page 1 / $pageCount');
      final first = await _renderOne(doc, 1);
      result['firstPageRenderMs'] = first.ms;
      result['firstPagePx'] = '${first.width}x${first.height}';
      result['firstPageNonWhiteSamples'] = first.nonWhite;
      result['firstPageLoadedBeforeRender'] = first.wasLoaded;

      if (renderCount > 1) {
        stderr.writeln('render pages 2-$renderCount');
        final more = Stopwatch()..start();
        final extra = <Map<String, Object?>>[];
        for (var n = 2; n <= renderCount; n++) {
          final one = await _renderOne(doc, n);
          extra.add({
            'page': n,
            'ms': one.ms,
            'px': '${one.width}x${one.height}',
            'nonWhiteSamples': one.nonWhite,
          });
        }
        more.stop();
        result['nextPagesRenderMs'] = more.elapsedMilliseconds;
        result['nextPages'] = extra;
      }
      result['fullRenderRefused'] =
          'Refused to render all $pageCount pages. Only page 1 and ${renderCount - 1} more were rendered (~${_longEdgePx.toInt()} px on the long edge).';
    }

    result['pagesLoadedAfterRender'] =
        doc.pages.where((p) => p.isLoaded).length;

    result['peakRssKb'] = _vmHwmKb();
    await doc.dispose();
    await PdfrxEntryFunctions.instance.stopBackgroundWorker();
  } catch (e, st) {
    result['error'] = e.toString();
    result['stack'] = st.toString().split('\n').take(12).join('\n');
    result['peakRssKb'] = _vmHwmKb();
    exitCode = 1;
  }

  _emit(result);
}

class _Open {
  _Open(this.document, this.ms, this.pages, this.loaded);
  final PdfDocument document;
  final int ms;
  final int pages;
  final int loaded;
}

Future<_Open> _open(String path) async {
  final sw = Stopwatch()..start();
  final doc = await PdfDocument.openFile(
    path,
    useProgressiveLoading: true,
  );
  final pages = doc.pages.length;
  sw.stop();
  final loaded = doc.pages.where((p) => p.isLoaded).length;
  return _Open(doc, sw.elapsedMilliseconds, pages, loaded);
}

class _Render {
  _Render(this.ms, this.width, this.height, this.nonWhite, this.wasLoaded);
  final int ms;
  final int width;
  final int height;
  final int nonWhite;
  final bool wasLoaded;
}

Future<_Render> _renderOne(PdfDocument doc, int pageNumber) async {
  final sw = Stopwatch()..start();
  var page = doc.pages[pageNumber - 1];
  final wasLoaded = page.isLoaded;
  if (!wasLoaded) {
    await doc.reloadPages(pageNumbersToReload: [pageNumber]);
    page = doc.pages[pageNumber - 1];
  }
  final longPt = math.max(page.width, page.height);
  if (longPt <= 0) {
    throw StateError('page $pageNumber has no size');
  }
  final scale = _longEdgePx / longPt;
  final image = await page.render(
    fullWidth: page.width * scale,
    fullHeight: page.height * scale,
    backgroundColor: 0xFFFFFFFF,
  );
  sw.stop();
  if (image == null) {
    throw StateError('page $pageNumber render returned null');
  }
  final nonWhite = _sampleNonWhite(image);
  final width = image.width;
  final height = image.height;
  image.dispose();
  return _Render(sw.elapsedMilliseconds, width, height, nonWhite, wasLoaded);
}

int _sampleNonWhite(PdfImage image) {
  final pixels = image.pixels;
  final stride = math.max(1, pixels.length ~/ (4 * 4000));
  var hits = 0;
  for (var i = 0; i + 3 < pixels.length; i += 4 * stride) {
    final b = pixels[i];
    final g = pixels[i + 1];
    final r = pixels[i + 2];
    if (r < 250 || g < 250 || b < 250) hits++;
  }
  return hits;
}

/// Same loop as pdfrx [PdfTextSearcher]: every page object, then
/// loadStructuredText. loadText returns null unless that page is already
/// loaded, and this open does not load every page.
Future<Map<String, Object?>> _searchIncome(PdfDocument doc) async {
  final pattern = RegExp('income', caseSensitive: false);
  final loadedBefore = doc.pages.where((p) => p.isLoaded).length;
  var iterated = 0;
  var textExtracted = 0;
  var matches = 0;
  final sw = Stopwatch()..start();
  for (final page in doc.pages) {
    iterated++;
    final loaded = page.isLoaded;
    final text = await page.loadStructuredText();
    if (!loaded) continue;
    textExtracted++;
    matches += pattern.allMatches(text.fullText).length;
  }
  sw.stop();
  final loadedAfter = doc.pages.where((p) => p.isLoaded).length;
  return {
    'searchQuery': 'income',
    'searchCaseInsensitive': true,
    'searchMs': sw.elapsedMilliseconds,
    'searchPagesIterated': iterated,
    'searchPagesTextExtracted': textExtracted,
    'searchPagesLoadedBefore': loadedBefore,
    'searchPagesLoadedAfter': loadedAfter,
    'searchMatchCount': matches,
    'searchWalkedEveryPageText': textExtracted == doc.pages.length,
  };
}

void _emit(Map<String, Object?> result) {
  stdout.writeln(jsonEncode(result));
}

int? _vmHwmKb() {
  try {
    for (final line in File('/proc/self/status').readAsLinesSync()) {
      if (line.startsWith('VmHWM:')) {
        return int.tryParse(line.split(RegExp(r'\s+'))[1]);
      }
    }
  } catch (_) {}
  return null;
}
