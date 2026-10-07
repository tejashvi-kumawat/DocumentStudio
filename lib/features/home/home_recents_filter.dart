import 'package:document_studio/domain/models/local_file_ref.dart';

/// How home recent/favorite rows are ordered after search filter.
enum HomeRecentsSort {
  recentFirst('Recent first'),
  nameAsc('Name A–Z'),
  nameDesc('Name Z–A');

  const HomeRecentsSort(this.label);
  final String label;
}

/// Filters documents by display name or path (case-insensitive substring).
/// Partial [DS-FILE-002] — library-wide filter not implemented.
List<LocalFileRef> filterHomeDocuments(List<LocalFileRef> files, String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) {
    return files;
  }
  final lower = trimmed.toLowerCase();
  return files
      .where(
        (f) =>
            f.displayName.toLowerCase().contains(lower) ||
            f.path.toLowerCase().contains(lower),
      )
      .toList();
}

/// Filters home recents by display name or path (case-insensitive substring).
List<LocalFileRef> filterHomeRecents(
  List<LocalFileRef> recents,
  String query,
) => filterHomeDocuments(recents, query);

List<LocalFileRef> applyHomeRecentsSort(
  List<LocalFileRef> files,
  HomeRecentsSort sort,
) {
  final copy = List<LocalFileRef>.from(files);
  switch (sort) {
    case HomeRecentsSort.recentFirst:
      return copy;
    case HomeRecentsSort.nameAsc:
      copy.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
      return copy;
    case HomeRecentsSort.nameDesc:
      copy.sort(
        (a, b) =>
            b.displayName.toLowerCase().compareTo(a.displayName.toLowerCase()),
      );
      return copy;
  }
}

List<LocalFileRef> filterAndSortHomeDocuments({
  required List<LocalFileRef> files,
  required String query,
  required HomeRecentsSort sort,
}) => applyHomeRecentsSort(filterHomeDocuments(files, query), sort);
