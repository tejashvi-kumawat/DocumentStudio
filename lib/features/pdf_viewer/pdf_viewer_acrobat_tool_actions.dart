import 'package:document_studio/features/annotations/markup/markup_tool.dart';
import 'package:document_studio/features/annotations/pdf_annotation_authoring.dart';
import 'package:document_studio/features/batch/batch_route.dart';
import 'package:document_studio/features/compression/compress_route.dart';
import 'package:document_studio/features/conversion/conversion_route.dart';
import 'package:document_studio/features/form_sign/form_sign_route.dart';
import 'package:document_studio/features/form_sign/sign_panel_tab.dart';
import 'package:document_studio/features/home/home_tool_route.dart';
import 'package:document_studio/features/ocr/ocr_route.dart';
import 'package:document_studio/features/page_management/organize_tool_catalog.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_acrobat_tool_catalog.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_tool_panel_scope.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio/features/pdf_markup/pdf_markup_route.dart';
import 'package:document_studio/features/security/security_route.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Runs a viewer tools-rail action for [toolId] on the open document.
void runPdfViewerAcrobatTool({
  required BuildContext context,
  required PdfViewerDocumentHandoff handoff,
  required String toolId,
  PdfViewerAcrobatToolAvailability availability =
      PdfViewerAcrobatToolAvailability.available,
}) {
  final markupTool = _markupToolForAcrobatId(toolId);
  if (markupTool != null) {
    PdfAnnotationAuthoring.open(context, markupTool);
    return;
  }

  if (toolId == 'create_pdf') {
    context.push(createPdfRoutePath);
    return;
  }
  if (toolId == 'images_to_pdf') {
    context.push(imagesToPdfRoutePath);
    return;
  }

  if (toolId == 'ocr_image' &&
      availability == PdfViewerAcrobatToolAvailability.blocked) {
    openViewerToolPanelOr(context, ViewerToolId.blockedOcrImage, () {
      _pushToolRoute(context, handoff, toolId);
    });
    return;
  }

  final panelTool = viewerToolIdFromAcrobatToolId(toolId);
  if (panelTool != null) {
    final useBlockedPanel =
        panelTool.isBlockedCapability &&
        availability == PdfViewerAcrobatToolAvailability.blocked;
    final useWorkingPanel = !panelTool.isBlockedCapability;
    if (useBlockedPanel || useWorkingPanel) {
      openViewerToolPanelOr(context, panelTool, () {
        _pushToolRoute(context, handoff, toolId);
      });
      return;
    }
  }

  final doc = handoff;
  switch (toolId) {
    case 'workspace':
      PdfViewerDocumentActions.openDocumentWorkspace(context, doc);
    case 'export_images':
      PdfViewerDocumentActions.exportToImages(context, doc);
    case 'export_jpg':
      PdfViewerDocumentActions.exportToJpg(context, doc);
    case 'export_png':
      PdfViewerDocumentActions.exportToPng(context, doc);
    case 'visual_sign' || 'stamps' || 'digital_sign':
      signPanelTabRequest.value = switch (toolId) {
        'stamps' => SignPanelTab.stamps,
        'digital_sign' => SignPanelTab.digital,
        _ => SignPanelTab.signatures,
      };
      openViewerToolPanelOr(context, ViewerToolId.visualSign, () {
        rememberViewerToolReturnFromContext(context, doc.documentArgs);
        context.push(visualSignRoutePath, extra: doc.documentArgs);
      });
    case 'place_image':
      openViewerToolPanelOr(context, ViewerToolId.placeImage, () {
        rememberViewerToolReturnFromContext(context, doc.documentArgs);
        context.push(placeImageRoutePath, extra: doc.documentArgs);
      });
    case 'insert_scan':
      openViewerToolPanelOr(context, ViewerToolId.insertScan, () {});
    case 'fill_form':
      openViewerToolPanelOr(context, ViewerToolId.fillForm, () {
        rememberViewerToolReturnFromContext(context, doc.documentArgs);
        context.push(fillFormRoutePath, extra: doc.documentArgs);
      });
    case 'redact':
      openViewerToolPanelOr(context, ViewerToolId.redact, () {
        rememberViewerToolReturnFromContext(context, doc.documentArgs);
        context.push(redactRoutePath);
      });
    case 'edit_text':
    case 'add_text':
      openViewerToolPanelOr(context, ViewerToolId.editText, () {
        rememberViewerToolReturnFromContext(context, doc.documentArgs);
        context.push(editTextRoutePath, extra: doc.documentArgs);
      });
    case 'add_link':
      openViewerToolPanelOr(context, ViewerToolId.addLink, () {});
    case 'office_convert':
      openViewerToolPanelOr(context, ViewerToolId.officeConvert, () {
        rememberViewerToolReturnFromContext(context, doc.documentArgs);
        context.push(officeConvertRoutePath, extra: doc.documentArgs);
      });
    case 'ink':
    case 'draw':
      openViewerToolPanelOr(context, ViewerToolId.ink, () {
        rememberViewerToolReturnFromContext(context, doc.documentArgs);
        context.push(drawInkRoutePath, extra: doc.documentArgs);
      });
    case 'ocr_image':
      openViewerToolPanelOr(context, ViewerToolId.ocrImage, () {
        rememberViewerToolReturnFromContext(context, doc.documentArgs);
        context.push(imageOcrRoutePath, extra: doc.documentArgs);
      });
    case 'ocr_searchable_pdf':
      openViewerToolPanelOr(context, ViewerToolId.searchablePdf, () {
        rememberViewerToolReturnFromContext(context, doc.documentArgs);
        context.push(searchablePdfRoutePath, extra: doc.documentArgs);
      });
    case 'batch':
      openViewerToolPanelOr(context, ViewerToolId.batch, () {
        rememberViewerToolReturnFromContext(context, doc.documentArgs);
        context.push(batchRoutePath, extra: doc.documentArgs);
      });
    default:
      if (toolId.startsWith('organize_')) {
        final organizeId = toolId.substring('organize_'.length);
        _runOrganizeTool(context, doc, organizeId);
      }
  }
}

