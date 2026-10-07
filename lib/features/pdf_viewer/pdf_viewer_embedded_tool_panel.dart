import 'package:document_studio/features/pdf_viewer/panels/viewer_edit_text_panel.dart';
import 'package:document_studio/features/annotations/markup/markup_tool_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_compress_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_organize_pages_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_accessibility_tags_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_batch_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_blocked_tool_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_compare_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_crop_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_searchable_pdf_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_export_images_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_fill_form_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_headers_footers_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_page_numbers_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_watermark_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_insert_pages_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_move_between_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_replace_pages_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_insert_scan_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_ocr_image_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_office_convert_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_protect_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_redact_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_unlock_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_resize_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_reverse_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_scoped_page_organize_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_merge_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_split_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_visual_sign_panel.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_embed.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio/features/security/metadata_editor_screen.dart';
import 'package:document_studio/features/security/remove_metadata_screen.dart';
import 'package:document_studio/features/security/security_route.dart';
import 'package:document_studio/infrastructure/conversion/pdf_to_images_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Right-side embedded tool form for the open viewer tab (T6).
class PdfViewerEmbeddedToolPanel extends ConsumerWidget {
  const PdfViewerEmbeddedToolPanel({
    super.key,
    required this.toolId,
    required this.handoff,
    required this.onClose,
    this.pageCount,
    this.selectedPages1Based = const {},
  });

