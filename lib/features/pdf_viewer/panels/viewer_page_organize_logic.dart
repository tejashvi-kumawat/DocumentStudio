import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/organize/organize_page_ref.dart';

/// All pages of [file] in document order (1-based page numbers).
List<OrganizePageRef> buildDocumentPageList(LocalFileRef file, int totalPages) {
  return [
    for (var n = 1; n <= totalPages; n++) OrganizePageRef.fromFilePage(file, n),
  ];
}

/// Pages to save for extract (selection only).
List<OrganizePageRef> pagesForExtract(
  LocalFileRef file,
  Set<int> selectedPages1Based,
) {
  final sorted = selectedPages1Based.toList()..sort();
  return [for (final n in sorted) OrganizePageRef.fromFilePage(file, n)];
}

/// Remaining pages after removing [deletePages1Based].
List<OrganizePageRef> pagesForDelete(
  LocalFileRef file,
  int totalPages,
  Set<int> deletePages1Based,
) {
  return [
    for (var n = 1; n <= totalPages; n++)
      if (!deletePages1Based.contains(n)) OrganizePageRef.fromFilePage(file, n),
  ];
}

/// Duplicate each page in [duplicatePages1Based] immediately after itself.
List<OrganizePageRef> pagesForDuplicate(
  LocalFileRef file,
  int totalPages,
  Set<int> duplicatePages1Based,
) {
  final list = <OrganizePageRef>[];
  for (var n = 1; n <= totalPages; n++) {
    final ref = OrganizePageRef.fromFilePage(file, n);
    list.add(ref);
    if (duplicatePages1Based.contains(n)) {
      list.add(OrganizePageRef.fromFilePage(file, n));
    }
  }
  return list;
}

/// Reorder pages after a thumbnail drag (0-based indices, insert-before semantics).
List<OrganizePageRef> pagesForReorder(
  LocalFileRef file,
  int totalPages,
  int fromIndex0,
  int toIndex0,
) {
  final order = [for (var i = 1; i <= totalPages; i++) i];
  if (fromIndex0 < 0 ||
      fromIndex0 >= order.length ||
      toIndex0 < 0 ||
      toIndex0 > order.length) {
    return buildDocumentPageList(file, totalPages);
  }
  final page = order.removeAt(fromIndex0);
  var insertAt = toIndex0;
  if (insertAt > fromIndex0) insertAt -= 1;
  order.insert(insertAt.clamp(0, order.length), page);
  return [for (final n in order) OrganizePageRef.fromFilePage(file, n)];
}

/// Replace [slots1Based] with pages from [source], in order.
///
/// Slots the source does not cover are dropped. Source pages past the last
/// slot are inserted immediately after that slot.
List<OrganizePageRef> pagesForReplaceFromFile({
  required LocalFileRef file,
  required int totalPages,
  required List<int> slots1Based,
  required LocalFileRef source,
  required int sourceCount,
}) {
  final slots = slots1Based.where((n) => n >= 1 && n <= totalPages).toSet();
  final list = <OrganizePageRef>[];
  var src = 1;
  var lastReplaced = -1;
  for (var n = 1; n <= totalPages; n++) {
    if (slots.contains(n)) {
      if (src <= sourceCount) {
        list.add(OrganizePageRef.fromFilePage(source, src));
        src++;
        lastReplaced = list.length - 1;
      }
    } else {
      list.add(OrganizePageRef.fromFilePage(file, n));
    }
  }
  if (src <= sourceCount) {
    final extras = <OrganizePageRef>[
      for (; src <= sourceCount; src++)
        OrganizePageRef.fromFilePage(source, src),
    ];
    final at = lastReplaced < 0 ? list.length : lastReplaced + 1;
    list.insertAll(at, extras);
  }
  return list;
}

/// Insert [insertFile] pages after [afterPage1Based] in document order.
List<OrganizePageRef> pagesForInsertAfterPage({
  required LocalFileRef file,
  required int totalPages,
  required int afterPage1Based,
  required LocalFileRef insertFile,
  required int insertPageCount,
}) {
  final list = <OrganizePageRef>[];
  for (var n = 1; n <= totalPages; n++) {
    list.add(OrganizePageRef.fromFilePage(file, n));
    if (n == afterPage1Based) {
      for (var p = 1; p <= insertPageCount; p++) {
        list.add(OrganizePageRef.fromFilePage(insertFile, p));
      }
    }
  }
  return list;
}

/// Reverse full document order.
List<OrganizePageRef> pagesForReverse(LocalFileRef file, int totalPages) {
  return [
    for (var n = totalPages; n >= 1; n--) OrganizePageRef.fromFilePage(file, n),
  ];
}

int normalizeRotationDegrees(int degrees) => ((degrees % 360) + 360) % 360;

/// Apply [deltaDegrees] to pages in [rotatePages1Based]; others unchanged.
List<OrganizePageRef> pagesForRotate(
  LocalFileRef file,
  int totalPages,
  Set<int> rotatePages1Based,
  int deltaDegrees,
) {
  return [
    for (var n = 1; n <= totalPages; n++)
      OrganizePageRef.fromFilePage(file, n).copyWith(
        rotationDegrees: rotatePages1Based.contains(n)
            ? normalizeRotationDegrees(deltaDegrees)
            : 0,
      ),
  ];
}

/// Insert [blank] after each page index in [afterPages1Based] (document order).
List<OrganizePageRef> pagesForBlankInsertAfter(
  LocalFileRef file,
  int totalPages,
  Set<int> afterPages1Based,
  LocalFileRef blank,
) {
  if (afterPages1Based.isEmpty) {
    return [
      ...buildDocumentPageList(file, totalPages),
      OrganizePageRef.fromFilePage(blank, 1),
    ];
  }
  final list = <OrganizePageRef>[];
  for (var n = 1; n <= totalPages; n++) {
    list.add(OrganizePageRef.fromFilePage(file, n));
    if (afterPages1Based.contains(n)) {
      list.add(OrganizePageRef.fromFilePage(blank, 1));
    }
  }
  return list;
}