void _pushToolRoute(
  BuildContext context,
  PdfViewerDocumentHandoff doc,
  String toolId,
) {
  final args = doc.documentArgs;
  switch (toolId) {
    case 'compress':
      pushCompressForPdf(context, file: doc.file, password: doc.password);
    case 'protect':
      rememberViewerToolReturnFromContext(context, args);
      context.push(protectRoutePath, extra: args);
    case 'unlock':
      rememberViewerToolReturnFromContext(context, args);
      context.push(unlockRoutePath, extra: args);
    case 'metadata':
      final meta = MetadataEditorRouteArgs(
        file: doc.file,
        password: doc.password,
      );
      rememberViewerToolReturnFromContext(context, meta);
      context.push(metadataRoutePath, extra: meta);
    case 'remove_metadata':
      rememberViewerToolReturnFromContext(context, args);
      context.push(removeMetadataRoutePath, extra: args);
    case 'watermark':
      rememberViewerToolReturnFromContext(context, args);
      context.push(watermarkRoutePath, extra: args);
    case 'page_numbers':
      rememberViewerToolReturnFromContext(context, args);
      context.push(pageNumbersRoutePath, extra: args);
    case 'headers_footers':
      rememberViewerToolReturnFromContext(context, args);
      context.push(headersFootersRoutePath, extra: args);
    case 'export_images':
    case 'export_jpg':
    case 'export_png':
      PdfViewerDocumentActions.exportToImages(context, doc);
    case 'organize_crop':
      PdfViewerDocumentActions.cropPages(context, doc);
    case 'organize_split':
      PdfViewerDocumentActions.splitPdf(context, doc);
    case 'organize_merge':
      PdfViewerDocumentActions.organizeTool(context, doc, '/organize/merge');
    default:
      break;
  }
}

