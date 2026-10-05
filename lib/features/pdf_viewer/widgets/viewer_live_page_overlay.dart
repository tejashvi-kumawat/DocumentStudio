import 'dart:math' as math;

import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/features/pdf_markup/header_footer/hf_preview_painter.dart';
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_markup_host.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_overlay_common.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_page_geom.dart';
import 'package:document_studio/features/pdf_viewer/widgets/watermark_preview_painter.dart';
import 'package:document_studio/features/pdf_viewer/widgets/page_crop_quad_math.dart';
import 'package:document_studio/features/pdf_viewer/widgets/page_placement_canvas.dart';
import 'package:document_studio/features/pdf_viewer/widgets/page_placement_math.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

/// Live tool overlays for a single page (widget tests + pdfrx page paint).
///
/// Does not require a [PdfPage] — use [ViewerLiveToolOverlaySurface] in tests.
List<Widget> buildViewerLiveToolOverlays({
  required ViewerLiveToolSession session,
  required Size pageSize,
  required int pageNumber,
  bool showRulers = false,
  double pageWidthPt = 612,
  double pageHeightPt = 792,
  PdfViewerController? controller,
  String? signDocumentPath,
}) {
  final overlays = <Widget>[];
  // Watermark / header & footer / page-number previews: always mounted and
  // driven by the session's preview notifiers, so option and page-scope
  // changes repaint every visible page without rebuilding the viewer.
  if (pageSize.width > 1 && pageSize.height > 1) {
    overlays.add(
      Positioned.fill(
        child: _LiveStampPreviewLayer(
          session: session,
          pageNumber: pageNumber,
          pageWidthPt: pageWidthPt,
          pageHeightPt: pageHeightPt,
        ),
      ),
    );
  }
  // Markup / sign / link / text / form tools: always mounted, self-updating
  // (see LiveMarkupPageHost) so they work on every visible page.
  overlays.add(
    Positioned.fill(
      child: LiveMarkupPageHost(
        session: session,
        controller: controller,
        signDocumentPath: signDocumentPath,
        geom: LivePageGeom(
          pageNumber: pageNumber,
          pagePx: pageSize,
          pageWidthPt: pageWidthPt,
          pageHeightPt: pageHeightPt,
        ),
      ),
    ),
  );
  if (showRulers) {
    overlays.add(
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: _PageRulersPainter(
              pageWidthPt: pageWidthPt,
              pageHeightPt: pageHeightPt,
            ),
          ),
        ),
      ),
    );
  }
  if (!session.isActive) return overlays;
  if (pageNumber != session.pageIndex1Based) return overlays;

  // Never bang on null/zero page geometry — wait until the page rect is known.
  final tool = session.toolId;
  if (tool == null) return overlays;
  if (!(pageSize.width > 1 && pageSize.height > 1)) return overlays;
  switch (tool) {
    case ViewerToolId.redact:
      overlays.add(
        Positioned.fill(
          child: _LiveRedactLayer(
            session: session,
            pageSize: pageSize,
          ),
        ),
      );
    case ViewerToolId.crop:
      overlays.add(
        Positioned.fill(
          child: session.cropMode == LiveCropMode.quad
              ? _LiveCropQuadLayer(
                  session: session,
                  pageSize: pageSize,
                )
              : _LiveCropRectLayer(
                  session: session,
                  tool: tool,
                  pageSize: pageSize,
                ),
        ),
      );
    default:
      break;
  }
  return overlays;
}

/// Renders drag/resize handles and ink on the real [PdfViewer] page (no sidebar canvas).
List<Widget> buildViewerLivePageOverlays({
  required BuildContext context,
  required Rect pageRect,
  required PdfPage page,
  required ViewerLiveToolSession session,
  bool showRulers = false,
  PdfViewerController? controller,
  String? signDocumentPath,
}) {
  return buildViewerLiveToolOverlays(
    session: session,
    pageSize: Size(pageRect.width, pageRect.height),
    pageNumber: page.pageNumber,
    showRulers: showRulers,
    pageWidthPt: page.width,
    pageHeightPt: page.height,
    controller: controller,
    signDocumentPath: signDocumentPath,
  );
}

