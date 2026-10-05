import 'package:document_studio/domain/organize/organize_page_ref.dart';

/// Page the viewer should show after the next document reload.
///
/// Page-list edits (insert, delete, reorder) renumber pages. Without this the
/// reload restores the old position and lands on the page *before* the one the
/// user just added.
abstract final class ViewerPendingPage {
  static int? _page;

  static void set(int? page1Based) => _page = page1Based;

  static int? take() {
    final p = _page;
    _page = null;
    return p;
  }
}

/// New number of the page that was [oldPage] before [pages] became the
/// document. Null when that page was removed.
int? remapPageAfterOrganize({
  required List<OrganizePageRef> pages,
  required String sourcePath,
  required int oldPage,
}) {
  for (var i = 0; i < pages.length; i++) {
    final p = pages[i];
    if (p.file.path == sourcePath && p.pageNumber1Based == oldPage) {
      return i + 1;
    }
  }
  return null;
}
