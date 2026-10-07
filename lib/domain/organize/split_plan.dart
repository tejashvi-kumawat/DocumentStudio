/// Inclusive 1-based page ranges for split / extract planning.
class PageRange {
  const PageRange(this.start1Based, this.end1Based, {this.explicitPages1Based});

  final int start1Based;
  final int end1Based;

  /// When set, output uses these pages in order (may be non-contiguous).
  final List<int>? explicitPages1Based;

  factory PageRange.fromExplicitPages(List<int> pages1Based) {
    final sorted = [...pages1Based]..sort();
    if (sorted.isEmpty) return const PageRange(1, 0);
    return PageRange(sorted.first, sorted.last, explicitPages1Based: sorted);
  }

  int get pageCount {
    if (explicitPages1Based != null) return explicitPages1Based!.length;
    return end1Based >= start1Based ? end1Based - start1Based + 1 : 0;
  }

  List<int> toPageNumbers1Based() {
    if (explicitPages1Based != null) {
      return List<int>.from(explicitPages1Based!);
    }
    return [for (var p = start1Based; p <= end1Based; p++) p];
  }

  String label() {
    if (explicitPages1Based != null) {
      final pages = explicitPages1Based!;
      if (pages.length <= 4) return pages.join(', ');
      return '${pages.first}…${pages.last} (${pages.length} pg)';
    }
    return start1Based == end1Based
        ? '$start1Based'
        : '$start1Based–$end1Based';
  }

  PageRange clampToDocument(int totalPages) {
    if (totalPages < 1) return const PageRange(1, 0);
    if (explicitPages1Based != null) {
      final clamped = [
        for (final p in explicitPages1Based!)
          if (p >= 1 && p <= totalPages) p,
      ];
      if (clamped.isEmpty) return const PageRange(1, 0);
      return PageRange.fromExplicitPages(clamped);
    }
    final s = start1Based.clamp(1, totalPages);
    final e = end1Based.clamp(s, totalPages);
    return PageRange(s, e);
  }
}

enum SplitMethodKind { everyN, singlePages, customRanges, selectedPages }

/// How selected-page split results are grouped into output files.
enum SelectedPagesOutputKind {
  /// One PDF containing all selected pages (in document order).
  singleExtract,

  /// One PDF per contiguous run within the selection.
  contiguousRanges,
}

/// Builds output part ranges from split settings (preview before execution).
List<PageRange> buildSplitPlan({
  required int totalPages,
  required SplitMethodKind method,
  int pagesPerFile = 1,
  int? everyN,
  List<PageRange> customRanges = const [],
  Set<int> selectedPages1Based = const {},
  SelectedPagesOutputKind selectedPagesOutput =
      SelectedPagesOutputKind.singleExtract,
}) {
  if (totalPages < 1) return const [];

  switch (method) {
    case SplitMethodKind.everyN:
      final n = (everyN ?? pagesPerFile).clamp(1, totalPages);
      final parts = <PageRange>[];
      for (var start = 1; start <= totalPages; start += n) {
        final end = (start + n - 1).clamp(1, totalPages);
        parts.add(PageRange(start, end));
      }
      return parts;
    case SplitMethodKind.singlePages:
      return [for (var p = 1; p <= totalPages; p++) PageRange(p, p)];
    case SplitMethodKind.customRanges:
      if (customRanges.isEmpty) {
        return [PageRange(1, totalPages)];
      }
      return [for (final r in customRanges) r.clampToDocument(totalPages)]
          .where((r) => r.pageCount > 0)
          .toList();
    case SplitMethodKind.selectedPages:
      return _planFromSelectedPages(
        totalPages: totalPages,
        selected: selectedPages1Based,
        output: selectedPagesOutput,
      );
  }
}

List<PageRange> _planFromSelectedPages({
  required int totalPages,
  required Set<int> selected,
  required SelectedPagesOutputKind output,
}) {
  final pages = selected.where((p) => p >= 1 && p <= totalPages).toList()
    ..sort();
  if (pages.isEmpty) return [];

  switch (output) {
    case SelectedPagesOutputKind.singleExtract:
      final contiguous =
          pages.last - pages.first + 1 == pages.length && pages.isNotEmpty;
      if (contiguous) {
        return [PageRange(pages.first, pages.last)];
      }
      return [PageRange.fromExplicitPages(pages)];
    case SelectedPagesOutputKind.contiguousRanges:
      return _contiguousRangesFromSortedPages(pages);
  }
}

List<PageRange> _contiguousRangesFromSortedPages(List<int> sorted) {
  if (sorted.isEmpty) return const [];
  final ranges = <PageRange>[];
  var start = sorted.first;
  var end = sorted.first;
  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i] == end + 1) {
      end = sorted[i];
    } else {
      ranges.add(PageRange(start, end));
      start = end = sorted[i];
    }
  }
  ranges.add(PageRange(start, end));
  return ranges;
}
