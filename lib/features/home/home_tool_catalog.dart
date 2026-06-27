import 'package:document_studio/features/batch/batch_route.dart';
import 'package:document_studio/features/pdf_markup/pdf_markup_route.dart';
import 'package:document_studio/features/security/security_route.dart';
import 'package:document_studio/features/conversion/conversion_route.dart';
import 'package:document_studio/features/form_sign/form_sign_route.dart';
import 'package:document_studio/features/home/home_tool.dart';
import 'package:document_studio/features/home/home_tool_availability.dart';
import 'package:document_studio/features/home/home_edit_pages_launch.dart';
import 'package:document_studio/features/home/home_tool_route.dart';
import 'package:document_studio/features/image_tools/image_tools_route.dart';
import 'package:document_studio/features/image_viewer/image_viewer_route.dart';
import 'package:document_studio/features/ocr/ocr_route.dart';
import 'package:document_studio/features/ocr/ocr_errors.dart';
import 'package:document_studio/infrastructure/ocr/ocr_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared tools catalog for Home, Tools hub, and command palette wiring.
List<HomeTool> buildHomeToolCatalog(BuildContext context, WidgetRef ref) {
  final ocrPort = ref.read(ocrPortProvider);
  final searchablePort = ref.read(searchablePdfPortProvider);
  final ocrBlocked = isOcrEngineBlocked(ocrPort);
  final searchableBlocked = isSearchablePdfEngineBlocked(searchablePort);

  void go(String path, HomeToolDocumentEntry entry) {
    pushHomeToolRoute(context, ref, path, documentEntry: entry);
  }

  return [
    HomeTool(
      id: 'create_pdf',
      label: 'Create PDF',
      subtitle: 'From plain text',
      icon: Icons.note_add_outlined,
      category: HomeToolCategory.createConvert,
      availability: HomeToolAvailability.available,
      documentEntry: HomeToolDocumentEntry.standalone,
      onTap: () => go(createPdfRoutePath, HomeToolDocumentEntry.standalone),
    ),
    HomeTool(
      id: 'images_to_pdf',
      label: 'Images to PDF',
      subtitle: 'Combine images into one PDF',
      icon: Icons.collections_bookmark_outlined,
      category: HomeToolCategory.createConvert,
      availability: HomeToolAvailability.available,
      documentEntry: HomeToolDocumentEntry.standalone,
      onTap: () => go(imagesToPdfRoutePath, HomeToolDocumentEntry.standalone),
    ),
    HomeTool(
      id: 'pdf_to_images',
      label: 'PDF to images',
      subtitle: 'Export pages as PNG or JPEG',
      icon: Icons.image_outlined,
      category: HomeToolCategory.createConvert,
      availability: HomeToolAvailability.available,
      documentEntry: HomeToolDocumentEntry.requiresOpenPdf,
      onTap: () => go(pdfToImagesRoutePath, HomeToolDocumentEntry.requiresOpenPdf),
    ),
    HomeTool(
      id: 'scan',
      label: 'Scan',
      subtitle: 'Import photos into a PDF',
      icon: Icons.document_scanner_outlined,
      category: HomeToolCategory.createConvert,
      availability: HomeToolAvailability.available,
      documentEntry: HomeToolDocumentEntry.standalone,
      onTap: () => go(scanRoutePath, HomeToolDocumentEntry.standalone),
    ),
    HomeTool(
      id: 'convert',
      label: 'Office convert',
      subtitle: 'Word, Excel, PowerPoint → PDF',
      icon: Icons.swap_horiz,
      category: HomeToolCategory.createConvert,
      availability: HomeToolAvailability.available,
      documentEntry: HomeToolDocumentEntry.standalone,
      onTap: () => go(officeConvertRoutePath, HomeToolDocumentEntry.standalone),
    ),
    HomeTool(
      id: 'fill_form',
      label: 'Fill PDF form',
      subtitle: 'Fill AcroForm fields',
      icon: Icons.checklist_outlined,
      category: HomeToolCategory.createConvert,
      availability: HomeToolAvailability.available,
      documentEntry: HomeToolDocumentEntry.pickFile,
      onTap: () => go(fillFormRoutePath, HomeToolDocumentEntry.pickFile),
    ),
    HomeTool(
      id: 'visual_sign',
      label: 'Sign PDF',
      subtitle: 'Add a visual signature',
      icon: Icons.draw_outlined,
      category: HomeToolCategory.createConvert,
      availability: partialVisualSignAvailability,
      documentEntry: HomeToolDocumentEntry.pickFile,
      onTap: () => go(visualSignRoutePath, HomeToolDocumentEntry.pickFile),
    ),
    HomeTool(
      id: 'place_image',
      label: 'Place image',
      subtitle: 'Insert an image onto a page',
      icon: Icons.image_outlined,
      category: HomeToolCategory.createConvert,
      availability: HomeToolAvailability.available,
      documentEntry: HomeToolDocumentEntry.requiresOpenPdf,
      onTap: () => go(placeImageRoutePath, HomeToolDocumentEntry.requiresOpenPdf),
    ),
    HomeTool(
      id: 'edit_text',
      label: 'Add text',
      subtitle: 'Type on the page',
      icon: Icons.text_fields,
      category: HomeToolCategory.createConvert,
      availability: HomeToolAvailability.available,
      documentEntry: HomeToolDocumentEntry.requiresOpenPdf,
      onTap: () => go(editTextRoutePath, HomeToolDocumentEntry.requiresOpenPdf),
    ),
    HomeTool(
      id: 'draw',
      label: 'Draw',
      subtitle: 'Ink strokes on the page',
      icon: Icons.gesture,
      category: HomeToolCategory.createConvert,
      availability: HomeToolAvailability.available,
      documentEntry: HomeToolDocumentEntry.requiresOpenPdf,
      onTap: () => go(drawInkRoutePath, HomeToolDocumentEntry.requiresOpenPdf),
    ),
    HomeTool(
      id: 'edit_pages',
      label: 'Edit pages',
      subtitle: 'Reorder and organize in workspace',
      icon: Icons.dashboard_customize_outlined,
      category: HomeToolCategory.organizePages,
      availability: HomeToolAvailability.available,
      documentEntry: HomeToolDocumentEntry.requiresOpenPdf,
      onTap: () => homeLaunchEditPages(context, ref),
    ),
    HomeTool(
      id: 'organize',
      label: 'Organize',
      subtitle: 'Merge, split, reorder',
      icon: Icons.view_day_outlined,
      category: HomeToolCategory.organizePages,
      availability: HomeToolAvailability.available,
      documentEntry: HomeToolDocumentEntry.standalone,
      onTap: () => go('/organize', HomeToolDocumentEntry.standalone),
    ),
    HomeTool(
      id: 'compress',
      label: 'Compress',
      subtitle: 'Reduce file size',
      icon: Icons.compress,
      category: HomeToolCategory.optimizeProtect,
      availability: HomeToolAvailability.available,
      documentEntry: HomeToolDocumentEntry.pickFile,
      onTap: () => go('/compress', HomeToolDocumentEntry.pickFile),
    ),
    HomeTool(
      id: 'redact',
      label: 'Redact PDF',
      subtitle: 'Permanently remove sensitive content',
      icon: Icons.block_flipped,
      category: HomeToolCategory.optimizeProtect,
      availability: HomeToolAvailability.blocked,
      documentEntry: HomeToolDocumentEntry.pickFile,
      onTap: () => go(redactRoutePath, HomeToolDocumentEntry.pickFile),
    ),
    HomeTool(
      id: 'headers_footers',
      label: 'Headers & footers',
      subtitle: 'Title, date, page variables',
      icon: Icons.vertical_align_center_outlined,
      category: HomeToolCategory.optimizeProtect,
      availability: HomeToolAvailability.available,
      documentEntry: HomeToolDocumentEntry.requiresOpenPdf,
      onTap: () => go(headersFootersRoutePath, HomeToolDocumentEntry.requiresOpenPdf),
    ),
    HomeTool(
      id: 'page_numbers',
      label: 'Page numbers',
      subtitle: 'Arabic or Roman numbering',
      icon: Icons.format_list_numbered,
      category: HomeToolCategory.optimizeProtect,
      availability: HomeToolAvailability.available,
      documentEntry: HomeToolDocumentEntry.requiresOpenPdf,
      onTap: () => go(pageNumbersRoutePath, HomeToolDocumentEntry.requiresOpenPdf),
    ),
    HomeTool(
      id: 'watermark',
      label: 'Watermark',
      subtitle: 'Semi-transparent text on every page',
      icon: Icons.branding_watermark_outlined,
      category: HomeToolCategory.optimizeProtect,
      availability: HomeToolAvailability.available,
      documentEntry: HomeToolDocumentEntry.pickFile,
      onTap: () => go(watermarkRoutePath, HomeToolDocumentEntry.pickFile),
    ),
    HomeTool(
      id: 'protect',
      label: 'Encrypt',
      subtitle: 'Encrypt with password & permissions',
      icon: Icons.lock_outline,
      category: HomeToolCategory.optimizeProtect,
      availability: HomeToolAvailability.available,
      documentEntry: HomeToolDocumentEntry.pickFile,
      onTap: () => go(protectRoutePath, HomeToolDocumentEntry.pickFile),
    ),
    HomeTool(
      id: 'unlock',
      label: 'Decrypt',
      subtitle: 'Remove the password',
      icon: Icons.lock_open_outlined,
      category: HomeToolCategory.optimizeProtect,
      availability: HomeToolAvailability.available,
      documentEntry: HomeToolDocumentEntry.pickFile,
      onTap: () => go(unlockRoutePath, HomeToolDocumentEntry.pickFile),
    ),
    HomeTool(
      id: 'metadata',
      label: 'Edit metadata',
      subtitle: 'Title, author, and properties',
      icon: Icons.description_outlined,
      category: HomeToolCategory.optimizeProtect,
      availability: HomeToolAvailability.available,
      documentEntry: HomeToolDocumentEntry.requiresOpenPdf,
      onTap: () => go(metadataRoutePath, HomeToolDocumentEntry.requiresOpenPdf),
    ),
    HomeTool(
      id: 'remove_metadata',
      label: 'Remove metadata',
      subtitle: 'Strip Info and XMP',
      icon: Icons.cleaning_services_outlined,
      category: HomeToolCategory.optimizeProtect,
      availability: HomeToolAvailability.available,
      documentEntry: HomeToolDocumentEntry.requiresOpenPdf,
      onTap: () => go(removeMetadataRoutePath, HomeToolDocumentEntry.requiresOpenPdf),
    ),
    HomeTool(
      id: 'image_viewer',
      label: 'Image viewer',
      subtitle: 'Pan and zoom local images',
      icon: Icons.image_outlined,
      category: HomeToolCategory.createConvert,
      availability: HomeToolAvailability.available,
      documentEntry: HomeToolDocumentEntry.standalone,
      onTap: () => go(imageViewerRoutePath, HomeToolDocumentEntry.standalone),
    ),
    HomeTool(
      id: 'image',
      label: 'Image tools',
      subtitle: 'Resize & convert images',
      icon: Icons.photo_size_select_large_outlined,
      category: HomeToolCategory.createConvert,
      availability: HomeToolAvailability.available,
      documentEntry: HomeToolDocumentEntry.standalone,
      onTap: () => go(imageToolsRoutePath, HomeToolDocumentEntry.standalone),
    ),
    HomeTool(
      id: 'ocr_image',
      label: 'Image OCR',
      subtitle: ocrBlocked
          ? 'Tesseract setup required'
          : 'Extract text (system Tesseract on desktop)',
      icon: Icons.document_scanner_outlined,
      category: HomeToolCategory.createConvert,
      availability: ocrBlocked
          ? HomeToolAvailability.blocked
          : HomeToolAvailability.available,
      documentEntry: HomeToolDocumentEntry.pickFile,
      onTap: () => go(imageOcrRoutePath, HomeToolDocumentEntry.pickFile),
    ),
    HomeTool(
      id: 'ocr_searchable_pdf',
      label: 'Searchable PDF',
      subtitle: searchableBlocked
          ? 'Needs bundled Tesseract CLI'
          : 'OCR scans into a text layer',
      icon: Icons.find_in_page_outlined,
      category: HomeToolCategory.createConvert,
      availability: searchableBlocked
          ? HomeToolAvailability.blocked
          : HomeToolAvailability.available,
      documentEntry: HomeToolDocumentEntry.pickFile,
      onTap: () => go(searchablePdfRoutePath, HomeToolDocumentEntry.pickFile),
    ),
    HomeTool(
      id: 'batch',
      label: 'Batch',
      subtitle: 'Multi-file jobs',
      icon: Icons.playlist_play_outlined,
      category: HomeToolCategory.automation,
      availability: HomeToolAvailability.available,
      documentEntry: HomeToolDocumentEntry.pickFile,
      onTap: () => go(batchRoutePath, HomeToolDocumentEntry.pickFile),
    ),
  ];
}

List<HomeTool> homeToolsInCategory(
  List<HomeTool> tools,
  HomeToolCategory category,
) {
  return tools.where((t) => t.category == category).toList();
}