/// Fixed-size host for [buildViewerLiveToolOverlays] — used by widget tests.
class ViewerLiveToolOverlaySurface extends StatelessWidget {
  const ViewerLiveToolOverlaySurface({
    super.key,
    required this.session,
    this.pageSize = const Size(400, 560),
    this.pageWidthPt = 612,
    this.pageHeightPt = 792,
    this.showRulers = false,
  });

  final ViewerLiveToolSession session;
  final Size pageSize;
  final double pageWidthPt;
  final double pageHeightPt;
  final bool showRulers;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        return SizedBox(
          width: pageSize.width,
          height: pageSize.height,
          child: Stack(
            fit: StackFit.expand,
            children: buildViewerLiveToolOverlays(
              session: session,
              pageSize: pageSize,
              pageNumber: session.pageIndex1Based,
              showRulers: showRulers,
              pageWidthPt: pageWidthPt,
              pageHeightPt: pageHeightPt,
            ),
          ),
        );
      },
    );
  }
}

/// Resize / move / draw cursor for a normalized box under the pointer.
MouseCursor _boxCursor(Iterable<Rect> rectsNorm, Size pageSize, Offset local) {
  final w = math.max(pageSize.width, 1);
  final h = math.max(pageSize.height, 1);
  for (final r in rectsNorm) {
    final box = Rect.fromLTRB(r.left * w, r.top * h, r.right * w, r.bottom * h);
    final handle = hitTestPlacementHandle(boxPx: box, local: local);
    if (handle != null) return cursorForPlacementHandle(handle);
    if (box.contains(local)) return SystemMouseCursors.move;
  }
  return SystemMouseCursors.precise;
}

/// Crop / redact with eight handles, move-inside, dimmed outside (crop only).
class _LiveCropRectLayer extends StatefulWidget {
  const _LiveCropRectLayer({
    required this.session,
    required this.tool,
    required this.pageSize,
  });

  final ViewerLiveToolSession session;
  final ViewerToolId tool;
  final Size pageSize;

  @override
  State<_LiveCropRectLayer> createState() => _LiveCropRectLayerState();
}

class _LiveCropRectLayerState extends State<_LiveCropRectLayer> {
  Rect? _dragBase;
  Offset? _dragStartLocal;
  PlacementHandle? _activeHandle;
  bool _creating = false;
  bool _tickScheduled = false;
  MouseCursor _cursor = SystemMouseCursors.precise;

  ViewerLiveToolSession get session => widget.session;

  void _hover(Offset local) {
    final r = session.dragRectNorm;
    final next = _boxCursor(r == null ? const [] : [r], widget.pageSize, local);
    if (next != _cursor) setState(() => _cursor = next);
  }

  @override
  void initState() {
    super.initState();
    session.addListener(_tick);
  }