void _runOrganizeTool(
  BuildContext context,
  PdfViewerDocumentHandoff doc,
  String organizeId,
) {
  final panelTool = _viewerPanelForOrganizeId(organizeId);
  if (panelTool != null) {
    openViewerToolPanelOr(context, panelTool, () {
      _pushOrganizeRoute(context, doc, organizeId);
    });
    return;
  }
  if (organizeId == 'resize') {
    openViewerToolPanelOr(context, ViewerToolId.resize, () {
      PdfViewerDocumentActions.resizePages(context, doc);
    });
    return;
  }
  final tool = OrganizeToolCatalog.tools.firstWhere(
    (t) => t.id == organizeId,
    orElse: () => throw StateError('Unknown organize tool: $organizeId'),
  );
  PdfViewerDocumentActions.organizeTool(context, doc, tool.routePath);
}

ViewerToolId? _viewerPanelForOrganizeId(String organizeId) =>
    switch (organizeId) {
      'crop' => ViewerToolId.crop,
      'resize' => ViewerToolId.resize,
      'split' => ViewerToolId.split,
      'extract' => ViewerToolId.extract,
      'delete' => ViewerToolId.deletePages,
      'rotate' => ViewerToolId.rotate,
      'duplicate' => ViewerToolId.duplicate,
      'reverse' => ViewerToolId.reverse,
      'blank' => ViewerToolId.insertBlank,
      'merge' => ViewerToolId.workspaceMerge,
      'reorder' => ViewerToolId.workspaceReorder,
      'move_between' => ViewerToolId.workspaceMoveBetween,
      'insert' => ViewerToolId.workspaceInsert,
      'replace' => ViewerToolId.workspaceReplace,
      _ => null,
    };

void _pushOrganizeRoute(
  BuildContext context,
  PdfViewerDocumentHandoff doc,
  String organizeId,
) {
  switch (organizeId) {
    case 'crop':
      PdfViewerDocumentActions.cropPages(context, doc);
    case 'split':
      PdfViewerDocumentActions.splitPdf(context, doc);
    case 'merge':
      PdfViewerDocumentActions.organizeTool(context, doc, '/organize/merge');
    case 'move_between':
      context.push('/organize/move-between', extra: [doc.file]);
    case 'reorder':
      openViewerToolPanelOr(context, ViewerToolId.workspaceReorder, () {
        context.push('/organize/reorder', extra: doc.documentArgs);
      });
    default:
      final tool = OrganizeToolCatalog.tools.firstWhere(
        (t) => t.id == organizeId,
        orElse: () => throw StateError('Unknown organize tool: $organizeId'),
      );
      PdfViewerDocumentActions.organizeTool(context, doc, tool.routePath);
  }
}

/// Comment and add-text rows that arm the markup editor instead of a form panel.
MarkupTool? _markupToolForAcrobatId(String toolId) => switch (toolId) {
  'markup_text' => MarkupTool.text,
  'comment_highlight' => MarkupTool.highlight,
  'comment_underline' => MarkupTool.underline,
  'comment_strikeout' => MarkupTool.strikeout,
  'comment_note' => MarkupTool.note,
  'comment_callout' => MarkupTool.callout,
  _ => null,
};

/// Nearest working alternative from a blocked tool card.
void runPdfViewerAcrobatToolAlternative({
  required BuildContext context,
  required PdfViewerDocumentHandoff handoff,
  required PdfViewerAcrobatToolDefinition tool,
}) {
  switch (tool.id) {
    case 'redact':
      runPdfViewerAcrobatTool(
        context: context,
        handoff: handoff,
        toolId: 'protect',
      );
    case 'fill_form':
      runPdfViewerAcrobatTool(
        context: context,
        handoff: handoff,
        toolId: 'visual_sign',
      );
    case 'office_convert':
      runPdfViewerAcrobatTool(
        context: context,
        handoff: handoff,
        toolId: 'export_images',
      );
    default:
      break;
  }
}
