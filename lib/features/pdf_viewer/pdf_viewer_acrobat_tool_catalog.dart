import 'package:document_studio/features/ocr/ocr_errors.dart';
import 'package:document_studio/features/page_management/organize_tool_catalog.dart';
import 'package:document_studio/infrastructure/ocr/ocr_port.dart';
import 'package:document_studio/infrastructure/ocr/ocr_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Groups for the viewer **Tools** list.
///
/// Most-used groups first. Rows are only tools this app ships.
enum PdfViewerAcrobatToolGroup {
  pages('Pages'),
  comment('Comment'),
  combine('Combine'),
  convert('Convert'),
  security('Security'),
  optimize('Optimize'),
  sign('Sign'),
  edit('Edit'),
  create('Create');

  const PdfViewerAcrobatToolGroup(this.title);
  final String title;
}

enum PdfViewerAcrobatToolAvailability { available, blocked }

class PdfViewerAcrobatToolDefinition {
  const PdfViewerAcrobatToolDefinition({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.group,
    this.availability = PdfViewerAcrobatToolAvailability.available,
    this.blockedReason,
    this.alternativeActionLabel,
  });

  final String id;
  final String label;
  final String subtitle;
  final IconData icon;
  final PdfViewerAcrobatToolGroup group;
  final PdfViewerAcrobatToolAvailability availability;
  final String? blockedReason;
  final String? alternativeActionLabel;

  Key get handoffKey => Key('acrobat_tool_$id');
}

const _combineOrganizeIds = {
  'merge',
  'split',
  'insert',
  'replace',
  'move_between',
};