  @override
  void dispose() {
    session.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    // Repaint in the same frame while dragging (a post-frame setState made
    // the rectangle trail the pointer by a frame).
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      setState(() {});
      return;
    }
    if (_tickScheduled) return;
    _tickScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tickScheduled = false;
      if (mounted) setState(() {});
    });
  }

  void _begin(Offset local) {
    final w = math.max(widget.pageSize.width, 1);
    final h = math.max(widget.pageSize.height, 1);
    final current = session.dragRectNorm;
    final rect = current ?? Rect.zero;
    final box = Rect.fromLTRB(
      rect.left * w,
      rect.top * h,
      rect.right * w,
      rect.bottom * h,
    );
    final handle = current == null
        ? null
        : hitTestPlacementHandle(boxPx: box, local: local);
    if (handle != null) {
      _dragBase = rect;
      _dragStartLocal = local;
      _activeHandle = handle;
      _creating = false;
      return;
    }
    if (current != null && box.contains(local)) {
      _dragBase = rect;
      _dragStartLocal = local;
      _activeHandle = null;
      _creating = false;
      return;
    }
    // Start a new rect from this point.
    final origin = Offset(
      (local.dx / w).clamp(0.0, 1.0),
      (local.dy / h).clamp(0.0, 1.0),
    );
    _creating = true;
    _dragBase = Rect.fromPoints(origin, origin);
    _dragStartLocal = local;
    _activeHandle = PlacementHandle.bottomRight;
    session.setDragRectNorm(_dragBase, origin: origin);
  }

  void _update(Offset local) {
    final base = _dragBase;
    final start = _dragStartLocal;
    if (base == null || start == null) return;
    final w = math.max(widget.pageSize.width, 1);
    final h = math.max(widget.pageSize.height, 1);
    final dx = (local.dx - start.dx) / w;
    final dy = (local.dy - start.dy) / h;
    if (_creating) {
      final origin = session.dragOriginNorm ?? base.topLeft;
      final end = Offset(
        (local.dx / w).clamp(0.0, 1.0),
        (local.dy / h).clamp(0.0, 1.0),
      );
      var draft = clampNormRect(Rect.fromPoints(origin, end));
      final aspect = widget.tool == ViewerToolId.crop
          ? session.cropAspectNorm
          : null;
      if (aspect != null) {
        draft = applyNormAspectRatio(draft, aspectWidthOverHeight: aspect);
      }
      session.setDragRectNorm(draft);
      return;
    }
    final handle = _activeHandle;
    if (handle == null) {
      session.setDragRectNorm(moveNormRect(base, dx: dx, dy: dy));
    } else {
      final keepAspect = widget.tool == ViewerToolId.crop &&
          session.cropAspectNorm != null;
      session.setDragRectNorm(
        resizeNormRect(
          base,
          handle: handle,
          dx: dx,
          dy: dy,
          keepAspect: keepAspect,
          aspectWidthOverHeight: session.cropAspectNorm,
        ),
      );
    }
  }

  void _end() {
    _dragBase = null;
    _dragStartLocal = null;
    _activeHandle = null;
    _creating = false;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.pageSize.width;
    final h = widget.pageSize.height;
    final rect = session.dragRectNorm;
    final isCrop = widget.tool == ViewerToolId.crop;
    final isRedact = widget.tool == ViewerToolId.redact;

    return MouseRegion(
      cursor: _cursor,
      onHover: (e) => _hover(e.localPosition),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _begin(e.localPosition),
        onPointerMove: (e) => _update(e.localPosition),
        onPointerUp: (e) {
          _end();
          _hover(e.localPosition);
        },
        onPointerCancel: (_) => _end(),
        child: CustomPaint(
          painter: _CropRectPainter(
            rect: rect,
            pageSize: Size(w, h),
            color: isRedact ? Colors.black : DsColors.primary,
            fill: isRedact,
            dimOutside: isCrop,
          ),
          child: rect == null && isCrop
              ? const Align(
                  alignment: Alignment(0, -0.9),
                  child: IgnorePointer(
                    child: LiveHintChip(
                      icon: Icons.crop_rounded,
                      text: 'Drag a rectangle around the area to keep',
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

/// Four-corner crop like a document scanner (drag corners / move interior).
class _LiveCropQuadLayer extends StatefulWidget {
  const _LiveCropQuadLayer({
    required this.session,
    required this.pageSize,
  });

  final ViewerLiveToolSession session;
  final Size pageSize;

  @override
  State<_LiveCropQuadLayer> createState() => _LiveCropQuadLayerState();
}

class _LiveCropQuadLayerState extends State<_LiveCropQuadLayer> {
  PageCropQuadNorm? _dragBase;
  Offset? _dragStartLocal;
  PageCropQuadCorner? _activeCorner;
  bool _moving = false;
  bool _tickScheduled = false;
  MouseCursor _cursor = SystemMouseCursors.basic;

  ViewerLiveToolSession get session => widget.session;

  void _hover(Offset local) {
    final quad = session.cropQuadNorm ?? PageCropQuadNorm.pageInset;
    final corner = hitTestCropQuadCorner(
      quad: quad,
      pageSize: widget.pageSize,
      local: local,
    );
    final b = quad.boundingRect;
    final inside = Rect.fromLTRB(
      b.left * widget.pageSize.width,
      b.top * widget.pageSize.height,
      b.right * widget.pageSize.width,
      b.bottom * widget.pageSize.height,
    ).contains(local);
    final next = corner != null
        ? SystemMouseCursors.grab
        : (inside ? SystemMouseCursors.move : SystemMouseCursors.basic);
    if (next != _cursor) setState(() => _cursor = next);
  }

  @override
  void initState() {
    super.initState();
    session.addListener(_tick);
    if (session.cropQuadNorm == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || session.cropQuadNorm != null) return;
        session.setCropQuadNorm(
          PageCropQuadNorm.fromRect(
            session.dragRectNorm ?? const Rect.fromLTRB(0.08, 0.08, 0.92, 0.92),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    session.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (!mounted || _tickScheduled) return;
    _tickScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tickScheduled = false;
      if (mounted) setState(() {});
    });
  }

  void _begin(Offset local) {
    final quad = session.cropQuadNorm ?? PageCropQuadNorm.pageInset;
    final corner = hitTestCropQuadCorner(
      quad: quad,
      pageSize: widget.pageSize,
      local: local,
    );
    if (corner != null) {
      _dragBase = quad;
      _dragStartLocal = local;
      _activeCorner = corner;
      _moving = false;
      return;
    }
    final box = quad.boundingRect;
    final w = math.max(widget.pageSize.width, 1);
    final h = math.max(widget.pageSize.height, 1);
    final px = Rect.fromLTRB(
      box.left * w,
      box.top * h,
      box.right * w,
      box.bottom * h,
    );
    if (px.contains(local)) {
      _dragBase = quad;
      _dragStartLocal = local;
      _activeCorner = null;
      _moving = true;
    }
  }

  void _update(Offset local) {
    final base = _dragBase;
    final start = _dragStartLocal;
    if (base == null || start == null) return;
    final w = math.max(widget.pageSize.width, 1);
    final h = math.max(widget.pageSize.height, 1);
    final dx = (local.dx - start.dx) / w;
    final dy = (local.dy - start.dy) / h;
    if (_moving) {
      session.setCropQuadNorm(movePageCropQuad(base, dx: dx, dy: dy));
      return;
    }
    final corner = _activeCorner;
    if (corner != null) {
      session.setCropQuadNorm(
        movePageCropQuadCorner(base, corner: corner, dx: dx, dy: dy),
      );
    }
  }

  void _end() {
    _dragBase = null;
    _dragStartLocal = null;
    _activeCorner = null;
    _moving = false;
  }

  @override
  Widget build(BuildContext context) {
    final quad = session.cropQuadNorm ?? PageCropQuadNorm.pageInset;
    return MouseRegion(
      cursor: _cursor,
      onHover: (e) => _hover(e.localPosition),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _begin(e.localPosition),
        onPointerMove: (e) => _update(e.localPosition),
        onPointerUp: (_) => _end(),
        onPointerCancel: (_) => _end(),
        child: CustomPaint(
          painter: _CropQuadPainter(
            quad: quad,
            pageSize: widget.pageSize,
            color: DsColors.primary,
          ),
        ),
      ),
    );
  }
}

class _CropRectPainter extends CustomPainter {
  _CropRectPainter({
    required this.rect,
    required this.pageSize,
    required this.color,
    required this.fill,
    required this.dimOutside,
  });

  final Rect? rect;
  final Size pageSize;
  final Color color;
  final bool fill;
  final bool dimOutside;

  @override
  void paint(Canvas canvas, Size size) {
    final r = rect;
    if (r == null) return;
    final box = Rect.fromLTRB(
      r.left * size.width,
      r.top * size.height,
      r.right * size.width,
      r.bottom * size.height,
    );
    if (dimOutside) {
      final dim = Paint()..color = Colors.black.withValues(alpha: 0.45);
      canvas.drawPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect(Offset.zero & size),
          Path()..addRect(box),
        ),
        dim,
      );
    }
    if (fill) {
      canvas.drawRect(box, Paint()..color = color.withValues(alpha: 0.85));
    }
    canvas.drawRect(
      box,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    const handle = 8.0;
    final handlePaint = Paint()..color = color;
    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final c in [
      box.topLeft,
      box.topRight,
      box.bottomLeft,
      box.bottomRight,
      Offset(box.center.dx, box.top),
      Offset(box.center.dx, box.bottom),
      Offset(box.left, box.center.dy),
      Offset(box.right, box.center.dy),
    ]) {
      final hr = Rect.fromCenter(center: c, width: handle, height: handle);
      canvas.drawRect(hr, handlePaint);
      canvas.drawRect(hr, white);
    }
  }

  @override
  bool shouldRepaint(covariant _CropRectPainter oldDelegate) => true;
}

class _CropQuadPainter extends CustomPainter {
  _CropQuadPainter({
    required this.quad,
    required this.pageSize,
    required this.color,
  });

  final PageCropQuadNorm quad;
  final Size pageSize;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    Offset px(Offset n) => Offset(n.dx * size.width, n.dy * size.height);
    final tl = px(quad.topLeft);
    final tr = px(quad.topRight);
    final br = px(quad.bottomRight);
    final bl = px(quad.bottomLeft);
    final path = Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(bl.dx, bl.dy)
      ..close();
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        path,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    const handle = 10.0;
    final fill = Paint()..color = color;
    final ring = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final c in [tl, tr, br, bl]) {
      canvas.drawCircle(c, handle / 2, fill);
      canvas.drawCircle(c, handle / 2, ring);
    }
  }

  @override
  bool shouldRepaint(covariant _CropQuadPainter oldDelegate) => true;
}

/// Helper used by panels to sync a picked image into the live overlay.
void syncLivePlacementImage(
  ViewerLiveToolSession session, {
  required Uint8List bytes,
  required double aspectWidthOverHeight,
  Offset? centerNorm,
}) {
  session.setImageBytes(bytes);
  session.setPlacement(
    centeredPlacementForAspect(
      imageAspectWidthOverHeight: aspectWidthOverHeight,
      centerNorm: centerNorm ?? session.lastPointerNorm,
    ),
  );
  session.setAwaitingClickPlacement(false);
  session.setKeepAspectRatio(true);
  if (session.toolId == ViewerToolId.placeImage) {
    session.setOpacity(1);
    // Keep existing rotation if replacing; only reset when at default activate.
  }
}

/// Default crop/redact box covering the center of the page.
Rect defaultLiveDragRect() {
  return const Rect.fromLTWH(0.15, 0.2, 0.7, 0.35);
}

double livePageAspectOr(double widthPt, double heightPt) {
  return widthPt / math.max(heightPt, 1);
}

/// Watermark + header/footer preview for one page, painted with the same
/// layout functions the PDF stamp writer uses. Draws nothing on pages outside
/// the preview's page scope; repaints straight from the preview notifiers.
class _LiveStampPreviewLayer extends StatelessWidget {
  const _LiveStampPreviewLayer({
    required this.session,
    required this.pageNumber,
    required this.pageWidthPt,
    required this.pageHeightPt,
  });

  final ViewerLiveToolSession session;
  final int pageNumber;
  final double pageWidthPt;
  final double pageHeightPt;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _StampPreviewPainter(
            session: session,
            pageNumber: pageNumber,
            pageWidthPt: pageWidthPt,
            pageHeightPt: pageHeightPt,
          ),
        ),
      ),
    );
  }
}

