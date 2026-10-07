import 'dart:math' as math;

import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/domain/compare/compare_models.dart';
import 'package:document_studio/features/compare/compare_controller.dart';
import 'package:document_studio/features/compare/compare_page_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:pdfrx/pdfrx.dart';

const _labelH = 28.0;
const _rowGap = 18.0;
const _listTop = 16.0;
const _listBottom = 96.0;

/// Row geometry of the side-by-side list for a given viewport width & zoom.
///
/// Both pages of an aligned row share one list item, so scrolling and zooming
/// are synchronized by construction; a page missing on one side leaves a
/// placeholder gap of the other page's height so matching pages line up.
class CompareSbsGeometry {
  CompareSbsGeometry(CompareResult r, double viewportWidth, double zoom)
    : compact = viewportWidth < 600,
      pad = viewportWidth < 600 ? 8.0 : 20.0,
      gutter = viewportWidth < 600 ? 10.0 : 28.0 {
    colWidth = math.max(120, (viewportWidth - 2 * pad - gutter) / 2 * zoom);
    var y = _listTop;
    for (final row in r.rows) {
      final pa = row.a == null ? null : r.oldDoc.pages[row.a!];
      final pb = row.b == null ? null : r.newDoc.pages[row.b!];
      double hOf(ComparePageData p) =>
          colWidth * p.heightPt / math.max(1, p.widthPt);
      final ha = pa == null ? 0.0 : hOf(pa);
      final hb = pb == null ? 0.0 : hOf(pb);
      final h = math.max(ha, hb);
      heightsA.add(pa == null ? h : ha);
      heightsB.add(pb == null ? h : hb);
      pageHeights.add(h);
      offsets.add(y);
      y += _labelH + h + _rowGap;
    }
    total = y + _listBottom;
  }

  final bool compact;
  final double pad;
  final double gutter;
  late final double colWidth;
  final heightsA = <double>[];
  final heightsB = <double>[];
  final pageHeights = <double>[];

  /// Scroll offset of each row's top.
  final offsets = <double>[];
  late final double total;

  double get contentWidth => 2 * colWidth + 2 * pad + gutter;

  double extent(int row) => _labelH + pageHeights[row] + _rowGap;

  /// Left edge of a page column inside the content.
  double colX({required bool oldSide}) =>
      oldSide ? pad : pad + colWidth + gutter;

  /// Scroll target placing [c] about a third of the way down the viewport,
  /// and the horizontal position of its first box.
  ({double y, double x, bool oldSide}) targetFor(
    CompareResult r,
    CompareChange c,
    double viewport,
  ) {
    final useOld = c.aRects.isNotEmpty && c.kind != CompareChangeKind.inserted;
    final rects = useOld ? c.aRects : c.bRects;
    if (rects.isEmpty) {
      return (y: offsets[c.row] - viewport * 0.2, x: 0, oldSide: true);
    }
    final page = rects.keys.first;
    final row = (useOld ? r.rowOfA[page] : r.rowOfB[page]) ?? c.row;
    final rect = rects[page]!.first;
    final h = useOld ? heightsA[row] : heightsB[row];
    final within = rect.area > 0.95 ? 0.0 : rect.t * h;
    return (
      y: offsets[row] + _labelH + within - viewport * 0.3,
      x: colX(oldSide: useOld) + rect.l * colWidth,
      oldSide: useOld,
    );
  }

