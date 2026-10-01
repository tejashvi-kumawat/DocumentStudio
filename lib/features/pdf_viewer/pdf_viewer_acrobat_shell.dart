import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/pdf_document_workspace.dart';
import 'package:document_studio/features/pdf_viewer/pdf_outline_panel.dart';
import 'package:document_studio/features/pdf_viewer/pdf_thumbnail_page_action.dart';
import 'package:document_studio/features/pdf_viewer/pdf_thumbnail_sidebar.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_all_tools_rail.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_embedded_tool_panel.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_left_icon_rail.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_attachments_panel.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_acrobat_canvas.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_params_config.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_scroll_layout.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_sidebar_content.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_sidebar_tabs.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_view_rotation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Breakpoint for inline right **All tools** rail (narrow = end drawer).
const kPdfViewerAcrobatToolsRailBreakpoint = 960.0;

/// Acrobat-style viewer chrome: left rail · canvas · right tools rail.
class PdfViewerAcrobatShell extends StatefulWidget {
  const PdfViewerAcrobatShell({
    super.key,
    required this.documentTabId,
    required this.file,
    required this.handoff,

    /// Stable path for PdfViewer ValueKey (session source, not working temp).
    this.viewerIdentityPath,
    this.password,
    this.presentationMode = false,
    this.readMode = false,
    this.leftRailEnabled = true,
    this.toolsRailEnabled = true,
    this.sidebarContent = PdfViewerSidebarContent.thumbnails,
    this.onSidebarContentChanged,
    this.onLeftRailEnabledChanged,
    this.onToolsRailEnabledChanged,
    this.scrollLayoutMode = PdfViewerScrollLayoutMode.continuous,
    this.viewRotation = PdfViewerViewRotation.degrees0,
    this.pagePaintCallbacks,
    this.linkHandlerParams,
    this.onControllerReady,
    this.onOpenContextMenu,
    this.annotationsPanel,
    this.activeToolPanel,
    this.onCloseToolPanel,
    this.pageCount,
    this.selectedPages1Based = const {},
    this.pageOverlaysBuilder,
    this.onReorderPages,
    this.onPageAction,
  });

  final String documentTabId;
  final LocalFileRef file;
  final PdfViewerDocumentHandoff handoff;
  final String? viewerIdentityPath;
  final String? password;
  final bool presentationMode;
  final bool readMode;
  final bool leftRailEnabled;
  final bool toolsRailEnabled;
  final PdfViewerSidebarContent sidebarContent;
  final ValueChanged<PdfViewerSidebarContent>? onSidebarContentChanged;
  final ValueChanged<bool>? onLeftRailEnabledChanged;
  final ValueChanged<bool>? onToolsRailEnabledChanged;
  final PdfViewerScrollLayoutMode scrollLayoutMode;
  final PdfViewerViewRotation viewRotation;
  final List<PdfViewerPagePaintCallback>? pagePaintCallbacks;
  final PdfLinkHandlerParams? linkHandlerParams;
  final void Function(PdfViewerController controller)? onControllerReady;
  final void Function(Offset globalPosition)? onOpenContextMenu;
  final Widget? annotationsPanel;
  final ViewerToolId? activeToolPanel;
  final VoidCallback? onCloseToolPanel;
  final int? pageCount;
  final Set<int> selectedPages1Based;
  final PdfPageOverlaysBuilder? pageOverlaysBuilder;
  final void Function(int fromIndex0, int toIndex0)? onReorderPages;
  final void Function(int page1Based, PdfThumbnailPageAction action)?
  onPageAction;

  @override
  State<PdfViewerAcrobatShell> createState() => PdfViewerAcrobatShellState();
}

class PdfViewerAcrobatShellState extends State<PdfViewerAcrobatShell> {
  /// Direct child of the rail row/column. A key here lets the thumbnail
  /// and tools rails appear or disappear without disposing [PdfViewer].
  static const _canvasSlot = ValueKey<String>('pdf_canvas_slot');
  PdfViewerController? _controller;
  String? _selectedBlockedToolId;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void _handleControllerReady(PdfViewerController controller) {
    setState(() => _controller = controller);
    widget.onControllerReady?.call(controller);
  }

  Future<void> _goToPage(int pageNumber) async {
    await _controller?.goToPage(pageNumber: pageNumber);
  }

  bool _wideLeftRail(double width) =>
      width >= kPdfViewerThumbnailSidebarBreakpoint;

  bool _wideToolsRail(double width) =>
      width >= kPdfViewerAcrobatToolsRailBreakpoint;