class _StampPreviewPainter extends CustomPainter {
  _StampPreviewPainter({
    required this.session,
    required this.pageNumber,
    required this.pageWidthPt,
    required this.pageHeightPt,
  }) : super(repaint: session.stampPreviewListenable);

  final ViewerLiveToolSession session;
  final int pageNumber;
  final double pageWidthPt;
  final double pageHeightPt;

  @override
  void paint(Canvas canvas, Size size) {
    final wm = session.watermarkPreviewNotifier.value;
    if (wm != null && wm.appliesTo(pageNumber)) {
      paintWatermarkMarks(
        canvas,
        size,
        spec: wm.spec,
        pageWidthPt: pageWidthPt,
        pageHeightPt: pageHeightPt,
        text: wm.textFor(pageNumber),
        image: wm.image,
      );
    }
    paintHeaderFooterPreview(
      canvas,
      size,
      state: session.headerFooterPreviewNotifier.value,
      page1Based: pageNumber,
      pageWidthPt: pageWidthPt,
      pageHeightPt: pageHeightPt,
    );
  }

  @override
  bool shouldRepaint(covariant _StampPreviewPainter old) =>
      old.session != session ||
      old.pageNumber != pageNumber ||
      old.pageWidthPt != pageWidthPt ||
      old.pageHeightPt != pageHeightPt;
}

