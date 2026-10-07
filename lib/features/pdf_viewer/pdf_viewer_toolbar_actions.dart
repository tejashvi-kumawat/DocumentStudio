import 'package:document_studio/design_system/shell/ds_grouped_menu_bar.dart';
import 'package:document_studio/design_system/shell/ds_status_bar.dart';
import 'package:document_studio/design_system/shell/ds_toolbar.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_fit_display.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_page_shortcuts.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_page_toolbar_controls.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_scroll_layout.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_view_rotation.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_zoom_controls.dart';
import 'package:document_studio/features/annotations/markup/markup_tool.dart';
import 'package:document_studio/features/annotations/pdf_annotation_authoring.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_scoped_page_organize_panel.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_tool_panel_scope.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Grouped viewer toolbar: File · Navigate · Zoom · View · Tools (Acrobat-style).
class PdfViewerToolbarActions extends StatelessWidget {
  const PdfViewerToolbarActions({
    super.key,
    required this.controller,
    this.file,
    this.handoff,
    this.password,
    this.onExportText,
    this.ocrBlocked = false,
    this.ocrBlockedReason,
    this.readMode = false,
    this.onToggleReadMode,
    this.rulersVisible = false,
    this.onToggleRulers,
    this.onPrint,
    this.fitDisplay,
    this.onOpenAnotherPdf,
    this.toolsRailEnabled = false,
    this.canUndo = false,
    this.canRedo = false,
    this.onUndo,
    this.onRedo,
    this.onSave,
    this.autosaveEnabled = false,
    this.onAutosaveChanged,
    this.onRotatePageLeft,
    this.onRotatePageRight,
    this.onCropPage,
    this.onToggleToolsRail,
    this.wideLayout = true,
    this.sidebarEnabled = true,
    this.annotationsPanelEnabled = false,
    this.presentationMode = false,
    this.scrollLayoutMode = PdfViewerScrollLayoutMode.continuous,
    this.onNavigate,
    this.onToggleSidebar,
    this.onToggleAnnotations,
    this.onTogglePresentation,
    this.onRotateView,
    this.viewRotation = PdfViewerViewRotation.degrees0,
    this.onScrollModeChanged,
    this.onGoToPage,
    this.onSearch,
    this.onShowBookmarks,
    this.onCopySelection,
    this.onSelectAllText,
    this.onDocumentInfo,
    this.onExportToImages,
    this.onEditPages,
    this.documentToolsMenu,
    this.onFitDisplayChanged,
  });

  final PdfViewerController? controller;
  final LocalFileRef? file;
  final PdfViewerDocumentHandoff? handoff;
  final String? password;
  final VoidCallback? onExportText;
  final bool ocrBlocked;
  final String? ocrBlockedReason;
  final bool readMode;
  final VoidCallback? onToggleReadMode;
  final bool rulersVisible;
  final VoidCallback? onToggleRulers;
  final VoidCallback? onPrint;
  final PdfViewerFitDisplay? fitDisplay;
  final VoidCallback? onOpenAnotherPdf;
  final bool toolsRailEnabled;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onSave;
  final bool autosaveEnabled;
  final ValueChanged<bool>? onAutosaveChanged;
  final VoidCallback? onRotatePageLeft;
  final VoidCallback? onRotatePageRight;
  final VoidCallback? onCropPage;
  final VoidCallback? onToggleToolsRail;
  final bool wideLayout;
  final bool sidebarEnabled;
  final bool annotationsPanelEnabled;
  final bool presentationMode;
  final PdfViewerScrollLayoutMode scrollLayoutMode;
  final void Function(PdfViewerPageStep step)? onNavigate;
  final VoidCallback? onToggleSidebar;
  final VoidCallback? onToggleAnnotations;
  final VoidCallback? onTogglePresentation;
  final VoidCallback? onRotateView;
  final PdfViewerViewRotation viewRotation;
  final ValueChanged<PdfViewerScrollLayoutMode>? onScrollModeChanged;
  final VoidCallback? onGoToPage;
  final VoidCallback? onSearch;
  final VoidCallback? onShowBookmarks;
  final VoidCallback? onCopySelection;
  final VoidCallback? onSelectAllText;
  final VoidCallback? onDocumentInfo;
  final VoidCallback? onExportToImages;
  final VoidCallback? onEditPages;
  final Widget? documentToolsMenu;
  final ValueChanged<PdfViewerFitDisplay>? onFitDisplayChanged;

  bool get _ready => controller?.isReady ?? false;

