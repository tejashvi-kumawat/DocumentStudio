import 'dart:math' as math;

import 'package:document_studio/domain/pdf_markup/header_footer/hf_layout.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_spec.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_tokens.dart';
import 'package:document_studio/features/pdf_markup/stamp_preview_text.dart';
import 'package:flutter/material.dart';

/// Live header/footer preview shared by the editor, the viewer page overlays
/// and the template gallery.
class HeaderFooterPreviewState {
  HeaderFooterPreviewState({
    required this.spec,
    required this.doc,
    this.visible = true,
    this.showGuides = false,
    this.focusZone,
  }) : _bates = hfBatesValues(spec, doc.pageCount);

  final HeaderFooterSpec spec;
  final HfDocInfo doc;
  final bool visible;

  /// Dashed margin guides (editing aid, never written to the PDF).
  final bool showGuides;

  /// Zone to outline (editing aid, never written to the PDF).
  final HfZone? focusZone;
  final List<int> _bates;

  bool appliesTo(int page1Based) =>
      visible && hfAppliesToPage(spec, page1Based, doc.pageCount);

  HfPageLayout layoutFor(int page1Based, double widthPt, double heightPt) {
    if (!visible) return HfPageLayout.empty;
    return layoutHeaderFooterPage(
      spec: spec,
      doc: doc,
      page1Based: page1Based,
      pageWidthPt: widthPt,
      pageHeightPt: heightPt,
      batesValue: page1Based < _bates.length ? _bates[page1Based] : null,
    );
  }
}

TextStyle hfPreviewTextStyle(HfFont font, double sizePx, Color color) =>
    stampPreviewTextStyle(font, sizePx, color);

Color hfColor(int rgb, [double opacity = 1]) =>
    Color(0xFF000000 | rgb).withValues(alpha: opacity.clamp(0.0, 1.0));

/// Paints [layout] on a page-sized canvas (points scaled to [size]).
void paintHeaderFooterLayout(
  Canvas canvas,
  Size size, {
  required HfPageLayout layout,
  required double pageWidthPt,
  HeaderFooterSpec? guidesFor,
  double pageHeightPt = 0,
  HfZone? focusZone,
}) {
  if (!(size.width > 1 && size.height > 1)) return;
  final scale = size.width / math.max(pageWidthPt, 1);
  canvas.save();
  canvas.clipRect(Offset.zero & size);
  final spec = guidesFor;
  if (spec != null) _paintGuides(canvas, size, spec, scale);
  for (final r in layout.rects) {
    canvas.drawRect(
      Rect.fromLTWH(
        r.leftPt * scale,
        r.topPt * scale,
        r.widthPt * scale,
        math.max(r.heightPt * scale, 0.6),
      ),
      Paint()..color = hfColor(r.colorRgb, r.opacity),
    );
  }
  for (final t in layout.texts) {
    final tp = stampTextPainter(t.text, t.font, t.sizePt * scale, hfColor(t.colorRgb));
    paintStampTextRun(
      canvas,
      tp,
      startXPx: t.xPt * scale,
      baselineYPx: t.baselinePt * scale,
      targetWidthPx: t.widthPt * scale,
    );
    tp.dispose();
  }
  if (focusZone != null) _paintFocus(canvas, scale, layout, focusZone);
  canvas.restore();
}

void _paintGuides(
  Canvas canvas,
  Size size,
  HeaderFooterSpec spec,
  double scale,
) {
  final m = spec.margins;
  final guide = Paint()
    ..color = const Color(0xFFE4002B).withValues(alpha: 0.3)
    ..strokeWidth = 1;
  void dashed(Offset a, Offset b) {
    const dash = 4.0;
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    for (var d = 0.0; d < total; d += dash * 2) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, total), guide);
    }
  }

  final top = m.top * scale;
  final bottom = size.height - m.bottom * scale;
  final left = m.left * scale;
  final right = size.width - m.right * scale;
  dashed(Offset(0, top), Offset(size.width, top));
  dashed(Offset(0, bottom), Offset(size.width, bottom));
  dashed(Offset(left, 0), Offset(left, size.height));
  dashed(Offset(right, 0), Offset(right, size.height));
}

void _paintFocus(
  Canvas canvas,
  double scale,
  HfPageLayout layout,
  HfZone focus,
) {
  Rect? box;
  for (final t in layout.texts) {
    if (t.zone != focus) continue;
    final r = Rect.fromLTRB(
      t.xPt * scale,
      t.topPt * scale,
      (t.xPt + t.widthPt) * scale,
      t.bottomPt * scale,
    );
    box = box == null ? r : box.expandToInclude(r);
  }
  if (box == null) return;
  final rr = RRect.fromRectAndRadius(box.inflate(3), const Radius.circular(3));
  canvas.drawRRect(
    rr,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF0A84FF).withValues(alpha: 0.7),
  );
}

/// Paints [state] for one page (viewer overlays, thumbnails, previews).
class HeaderFooterPreviewPainter extends CustomPainter {
  HeaderFooterPreviewPainter({
    required this.state,
    required this.page1Based,
    required this.pageWidthPt,
    required this.pageHeightPt,
    this.showGuides,
    super.repaint,
  });

  final HeaderFooterPreviewState? state;
  final int page1Based;
  final double pageWidthPt;
  final double pageHeightPt;
  final bool? showGuides;

  @override
  void paint(Canvas canvas, Size size) {
    paintHeaderFooterPreview(
      canvas,
      size,
      state: state,
      page1Based: page1Based,
      pageWidthPt: pageWidthPt,
      pageHeightPt: pageHeightPt,
      showGuides: showGuides,
    );
  }

  @override
  bool shouldRepaint(covariant HeaderFooterPreviewPainter old) =>
      old.state != state ||
      old.page1Based != page1Based ||
      old.pageWidthPt != pageWidthPt ||
      old.pageHeightPt != pageHeightPt ||
      old.showGuides != showGuides;
}

void paintHeaderFooterPreview(
  Canvas canvas,
  Size size, {
  required HeaderFooterPreviewState? state,
  required int page1Based,
  required double pageWidthPt,
  required double pageHeightPt,
  bool? showGuides,
}) {
  final s = state;
  if (s == null || !s.appliesTo(page1Based)) return;
  final layout = s.layoutFor(page1Based, pageWidthPt, pageHeightPt);
  paintHeaderFooterLayout(
    canvas,
    size,
    layout: layout,
    pageWidthPt: pageWidthPt,
    pageHeightPt: pageHeightPt,
    guidesFor: (showGuides ?? s.showGuides) ? s.spec : null,
    focusZone: s.focusZone,
  );
}

/// Sample document info for template thumbnails.
const hfSampleDocInfo = HfDocInfo(
  fileName: 'Quarterly-Report.pdf',
  pageCount: 12,
  title: 'Quarterly Report',
  author: 'A. Author',
  subject: 'Finance',
);