/// Horizontal + vertical rulers in PDF points (does not remount PdfViewer).
class _PageRulersPainter extends CustomPainter {
  _PageRulersPainter({
    required this.pageWidthPt,
    required this.pageHeightPt,
  });

  final double pageWidthPt;
  final double pageHeightPt;

  @override
  void paint(Canvas canvas, Size size) {
    const band = 18.0;
    final bg = Paint()..color = const Color(0xFFF4F4F4);
    final line = Paint()
      ..color = const Color(0xFF888888)
      ..strokeWidth = 1;
    final major = Paint()
      ..color = const Color(0xFF444444)
      ..strokeWidth = 1;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, band), bg);
    canvas.drawRect(Rect.fromLTWH(0, 0, band, size.height), bg);

    final tp = TextPainter(textDirection: TextDirection.ltr);
    final stepX = _niceStep(pageWidthPt / 8);
    for (var pt = 0.0; pt <= pageWidthPt + 0.1; pt += stepX) {
      final x = band + (pt / pageWidthPt) * (size.width - band);
      final isMajor = (pt % (stepX * 2)).abs() < 0.01;
      canvas.drawLine(
        Offset(x, isMajor ? 0 : band * 0.45),
        Offset(x, band),
        isMajor ? major : line,
      );
      if (isMajor) {
        tp.text = TextSpan(
          text: pt.round().toString(),
          style: const TextStyle(fontSize: 9, color: Color(0xFF333333)),
        );
        tp.layout();
        tp.paint(canvas, Offset(x + 2, 2));
      }
    }

    final stepY = _niceStep(pageHeightPt / 8);
    for (var pt = 0.0; pt <= pageHeightPt + 0.1; pt += stepY) {
      final y = band + (pt / pageHeightPt) * (size.height - band);
      final isMajor = (pt % (stepY * 2)).abs() < 0.01;
      canvas.drawLine(
        Offset(isMajor ? 0 : band * 0.45, y),
        Offset(band, y),
        isMajor ? major : line,
      );
      if (isMajor) {
        tp.text = TextSpan(
          text: pt.round().toString(),
          style: const TextStyle(fontSize: 9, color: Color(0xFF333333)),
        );
        tp.layout();
        tp.paint(canvas, Offset(2, y + 2));
      }
    }
  }

  double _niceStep(double rough) {
    if (rough <= 0) return 36;
    final mag = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
    final norm = rough / mag;
    final nice = norm < 1.5 ? 1.0 : (norm < 3.5 ? 2.0 : (norm < 7.5 ? 5.0 : 10.0));
    return nice * mag;
  }

  @override
  bool shouldRepaint(covariant _PageRulersPainter oldDelegate) =>
      oldDelegate.pageWidthPt != pageWidthPt ||
      oldDelegate.pageHeightPt != pageHeightPt;
}

