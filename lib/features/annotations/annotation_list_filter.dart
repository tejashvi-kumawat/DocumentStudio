import 'package:document_studio/features/annotations/annotation_port.dart';

/// Category filter for [AnnotationListPanel] (DS-ANN-006).
enum AnnotationKindFilter {
  all,
  markup,
  notes,
  ink,
  stamps,
  links,
}

/// Search + kind filter applied to loaded annotations.
class AnnotationListFilterState {
  const AnnotationListFilterState({
    this.query = '',
    this.kindFilter = AnnotationKindFilter.all,
  });

  final String query;
  final AnnotationKindFilter kindFilter;

  AnnotationListFilterState copyWith({
    String? query,
    AnnotationKindFilter? kindFilter,
  }) {
    return AnnotationListFilterState(
      query: query ?? this.query,
      kindFilter: kindFilter ?? this.kindFilter,
    );
  }
}

/// Returns [items] matching [state] (case-insensitive search on label, author, page).
List<PdfMarkupAnnotation> filterAnnotationList(
  List<PdfMarkupAnnotation> items,
  AnnotationListFilterState state,
) {
  final trimmed = state.query.trim().toLowerCase();
  return items.where((item) {
    if (!_matchesKindFilter(item.kind, state.kindFilter)) {
      return false;
    }
    if (trimmed.isEmpty) return true;
    final haystack = [
      item.displayLabel,
      item.author,
      item.contents,
      item.subject,
      'page ${item.pageNumber}',
      item.pageNumber.toString(),
      _kindSearchTokens(item.kind),
    ].whereType<String>().join(' ').toLowerCase();
    return haystack.contains(trimmed);
  }).toList(growable: false);
}

bool _matchesKindFilter(PdfAnnotationKind kind, AnnotationKindFilter filter) {
  return switch (filter) {
    AnnotationKindFilter.all => true,
    AnnotationKindFilter.markup =>
      kind == PdfAnnotationKind.highlight ||
          kind == PdfAnnotationKind.underline ||
          kind == PdfAnnotationKind.strikeOut ||
          kind == PdfAnnotationKind.squiggly,
    AnnotationKindFilter.notes =>
      kind == PdfAnnotationKind.comment ||
          kind == PdfAnnotationKind.text ||
          kind == PdfAnnotationKind.freeText,
    AnnotationKindFilter.ink => kind == PdfAnnotationKind.ink,
    AnnotationKindFilter.stamps => kind == PdfAnnotationKind.stamp,
    AnnotationKindFilter.links =>
      kind == PdfAnnotationKind.uriLink ||
          kind == PdfAnnotationKind.destinationLink,
  };
}

String _kindSearchTokens(PdfAnnotationKind kind) => switch (kind) {
      PdfAnnotationKind.highlight => 'highlight markup',
      PdfAnnotationKind.underline => 'underline markup',
      PdfAnnotationKind.strikeOut => 'strike markup',
      PdfAnnotationKind.squiggly => 'squiggly markup',
      PdfAnnotationKind.text => 'text note',
      PdfAnnotationKind.freeText => 'text box note',
      PdfAnnotationKind.ink => 'ink draw pen',
      PdfAnnotationKind.stamp => 'stamp',
      PdfAnnotationKind.comment => 'comment sticky note',
      PdfAnnotationKind.uriLink => 'link web uri',
      PdfAnnotationKind.destinationLink => 'link internal destination',
      PdfAnnotationKind.unknown => 'annotation',
    };

String annotationKindFilterLabel(AnnotationKindFilter filter) => switch (filter) {
      AnnotationKindFilter.all => 'All types',
      AnnotationKindFilter.markup => 'Text markup',
      AnnotationKindFilter.notes => 'Notes & text',
      AnnotationKindFilter.ink => 'Ink',
      AnnotationKindFilter.stamps => 'Stamps',
      AnnotationKindFilter.links => 'Links',
    };
