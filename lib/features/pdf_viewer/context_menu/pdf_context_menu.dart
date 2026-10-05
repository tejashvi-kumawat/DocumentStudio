import 'dart:async';

import 'package:document_studio/design_system/widgets/ds_context_menu.dart';
import 'package:document_studio/domain/pdf_markup/markup_objects.dart';
import 'package:document_studio/features/annotations/markup/markup_editor_controller.dart';
import 'package:document_studio/features/annotations/markup/markup_text_snap.dart';
import 'package:document_studio/features/annotations/markup/markup_tool.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_zoom_controls.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

/// What the viewer screen lets the context menu do. Keeps the menu free of
/// screen internals; every callback maps to an existing toolbar action.
class PdfContextMenuHost {
  const PdfContextMenuHost({
    required this.controller,
    required this.markup,
    required this.openTool,
    required this.armMarkup,
    required this.find,
    required this.goToPage,
    required this.print,
    required this.documentProperties,
    required this.rotatePage,
    required this.snack,
  });

  final PdfViewerController? controller;
  final MarkupEditorController markup;
  final void Function(ViewerToolId tool) openTool;
  final void Function(MarkupTool tool) armMarkup;
  final VoidCallback find;
  final VoidCallback goToPage;
  final VoidCallback print;
  final VoidCallback documentProperties;
  final void Function(int degrees) rotatePage;
  final void Function(String message) snack;
}

/// Context-sensitive menu (Acrobat-style): items depend on what was clicked —
/// selected text, a selected markup object, or empty page.
Widget? buildPdfViewerContextMenu(
  BuildContext context,
  PdfViewerContextMenuBuilderParams params,
  PdfContextMenuHost host,
) {
  final entries = pdfContextMenuEntries(params, host);
  if (entries.isEmpty) return null;
  final size = MediaQuery.sizeOf(context);
  final h = DsContextMenuPanel.estimateHeight(entries);
  final left = params.anchorA.dx.clamp(8.0, (size.width - 260).clamp(8.0, 4000));
  final top = params.anchorA.dy.clamp(8.0, (size.height - h - 24).clamp(8.0, 4000));
  return Positioned(
    left: left.toDouble(),
    top: top.toDouble(),
    child: DsContextMenuPanel(
      entries: entries,
      onDismiss: params.dismissContextMenu,
    ),
  );
}

