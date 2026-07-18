import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:document_studio/features/pdf_viewer/pdf_approach_pages.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Decodes the page under the viewport, plus one ahead and one behind.
///
/// pdfrx paints a missing page as a white rectangle. On a drawing set whose
/// first sheet is blank white, that rectangle is indistinguishable from page
/// 1, so a fast scroll looked like every sheet was page 1. This cache never
/// stores one page's bitmap under another page's number. A page with no
/// pixels yet is painted as a quiet page number.
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
  bool sync({
    required bool moving,
    required double devicePixelRatio,
  }) {
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
      final wanted = _wantedScale(
        page,
        inViewport: window.visiblePages.contains(pageNumber),
      );
      final held = _held[pageNumber];
      if (held != null && held.scale + 0.02 >= wanted) {
        _cancelJob(pageNumber);
        continue;
      }
      final job = _jobs[pageNumber];
      if (job != null && (job.scale - wanted).abs() < 0.02) continue;
      if (job != null) _cancelJob(pageNumber);
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
      final wanted = _wantedScale(page, inViewport: _visible.contains(pageNumber));
      final held = _held[pageNumber];
      if (held != null && held.scale + 0.02 >= wanted) continue;
      final token = page.createCancellationToken();
      final job = _DecodeJob(scale: wanted, token: token);
      _jobs[pageNumber] = job;
      _running++;
      unawaited(_run(page, pageNumber, job));
    }
  }

  Future<void> _run(PdfPage page, int pageNumber, _DecodeJob job) async {
    PdfImage? rendered;
    var landedScale = 0.0;
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
      if (_disposed || job.token.isCanceled || !identical(_jobs[pageNumber], job)) {
        image.dispose();
        return;
      }
      if (page.pageNumber != pageNumber) {
        image.dispose();
        return;
      }
      _held.remove(pageNumber)?.image.dispose();
      _held[pageNumber] = _HeldBitmap(image, job.scale);
      landedScale = job.scale;
      _notify();
    } catch (_) {
      // A failed decode stays a page-number placeholder.
    } finally {
      rendered?.dispose();
      if (identical(_jobs[pageNumber], job)) _jobs.remove(pageNumber);
      if (landedScale > 0 && !_disposed) {
        _queueUpgrade(page, pageNumber, landedScale);
      }
      _running = math.max(0, _running - 1);
      if (!_disposed) _pump();
    }
  }

  double _scaleFor(PdfPage page, bool inViewport) {
    return pdfApproachScaleFor(
      moving: _moving,
      inViewport: inViewport,
      pageWidth: page.width,
      pageHeight: page.height,
      zoom: _zoom > 0 ? _zoom : 1,
      devicePixelRatio: _dpr,
    );
  }

  /// First pixels are the 400px preview so a sheet appears before the
  /// screen-resolution pass. A page that already has a bitmap keeps the
  /// sharper target.
  double _wantedScale(PdfPage page, {required bool inViewport}) {
    final target = _scaleFor(page, inViewport);
    if (_held[page.pageNumber] != null) return target;
    final preview = _scaleFor(page, false);
    return math.min(target, preview);
  }

  void _queueUpgrade(PdfPage page, int pageNumber, double landedScale) {
    if (_moving || !_visible.contains(pageNumber)) return;
    if (page.pageNumber != pageNumber) return;
    final settled = _scaleFor(page, true);
    if (landedScale + 0.02 >= settled) return;
    if (_jobs.containsKey(pageNumber)) return;
    if (_waiting.contains(pageNumber)) return;
    _waiting = [pageNumber, ..._waiting];
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
    return Object.hash(
      layouts.length,
      rect.width.round(),
      rect.height.round(),
    );
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

  /// Quiet sheet with this page's number. Not white, and not any bitmap.
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
    final fontSize = (rect.shortestSide * 0.08).clamp(14.0, 42.0);
    final painter = TextPainter(
      text: TextSpan(
        text: '$pageNumber',
        style: TextStyle(
          color: const Color(0xFF64748B),
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: rect.width);
    painter.paint(
      canvas,
      rect.center - Offset(painter.width / 2, painter.height / 2),
    );
    painter.dispose();
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