  void _setFit(PdfViewerFitDisplay mode) {
    onFitDisplayChanged?.call(mode);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ready;

    void tool(ViewerToolId id) => openViewerToolPanel(context, id);
    void markup(MarkupTool t) => PdfAnnotationAuthoring.open(context, t);
    void extractParity(String parity) {
      ViewerScopedPageOrganizePanel.pendingRange = parity;
      tool(ViewerToolId.extract);
    }

    final zoomControls = PdfViewerZoomToolbarControls(
      controller: controller,
      dense: true,
      onFitWidthApplied: () => _setFit(PdfViewerFitDisplay.fitWidth),
      onFitPageApplied: () => _setFit(PdfViewerFitDisplay.fitPage),
      onManualZoomApplied: () => _setFit(PdfViewerFitDisplay.custom),
    );

    final pageControls = PdfViewerPageToolbarControls(
      controller: controller,
      availability: controller == null
          ? const PdfViewerPageNavAvailability(
              navigationEnabled: false,
              canGoPrevious: false,
              canGoNext: false,
            )
          : null,
      onNavigate: onNavigate ?? (_) {},
      dense: true,
    );

    // Compact phone toolbar: page · Edit · Pages · Protect · Tools (always).
    // Group menus replace a long icon row / single overflow dump.
    if (!wideLayout) {
      final narrow = MediaQuery.sizeOf(context).width < 400;
      return DsGroupedMenuBar(
        leading: pageControls,
        children: [
          DsGroupedMenuButton(
            label: 'Edit',
            icon: Icons.edit_note_rounded,
            iconOnly: narrow,
            enabled: ready,
            items: [
              DsGroupedMenuItem(
                label: 'Add text',
                icon: Icons.text_fields_rounded,
                onSelected: () => markup(MarkupTool.text),
              ),
              DsGroupedMenuItem(
                label: 'Add image',
                icon: Icons.add_photo_alternate_outlined,
                onSelected: () => markup(MarkupTool.image),
              ),
              DsGroupedMenuItem(
                label: 'Link',
                icon: Icons.link,
                onSelected: () => markup(MarkupTool.link),
              ),
              DsGroupedMenuItem(
                label: 'Header & footer',
                icon: Icons.vertical_align_center_outlined,
                onSelected: () => tool(ViewerToolId.headersFooters),
              ),
              DsGroupedMenuItem(
                label: 'Watermark',
                icon: Icons.branding_watermark_outlined,
                onSelected: () => tool(ViewerToolId.watermark),
              ),
              DsGroupedMenuItem(
                label: 'Page numbers',
                icon: Icons.format_list_numbered_rounded,
                onSelected: () => tool(ViewerToolId.pageNumbers),
              ),
              DsGroupedMenuItem(
                label: 'Redact',
                icon: Icons.format_color_fill_rounded,
                onSelected: () => tool(ViewerToolId.redact),
              ),
              DsGroupedMenuItem(
                label: 'Fill form',
                icon: Icons.edit_document,
                onSelected: () => tool(ViewerToolId.fillForm),
              ),
            ],
          ),
          DsGroupedMenuButton(
            label: 'Pages',
            icon: Icons.auto_stories_outlined,
            iconOnly: narrow,
            enabled: ready,
            items: [
              DsGroupedMenuItem(
                label: 'Organize pages',
                icon: Icons.grid_view_rounded,
                onSelected: () => tool(ViewerToolId.workspaceReorder),
              ),
              DsGroupedMenuItem(
                label: 'Rotate pages',
                icon: Icons.rotate_90_degrees_cw_outlined,
                onSelected: () => tool(ViewerToolId.rotate),
              ),
              DsGroupedMenuItem(
                label: 'Crop pages',
                icon: Icons.crop_rounded,
                onSelected: () => tool(ViewerToolId.crop),
              ),
              DsGroupedMenuItem(
                label: 'Split PDF',
                icon: Icons.call_split_rounded,
                onSelected: () => tool(ViewerToolId.split),
              ),
              DsGroupedMenuItem(
                label: 'Extract pages',
                icon: Icons.file_upload_outlined,
                onSelected: () => tool(ViewerToolId.extract),
              ),
            ],
          ),
          DsGroupedMenuButton(
            label: 'Protect',
            icon: Icons.verified_user_outlined,
            iconOnly: narrow,
            enabled: ready,
            items: [
              DsGroupedMenuItem(
                label: 'Sign',
                icon: Icons.draw_outlined,
                onSelected: () => tool(ViewerToolId.visualSign),
              ),
              DsGroupedMenuItem(
                label: 'Encrypt',
                icon: Icons.lock_outline_rounded,
                onSelected: () => tool(ViewerToolId.protect),
              ),
              DsGroupedMenuItem(
                label: 'Decrypt',
                icon: Icons.lock_open_rounded,
                onSelected: () => tool(ViewerToolId.unlock),
              ),
              DsGroupedMenuItem(
                label: 'Edit metadata',
                icon: Icons.info_outline_rounded,
                onSelected: () => tool(ViewerToolId.metadata),
              ),
              DsGroupedMenuItem(
                label: 'Compress',
                icon: Icons.compress_rounded,
                onSelected: () => tool(ViewerToolId.compress),
              ),
            ],
          ),
          DsGroupedMenuButton(
            label: 'Tools',
            icon: Icons.apps_outlined,
            iconOnly: narrow,
            emphasize: true,
            items: [
              DsGroupedMenuItem(
                label: toolsRailEnabled ? 'Hide all tools' : 'All tools',
                icon: Icons.apps_outlined,
                onSelected: onToggleToolsRail ?? () {},
              ),
              DsGroupedMenuItem(
                label: 'Find',
                icon: Icons.search_rounded,
                onSelected: onSearch ?? () {},
                dividerBefore: true,
              ),
              DsGroupedMenuItem(
                label: 'Comment / annotate',
                icon: Icons.mode_comment_outlined,
                onSelected: () => markup(MarkupTool.highlight),
              ),
              DsGroupedMenuItem(
                label: 'Crop page',
                icon: Icons.crop_rounded,
                onSelected: onCropPage ?? () => tool(ViewerToolId.crop),
              ),
              DsGroupedMenuItem(
                label: 'Make searchable (OCR)',
                icon: Icons.document_scanner_outlined,
                onSelected: () => tool(
                  ocrBlocked
                      ? ViewerToolId.blockedSearchablePdf
                      : ViewerToolId.searchablePdf,
                ),
              ),
              DsGroupedMenuItem(
                label: 'Convert to Office',
                icon: Icons.description_outlined,
                onSelected: () => tool(ViewerToolId.officeConvert),
              ),
              DsGroupedMenuItem(
                label: 'Undo',
                icon: Icons.undo_rounded,
                onSelected: onUndo ?? () {},
                dividerBefore: true,
                enabled: canUndo,
              ),
              DsGroupedMenuItem(
                label: 'Redo',
                icon: Icons.redo_rounded,
                onSelected: onRedo ?? () {},
                enabled: canRedo,
              ),
              if (onSave != null)
                DsGroupedMenuItem(
                  label: 'Save',
                  icon: Icons.save_outlined,
                  onSelected: onSave!,
                ),
              DsGroupedMenuItem(
                label: sidebarEnabled
                    ? 'Hide page thumbnails'
                    : 'Page thumbnails',
                icon: Icons.view_sidebar_outlined,
                onSelected: onToggleSidebar ?? () {},
                dividerBefore: true,
              ),
              DsGroupedMenuItem(
                label: 'Zoom in',
                icon: Icons.zoom_in_rounded,
                onSelected: () {
                  final c = controller;
                  if (c == null) return;
                  pdfViewerZoomIn(c);
                  _setFit(PdfViewerFitDisplay.custom);
                },
              ),
              DsGroupedMenuItem(
                label: 'Zoom out',
                icon: Icons.zoom_out_rounded,
                onSelected: () {
                  final c = controller;
                  if (c == null) return;
                  pdfViewerZoomOut(c);
                  _setFit(PdfViewerFitDisplay.custom);
                },
              ),
              if (onPrint != null)
                DsGroupedMenuItem(
                  label: 'Print…',
                  icon: Icons.print_outlined,
                  onSelected: onPrint!,
                  dividerBefore: true,
                ),
              DsGroupedMenuItem(
                label: 'Document properties',
                icon: Icons.info_outline,
                onSelected: onDocumentInfo ?? () {},
              ),
            ],
          ),
        ],
      );
    }

    final wide =
        MediaQuery.sizeOf(context).width >= kDsStatusBarCompactBreakpoint;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DsToolbarIconButton(
            dense: true,
            icon: sidebarEnabled
                ? Icons.view_sidebar_rounded
                : Icons.view_sidebar_outlined,
            tooltip: sidebarEnabled ? 'Hide sidebar' : 'Show sidebar',
            selected: sidebarEnabled,
            onPressed: onToggleSidebar,
          ),
          DsToolbarIconButton(
            dense: true,
            icon: Icons.undo_rounded,
            tooltip: 'Undo',
            onPressed: canUndo ? onUndo : null,
          ),
          DsToolbarIconButton(
            dense: true,
            icon: Icons.redo_rounded,
            tooltip: 'Redo',
            onPressed: canRedo ? onRedo : null,
          ),
          const DsToolbarDivider(dense: true),
          pageControls,
          if (wide) zoomControls,
          const DsToolbarDivider(dense: true),
          _ToolMenu(
            label: 'Comment',
            icon: Icons.mode_comment_outlined,
            enabled: ready,
            items: [
              for (final t in const [
                MarkupTool.text,
                MarkupTool.highlight,
                MarkupTool.underline,
                MarkupTool.strikeout,
                MarkupTool.note,
                MarkupTool.callout,
                MarkupTool.pen,
                MarkupTool.highlighter,
                MarkupTool.rectangle,
                MarkupTool.ellipse,
                MarkupTool.arrow,
                MarkupTool.line,
                MarkupTool.cloud,
              ])
                _ToolItem(
                  t.label,
                  t.icon,
                  () => markup(t),
                  dividerBefore:
                      t == MarkupTool.pen || t == MarkupTool.rectangle,
                ),
            ],
          ),
          _ToolMenu(
            label: 'Edit',
            icon: Icons.edit_note_rounded,
            enabled: ready,
            items: [
              _ToolItem(
                'Add text',
                Icons.text_fields_rounded,
                () => markup(MarkupTool.text),
              ),
              _ToolItem(
                'Add image',
                Icons.add_photo_alternate_outlined,
                () => markup(MarkupTool.image),
              ),
              _ToolItem(
                'Add link',
                Icons.link_rounded,
                () => markup(MarkupTool.link),
              ),
              _ToolItem(
                'Watermark',
                Icons.branding_watermark_outlined,
                () => tool(ViewerToolId.watermark),
                dividerBefore: true,
              ),
              _ToolItem(
                'Header & footer',
                Icons.vertical_split_outlined,
                () => tool(ViewerToolId.headersFooters),
              ),
              _ToolItem(
                'Page numbers',
                Icons.format_list_numbered_rounded,
                () => tool(ViewerToolId.pageNumbers),
              ),
              _ToolItem(
                'Redact',
                Icons.format_color_fill_rounded,
                () => tool(ViewerToolId.redact),
                dividerBefore: true,
              ),
              _ToolItem(
                'Fill form',
                Icons.edit_document,
                () => tool(ViewerToolId.fillForm),
              ),
            ],
          ),
          _ToolMenu(
            label: 'Pages',
            icon: Icons.auto_stories_outlined,
            enabled: ready,
            items: [
              _ToolItem(
                'Organize pages',
                Icons.grid_view_rounded,
                () => tool(ViewerToolId.workspaceReorder),
              ),
              _ToolItem(
                'Rotate pages',
                Icons.rotate_90_degrees_cw_outlined,
                () => tool(ViewerToolId.rotate),
              ),
              _ToolItem(
                'Crop pages',
                Icons.crop_rounded,
                () => tool(ViewerToolId.crop),
              ),
              _ToolItem(
                'Resize pages',
                Icons.aspect_ratio_rounded,
                () => tool(ViewerToolId.resize),
              ),
              _ToolItem(
                'Insert blank page',
                Icons.note_add_outlined,
                () => tool(ViewerToolId.insertBlank),
                dividerBefore: true,
              ),
              _ToolItem(
                'Duplicate pages',
                Icons.copy_all_rounded,
                () => tool(ViewerToolId.duplicate),
              ),
              _ToolItem(
                'Delete pages',
                Icons.delete_outline_rounded,
                () => tool(ViewerToolId.deletePages),
              ),
              _ToolItem(
                'Reverse order',
                Icons.swap_vert_rounded,
                () => tool(ViewerToolId.reverse),
              ),
              _ToolItem(
                'Split PDF',
                Icons.call_split_rounded,
                () => tool(ViewerToolId.split),
                dividerBefore: true,
              ),
              _ToolItem(
                'Extract pages',
                Icons.file_upload_outlined,
                () => tool(ViewerToolId.extract),
              ),
              _ToolItem(
                'Extract odd pages',
                Icons.filter_1_rounded,
                () => extractParity('odd'),
              ),
              _ToolItem(
                'Extract even pages',
                Icons.filter_2_rounded,
                () => extractParity('even'),
              ),
            ],
          ),
          _ToolMenu(
            label: 'Protect',
            icon: Icons.verified_user_outlined,
            enabled: ready,
            items: [
              _ToolItem(
                'Sign',
                Icons.draw_outlined,
                () => tool(ViewerToolId.visualSign),
              ),
              _ToolItem(
                'Encrypt',
                Icons.lock_outline_rounded,
                () => tool(ViewerToolId.protect),
                dividerBefore: true,
              ),
              _ToolItem(
                'Decrypt',
                Icons.lock_open_rounded,
                () => tool(ViewerToolId.unlock),
              ),
              _ToolItem(
                'Edit metadata',
                Icons.info_outline_rounded,
                () => tool(ViewerToolId.metadata),
                dividerBefore: true,
              ),
              _ToolItem(
                'Remove metadata',
                Icons.cleaning_services_outlined,
                () => tool(ViewerToolId.removeMetadata),
              ),
            ],
          ),
          _ToolMenu(
            label: 'Convert',
            icon: Icons.transform_rounded,
            enabled: ready,
            items: [
              _ToolItem(
                'Compress',
                Icons.compress_rounded,
                () => tool(ViewerToolId.compress),
              ),
              _ToolItem(
                'Make searchable (OCR)',
                Icons.document_scanner_outlined,
                () => tool(
                  ocrBlocked
                      ? ViewerToolId.blockedSearchablePdf
                      : ViewerToolId.searchablePdf,
                ),
              ),
              _ToolItem(
                'Export to images',
                Icons.image_outlined,
                () => tool(ViewerToolId.exportImages),
                dividerBefore: true,
              ),
              _ToolItem(
                'Convert to Office',
                Icons.description_outlined,
                () => tool(ViewerToolId.officeConvert),
              ),
              if (onExportText != null)
                _ToolItem('Export text', Icons.notes_rounded, onExportText!),
              _ToolItem(
                'Compare with…',
                Icons.compare_rounded,
                () => tool(ViewerToolId.compare),
                dividerBefore: true,
              ),
            ],
          ),
          const DsToolbarDivider(dense: true),
          DsToolbarIconButton(
            dense: true,
            icon: Icons.rotate_left_rounded,
            tooltip: 'Rotate page left',
            onPressed: ready ? onRotatePageLeft : null,
          ),
          DsToolbarIconButton(
            dense: true,
            icon: Icons.rotate_right_rounded,
            tooltip: 'Rotate page right',
            onPressed: ready ? onRotatePageRight : null,
          ),
          DsToolbarIconButton(
            dense: true,
            icon: Icons.crop_rounded,
            tooltip: 'Crop',
            onPressed: ready ? onCropPage : null,
          ),
          DsToolbarIconButton(
            dense: true,
            icon: Icons.search_rounded,
            tooltip: 'Find (Ctrl+F)',
            onPressed: onSearch,
          ),
          DsToolbarIconButton(
            dense: true,
            key: const Key('pdf_viewer_layers_toggle'),
            icon: annotationsPanelEnabled
                ? Icons.layers_rounded
                : Icons.layers_outlined,
            tooltip: annotationsPanelEnabled ? 'Hide layers' : 'Layers',
            selected: annotationsPanelEnabled,
            onPressed: onToggleAnnotations,
          ),
          const DsToolbarDivider(dense: true),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 32),
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: onToggleToolsRail,
              icon: Icon(
                toolsRailEnabled ? Icons.apps_rounded : Icons.apps_outlined,
                size: 17,
              ),
              label: const Text('Tools'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolItem {
  const _ToolItem(
    this.label,
    this.icon,
    this.onSelected, {
    this.dividerBefore = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;
  final bool dividerBefore;
}

/// Toolbar category: a compact button that drops down its tools right below.
class _ToolMenu extends StatelessWidget {
  const _ToolMenu({
    required this.label,
    required this.icon,
    required this.items,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final List<_ToolItem> items;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 6),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      menuChildren: [
        for (final item in items) ...[
          if (item.dividerBefore) const Divider(height: 9),
          MenuItemButton(
            leadingIcon: Icon(item.icon, size: 18),
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 14),
              ),
            ),
            onPressed: item.onSelected,
            child: Text(item.label, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ],
      builder: (context, menu, _) {
        void toggle() => menu.isOpen ? menu.close() : menu.open();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: TextButton(
            onPressed: enabled ? toggle : null,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: theme.colorScheme.onSurface,
              backgroundColor: menu.isOpen
                  ? theme.colorScheme.primary.withValues(alpha: 0.12)
                  : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 1),
                AnimatedRotation(
                  turns: menu.isOpen ? 0.5 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: const Icon(Icons.expand_more_rounded, size: 16),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