  final ViewerToolId toolId;
  final PdfViewerDocumentHandoff handoff;
  final VoidCallback onClose;
  final int? pageCount;
  final Set<int> selectedPages1Based;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ViewerToolPanelChrome(
      title: toolId.panelTitle,
      documentName: handoff.file.displayName,
      onClose: onClose,
      child: _buildToolBody(context, ref),
    );
  }

  Widget _buildToolBody(BuildContext context, WidgetRef ref) {
    final file = handoff.file;
    final password = handoff.password;
    switch (toolId) {
      case ViewerToolId.compress:
        return ViewerCompressPanel(handoff: handoff);
      case ViewerToolId.protect:
        return ViewerProtectPanel(handoff: handoff);
      case ViewerToolId.unlock:
        return ViewerUnlockPanel(handoff: handoff);
      case ViewerToolId.metadata:
        return MetadataEditorScreen(
          deps: metadataEditorDepsFromRef(ref),
          initialFile: file,
          initialPassword: password,
          embedInViewerPanel: true,
        );
      case ViewerToolId.accessibilityTags:
        return ViewerAccessibilityTagsPanel(handoff: handoff);
      case ViewerToolId.removeMetadata:
        return RemoveMetadataScreen(
          deps: removeMetadataDepsFromRef(ref),
          initialFile: file,
          initialPassword: password,
          embedInViewerPanel: true,
        );
      case ViewerToolId.watermark:
        return ViewerWatermarkPanel(
          handoff: handoff,
          pageCount: pageCount,
          selectedPages1Based: selectedPages1Based,
        );
      case ViewerToolId.pageNumbers:
        return ViewerPageNumbersPanel(
          handoff: handoff,
          pageCount: pageCount,
          selectedPages1Based: selectedPages1Based,
        );
      case ViewerToolId.headersFooters:
        return ViewerHeadersFootersPanel(
          handoff: handoff,
          pageCount: pageCount,
          selectedPages1Based: selectedPages1Based,
        );
      case ViewerToolId.crop:
        return ViewerCropPanel(
          handoff: handoff,
          pageCount: pageCount,
          selectedPages1Based: selectedPages1Based,
        );
      case ViewerToolId.resize:
        return ViewerResizePanel(
          handoff: handoff,
          pageCount: pageCount,
          selectedPages1Based: selectedPages1Based,
        );
      case ViewerToolId.exportImages:
        return ViewerExportImagesPanel(
          handoff: handoff,
          format: PdfToImageFormat.png,
          pageCount: pageCount,
          selectedPages1Based: selectedPages1Based,
        );
      case ViewerToolId.exportJpg:
        return ViewerExportImagesPanel(
          handoff: handoff,
          format: PdfToImageFormat.jpeg,
          pageCount: pageCount,
          selectedPages1Based: selectedPages1Based,
        );
      case ViewerToolId.exportPng:
        return ViewerExportImagesPanel(
          handoff: handoff,
          format: PdfToImageFormat.png,
          pageCount: pageCount,
          selectedPages1Based: selectedPages1Based,
        );
      case ViewerToolId.split:
        return ViewerSplitPanel(handoff: handoff, pageCount: pageCount);
      case ViewerToolId.extract:
        return ViewerScopedPageOrganizePanel(
          mode: ViewerScopedOrganizeMode.extract,
          handoff: handoff,
          pageCount: pageCount,
          selectedPages1Based: selectedPages1Based,
        );
      case ViewerToolId.deletePages:
        return ViewerScopedPageOrganizePanel(
          mode: ViewerScopedOrganizeMode.delete,
          handoff: handoff,
          pageCount: pageCount,
          selectedPages1Based: selectedPages1Based,
        );
      case ViewerToolId.rotate:
        return ViewerScopedPageOrganizePanel(
          mode: ViewerScopedOrganizeMode.rotate,
          handoff: handoff,
          pageCount: pageCount,
          selectedPages1Based: selectedPages1Based,
        );
      case ViewerToolId.duplicate:
        return ViewerScopedPageOrganizePanel(
          mode: ViewerScopedOrganizeMode.duplicate,
          handoff: handoff,
          pageCount: pageCount,
          selectedPages1Based: selectedPages1Based,
        );
      case ViewerToolId.insertBlank:
        return ViewerScopedPageOrganizePanel(
          mode: ViewerScopedOrganizeMode.insertBlank,
          handoff: handoff,
          pageCount: pageCount,
          selectedPages1Based: selectedPages1Based,
        );
      case ViewerToolId.reverse:
        return ViewerReversePanel(handoff: handoff, pageCount: pageCount);
      case ViewerToolId.workspaceMerge:
        return ViewerMergePanel(handoff: handoff, pageCount: pageCount);
      case ViewerToolId.workspaceReorder:
        return ViewerOrganizePagesPanel(handoff: handoff, pageCount: pageCount);
      case ViewerToolId.workspaceMoveBetween:
        return const ViewerMoveBetweenPanel();
      case ViewerToolId.workspaceInsert:
        return ViewerInsertPagesPanel(
          handoff: handoff,
          pageCount: pageCount,
          selectedPages1Based: selectedPages1Based,
        );
      case ViewerToolId.workspaceReplace:
        return ViewerReplacePagesPanel(
          handoff: handoff,
          pageCount: pageCount,
          selectedPages1Based: selectedPages1Based,
        );
      case ViewerToolId.editText:
        return ViewerEditTextPanel(handoff: handoff);
      case ViewerToolId.redact:
        return ViewerRedactPanel(handoff: handoff, pageCount: pageCount);
      case ViewerToolId.fillForm:
        return ViewerFillFormPanel(handoff: handoff);
      case ViewerToolId.officeConvert:
        return ViewerOfficeConvertPanel(handoff: handoff);
      case ViewerToolId.ink:
      case ViewerToolId.placeImage:
      case ViewerToolId.markupBurn:
      case ViewerToolId.addLink:
        return const MarkupToolPanel();
      case ViewerToolId.searchablePdf:
        return ViewerSearchablePdfPanel(
          handoff: handoff,
          pageCount: pageCount,
          selectedPages1Based: selectedPages1Based,
        );
      case ViewerToolId.blockedSearchablePdf:
        return ViewerBlockedToolPanel(
          title: toolId.panelTitle,
          reason: 'Searchable PDF isn’t ready on this device yet.',
          handoff: handoff,
        );
      case ViewerToolId.blockedOcrImage:
        return ViewerBlockedToolPanel(
          title: toolId.panelTitle,
          reason: 'Text recognition isn’t ready on this device yet.',
          handoff: handoff,
        );
      case ViewerToolId.visualSign:
        return ViewerVisualSignPanel(handoff: handoff);
      case ViewerToolId.insertScan:
        return ViewerInsertScanPanel(handoff: handoff, pageCount: pageCount);
      case ViewerToolId.ocrImage:
        return ViewerOcrImagePanel(handoff: handoff);
      case ViewerToolId.batch:
        return ViewerBatchPanel(
          handoff: handoff,
          pageCount: pageCount,
          selectedPages1Based: selectedPages1Based,
        );
      case ViewerToolId.compare:
        return ViewerComparePanel(handoff: handoff);
    }
  }
}
