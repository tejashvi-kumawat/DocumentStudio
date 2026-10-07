import 'dart:math' as math;

import 'package:document_studio/domain/pdf_markup/header_footer/hf_font_metrics.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_spec.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_tokens.dart';

/// One laid-out line of text. Coordinates are points in the page's *visual*
/// space (after `/Rotate`), top-left origin.
class HfTextMark {
  const HfTextMark({
    required this.zone,
    required this.text,
    required this.font,
    required this.sizePt,
    required this.colorRgb,
    required this.xPt,
    required this.baselinePt,
    required this.widthPt,
  });

  final HfZone zone;

  /// Sanitized (WinAnsi-safe) text.
  final String text;
  final HfFont font;
  final double sizePt;
  final int colorRgb;

  /// Baseline start.
  final double xPt;
  final double baselinePt;
  final double widthPt;

  double get topPt => baselinePt - hfAscentEm * sizePt;
  double get bottomPt => baselinePt + hfDescentEm * sizePt;
}

/// Filled rectangle (rules and bands), top-left origin, points.
class HfRectMark {
  const HfRectMark({
    required this.leftPt,
    required this.topPt,
    required this.widthPt,
    required this.heightPt,
    required this.colorRgb,
    this.opacity = 1,
  });

  final double leftPt;
  final double topPt;
  final double widthPt;
  final double heightPt;
  final int colorRgb;
  final double opacity;
}

class HfPageLayout {
  const HfPageLayout({this.texts = const [], this.rects = const []});

  static const empty = HfPageLayout();

  final List<HfTextMark> texts;
  final List<HfRectMark> rects;

  bool get isEmpty => texts.isEmpty && rects.isEmpty;
}

/// Parses "1-3, 5, 8-" style ranges (1-based, clamped to [pageCount]).
/// Returns null when the expression is invalid.
Set<int>? parseHfPageRange(String input, int pageCount) {
  final pages = <int>{};
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  for (final raw in trimmed.split(RegExp(r'[,;\s]+'))) {
    final part = raw.trim();
    if (part.isEmpty) continue;
    final m = RegExp(r'^(\d*)\s*-\s*(\d*)$').firstMatch(part);
    if (m != null) {
      final a = m.group(1)!.isEmpty ? 1 : int.parse(m.group(1)!);
      final b = m.group(2)!.isEmpty ? pageCount : int.parse(m.group(2)!);
      if (a < 1 || b < a) return null;
      for (var p = a; p <= math.min(b, pageCount); p++) {
        pages.add(p);
      }
    } else {
      final n = int.tryParse(part);
      if (n == null || n < 1) return null;
      if (n <= pageCount) pages.add(n);
    }
  }
  return pages;
}

/// Whether [page1Based] receives the header/footer.
bool hfAppliesToPage(HeaderFooterSpec spec, int page1Based, int pageCount) {
  if (page1Based < 1 || page1Based > pageCount) return false;
  if (spec.skipFirstPage && page1Based == 1) return false;
  switch (spec.range) {
    case HfPageRange.all:
      return true;
    case HfPageRange.odd:
      return page1Based.isOdd;
    case HfPageRange.even:
      return page1Based.isEven;
    case HfPageRange.custom:
      return parseHfPageRange(
            spec.customRange,
            pageCount,
          )?.contains(page1Based) ??
          false;
  }
}

/// Precomputes the Bates counter of every stamped page (counts only pages
/// that receive the header/footer, like Acrobat).
List<int> hfBatesValues(HeaderFooterSpec spec, int pageCount) {
  final values = List<int>.filled(pageCount + 1, 0);
  var next = spec.bates.start;
  Set<int>? custom;
  if (spec.range == HfPageRange.custom) {
    custom = parseHfPageRange(spec.customRange, pageCount) ?? const {};
  }
  for (var p = 1; p <= pageCount; p++) {
    final applies =
        !(spec.skipFirstPage && p == 1) &&
        switch (spec.range) {
          HfPageRange.all => true,
          HfPageRange.odd => p.isOdd,
          HfPageRange.even => p.isEven,
          HfPageRange.custom => custom!.contains(p),
        };
    if (applies) values[p] = next++;
  }
  return values;
}

/// Human readable validation issues for the whole spec.
List<String> validateHeaderFooterSpec(HeaderFooterSpec spec, int pageCount) {
  final issues = <String>[];
  if (!spec.hasContent) issues.add('Add text to at least one zone');
  for (final z in HfZone.values) {
    for (final i in validateHfTemplate(spec.zone(z).text)) {
      issues.add('${z.label}: $i');
    }
  }
  if (spec.range == HfPageRange.custom &&
      parseHfPageRange(spec.customRange, pageCount) == null) {
    issues.add('Enter a valid page range (e.g. 1-3, 5, 8-)');
  }
  if (spec.startNumber < 0) issues.add('Start number must be 0 or more');
  return issues;
}