  /// Row whose band contains [offset].
  int rowAt(double offset) {
    if (offsets.isEmpty) return 0;
    var lo = 0;
    var hi = offsets.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (offsets[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}

class CompareSideBySide extends StatelessWidget {
  const CompareSideBySide({
    super.key,
    required this.controller,
    required this.geometry,
    required this.scroll,
    required this.hScroll,
    required this.flash,
  });

  final CompareController controller;
  final CompareSbsGeometry geometry;
  final ScrollController scroll;
  final ScrollController hScroll;
  final Animation<double> flash;

  @override
  Widget build(BuildContext context) {
    final r = controller.result!;
    final list = Scrollbar(
      controller: scroll,
      child: ListView.builder(
        controller: scroll,
        padding: const EdgeInsets.only(top: _listTop, bottom: _listBottom),
        scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
        itemCount: r.rows.length,
        itemExtentBuilder: (i, _) =>
            i < r.rows.length ? geometry.extent(i) : null,
        itemBuilder: (context, i) => _Row(
          row: i,
          pair: r.rows[i],
          result: r,
          geometry: geometry,
          controller: controller,
          flash: flash,
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, c) {
        if (geometry.contentWidth <= c.maxWidth + 0.5) return list;
        return Scrollbar(
          controller: hScroll,
          thumbVisibility: true,
          notificationPredicate: (n) => n.depth == 0,
          child: SingleChildScrollView(
            controller: hScroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: geometry.contentWidth, child: list),
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.row,
    required this.pair,
    required this.result,
    required this.geometry,
    required this.controller,
    required this.flash,
  });

  final int row;
  final ComparePagePair pair;
  final CompareResult result;
  final CompareSbsGeometry geometry;
  final CompareController controller;
  final Animation<double> flash;

  @override
  Widget build(BuildContext context) {
    final changes = controller.changesOnRow(row);
    final w = geometry.colWidth;
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);
    final labelStyle = theme.textTheme.labelMedium?.copyWith(color: secondary);
    String label(int? page, bool old) {
      if (page == null) return old ? 'Not in original' : 'Not in revised';
      return '${old ? 'Original' : 'Revised'} · page ${page + 1}';
    }

    final count = changes.length;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: geometry.pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: _labelH,
            child: Row(
              children: [
                SizedBox(
                  width: w,
                  child: Text(
                    label(pair.a, true),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle,
                  ),
                ),
                SizedBox(
                  width: geometry.gutter,
                  child: count == 0 || geometry.gutter < 20
                      ? null
                      : Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            decoration: BoxDecoration(
                              color: DsColors.textPrimary(theme.brightness)
                                  .withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$count',
                              style: TextStyle(
                                color: DsColors.groupedCell(theme.brightness),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                ),
                SizedBox(
                  width: w,
                  child: Text(
                    label(pair.b, false),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle,
                  ),
                ),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PageCell(
                doc: controller.oldPdf,
                page: pair.a,
                otherPage: pair.b,
                movedTo: pair.b == null && pair.a != null
                    ? result.movedAtoB[pair.a]
                    : null,
                movedFrom: null,
                gapMovedCounterpart: pair.a == null && pair.b != null
                    ? result.movedBtoA[pair.b]
                    : null,
                width: w,
                height: geometry.heightsA[row],
                oldSide: true,
                changes: changes,
                selectedId: controller.selectedId,
                flash: flash,
              ),
              SizedBox(width: geometry.gutter),
              _PageCell(
                doc: controller.newPdf,
                page: pair.b,
                otherPage: pair.a,
                movedTo: null,
                movedFrom: pair.a == null && pair.b != null
                    ? result.movedBtoA[pair.b]
                    : null,
                gapMovedCounterpart: pair.b == null && pair.a != null
                    ? result.movedAtoB[pair.a]
                    : null,
                width: w,
                height: geometry.heightsB[row],
                oldSide: false,
                changes: changes,
                selectedId: controller.selectedId,
                flash: flash,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PageCell extends StatelessWidget {
  const _PageCell({
    required this.doc,
    required this.page,
    required this.otherPage,
    required this.movedTo,
    required this.movedFrom,
    required this.gapMovedCounterpart,
    required this.width,
    required this.height,
    required this.oldSide,
    required this.changes,
    required this.selectedId,
    required this.flash,
  });

  final PdfDocument? doc;
  final int? page;
  final int? otherPage;

  /// For an old page shown opposite a gap: its new position, if it moved.
  final int? movedTo;

  /// For a new page shown opposite a gap: its old position, if it moved.
  final int? movedFrom;

  /// When this cell is a gap opposite a moved page: that page's position in
  /// this cell's document.
  final int? gapMovedCounterpart;
  final double width;
  final double height;
  final bool oldSide;
  final List<CompareChange> changes;
  final int? selectedId;
  final Animation<double> flash;

  @override
  Widget build(BuildContext context) {
    final p = page;
    final brightness = Theme.of(context).brightness;
    if (p == null || doc == null) {
      return _Gap(
        width: width,
        height: height,
        oldSide: oldSide,
        otherPage: otherPage,
        movedCounterpart: gapMovedCounterpart,
        brightness: brightness,
      );
    }
    final moveNote = movedTo != null
        ? 'Moved to revised page ${movedTo! + 1}'
        : movedFrom != null
        ? 'Moved from original page ${movedFrom! + 1}'
        : null;
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: DsSpacing.cardShadowLight(opacity: 0.14),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: PdfPageView(
                key: ValueKey('${oldSide ? 'a' : 'b'}-$p'),
                document: doc,
                pageNumber: p + 1,
                maximumDpi: 220,
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                painter: CompareHighlightPainter(
                  changes: changes,
                  page: p,
                  oldSide: oldSide,
                  selectedId: selectedId,
                  flash: flash,
                ),
              ),
            ),
            if (moveNote != null)
              Positioned(
                left: 8,
                top: 8,
                right: 8,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: _Badge(text: moveNote, color: compareChangedColor),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Gap extends StatelessWidget {
  const _Gap({
    required this.width,
    required this.height,
    required this.oldSide,
    required this.otherPage,
    required this.movedCounterpart,
    required this.brightness,
  });

  final double width;
  final double height;
  final bool oldSide;
  final int? otherPage;
  final int? movedCounterpart;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    // A gap on the original side means the page was inserted, and vice versa.
    final moved = movedCounterpart;
    final color = moved != null
        ? compareChangedColor
        : oldSide
        ? compareInsertColor
        : compareDeleteColor;
    final title = moved != null
        ? 'Moved page'
        : oldSide
        ? 'Inserted page'
        : 'Deleted page';
    final other = otherPage;
    final subtitle = moved != null
        ? (oldSide
              ? 'Was original page ${moved + 1}'
              : 'Now revised page ${moved + 1}')
        : other == null
        ? null
        : oldSide
        ? 'Revised page ${other + 1} has no match in the original'
        : 'Original page ${other + 1} was removed';
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: brightness == Brightness.dark ? 0.08 : 0.05,
        ),
        borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.2),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(DsSpacing.sm),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: math.max(80, width - 16)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    moved != null
                        ? Icons.swap_vert_rounded
                        : oldSide
                        ? Icons.note_add_outlined
                        : Icons.delete_outline,
                    color: color,
                    size: 28,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: color, fontWeight: FontWeight.w600),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: DsColors.textSecondary(brightness),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