  Widget _buildLeftRailBody(PdfViewerController controller) {
    switch (widget.sidebarContent) {
      case PdfViewerSidebarContent.outline:
        return PdfOutlinePanel(
          controller: controller,
          pdfPath: widget.file.path,
        );
      case PdfViewerSidebarContent.attachments:
        return PdfViewerAttachmentsPanel(
          pdfPath: widget.file.path,
          protectedPdfPaths: [
            widget.file.path,
            if (widget.viewerIdentityPath != null) widget.viewerIdentityPath!,
          ],
          reloadToken:
              '${widget.file.sizeBytes ?? 0}:'
              '${widget.file.lastModified?.microsecondsSinceEpoch ?? 0}',
        );
      case PdfViewerSidebarContent.thumbnails:
        return PdfThumbnailSidebar(
          controller: controller,
          onPageSelected: _goToPage,
          onReorderPages: widget.onReorderPages,
          onPageAction: widget.onPageAction,
        );
    }
  }

  Widget _buildLeftRailColumn(
    PdfViewerController controller, {
    bool hideTabs = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark ? DsColors.borderDark : DsColors.borderLight;

    return SizedBox(
      width: PdfThumbnailSidebar.sidebarWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!hideTabs && widget.onSidebarContentChanged != null)
            PdfViewerSidebarTabs(
              content: widget.sidebarContent,
              onContentChanged: widget.onSidebarContentChanged!,
            ),
          Expanded(child: _buildLeftRailBody(controller)),
          Divider(height: 1, color: borderColor),
        ],
      ),
    );
  }

  /// Compact: full-width horizontal page strip under the app bar (not a side column).
  Widget _buildCompactPagesStrip(PdfViewerController controller) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark ? DsColors.borderDark : DsColors.borderLight;
    return Material(
      color: isDark
          ? DsColors.surfaceContainerDark
          : DsColors.surfaceContainerLight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onSidebarContentChanged != null)
            PdfViewerSidebarTabs(
              content: widget.sidebarContent,
              onContentChanged: widget.onSidebarContentChanged!,
            ),
          SizedBox(
            height: PdfThumbnailSidebar.mobileStripHeight,
            child: widget.sidebarContent == PdfViewerSidebarContent.thumbnails
                ? PdfThumbnailSidebar(
                    controller: controller,
                    onPageSelected: _goToPage,
                    scrollAxis: Axis.horizontal,
                    onReorderPages: widget.onReorderPages,
                    onPageAction: widget.onPageAction,
                  )
                : _buildLeftRailBody(controller),
          ),
          Divider(height: 1, color: borderColor),
        ],
      ),
    );
  }

  /// Phone / narrow: the open tool form, full width. Not sized from the
  /// viewport, and never used as a [PdfViewer] key.
  static const phoneToolPanelHeight = 340.0;

  Widget _buildPhoneToolPanel() {
    final tool = widget.activeToolPanel;
    if (tool == null) return const SizedBox.shrink();
    return Material(
      elevation: 2,
      child: SizedBox(
        height: phoneToolPanelHeight,
        child: PdfViewerEmbeddedToolPanel(
          toolId: tool,
          handoff: widget.handoff,
          pageCount: widget.pageCount,
          selectedPages1Based: widget.selectedPages1Based,
          onClose: widget.onCloseToolPanel ?? () {},
        ),
      ),
    );
  }

  Widget _allToolsRail({required bool dismissOnTool}) {
    return PdfViewerAllToolsRail(
      handoff: widget.handoff,
      selectedBlockedToolId: _selectedBlockedToolId,
      onSelectedBlockedToolIdChanged: (id) {
        setState(() => _selectedBlockedToolId = id);
      },
      onClose: () => widget.onToolsRailEnabledChanged?.call(false),
      onToolInvoked: dismissOnTool
          ? () => widget.onToolsRailEnabledChanged?.call(false)
          : null,
    );
  }

  /// Full-height tools list. Stays in the viewer tree so actions see the
  /// open-document tool scope. The shell already ends above the system nav
  /// inset (the status strip below this shell pads for it).
  Widget _buildAllToolsSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetColor = isDark
        ? DsColors.surfaceContainerDark
        : DsColors.surfaceContainerLight;
    return Positioned.fill(
      child: Material(
        key: const Key('acrobat_tools_sheet'),
        color: sheetColor,
        child: _allToolsRail(dismissOnTool: true),
      ),
    );
  }

  Widget? _buildInlineLeftRail(PdfViewerController? controller, bool wide) {
    if (widget.presentationMode ||
        widget.readMode ||
        !widget.leftRailEnabled ||
        !wide ||
        controller == null) {
      return null;
    }
    return RepaintBoundary(
      child: _buildLeftRailColumn(
        controller,
        hideTabs: widget.onSidebarContentChanged != null,
      ),
    );
  }

  Widget? _buildRightToolsPane(bool wide) {
    if (widget.presentationMode ||
        widget.readMode ||
        !widget.toolsRailEnabled ||
        !wide) {
      return null;
    }
    if (widget.activeToolPanel case final tool?) {
      return PdfViewerEmbeddedToolPanel(
        toolId: tool,
        handoff: widget.handoff,
        pageCount: widget.pageCount,
        selectedPages1Based: widget.selectedPages1Based,
        onClose: widget.onCloseToolPanel ?? () {},
      );
    }
    return _allToolsRail(dismissOnTool: false);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wideLeft = _wideLeftRail(width);
    final wideTools = _wideToolsRail(width);
    final compact = !wideLeft;
    final controller = _controller;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark ? DsColors.borderDark : DsColors.borderLight;

    final showCompactPages =
        compact &&
        !widget.presentationMode &&
        !widget.readMode &&
        widget.leftRailEnabled &&
        controller != null;

    final narrowTools =
        !wideTools && !widget.presentationMode && !widget.readMode;
    final showPhoneToolPanel = narrowTools && widget.activeToolPanel != null;
    final showAllToolsSheet =
        narrowTools &&
        widget.toolsRailEnabled &&
        widget.activeToolPanel == null;

    final canvas = ColoredBox(
      color: pdfViewerAcrobatCanvasColor(
        Theme.of(context).brightness,
        presentationMode: widget.presentationMode,
      ),
      child: PdfDocumentWorkspace(
        key: ValueKey(widget.documentTabId),
        documentTabId: widget.documentTabId,
        file: widget.file,
        viewerIdentityPath: widget.viewerIdentityPath ?? widget.file.path,
        password: widget.password,
        embedLeftSidebar: false,
        sidebarEnabled: false,
        sidebarContent: widget.sidebarContent,
        scrollLayoutMode: widget.scrollLayoutMode,
        viewRotation: widget.viewRotation,
        pagePaintCallbacks: widget.pagePaintCallbacks,
        linkHandlerParams: widget.linkHandlerParams,
        pageOverlaysBuilder: widget.pageOverlaysBuilder,
        onControllerReady: _handleControllerReady,
        onOpenContextMenu: widget.onOpenContextMenu,
        canvasMargin: !widget.presentationMode && !widget.readMode,
        immersiveSinglePage: widget.presentationMode,
        presentationAdvanceOnTap: widget.presentationMode,
      ),
    );

    // Phone: pages strip + canvas. All tools is a bottom sheet, not a side
    // column and not the desktop document-tab strip.
    if (compact) {
      return Scaffold(
        key: _scaffoldKey,
        body: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showCompactPages) _buildCompactPagesStrip(controller),
                Expanded(key: _canvasSlot, child: canvas),
                if (showPhoneToolPanel) _buildPhoneToolPanel(),
              ],
            ),
            if (showAllToolsSheet) _buildAllToolsSheet(),
          ],
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      body: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.presentationMode &&
                  !widget.readMode &&
                  wideLeft &&
                  widget.onSidebarContentChanged != null)
                PdfViewerLeftIconRail(
                  content: widget.sidebarContent,
                  onContentChanged: (next) {
                    widget.onSidebarContentChanged!(next);
                    widget.onLeftRailEnabledChanged?.call(true);
                  },
                  expanded: widget.leftRailEnabled,
                  onToggleExpanded: widget.onLeftRailEnabledChanged == null
                      ? null
                      : () => widget.onLeftRailEnabledChanged!(
                          !widget.leftRailEnabled,
                        ),
                ),
              if (_buildInlineLeftRail(controller, wideLeft)
                  case final left?) ...[
                left,
                VerticalDivider(width: 1, thickness: 1, color: dividerColor),
              ],
              Expanded(
                key: _canvasSlot,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: canvas),
                          if (widget.annotationsPanel case final panel?)
                            SizedBox(width: 280, child: panel),
                        ],
                      ),
                    ),
                    if (showPhoneToolPanel) _buildPhoneToolPanel(),
                  ],
                ),
              ),
              if (_buildRightToolsPane(wideTools) case final tools?) ...[
                VerticalDivider(width: 1, thickness: 1, color: dividerColor),
                tools,
              ],
            ],
          ),
          if (showAllToolsSheet) _buildAllToolsSheet(),
        ],
      ),
    );
  }

  /// Opens the tools list on narrow layouts (in-tree sheet; no side drawer).
  void openToolsDrawer() {
    if (_wideToolsRail(MediaQuery.sizeOf(context).width)) return;
    widget.onToolsRailEnabledChanged?.call(true);
  }

  /// Opens the left pages strip on narrow layouts (inline; no side drawer).
  void openLeftDrawer() {
    if (_wideLeftRail(MediaQuery.sizeOf(context).width)) return;
  }
}
