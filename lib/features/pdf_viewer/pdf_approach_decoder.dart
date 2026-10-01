import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:document_studio/features/pdf_viewer/pdf_approach_pages.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_params_config.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Decodes the page under the viewport, plus one ahead and one behind.
///
/// pdfrx paints a missing page as a white rectangle. On a drawing set whose
/// first sheet is blank white, that rectangle is indistinguishable from page
/// 1, so a fast scroll looked like every sheet was page 1. This cache never
/// stores one page's bitmap under another page's number. A page with no
/// pixels yet is a flat fill of that page's size. The only bitmap ever decoded
/// or painted is the screen scale (zoom × device pixel ratio, long edge capped
/// at [kPdfSettledRenderLongEdgePx]). Until that bitmap exists the page stays
/// blank. Zooming out keeps a sharper bitmap. A zoom-in that would make the
/// current bitmap soft keeps it up until the new screen-scale bitmap arrives.
class PdfApproachDecoder extends ChangeNotifier {
  PdfViewerController? _controller;
  final Map<int, _HeldBitmap> _held = {};
  final Map<int, _DecodeJob> _jobs = {};
  List<int> _waiting = const [];
  int _running = 0;
  bool _disposed = false;
  bool _notifyScheduled = false;
  Set<int> _visible = const {};
  Set<int> _decode = const {};
  int _layoutMark = 0;
  bool _moving = false;
  double _zoom = 0;
  double _dpr = 1;

  static final Map<PdfViewerController, PdfApproachDecoder> _attached = {};

  static PdfApproachDecoder? lookup(PdfViewerController controller) =>
      _attached[controller];

  /// True while a page decode owns the PDFium worker. Thumbnails wait.
  bool get blocksThumbnails => _running > 0;

  int get runningDecodes => _running;

  /// Bitmap rendered from this page, or null. Never another page's image.
  ui.Image? imageFor(int pageNumber) => _held[pageNumber]?.image;

  void attach(PdfViewerController controller) {
    final previous = _controller;
    if (identical(previous, controller)) {
      _attached[controller] = this;
      return;
    }
    if (previous != null) detach(previous);
    _clearSlots();
    _controller = controller;
    _attached[controller] = this;
    _visible = const {};
    _decode = const {};
    _layoutMark = 0;
  }

  void detach(PdfViewerController controller) {
    if (_attached[controller] == this) _attached.remove(controller);
    if (!identical(_controller, controller)) return;
    _cancelAll();
    _clearSlots();
    _controller = null;
  }

  /// False when the viewer has no layout yet, so the caller can retry.
  bool sync({required bool moving, required double devicePixelRatio}) {
    final controller = _controller;
    if (_disposed || controller == null || !controller.isReady) return false;
    final PdfPageLayout layout;
    final Rect visible;
    try {
      layout = controller.layout;
      visible = controller.visibleRect;
    } catch (_) {
      return false;
    }
    final layouts = layout.pageLayouts;
    if (layouts.isEmpty) return controller.pageCount == 0;
    final window = pdfApproachPageWindow(layouts: layouts, visible: visible);
    final dpr = devicePixelRatio > 0 ? devicePixelRatio : 1.0;
    final zoom = controller.currentZoom;
    final mark = _layoutMarkOf(layouts, window.visiblePages);
    if (_sameWindow(window, moving, zoom, dpr, mark)) return true;
    _visible = window.visiblePages;
    _decode = window.decodePages;
    _layoutMark = mark;
    _moving = moving;
    _zoom = zoom;
    _dpr = dpr;

    final pages = controller.pages;
    for (final pageNumber in _jobs.keys.toList()) {
      if (!window.decodePages.contains(pageNumber)) _cancelJob(pageNumber);
    }
    var dropped = false;
    for (final pageNumber in _held.keys.toList()) {
      if (window.decodePages.contains(pageNumber)) continue;
      _held.remove(pageNumber)?.image.dispose();
      dropped = true;
    }

    final order = pdfApproachDecodeOrder(
      visiblePages: window.visiblePages,
      decodePages: window.decodePages,
      currentPage: controller.pageNumber,
    );
    final waiting = <int>[];
    for (final pageNumber in order) {
      if (pageNumber < 1 || pageNumber > pages.length) continue;
      final page = pages[pageNumber - 1];
      if (page.pageNumber != pageNumber) continue;
      final target = _screenScale(page);
      final held = _held[pageNumber];
      if (held != null &&
          pdfViewerKeepsRenderedScale(held: held.scale, target: target)) {
        _cancelJob(pageNumber);
        continue;
      }
      if (_jobCovers(pageNumber, target)) continue;
      if (_jobs.containsKey(pageNumber)) _cancelJob(pageNumber);
      waiting.add(pageNumber);
    }
    _waiting = waiting;
    _pump();
    if (dropped) _notify();
    return true;
  }

  void _pump() {
    final controller = _controller;
    if (_disposed || controller == null || !controller.isReady) return;
    while (_running < kPdfApproachMaxDecodes && _waiting.isNotEmpty) {
      final pageNumber = _waiting.removeAt(0);
      if (_jobs.containsKey(pageNumber)) continue;
      if (pageNumber < 1 || pageNumber > controller.pages.length) continue;
      final page = controller.pages[pageNumber - 1];
      if (page.pageNumber != pageNumber) continue;
      final target = _screenScale(page);
      final held = _held[pageNumber];
      if (held != null &&
          pdfViewerKeepsRenderedScale(held: held.scale, target: target)) {
        continue;
      }
      if (_jobCovers(pageNumber, target)) continue;
      final token = page.createCancellationToken();
      final job = _DecodeJob(scale: target, token: token);
      _jobs[pageNumber] = job;
      _running++;
      unawaited(_run(page, pageNumber, job));
    }
  }