/// Full feature inventory for the viewer tools list.
///
/// Tools the app does not have (share, request signatures, send for comments,
/// prepare a form) are omitted — no dead rows.
List<PdfViewerAcrobatToolDefinition> buildPdfViewerAcrobatToolCatalog(
  WidgetRef ref,
) {
  final ocrBlocked = isOcrEngineBlocked(ref.read(ocrPortProvider));
  final searchableBlocked =
      isSearchablePdfEngineBlocked(ref.read(searchablePdfPortProvider));

  final organizeAndCombine = OrganizeToolCatalog.tools.map((t) {
    final combine = _combineOrganizeIds.contains(t.id);
    return PdfViewerAcrobatToolDefinition(
      id: 'organize_${t.id}',
      label: t.label,
      subtitle: t.description,
      icon: t.icon,
      group: combine
          ? PdfViewerAcrobatToolGroup.combine
          : PdfViewerAcrobatToolGroup.pages,
    );
  });

  const create = [
    PdfViewerAcrobatToolDefinition(
      id: 'create_pdf',
      label: 'Create PDF',
      subtitle: 'From plain text',
      icon: Icons.note_add_outlined,
      group: PdfViewerAcrobatToolGroup.create,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'images_to_pdf',
      label: 'Images to PDF',
      subtitle: 'Combine images into one PDF',
      icon: Icons.collections_outlined,
      group: PdfViewerAcrobatToolGroup.create,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'office_to_pdf',
      label: 'From Office',
      subtitle: 'Word, Excel, or PowerPoint',
      icon: Icons.description_outlined,
      group: PdfViewerAcrobatToolGroup.create,
    ),
  ];

  const edit = [
    PdfViewerAcrobatToolDefinition(
      id: 'edit_text',
      label: 'Edit text',
      subtitle: 'Click a run to replace it',
      icon: Icons.edit_outlined,
      group: PdfViewerAcrobatToolGroup.edit,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'markup_text',
      label: 'Add text',
      subtitle: 'Place a text box on the page',
      icon: Icons.text_fields,
      group: PdfViewerAcrobatToolGroup.comment,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'place_image',
      label: 'Add image',
      subtitle: 'Stamp an image on this page',
      icon: Icons.add_photo_alternate_outlined,
      group: PdfViewerAcrobatToolGroup.edit,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'add_link',
      label: 'Link',
      subtitle: 'URI or page link',
      icon: Icons.link,
      group: PdfViewerAcrobatToolGroup.edit,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'headers_footers',
      label: 'Header & footer',
      subtitle: 'Title, date, page variables',
      icon: Icons.vertical_align_center_outlined,
      group: PdfViewerAcrobatToolGroup.pages,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'watermark',
      label: 'Watermark',
      subtitle: 'Text overlay on pages',
      icon: Icons.branding_watermark_outlined,
      group: PdfViewerAcrobatToolGroup.optimize,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'page_numbers',
      label: 'Page numbers',
      subtitle: 'Arabic or Roman',
      icon: Icons.format_list_numbered,
      group: PdfViewerAcrobatToolGroup.pages,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'compare',
      label: 'Compare PDFs',
      subtitle: 'Text, images, and pages vs another file',
      icon: Icons.compare_outlined,
      group: PdfViewerAcrobatToolGroup.edit,
    ),
  ];

  const fillSign = [
    PdfViewerAcrobatToolDefinition(
      id: 'visual_sign',
      label: 'Sign',
      subtitle: 'Signature or initials on the page',
      icon: Icons.draw_outlined,
      group: PdfViewerAcrobatToolGroup.sign,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'stamps',
      label: 'Stamps',
      subtitle: 'Approved, date, and custom stamps',
      icon: Icons.approval_outlined,
      group: PdfViewerAcrobatToolGroup.sign,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'digital_sign',
      label: 'Certificate signature',
      subtitle: 'Sign with a certificate and validate',
      icon: Icons.verified_user_outlined,
      group: PdfViewerAcrobatToolGroup.sign,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'fill_form',
      label: 'Fill form',
      subtitle: 'Fill fields on this PDF',
      icon: Icons.checklist_outlined,
      group: PdfViewerAcrobatToolGroup.sign,
    ),
  ];

  const export = [
    PdfViewerAcrobatToolDefinition(
      id: 'export_images',
      label: 'Export to images',
      subtitle: 'PNG or JPEG per page',
      icon: Icons.image_outlined,
      group: PdfViewerAcrobatToolGroup.convert,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'export_jpg',
      label: 'Export to JPG',
      subtitle: 'JPEG pages from this PDF',
      icon: Icons.photo_outlined,
      group: PdfViewerAcrobatToolGroup.convert,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'export_png',
      label: 'Export to PNG',
      subtitle: 'Lossless page images',
      icon: Icons.image_outlined,
      group: PdfViewerAcrobatToolGroup.convert,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'office_convert',
      label: 'Convert to Office',
      subtitle: 'Word, Excel, PowerPoint',
      icon: Icons.swap_horiz,
      group: PdfViewerAcrobatToolGroup.convert,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'compress',
      label: 'Compress PDF',
      subtitle: 'Reduce file size',
      icon: Icons.compress,
      group: PdfViewerAcrobatToolGroup.optimize,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'batch',
      label: 'Batch',
      subtitle: 'One operation on this file',
      icon: Icons.playlist_play_outlined,
      group: PdfViewerAcrobatToolGroup.optimize,
    ),
  ];

  const comments = [
    PdfViewerAcrobatToolDefinition(
      id: 'comment_highlight',
      label: 'Highlight',
      subtitle: 'Mark text on this page',
      icon: Icons.highlight,
      group: PdfViewerAcrobatToolGroup.comment,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'comment_underline',
      label: 'Underline',
      subtitle: 'Underline selected text',
      icon: Icons.format_underline,
      group: PdfViewerAcrobatToolGroup.comment,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'comment_strikeout',
      label: 'Strikethrough',
      subtitle: 'Strike selected text',
      icon: Icons.format_strikethrough,
      group: PdfViewerAcrobatToolGroup.comment,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'comment_note',
      label: 'Sticky note',
      subtitle: 'Add a note on this page',
      icon: Icons.sticky_note_2_outlined,
      group: PdfViewerAcrobatToolGroup.comment,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'ink',
      label: 'Draw',
      subtitle: 'Pen strokes on this page',
      icon: Icons.brush_outlined,
      group: PdfViewerAcrobatToolGroup.comment,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'comment_callout',
      label: 'Callout',
      subtitle: 'Text callout on this page',
      icon: Icons.chat_bubble_outline,
      group: PdfViewerAcrobatToolGroup.comment,
    ),
  ];

  final scanOcr = [
    PdfViewerAcrobatToolDefinition(
      id: 'insert_scan',
      label: 'Insert scan',
      subtitle: 'Append photos after this page',
      icon: Icons.document_scanner_outlined,
      group: PdfViewerAcrobatToolGroup.pages,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'ocr_image',
      label: 'Image OCR',
      subtitle: ocrBlocked
          ? 'Tesseract setup required'
          : 'Extract text via system Tesseract',
      icon: Icons.document_scanner_outlined,
      group: PdfViewerAcrobatToolGroup.convert,
      availability: ocrBlocked
          ? PdfViewerAcrobatToolAvailability.blocked
          : PdfViewerAcrobatToolAvailability.available,
      blockedReason: ocrBlocked ? BlockedOcrPort.blockedReason : null,
      alternativeActionLabel: 'Copy text from PDF',
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'ocr_searchable_pdf',
      label: 'Searchable PDF',
      subtitle: searchableBlocked
          ? 'Tesseract setup required'
          : 'OCR into a text layer',
      icon: Icons.find_in_page_outlined,
      group: PdfViewerAcrobatToolGroup.convert,
      availability: searchableBlocked
          ? PdfViewerAcrobatToolAvailability.blocked
          : PdfViewerAcrobatToolAvailability.available,
      blockedReason:
          searchableBlocked ? BlockedSearchablePdfPort.blockedReason : null,
    ),
  ];

  const protect = [
    PdfViewerAcrobatToolDefinition(
      id: 'protect',
      label: 'Encrypt',
      subtitle: 'Password and permissions on this PDF',
      icon: Icons.lock_outline,
      group: PdfViewerAcrobatToolGroup.security,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'unlock',
      label: 'Decrypt',
      subtitle: 'Remove the password from this PDF',
      icon: Icons.lock_open_outlined,
      group: PdfViewerAcrobatToolGroup.security,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'metadata',
      label: 'Edit metadata',
      subtitle: 'Title, author, properties',
      icon: Icons.edit_note_outlined,
      group: PdfViewerAcrobatToolGroup.optimize,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'remove_metadata',
      label: 'Remove metadata',
      subtitle: 'Strip Info and XMP',
      icon: Icons.cleaning_services_outlined,
      group: PdfViewerAcrobatToolGroup.optimize,
    ),
    PdfViewerAcrobatToolDefinition(
      id: 'accessibility_tags',
      label: 'Accessibility',
      subtitle: 'Language, MarkInfo, reading order',
      icon: Icons.accessibility_new_outlined,
      group: PdfViewerAcrobatToolGroup.security,
    ),
  ];

  const redact = [
    PdfViewerAcrobatToolDefinition(
      id: 'redact',
      label: 'Redact',
      subtitle: 'Remove content permanently',
      icon: Icons.block_flipped,
      group: PdfViewerAcrobatToolGroup.security,
    ),
  ];

  return [
    ...create,
    ...organizeAndCombine,
    ...edit,
    ...fillSign,
    ...export,
    ...comments,
    ...scanOcr,
    ...protect,
    ...redact,
  ];
}