/// Single source of truth for header/footer geometry — used by the live
/// preview painter and by the PDF overlay writer so both agree exactly.
///
/// [batesValue] is the page's Bates counter (see [hfBatesValues]).
HfPageLayout layoutHeaderFooterPage({
  required HeaderFooterSpec spec,
  required HfDocInfo doc,
  required int page1Based,
  required double pageWidthPt,
  required double pageHeightPt,
  int? batesValue,
}) {
  if (!hfAppliesToPage(spec, page1Based, doc.pageCount)) {
    return HfPageLayout.empty;
  }
  final w = math.max(pageWidthPt, 1.0);
  final h = math.max(pageHeightPt, 1.0);
  final m = spec.margins;
  final ctx = HfPageContext(
    page1Based: page1Based,
    batesValue: batesValue ?? spec.bates.start + page1Based - 1,
  );
  final mirror = spec.mirrorOnEvenPages && page1Based.isEven;

  final texts = <HfTextMark>[];
  var headerBottom = double.negativeInfinity;
  var footerTop = double.infinity;

  for (final zone in HfZone.values) {
    final style = spec.zone(zone);
    if (style.isEmpty) continue;
    final placed = mirror ? zone.mirrored : zone;
    final size = style.sizePt.clamp(4.0, 72.0).toDouble();
    final resolved = resolveHfTemplate(
      style.text,
      spec: spec,
      doc: doc,
      page: ctx,
    );
    final lines = [
      for (final l in resolved.split('\n')) hfSanitize(l.trimRight()),
    ];
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    if (lines.isEmpty) continue;
    final lineH = size * hfLineHeightEm;
    final n = lines.length;
    for (var i = 0; i < n; i++) {
      final text = lines[i];
      if (text.trim().isEmpty) continue;
      final width = hfTextWidthPt(text, style.font, size);
      final x = switch (placed.align) {
        HfAlign.left => m.left,
        HfAlign.center => m.left + (w - m.left - m.right - width) / 2,
        HfAlign.right => w - m.right - width,
      };
      // Header blocks grow downward from the top margin; footer blocks grow
      // upward from the bottom margin.
      final baseline = zone.isHeader
          ? m.top + hfAscentEm * size + i * lineH
          : h - m.bottom - hfDescentEm * size - (n - 1 - i) * lineH;
      final mark = HfTextMark(
        zone: placed,
        text: text,
        font: style.font,
        sizePt: size,
        colorRgb: style.colorRgb,
        xPt: x,
        baselinePt: baseline,
        widthPt: width,
      );
      texts.add(mark);
      if (zone.isHeader) {
        headerBottom = math.max(headerBottom, mark.bottomPt);
      } else {
        footerTop = math.min(footerTop, mark.topPt);
      }
    }
  }

  final rects = <HfRectMark>[];
  const pad = 6.0;
  final hd = spec.header;
  final fd = spec.footer;
  final hasHeader = headerBottom.isFinite;
  final hasFooter = footerTop.isFinite;
  final band = hd.bandRgb;
  if (band != null) {
    final bottom = hasHeader ? headerBottom + pad : m.top * 1.5;
    rects.add(
      HfRectMark(
        leftPt: 0,
        topPt: 0,
        widthPt: w,
        heightPt: bottom.clamp(0.0, h / 2),
        colorRgb: band,
        opacity: hd.bandOpacity,
      ),
    );
  }
  final fBand = fd.bandRgb;
  if (fBand != null) {
    final top = hasFooter ? footerTop - pad : h - m.bottom * 1.5;
    final t = top.clamp(h / 2, h);
    rects.add(
      HfRectMark(
        leftPt: 0,
        topPt: t,
        widthPt: w,
        heightPt: h - t,
        colorRgb: fBand,
        opacity: fd.bandOpacity,
      ),
    );
  }
  final ruleSpan = math.max(0.0, w - m.left - m.right);
  if (hd.ruleEnabled && hasHeader) {
    rects.add(
      HfRectMark(
        leftPt: m.left,
        topPt: headerBottom + pad * 0.5,
        widthPt: ruleSpan,
        heightPt: hd.ruleWidthPt.clamp(0.25, 6.0),
        colorRgb: hd.ruleRgb,
      ),
    );
  }
  if (fd.ruleEnabled && hasFooter) {
    final t = fd.ruleWidthPt.clamp(0.25, 6.0);
    rects.add(
      HfRectMark(
        leftPt: m.left,
        topPt: footerTop - pad * 0.5 - t,
        widthPt: ruleSpan,
        heightPt: t,
        colorRgb: fd.ruleRgb,
      ),
    );
  }
  return HfPageLayout(texts: texts, rects: rects);
}
