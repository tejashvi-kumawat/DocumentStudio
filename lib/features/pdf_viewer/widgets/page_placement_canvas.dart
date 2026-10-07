import 'dart:math' as math;

import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/domain/pdf_stamp/pdf_page_stamp_models.dart';
import 'package:document_studio/features/pdf_viewer/widgets/page_placement_math.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

/// Normalized placement on a page preview (top-left origin, 0–1).
class PagePlacementNorm {
  const PagePlacementNorm({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  Rect get rect => Rect.fromLTWH(left, top, width, height);

  PagePlacementNorm copyWith({
    double? left,
    double? top,
    double? width,
    double? height,
  }) {
    return PagePlacementNorm(
      left: left ?? this.left,
      top: top ?? this.top,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  /// Converts to PDF user-space stamp rect (bottom-left origin).
  PdfStampRect toPdfStampRect({
    required double pageWidthPt,
    required double pageHeightPt,
  }) {
    final x = left * pageWidthPt;
    final w = width * pageWidthPt;
    final h = height * pageHeightPt;
    final y = (1 - top - height) * pageHeightPt;
    return PdfStampRect(xPt: x, yPt: y, widthPt: w, heightPt: h);
  }

  /// Text baseline near bottom-left of the box (PDF space).
  ({double xPt, double yPt}) toPdfTextAnchor({
    required double pageWidthPt,
    required double pageHeightPt,
    double fontSizePt = 28,
  }) {
    final x = left * pageWidthPt;
    final y = (1 - top - height) * pageHeightPt + fontSizePt * 0.2;
    return (xPt: x, yPt: y);
  }
}

/// Page preview with a draggable / resizable overlay (image or text).
class PagePlacementCanvas extends StatefulWidget {
  const PagePlacementCanvas({
    super.key,
    required this.document,
    required this.pageIndex0Based,
    required this.pageWidthPt,
    required this.pageHeightPt,
    required this.placement,
    required this.onPlacementChanged,
    this.imageBytes,
    this.labelText,
    this.enabled = true,
  });

  final PdfDocument document;
  final int pageIndex0Based;
  final double pageWidthPt;
  final double pageHeightPt;
  final PagePlacementNorm placement;
  final ValueChanged<PagePlacementNorm> onPlacementChanged;
  final Uint8List? imageBytes;
  final String? labelText;
  final bool enabled;

  @override
  State<PagePlacementCanvas> createState() => _PagePlacementCanvasState();
}

class _PagePlacementCanvasState extends State<PagePlacementCanvas> {
  PagePlacementNorm? _dragBase;
  Offset? _dragStartLocal;
  PlacementHandle? _activeHandle;

  void _begin(Offset local, {PlacementHandle? handle}) {
    _dragBase = widget.placement;
    _dragStartLocal = local;
    _activeHandle = handle;
  }

  void _update(Offset local, Size pageSize) {
    final base = _dragBase;
    final start = _dragStartLocal;
    if (base == null || start == null) return;
    final dx = (local.dx - start.dx) / pageSize.width;
    final dy = (local.dy - start.dy) / pageSize.height;
    final handle = _activeHandle;
    if (handle == null) {
      widget.onPlacementChanged(movePagePlacement(base, dx: dx, dy: dy));
    } else {
      final aspect = base.height > 1e-9 ? base.width / base.height : 1.0;
      widget.onPlacementChanged(
        resizePagePlacement(
          base,
          handle: handle,
          dx: dx,
          dy: dy,
          keepAspect: !HardwareKeyboard.instance.isShiftPressed,
          aspectWidthOverHeight: aspect,
        ),
      );
    }
  }

  void _end() {
    _dragBase = null;
    _dragStartLocal = null;
    _activeHandle = null;
  }

  @override
  Widget build(BuildContext context) {
    final page =
        widget.document.pages[widget.pageIndex0Based.clamp(
          0,
          widget.document.pages.length - 1,
        )];
    return AspectRatio(
      aspectRatio: widget.pageWidthPt / widget.pageHeightPt,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final pageSize = Size(w, h);
          final p = widget.placement;
          final box = Rect.fromLTWH(
            p.left * w,
            p.top * h,
            p.width * w,
            p.height * h,
          );
          return ColoredBox(
            color: const Color(0xFFF4F4F4),
            child: Stack(
              fit: StackFit.expand,
              children: [
                PdfPageView(
                  document: widget.document,
                  pageNumber: page.pageNumber,
                ),
                if (widget.enabled)
                  Positioned.fill(
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (e) {
                        final handle = hitTestPlacementHandle(
                          boxPx: box,
                          local: e.localPosition,
                        );
                        if (handle != null || box.contains(e.localPosition)) {
                          _begin(e.localPosition, handle: handle);
                        }
                      },
                      onPointerMove: (e) => _update(e.localPosition, pageSize),
                      onPointerUp: (_) => _end(),
                      onPointerCancel: (_) => _end(),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned.fromRect(
                            rect: box,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: DsColors.primary,
                                  width: 1.5,
                                ),
                                color: Colors.white.withValues(alpha: 0.15),
                              ),
                              child: Stack(
                                children: [
                                  if (widget.imageBytes != null)
                                    Positioned.fill(
                                      child: Image.memory(
                                        widget.imageBytes!,
                                        fit: BoxFit.fill,
                                      ),
                                    )
                                  else if (widget.labelText != null &&
                                      widget.labelText!.trim().isNotEmpty)
                                    Center(
                                      child: Text(
                                        widget.labelText!,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF1A1A1A),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Pastes image bytes from the clipboard when available (desktop).
Future<Uint8List?> readClipboardImageBytes() async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  if (data?.text != null && data!.text!.isNotEmpty) {
    return null;
  }
  return null;
}

/// Converts a pixel aspect (width/height) to normalized page units, where
/// 1.0 horizontally is [pageWidthPt] and 1.0 vertically is [pageHeightPt].
double normAspectForPixelAspect(
  double imageAspectWidthOverHeight, {
  double pageWidthPt = 612,
  double pageHeightPt = 792,
}) {
  final pw = pageWidthPt > 1 ? pageWidthPt : 612.0;
  final ph = pageHeightPt > 1 ? pageHeightPt : 792.0;
  return math.max(imageAspectWidthOverHeight, 0.01) * ph / pw;
}

/// Fits a box of normalized aspect [normAspect] inside [maxW] x [maxH].
({double w, double h}) _fitNormAspect(
  double normAspect, {
  required double maxW,
  required double maxH,
}) {
  var w = maxW;
  var h = w / normAspect;
  if (h > maxH) {
    h = maxH;
    w = h * normAspect;
  }
  return (w: w, h: h);
}

PagePlacementNorm defaultPlacementForAspect({
  required double imageAspectWidthOverHeight,
  double maxWidthFraction = 0.35,
  double pageWidthPt = 612,
  double pageHeightPt = 792,
}) {
  final a = normAspectForPixelAspect(
    imageAspectWidthOverHeight,
    pageWidthPt: pageWidthPt,
    pageHeightPt: pageHeightPt,
  );
  final s = _fitNormAspect(a, maxW: maxWidthFraction, maxH: 0.45);
  return clampPagePlacement(
    PagePlacementNorm(
      left: 1 - s.w - 0.06,
      top: 1 - s.h - 0.06,
      width: s.w,
      height: s.h,
    ),
    minFraction: 0.005,
  );
}

/// Centers an aspect-correct box on the page (Acrobat Add Image default).
PagePlacementNorm centeredPlacementForAspect({
  required double imageAspectWidthOverHeight,
  double maxWidthFraction = 0.32,
  Offset? centerNorm,
  double pageWidthPt = 612,
  double pageHeightPt = 792,
}) {
  final a = normAspectForPixelAspect(
    imageAspectWidthOverHeight,
    pageWidthPt: pageWidthPt,
    pageHeightPt: pageHeightPt,
  );
  final s = _fitNormAspect(a, maxW: maxWidthFraction, maxH: 0.45);
  final w = s.w;
  final h = s.h;
  final cx = (centerNorm?.dx ?? 0.5).clamp(0.0, 1.0);
  final cy = (centerNorm?.dy ?? 0.5).clamp(0.0, 1.0);
  return clampPagePlacement(
    PagePlacementNorm(left: cx - w / 2, top: cy - h / 2, width: w, height: h),
    minFraction: 0.005,
  );
}