List<DsMenuEntry> pdfContextMenuEntries(
  PdfViewerContextMenuBuilderParams params,
  PdfContextMenuHost host,
) {
  final c = host.controller;
  final ready = c != null && c.isReady;
  final delegate = params.textSelectionDelegate;
  final hasText = delegate.hasSelectedText;
  final markupSel = host.markup.selectedObjects;
  final out = <DsMenuEntry>[];

  void divider() {
    if (out.isNotEmpty && out.last is! DsMenuDivider) {
      out.add(const DsMenuDivider());
    }
  }

  if (markupSel.isNotEmpty) {
    out.addAll(_markupEntries(host.markup));
    divider();
  }

  if (hasText) {
    out.addAll([
      DsMenuItem(
        label: 'Copy',
        icon: Icons.copy_outlined,
        shortcut: 'Ctrl+C',
        onTap: delegate.isCopyAllowed
            ? () => unawaited(delegate.copyTextSelection())
            : null,
      ),
      DsMenuItem(
        label: 'Select All',
        shortcut: 'Ctrl+A',
        onTap: () => unawaited(delegate.selectAllText()),
      ),
      const DsMenuDivider(),
      DsMenuItem(
        label: 'Highlight Text',
        icon: Icons.highlight_outlined,
        onTap: () => unawaited(_markSelection(host, TextMarkupKind.highlight)),
      ),
      DsMenuItem(
        label: 'Underline Text',
        icon: Icons.format_underline,
        onTap: () => unawaited(_markSelection(host, TextMarkupKind.underline)),
      ),
      DsMenuItem(
        label: 'Strikethrough Text',
        icon: Icons.format_strikethrough,
        onTap: () => unawaited(_markSelection(host, TextMarkupKind.strikeout)),
      ),
      DsMenuItem(
        label: 'Squiggly Underline',
        icon: Icons.waves,
        onTap: () => unawaited(_markSelection(host, TextMarkupKind.squiggly)),
      ),
      const DsMenuDivider(),
      DsMenuItem(
        label: 'Edit Text',
        icon: Icons.edit_outlined,
        onTap: () => host.openTool(ViewerToolId.editText),
      ),
      DsMenuItem(
        label: 'Add Link…',
        icon: Icons.link,
        onTap: () => host.openTool(ViewerToolId.addLink),
      ),
      DsMenuItem(
        label: 'Redact Text…',
        icon: Icons.hide_source,
        onTap: () => host.openTool(ViewerToolId.redact),
      ),
      const DsMenuDivider(),
      DsMenuItem(
        label: 'Find…',
        icon: Icons.search,
        shortcut: 'Ctrl+F',
        onTap: host.find,
      ),
    ]);
    return out;
  }

  if (markupSel.isEmpty) {
    out.addAll([
      DsMenuItem(
        label: 'Select All Text',
        shortcut: 'Ctrl+A',
        onTap: ready ? () => unawaited(delegate.selectAllText()) : null,
      ),
      DsMenuItem(
        label: 'Paste',
        icon: Icons.paste_outlined,
        shortcut: 'Ctrl+V',
        onTap: host.markup.hasClipboard ? () => host.markup.paste() : null,
      ),
      const DsMenuDivider(),
      DsMenuItem(
        label: 'Add Text Box',
        icon: Icons.text_fields,
        onTap: () => host.armMarkup(MarkupTool.text),
      ),
      DsMenuItem(
        label: 'Add Sticky Note',
        icon: Icons.sticky_note_2_outlined,
        onTap: () => host.armMarkup(MarkupTool.note),
      ),
      DsMenuItem(
        label: 'Add Image…',
        icon: Icons.add_photo_alternate_outlined,
        onTap: () => host.openTool(ViewerToolId.placeImage),
      ),
      DsMenuItem(
        label: 'Edit Text & Images',
        icon: Icons.edit_outlined,
        onTap: () => host.openTool(ViewerToolId.editText),
      ),
      DsMenuItem(
        label: 'Sign…',
        icon: Icons.draw_outlined,
        onTap: () => host.openTool(ViewerToolId.visualSign),
      ),
      const DsMenuDivider(),
    ]);
  }

  out.addAll([
    DsMenuItem(
      label: 'Zoom',
      icon: Icons.zoom_in,
      children: [
        DsMenuItem(
          label: 'Zoom In',
          shortcut: 'Ctrl++',
          onTap: ready ? () => unawaited(pdfViewerZoomIn(c)) : null,
        ),
        DsMenuItem(
          label: 'Zoom Out',
          shortcut: 'Ctrl+−',
          onTap: ready ? () => unawaited(pdfViewerZoomOut(c)) : null,
        ),
        const DsMenuDivider(),
        DsMenuItem(
          label: 'Fit One Full Page',
          shortcut: 'Ctrl+0',
          onTap: ready ? () => unawaited(pdfViewerApplyFitPage(c)) : null,
        ),
        DsMenuItem(
          label: 'Fit Width',
          shortcut: 'Ctrl+2',
          onTap: ready ? () => unawaited(pdfViewerApplyFitWidth(c)) : null,
        ),
        DsMenuItem(
          label: 'Fit Height',
          onTap: ready ? () => unawaited(pdfViewerApplyFitHeight(c)) : null,
        ),
      ],
    ),
    DsMenuItem(
      label: 'Go to Page…',
      icon: Icons.numbers,
      shortcut: 'Ctrl+Shift+N',
      onTap: ready ? host.goToPage : null,
    ),
    DsMenuItem(
      label: 'Find…',
      icon: Icons.search,
      shortcut: 'Ctrl+F',
      onTap: ready ? host.find : null,
    ),
    DsMenuItem(
      label: 'Rotate Pages',
      icon: Icons.rotate_right,
      children: [
        DsMenuItem(
          label: 'Clockwise',
          shortcut: 'Ctrl+Shift++',
          onTap: ready ? () => host.rotatePage(90) : null,
        ),
        DsMenuItem(
          label: 'Counterclockwise',
          shortcut: 'Ctrl+Shift+−',
          onTap: ready ? () => host.rotatePage(-90) : null,
        ),
      ],
    ),
    const DsMenuDivider(),
    DsMenuItem(
      label: 'Organize Pages',
      icon: Icons.view_module_outlined,
      onTap: () => host.openTool(ViewerToolId.workspaceReorder),
    ),
    DsMenuItem(
      label: 'Split Document…',
      icon: Icons.call_split,
      onTap: () => host.openTool(ViewerToolId.split),
    ),
    DsMenuItem(
      label: 'Extract Pages…',
      icon: Icons.content_cut,
      onTap: () => host.openTool(ViewerToolId.extract),
    ),
    DsMenuItem(
      label: 'Compress PDF…',
      icon: Icons.compress,
      onTap: () => host.openTool(ViewerToolId.compress),
    ),
    DsMenuItem(
      label: 'Export to Images…',
      icon: Icons.image_outlined,
      onTap: () => host.openTool(ViewerToolId.exportImages),
    ),
    const DsMenuDivider(),
    DsMenuItem(
      label: 'Print…',
      icon: Icons.print_outlined,
      shortcut: 'Ctrl+P',
      onTap: host.print,
    ),
    DsMenuItem(
      label: 'Document Properties…',
      icon: Icons.info_outline,
      shortcut: 'Ctrl+D',
      onTap: host.documentProperties,
    ),
  ]);
  return out;
}