  Future<void> _run(PdfPage page, int pageNumber, _DecodeJob job) async {
    PdfImage? rendered;
    var retryFull = false;
    try {
      final width = page.width * job.scale;
      final height = page.height * job.scale;
      if (width < 1 || height < 1 || page.pageNumber != pageNumber) return;
      rendered = await page.render(
        fullWidth: width,
        fullHeight: height,
        backgroundColor: 0xffffffff,
        flags: PdfPageRenderFlags.limitedImageCache,
        cancellationToken: job.token,
      );
      if (rendered == null || _disposed || job.token.isCanceled) return;
      if (!identical(_jobs[pageNumber], job)) return;
      if (!_decode.contains(pageNumber)) return;
      final image = await rendered.createImage();
      if (_disposed ||
          job.token.isCanceled ||
          !identical(_jobs[pageNumber], job)) {
        image.dispose();
        return;
      }
      if (page.pageNumber != pageNumber) {
        image.dispose();
        return;
      }
      final screen = _screenScale(page);
      // A decode below the screen target is never shown. The page stays blank,
      // or keeps the sharper bitmap already on screen, until a full one arrives.
      if (job.scale + 0.02 < screen) {
        image.dispose();
        retryFull = true;
        return;
      }
      final existing = _held[pageNumber];
      if (existing != null && existing.scale > job.scale + 0.02) {
        image.dispose();
        return;
      }
      _held.remove(pageNumber)?.image.dispose();
      _held[pageNumber] = _HeldBitmap(image, job.scale);
      _notify();
    } catch (_) {
      // A failed decode stays a flat fill until the next request.
    } finally {
      rendered?.dispose();
      if (identical(_jobs[pageNumber], job)) _jobs.remove(pageNumber);
      _running = math.max(0, _running - 1);
      if (retryFull && !_disposed) _retryFull(page, pageNumber);
      if (!_disposed) _pump();
    }
  }

  /// The only scale a new decode may use.
  double _screenScale(PdfPage page) {
    return pdfApproachScaleFor(
      moving: _moving,
      inViewport: _visible.contains(page.pageNumber),
      pageWidth: page.width,
      pageHeight: page.height,
      zoom: _zoom > 0 ? _zoom : 1,
      devicePixelRatio: _dpr,
    );
  }

  void _retryFull(PdfPage page, int pageNumber) {
    if (page.pageNumber != pageNumber || !_decode.contains(pageNumber)) return;
    if (_jobs.containsKey(pageNumber) || _waiting.contains(pageNumber)) return;
    final target = _screenScale(page);
    final held = _held[pageNumber]?.scale;
    if (held != null &&
        pdfViewerKeepsRenderedScale(held: held, target: target)) {
      return;
    }
    _waiting = [pageNumber, ..._waiting];
  }

  /// True when a decode already running is at [wanted] or sharper.
  bool _jobCovers(int pageNumber, double wanted) {
    final job = _jobs[pageNumber];
    if (job == null) return false;
    if ((job.scale - wanted).abs() < 0.02) return true;
    return job.scale + 0.02 >= wanted;
  }

  bool _sameWindow(
    ({Set<int> visiblePages, Set<int> decodePages}) window,
    bool moving,
    double zoom,
    double dpr,
    int layoutMark,
  ) {
    return moving == _moving &&
        layoutMark == _layoutMark &&
        (zoom - _zoom).abs() < 0.01 &&
        (dpr - _dpr).abs() < 0.01 &&
        _setSame(_visible, window.visiblePages) &&
        _setSame(_decode, window.decodePages);
  }

  int _layoutMarkOf(List<Rect> layouts, Set<int> visiblePages) {
    if (layouts.isEmpty || visiblePages.isEmpty) return layouts.length;
    final rect = layouts[visiblePages.reduce(math.min) - 1];
    return Object.hash(layouts.length, rect.width.round(), rect.height.round());
  }

  bool _setSame(Set<int> a, Set<int> b) {
    if (identical(a, b) || a.length != b.length) return identical(a, b);
    for (final value in a) {
      if (!b.contains(value)) return false;
    }
    return true;
  }

  void _cancelJob(int pageNumber) {
    final job = _jobs.remove(pageNumber);
    job?.token.cancel();
    _waiting = [
      for (final page in _waiting)
        if (page != pageNumber) page,
    ];
  }

  void _cancelAll() {
    for (final job in _jobs.values) {
      job.token.cancel();
    }
    _jobs.clear();
    _waiting = const [];
  }

  void _clearSlots() {
    for (final held in _held.values) {
      held.image.dispose();
    }
    _held.clear();
  }

  void _notify() {
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  /// This page's own pixels, or a flat fill of [rect] until they exist.
  ///
  /// No page number. Never another page's bitmap.
  void paintStandIn(ui.Canvas canvas, Rect rect, int pageNumber) {
    final image = imageFor(pageNumber);
    if (image != null) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        rect,
        Paint()..filterQuality = FilterQuality.medium,
      );
      return;
    }
    canvas.drawRect(rect, Paint()..color = const Color(0xFFE8EEF4));
  }

  @override
  void dispose() {
    _disposed = true;
    final controller = _controller;
    if (controller != null) detach(controller);
    _cancelAll();
    _clearSlots();
    super.dispose();
  }
}

class _HeldBitmap {
  _HeldBitmap(this.image, this.scale);

  final ui.Image image;
  final double scale;
}

class _DecodeJob {
  _DecodeJob({required this.scale, required this.token});

  final double scale;
  final PdfPageRenderCancellationToken token;
}
