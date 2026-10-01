import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/organize/organize_page_ref.dart';
import 'package:document_studio/infrastructure/pdf/pdf_page_box_options.dart';

/// Crop vs MediaBox resize for the shared qpdf page-box tool UI.
enum PageBoxQpdfToolMode { crop, resize }

/// Selected source page numbers (1-based) for qpdf crop/resize.
Set<int> pageBoxSelectedSourcePages1Based({
  required List<OrganizePageRef> pages,
  required Set<String> selectedIds,
}) {
  return {
    for (final p in pages)
      if (selectedIds.contains(p.id)) p.pageNumber1Based,
  };
}

/// Whether Apply is enabled for crop/resize (engine ready + pages + crop margin).
bool pageBoxQpdfCanApply({
  required PageBoxQpdfToolMode mode,
  required bool engineSupported,
  required bool busy,
  required int pageCount,
  required Set<int> selectedPages1Based,
  required PdfCropMarginPreset cropMargin,
}) {
  if (!engineSupported || busy || pageCount < 1) return false;
  if (selectedPages1Based.isEmpty) return false;
  if (mode == PageBoxQpdfToolMode.crop &&
      cropMargin == PdfCropMarginPreset.none) {
    return false;
  }
  return true;
}

String pageBoxQpdfExportPreviewSubtitle({
  required PageBoxQpdfToolMode mode,
  required int selectedCount,
  required LocalFileRef file,
  required PdfCropMarginPreset cropMargin,
  required PdfPaperSize paperSize,
}) {
  if (mode == PageBoxQpdfToolMode.crop) {
    return '$selectedCount page(s) · ${cropMargin.label} · ${file.displayName}';
  }
  return '$selectedCount page(s) · ${paperSize.name.toUpperCase()} · '
      '${file.displayName}';
}

String pageBoxQpdfExportPreviewFootnote(PageBoxQpdfToolMode mode) {
  if (mode == PageBoxQpdfToolMode.crop) {
    return 'Trims CropBox on selected pages. Hidden content is not deleted.';
  }
  return 'Sets MediaBox on selected pages. Content is not scaled to fit.';
}