const _acrobatRailGroupOrder = <PdfViewerAcrobatToolGroup>[
  PdfViewerAcrobatToolGroup.pages,
  PdfViewerAcrobatToolGroup.comment,
  PdfViewerAcrobatToolGroup.combine,
  PdfViewerAcrobatToolGroup.convert,
  PdfViewerAcrobatToolGroup.security,
  PdfViewerAcrobatToolGroup.optimize,
  PdfViewerAcrobatToolGroup.sign,
  PdfViewerAcrobatToolGroup.edit,
  PdfViewerAcrobatToolGroup.create,
];

List<PdfViewerAcrobatToolGroup> pdfViewerAcrobatToolGroupsInOrder(
  List<PdfViewerAcrobatToolDefinition> tools,
) {
  final present = tools.map((t) => t.group).toSet();
  final order = <PdfViewerAcrobatToolGroup>[];
  for (final g in _acrobatRailGroupOrder) {
    if (present.contains(g)) order.add(g);
  }
  for (final g in present) {
    if (!order.contains(g)) order.add(g);
  }
  return order;
}

/// Section title in the All tools list.
String pdfViewerAcrobatRailSectionTitle(PdfViewerAcrobatToolGroup group) =>
    group.title;

List<PdfViewerAcrobatToolDefinition> pdfViewerAcrobatToolsInGroup(
  List<PdfViewerAcrobatToolDefinition> tools,
  PdfViewerAcrobatToolGroup group,
) {
  return tools.where((t) => t.group == group).toList();
}