/// Multi-box redact with search-match highlights.
class _LiveRedactLayer extends StatefulWidget {
  const _LiveRedactLayer({
    required this.session,
    required this.pageSize,
  });

  final ViewerLiveToolSession session;
  final Size pageSize;

  @override
  State<_LiveRedactLayer> createState() => _LiveRedactLayerState();
}

class _LiveRedactLayerState extends State<_LiveRedactLayer> {
  Rect? _dragBase;
  Offset? _dragStartLocal;
  PlacementHandle? _activeHandle;
  bool _creating = false;
  bool _tickScheduled = false;
  MouseCursor _cursor = SystemMouseCursors.precise;

  ViewerLiveToolSession get session => widget.session;

  void _hover(Offset local) {
    final next = _boxCursor(session.redactRectsNorm, widget.pageSize, local);
    if (next != _cursor) setState(() => _cursor = next);
  }

  @override
  void initState() {
    super.initState();
    session.addListener(_tick);
  }

  @override
  void dispose() {
    session.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (!mounted || _tickScheduled) return;
    _tickScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tickScheduled = false;
      if (mounted) setState(() {});
    });
  }

  void _begin(Offset local) {
    final w = math.max(widget.pageSize.width, 1);
    final h = math.max(widget.pageSize.height, 1);
    final rects = session.redactRectsNorm;
    for (var i = 0; i < rects.length; i++) {
      final r = rects[i];
      final box = Rect.fromLTRB(r.left * w, r.top * h, r.right * w, r.bottom * h);
      final handle = hitTestPlacementHandle(boxPx: box, local: local);
      if (handle != null || box.contains(local)) {
        session.setActiveRedactIndex(i);
        _dragBase = r;
        _dragStartLocal = local;
        _activeHandle = handle;
        _creating = false;
        return;
      }
    }
    final origin = Offset(
      (local.dx / w).clamp(0.0, 1.0),
      (local.dy / h).clamp(0.0, 1.0),
    );
    _creating = true;
    _dragBase = Rect.fromPoints(origin, origin);
    _dragStartLocal = local;
    _activeHandle = PlacementHandle.bottomRight;
    session.addRedactRect(_dragBase!);
  }

  void _update(Offset local) {
    final base = _dragBase;
    final start = _dragStartLocal;
    if (base == null || start == null) return;
    final w = math.max(widget.pageSize.width, 1);
    final h = math.max(widget.pageSize.height, 1);
    final dx = (local.dx - start.dx) / w;
    final dy = (local.dy - start.dy) / h;
    if (_creating) {
      final origin = base.topLeft;
      final end = Offset(
        (local.dx / w).clamp(0.0, 1.0),
        (local.dy / h).clamp(0.0, 1.0),
      );
      session.setDragRectNorm(clampNormRect(Rect.fromPoints(origin, end)));
      return;
    }
    final handle = _activeHandle;
    if (handle == null) {
      session.setDragRectNorm(moveNormRect(base, dx: dx, dy: dy));
    } else {
      session.setDragRectNorm(
        resizeNormRect(base, handle: handle, dx: dx, dy: dy),
      );
    }
  }

  void _end() {
    _dragBase = null;
    _dragStartLocal = null;
    _activeHandle = null;
    _creating = false;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.pageSize.width;
    final h = widget.pageSize.height;
    return MouseRegion(
      cursor: _cursor,
      onHover: (e) => _hover(e.localPosition),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _begin(e.localPosition),
        onPointerMove: (e) => _update(e.localPosition),
        onPointerUp: (e) {
          _end();
          _hover(e.localPosition);
        },
        onPointerCancel: (_) => _end(),
        child: CustomPaint(
          painter: _RedactMultiPainter(
            rects: session.redactRectsNorm,
            highlights: session.searchHighlightRectsNorm,
            activeIndex: session.activeRedactIndex,
            pageSize: Size(w, h),
          ),
        ),
      ),
    );
  }
}

