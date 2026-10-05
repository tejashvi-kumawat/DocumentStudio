import 'dart:math' as math;

import 'package:document_studio/features/pdf_viewer/pdf_viewer_vertical_zoom_bar.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/pdf_document_workspace.dart';
import 'package:document_studio/features/pdf_viewer/pdf_outline_panel.dart';
import 'package:document_studio/features/pdf_viewer/pdf_thumbnail_page_action.dart';
import 'package:document_studio/features/pdf_viewer/pdf_thumbnail_sidebar.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_scaffold.dart';
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
    this.contextMenuBuilder,
    this.searchPanel,
    this.bookmarksBuilder,
    this.annotationsPanel,
    this.activeToolPanel,
    this.editContext,
    this.editHasSelection,
    this.railControls,
    this.onCloseToolPanel,
    this.pageCount,
    this.selectedPages1Based = const {},
    this.pageOverlaysBuilder,
    this.onReorderPages,
    this.onPageAction,
    this.canvasOverlay,
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
  final PdfViewerContextMenuBuilder? contextMenuBuilder;

  /// Left-rail search results (built by the screen that owns the searcher).
  final Widget? searchPanel;

  /// Editable bookmarks panel; falls back to the read-only outline.
  final Widget Function(PdfViewerController controller)? bookmarksBuilder;
  final Widget? annotationsPanel;
  final ViewerToolId? activeToolPanel;

  /// Edit mode shows no side form until an object is selected: this notifies
  /// when selection changes and [editHasSelection] says whether one exists.
  final Listenable? editContext;

  /// Page / zoom / view controls for the left icon rail.
  final Widget? railControls;
  final bool Function()? editHasSelection;
  final VoidCallback? onCloseToolPanel;
  final int? pageCount;
  final Set<int> selectedPages1Based;
  final PdfPageOverlaysBuilder? pageOverlaysBuilder;
  final void Function(int fromIndex0, int toIndex0)? onReorderPages;
  final void Function(int page1Based, PdfThumbnailPageAction action)?
  onPageAction;

  /// Drawn on the page only (draw button). Not over the tool row, the page
  /// strip, or the Tools rail.
  final Widget? canvasOverlay;

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

  /// User-resizable panes (drag the divider). Thumbnails keep their fixed
  /// width because their layout is sized to it.
  double _toolsPaneWidth = viewerAcrobatOptionsWidth;
  double _sidePaneWidth = 280;

  double get _leftWidth =>
      widget.sidebarContent == PdfViewerSidebarContent.thumbnails
          ? PdfThumbnailSidebar.sidebarWidth
          : _sidePaneWidth;

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
        final custom = widget.bookmarksBuilder;
        if (custom != null) return custom(controller);
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
      case PdfViewerSidebarContent.search:
        return widget.searchPanel ?? const SizedBox.shrink();
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
      width: _leftWidth,
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

  /// Preferred height of the open tool form under the page on a narrow
  /// window. Shorter windows use half the column so the page stays visible.
  static const phoneToolPanelHeight = 340.0;

  double _sheetHeight(double maxHeight) {
    if (!maxHeight.isFinite || maxHeight <= 0) return 0;
    return math.min(phoneToolPanelHeight, maxHeight * 0.5);
  }

  /// Tabs + thumbnail strip + divider. Used only to decide whether the strip
  /// fits; the strip widget keeps its own height.
  double _compactStripExtent() {
    final tabs = widget.onSidebarContentChanged != null ? 36.0 : 0.0;
    return tabs + PdfThumbnailSidebar.mobileStripHeight + 1;
  }

  Widget _buildPhoneToolPanel() {
    final tool = widget.activeToolPanel;
    if (tool == null) return const SizedBox.shrink();
    return Material(
      elevation: 2,
      child: PdfViewerEmbeddedToolPanel(
        toolId: tool,
        handoff: widget.handoff,
        pageCount: widget.pageCount,
        selectedPages1Based: widget.selectedPages1Based,
        onClose: widget.onCloseToolPanel ?? () {},
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
    // Edit's panel also loads the page objects, so it stays mounted even
    // with the tools rail switched off.
    final editing = widget.activeToolPanel == ViewerToolId.editText;
    if (widget.presentationMode ||
        widget.readMode ||
        (!widget.toolsRailEnabled && !editing) ||
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
        contextMenuBuilder: widget.contextMenuBuilder,
        canvasMargin: !widget.presentationMode && !widget.readMode,
        immersiveSinglePage: widget.presentationMode,
        presentationAdvanceOnTap: widget.presentationMode,
      ),
    );

    final overlay = widget.canvasOverlay;
    final zoomBar = controller != null &&
            !widget.presentationMode &&
            !widget.readMode
        ? PdfViewerVerticalZoomBar(controller: controller)
        : null;
    // Always a Stack: switching between canvas-only and Stack when the
    // controller arrives would remount the viewer.
    final page = Stack(
      fit: StackFit.expand,
      children: [canvas, ?overlay, ?zoomBar],
    );

    // Phone: pages strip + canvas. The tool form is full width and at most
    // half the column, so a short phone (or a short desktop window) still
    // shows the page. All tools is a sheet, not a side column.
    if (compact) {
      return Scaffold(
        key: _scaffoldKey,
        body: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final maxH = constraints.maxHeight;
                final panelH = showPhoneToolPanel ? _sheetHeight(maxH) : 0.0;
                final showStrip =
                    showCompactPages &&
                    maxH - panelH >= _compactStripExtent() + 64;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showStrip) _buildCompactPagesStrip(controller),
                    Expanded(key: _canvasSlot, child: page),
                    if (panelH > 0)
                      SizedBox(height: panelH, child: _buildPhoneToolPanel()),
                  ],
                );
              },
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
                    // Click the active icon again to close the panel.
                    if (next == widget.sidebarContent && widget.leftRailEnabled) {
                      widget.onLeftRailEnabledChanged?.call(false);
                      return;
                    }
                    widget.onSidebarContentChanged!(next);
                    widget.onLeftRailEnabledChanged?.call(true);
                  },
                  expanded: widget.leftRailEnabled,
                  controls: widget.railControls,
                  onToggleExpanded: widget.onLeftRailEnabledChanged == null
                      ? null
                      : () => widget.onLeftRailEnabledChanged!(
                          !widget.leftRailEnabled,
                        ),
                ),
              if (_buildInlineLeftRail(controller, wideLeft)
                  case final left?) ...[
                left,
                if (widget.sidebarContent == PdfViewerSidebarContent.thumbnails)
                  VerticalDivider(width: 1, thickness: 1, color: dividerColor)
                else
                  _ResizeHandle(
                    color: dividerColor,
                    onDrag: (dx) => setState(
                      () => _sidePaneWidth =
                          (_sidePaneWidth + dx).clamp(220.0, 520.0),
                    ),
                  ),
              ],
              Expanded(
                key: _canvasSlot,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final panelH = showPhoneToolPanel
                        ? _sheetHeight(constraints.maxHeight)
                        : 0.0;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: page),
                              if (widget.annotationsPanel case final panel?)
                                SizedBox(width: 280, child: panel),
                            ],
                          ),
                        ),
                        if (panelH > 0)
                          SizedBox(
                            height: panelH,
                            child: _buildPhoneToolPanel(),
                          ),
                      ],
                    );
                  },
                ),
              ),
              if (_buildRightToolsPane(wideTools) case final tools?)
                ListenableBuilder(
                  listenable: widget.editContext ?? const _NeverListenable(),
                  builder: (context, _) {
                    final editing =
                        widget.activeToolPanel == ViewerToolId.editText;
                    final show = !editing ||
                        (widget.editHasSelection?.call() ?? true);
                    final paneW =
                        widget.activeToolPanel == ViewerToolId.workspaceReorder
                            ? math.max(
                                _toolsPaneWidth,
                                (MediaQuery.sizeOf(context).width * 0.58)
                                    .clamp(420.0, 980.0),
                              )
                            : _toolsPaneWidth;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (show)
                          _ResizeHandle(
                            key: const ValueKey('tools-handle'),
                            color: dividerColor,
                            onDrag: (dx) => setState(
                              () => _toolsPaneWidth =
                                  (_toolsPaneWidth - dx).clamp(300.0, 640.0),
                            ),
                          ),
                        // Stays mounted (Offstage) so Edit keeps loading and
                        // saving objects while no form is shown.
                        SizedBox(
                          key: const ValueKey('tools-pane'),
                          width: show ? paneW : 0,
                          child: Offstage(
                            offstage: !show,
                            child: ViewerOptionsWidthScope(
                              width: widget.activeToolPanel ==
                                      ViewerToolId.workspaceReorder
                                  ? double.infinity
                                  : _toolsPaneWidth,
                              child: tools,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
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


/// Thin draggable divider between panes.
class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({super.key, required this.color, required this.onDrag});

  final Color color;
  final ValueChanged<double> onDrag;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _hot = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hot = true),
      onExit: (_) => setState(() => _hot = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        child: SizedBox(
          width: 7,
          child: Center(
            child: Container(
              width: _hot ? 3 : 1,
              color: _hot ? DsColors.primary : widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

class _NeverListenable implements Listenable {
  const _NeverListenable();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}