List<DsMenuEntry> _markupEntries(MarkupEditorController m) {
  final locked = m.selectedObjects.any((o) => o.locked);
  return [
    DsMenuItem(
      label: 'Cut',
      icon: Icons.content_cut,
      shortcut: 'Ctrl+X',
      onTap: locked ? null : m.cutSelection,
    ),
    DsMenuItem(
      label: 'Copy',
      icon: Icons.copy_outlined,
      shortcut: 'Ctrl+C',
      onTap: m.copySelection,
    ),
    DsMenuItem(
      label: 'Paste',
      icon: Icons.paste_outlined,
      shortcut: 'Ctrl+V',
      onTap: m.hasClipboard ? () => m.paste() : null,
    ),
    DsMenuItem(
      label: 'Duplicate',
      icon: Icons.control_point_duplicate,
      shortcut: 'Ctrl+D',
      onTap: m.duplicateSelection,
    ),
    DsMenuItem(
      label: 'Delete',
      icon: Icons.delete_outline,
      shortcut: 'Del',
      destructive: true,
      onTap: locked ? null : m.deleteSelected,
    ),
    const DsMenuDivider(),
    DsMenuItem(
      label: 'Group',
      icon: Icons.group_work_outlined,
      shortcut: 'Ctrl+G',
      onTap: m.canGroup ? m.groupSelection : null,
    ),
    DsMenuItem(
      label: 'Ungroup',
      shortcut: 'Ctrl+Shift+G',
      onTap: m.canUngroup ? m.ungroupSelection : null,
    ),
    DsMenuItem(
      label: 'Arrange',
      icon: Icons.layers_outlined,
      children: [
        DsMenuItem(label: 'Bring to Front', onTap: m.bringToFront),
        DsMenuItem(label: 'Bring Forward', onTap: m.bringForward),
        DsMenuItem(label: 'Send Backward', onTap: m.sendBackward),
        DsMenuItem(label: 'Send to Back', onTap: m.sendToBack),
      ],
    ),
  ];
}

/// Turns the pdfrx text selection into a text-markup annotation.
Future<void> _markSelection(
  PdfContextMenuHost host,
  TextMarkupKind kind,
) async {
  final c = host.controller;
  if (c == null || !c.isReady) return;
  final ranges = await c.textSelectionDelegate.getSelectedTextRanges();
  if (ranges.isEmpty) return;
  final m = host.markup;
  for (final range in ranges) {
    final page = c.document.pages[range.pageNumber - 1];
    final text = MarkupPageText(
      range.pageText.fullText,
      [for (final r in range.pageText.charRects) r.toRect(page: page)],
    );
    final lines = text.linesForRange(range.start, range.end);
    if (lines.isEmpty) continue;
    m.addObject(
      TextMarkupMarkup(
        id: m.newId(),
        page: range.pageNumber,
        kind: kind,
        rects: lines,
        markupColor: m.textMarkupColor(kind),
        text: range.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
        opacity: m.opacity,
      ),
      select: false,
    );
  }
  c.textSelectionDelegate.clearTextSelection();
  host.snack('Markup added');
}

/// Copies plain text to the clipboard (used by selection actions).
Future<void> copyPlainText(String text) =>
    Clipboard.setData(ClipboardData(text: text));