class _RedactMultiPainter extends CustomPainter {
  _RedactMultiPainter({
    required this.rects,
    required this.highlights,
    required this.activeIndex,
    required this.pageSize,
  });

  final List<Rect> rects;
  final List<Rect> highlights;
  final int activeIndex;
  final Size pageSize;

  @override
  void paint(Canvas canvas, Size size) {
    final hlPaint = Paint()
      ..color = const Color(0xFFF5D76E).withValues(alpha: 0.45);
    for (final r in highlights) {
      canvas.drawRect(
        Rect.fromLTRB(
          r.left * pageSize.width,
          r.top * pageSize.height,
          r.right * pageSize.width,
          r.bottom * pageSize.height,
        ),
        hlPaint,
      );
    }
    for (var i = 0; i < rects.length; i++) {
      final r = rects[i];
      final box = Rect.fromLTRB(
        r.left * pageSize.width,
        r.top * pageSize.height,
        r.right * pageSize.width,
        r.bottom * pageSize.height,
      );
      canvas.drawRect(box, Paint()..color = Colors.black.withValues(alpha: 0.85));
      canvas.drawRect(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = i == activeIndex ? 2 : 1
          ..color = i == activeIndex ? const Color(0xFFE4002B) : Colors.white54,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RedactMultiPainter oldDelegate) =>
      oldDelegate.rects != rects ||
      oldDelegate.highlights != highlights ||
      oldDelegate.activeIndex != activeIndex ||
      oldDelegate.pageSize != pageSize;
}
