import 'package:document_studio/app/keyboard/text_input_guard.dart';

import 'dart:async';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/errors/document_studio_error_ui.dart';
import 'package:document_studio/core/pdf/pdf_document_cache.dart';
import 'package:document_studio/core/pdf/pdf_open_limits.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/organize/organize_page_ref.dart';
import 'package:document_studio/features/document_lifecycle/document_session.dart';
import 'package:document_studio/features/document_lifecycle/document_session_autosave.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_page_organize_logic.dart';
import 'package:document_studio/features/pdf_viewer/pdf_thumbnail_page_action.dart';
import 'package:document_studio/features/page_management/pdf_password_prompt.dart';
import 'package:document_studio/features/pdf_viewer/document_tabs_controller.dart';
import 'package:document_studio/features/pdf_viewer/pdf_document_tab_bar.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_acrobat_shell.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_all_tools_rail.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_embed.dart';
import 'package:document_studio/features/pdf_viewer/document_properties_dialog.dart';
import 'package:document_studio/features/pdf_viewer/pdf_link_handler.dart';
import 'package:document_studio/features/pdf_viewer/pdf_ocr_find_highlight.dart';
import 'package:document_studio/features/pdf_viewer/pdf_ocr_page_searcher.dart';
import 'package:document_studio/features/pdf_viewer/pdf_search_flow.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_fit_display.dart';
import 'package:document_studio/features/pdf_viewer/pdf_search_match_bar.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_sidebar_content.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_shell_page.dart';
import 'package:document_studio/features/form_sign/sign_placement_bridge.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_acrobat_top_chrome.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_markup_palette.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_tool_row.dart';
import 'package:document_studio/features/annotations/markup/markup_dialogs.dart';
import 'package:document_studio/features/annotations/markup/markup_editor_controller.dart';
import 'package:document_studio/features/annotations/markup/markup_keyboard.dart';
import 'package:document_studio/features/annotations/markup/markup_layers_panel.dart';
import 'package:document_studio/features/annotations/markup/markup_page_layer.dart';
import 'package:document_studio/features/annotations/markup/markup_providers.dart';
import 'package:document_studio/features/annotations/markup/markup_tool.dart';
import 'package:document_studio/features/pdf_viewer/pdf_go_to_page_dialog.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_controller_safe.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_page_shortcuts.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_read_shortcuts.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_zoom_controls.dart';
import 'package:document_studio/features/pdf_viewer/viewer_shortcut_actions.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_shortcuts.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_params_config.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_presentation_mode.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_read_mode.dart';
import 'package:document_studio/features/pdf_viewer/pdf_page_labels.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_scroll_layout.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_view_rotation.dart';
import 'package:document_studio/features/print/print_exception.dart';
import 'package:document_studio/features/print/pdf_print_button.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_tool_panel_scope.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_loading_placeholder.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_tab_open_session.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:flutter/services.dart';
import 'package:document_studio/infrastructure/ocr/pdf_background_ocr_index.dart';
import 'package:document_studio/features/pdf_viewer/widgets/viewer_live_page_overlay.dart';
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_soft_reload.dart';
import 'package:document_studio/infrastructure/ocr/ocr_providers.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfViewerScreen extends ConsumerStatefulWidget {
  const PdfViewerScreen({super.key, required this.file, this.password})
    : shellEmbedded = false,
      tabId = null,
      foreground = true;

  /// Viewer bound to one document tab. The tab shell keeps several alive in
  /// an [IndexedStack]; only the [foreground] one registers global shortcuts.
  const PdfViewerScreen.shellEmbedded({
    super.key,
    this.tabId,
    this.foreground = true,
  }) : file = null,
       password = null,
       shellEmbedded = true;

  final LocalFileRef? file;
  final String? password;
  final bool shellEmbedded;
  final String? tabId;
  final bool foreground;

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen> {
  PdfViewerController? _controller;
  PdfTextSearcher? _searcher;
  List<PdfViewerPagePaintCallback>? _searchPagePaintCallbacks;
  bool _searchPaintCallbacksRebuildScheduled = false;
  bool _tabsRebuildScheduled = false;
  bool _searchUiVisible = false;
  String _searchQuery = '';
  final FocusNode _findFocusNode = FocusNode();

  /// OCR-index page hits when the text layer has no matches (1-based).
  List<int> _ocrFindPages = const [];
  int _ocrFindIndex = 0;

  /// Thumbnails are opt-in via the toolbar; open documents in continuous page view.
  bool _sidebarEnabled = false;
  bool _toolsRailEnabled = true;
  ViewerToolId? _activeViewerTool;
  PdfViewerSidebarContent _sidebarContent = PdfViewerSidebarContent.thumbnails;
  final _acrobatShellKeysByTabId =
      <String, GlobalKey<PdfViewerAcrobatShellState>>{};
  PdfLinkHandlerParams? _linkHandlerParams;

  /// While a page tool is active, existing links sit under its overlay so
  /// clicks place / draw instead of following the link.
  PdfLinkHandlerParams? _linkHandlerParamsUnderTools;
  bool _annotationsPanelEnabled = false;

  /// DS-READ-006 — presentation: one page, black surround; restores page/zoom on exit.
  bool _presentationMode = false;
  PdfViewerPresentationSnapshot? _presentationSnapshot;

  /// Read mode: hide tools rail + thumbnails; page fills canvas.
  bool _readMode = false;
  final PdfViewerScrollLayoutMode _scrollLayoutMode =
      PdfViewerScrollLayoutMode.continuous;
  final PdfViewerViewRotation _viewRotation = PdfViewerViewRotation.degrees0;
  final Map<String, PdfViewerTabOpenSession> _openSessions = {};
  int? _lastSoftReloadRevision;
  String? _lastSoftReloadPath;
  PdfBackgroundOcrIndex? _backgroundOcr;
  bool _softReloadInFlight = false;
  String? _ocrIndexedPath;

  DocumentTabsController? _tabsController;
  ViewerShortcutActionsNotifier? _viewerShortcutsNotifier;
  bool _sidebarDefaultApplied = false;
  String? _registeredShortcutsFilePath;

  late final MarkupEditorController _markup = ref.read(markupEditorProvider);
  void _markupPaint(Canvas canvas, Rect pageRect, PdfPage page) {
    if (!identical(_markup.session, _markupBoundSession)) return;
    _markup.paintMultiply(canvas, pageRect, page.pageNumber);
  }

  List<PdfViewerPagePaintCallback>? _paintCallbacksSource;
  List<PdfViewerPagePaintCallback>? _paintCallbacks;
  bool _markupCanUndo = false;
  bool _markupCanRedo = false;
  DocumentSession? _markupBoundSession;

  /// Markup (multiply-blended highlights) first, search hits on top.
  List<PdfViewerPagePaintCallback> get _pagePaintCallbacks {
    final src = _searchPagePaintCallbacks;
    final cached = _paintCallbacks;
    if (cached != null && identical(src, _paintCallbacksSource)) return cached;
    _paintCallbacksSource = src;
    return _paintCallbacks = [_markupPaint, ...?src];
  }

  void _onMarkupChanged() {
    if (!mounted) return;
    final u = _markup.canUndo, r = _markup.canRedo;
    if (u == _markupCanUndo && r == _markupCanRedo) return;
    _markupCanUndo = u;
    _markupCanRedo = r;
    setState(() {});
  }

  /// The markup editor is shared by all live viewers; only the foreground one
  /// may bind it, and it rebinds whenever it comes back to the front.
  void _bindMarkup(DocumentSession session) {
    if (!widget.foreground) return;
    if (identical(_markupBoundSession, session) &&
        identical(_markup.session, session)) {
      return;
    }
    _markupBoundSession = session;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !widget.foreground ||
          !identical(_markupBoundSession, session) ||
          identical(_markup.session, session)) {
        return;
      }
      _markup.onMultiplyChanged = () {
        final c = _controller;
        if (c != null && c.isReady) c.invalidate();
      };
      _markup.bind(session, commit: (bytes) => _commitMarkup(session, bytes));
    });
  }

  Future<bool> _commitMarkup(DocumentSession session, Uint8List bytes) async {
    if (!mounted) return false;
    final saved = await commitBytesToSession(
      context: context,
      storage: ref.read(fileStorageProvider),
      tabs: ref.read(documentTabsControllerProvider),
      session: session,
      bytes: bytes,
      successMessage: '',
      silent: true,
    );
    return saved != null;
  }

  static MarkupTool? _markupToolFor(ViewerToolId tool, LiveDrawTool? draw) {
    return switch (tool) {
      ViewerToolId.editText => MarkupTool.text,
      ViewerToolId.addLink => MarkupTool.link,
      ViewerToolId.placeImage => MarkupTool.image,
      ViewerToolId.ink => switch (draw) {
        LiveDrawTool.highlighter => MarkupTool.highlighter,
        LiveDrawTool.line => MarkupTool.line,
        LiveDrawTool.arrow => MarkupTool.arrow,
        LiveDrawTool.rectangle => MarkupTool.rectangle,
        LiveDrawTool.ellipse => MarkupTool.ellipse,
        LiveDrawTool.callout => MarkupTool.callout,
        _ => MarkupTool.pen,
      },
      _ => null,
    };
  }

  static bool _isMarkupTool(ViewerToolId? tool) =>
      tool == ViewerToolId.markupBurn ||
      tool == ViewerToolId.ink ||
      tool == ViewerToolId.editText ||
      tool == ViewerToolId.addLink ||
      tool == ViewerToolId.placeImage;

  /// Opens the markup editor (side panel + editable page objects).
  void _openMarkup([MarkupTool? tool]) {
    ref.read(viewerLiveToolSessionProvider).deactivate();
    _markup.enterEditMode(tool ?? _markup.tool);
    setState(() {
      _activeViewerTool = ViewerToolId.markupBurn;
      _toolsRailEnabled = true;
      _readMode = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _markup.keyboardFocus.requestFocus();
    });
  }

  /// Arms a pencil/edit markup tool on the open page. Does not open a side
  /// panel and does not change the current page.
  void _armPageMarkup(MarkupTool tool) {
    ref.read(viewerLiveToolSessionProvider).deactivate();
    _markup.setTool(tool);
    setState(() {
      _activeViewerTool = null;
      _readMode = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _markup.keyboardFocus.requestFocus();
    });
  }

  int? _pageCountOrNull() {
    final c = _controller;
    if (c == null) return null;
    final snap = PdfViewerControllerNavSnapshot.of(c);
    return snap.isReady ? snap.pageCount : null;
  }

  late final MarkupPageActions _markupActions = MarkupPageActions(
    activateLink: (link) {
      if (link.isUri) {
        unawaited(openMarkupLinkUri(context, link));
        return;
      }
      final page = link.destPage;
      final c = _controller;
      if (page == null || c == null || !c.isReady) return;
      unawaited(c.goToPage(pageNumber: page.clamp(1, c.pageCount)));
    },
    editLink: (link, {required bool isNew}) => showMarkupLinkDialog(
      context,
      link: link,
      pageCount: _pageCountOrNull() ?? 1,
      isNew: isNew,
    ),
    pickImage: () => pickMarkupImage(context, ref.read(fileStorageProvider)),
  );

  /// Scrolls so [bounds] (display points on [page]) is visible.
  Future<void> _revealMarkup(int page, Rect bounds) async {
    if (!_isMarkupTool(_activeViewerTool)) _openMarkup();
    final c = _controller;
    if (c == null || !c.isReady) return;
    final geo = _markup.geometryOf(page);
    final layouts = c.layout.pageLayouts;
    if (geo == null || page < 1 || page > layouts.length) {
      await c.goToPage(pageNumber: page);
      return;
    }
    final pl = layouts[page - 1];
    final s = pl.width / geo.displayWidth;
    final target = Rect.fromLTWH(
      pl.left + bounds.left * s,
      pl.top + bounds.top * s,
      bounds.width * s,
      bounds.height * s,
    );
    await c.ensureVisible(target, margin: 48);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_sidebarDefaultApplied) {
      _sidebarDefaultApplied = true;
      final width = MediaQuery.sizeOf(context).width;
      if (width < kPdfViewerThumbnailSidebarBreakpoint) {
        _sidebarEnabled = false;
      }
      if (width < kPdfViewerAcrobatToolsRailBreakpoint) {
        _toolsRailEnabled = false;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _linkHandlerParams = PdfLinkHandlerParams(onLinkTap: _onPdfLinkTap);
    _linkHandlerParamsUnderTools = PdfLinkHandlerParams(
      onLinkTap: _onPdfLinkTap,
      laidOverPageOverlays: false,
    );
    _viewerShortcutsNotifier = ref.read(viewerShortcutActionsProvider.notifier);
    _markup.addListener(_onMarkupChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tabsController = ref.read(documentTabsControllerProvider);
      _tabsController!.addListener(_onTabsChanged);
      if (widget.shellEmbedded) {
        final tab = _boundTab(_tabsController!);
        if (tab != null) {
          _validateTab(tab);
        }
      } else if (widget.file != null) {
        _tabsController!.openDocument(widget.file!, password: widget.password);
        final tab = ref.read(documentTabsControllerProvider).activeTab;
        if (tab != null) {
          _validateTab(tab);
        }
      }
      _consumePendingViewerToolPanel();
    });
  }

  void _consumePendingViewerToolPanel() {
    final tabs = ref.read(documentTabsControllerProvider);
    if (widget.tabId != null &&
        (tabs.isHomeActive || tabs.activeTab?.id != widget.tabId)) {
      return;
    }
    final pending = tabs.takePendingViewerToolPanel();
    if (pending == null || !mounted) return;
    setState(() {
      _activeViewerTool = pending;
      _toolsRailEnabled = true;
    });
  }

  void _leaveViewer() {
    if (widget.shellEmbedded) {
      ref.read(documentTabsControllerProvider).showHome();
      return;
    }
    ref.read(viewerShortcutActionsProvider.notifier).clear();
    context.pop();
  }

  void _onSignPlacementCancel() {
    ref.read(signPlacementControllerProvider).cancelPageInteraction();
  }

  void _onSignPlacementDone() {
    final c = ref.read(signPlacementControllerProvider);
    if (c.hasItems) {
      c.requestApply();
      return;
    }
    c.cancelPageInteraction();
  }

  String _signPlacementStatusLabel(SignPlacementController c) {
    if (c.drawFieldMode) return 'Draw signature field';
    if (c.armed != null) return 'Drag to place “${c.armed!.label}”';
    if (c.items.length > 1) {
      return '${c.items.length} items · adjust then Done';
    }
    return 'Adjust signature';
  }

  PdfViewerTabOpenSession _sessionFor(PdfViewerTab tab) {
    return _openSessions.putIfAbsent(tab.id, PdfViewerTabOpenSession.new);
  }

  void _pruneOpenSessions() {
    final ids = ref
        .read(documentTabsControllerProvider)
        .tabs
        .map((t) => t.id)
        .toSet();
    final dropped = <PdfViewerTabOpenSession>[];
    _openSessions.removeWhere((id, session) {
      if (ids.contains(id)) return false;
      dropped.add(session);
      return true;
    });
    for (final s in dropped) {
      s.releaseWarmLease();
    }
    _acrobatShellKeysByTabId.removeWhere((id, _) => !ids.contains(id));
  }

  GlobalKey<PdfViewerAcrobatShellState> _acrobatShellKeyFor(String tabId) {
    return _acrobatShellKeysByTabId.putIfAbsent(
      tabId,
      () => GlobalKey<PdfViewerAcrobatShellState>(
        debugLabel: 'acrobatShell_$tabId',
      ),
    );
  }

  Future<void> _validateTab(PdfViewerTab tab) async {
    // A newly opened tab gets its own screen, which validates it.
    if (widget.tabId != null && tab.id != widget.tabId) return;
    final session = _sessionFor(tab);
    if (session.validating || session.validated) return;

    setState(() {
      session.validating = true;
      session.error = null;
    });

    final tooLarge = pdfOpenLimitErrorForFile(tab.file);
    if (tooLarge != null) {
      session.releaseWarmLease();
      session.error = tooLarge;
      session.validating = false;
      if (mounted) setState(() {});
      return;
    }

    // One acquire: validation success *is* the warm pin the viewer reuses.
    // (Previously validateOpenable opened+released, then we acquired again.)
    var resolved = session.resolvedPassword ?? tab.password;
    while (true) {
      try {
        session.releaseWarmLease();
        session.warmLease = await PdfDocumentCache.instance.acquire(
          // Prefer resolved source so hardlink working path shares the inode
          // cache entry; never open a portal FUSE path.
          tab.session.sourcePath,
          password: resolved,
        );
        break;
      } on PdfPasswordException catch (e) {
        if (!mounted) {
          session.releaseWarmLease();
          return;
        }
        final entered = await promptPdfPassword(context);
        if (!mounted) {
          session.releaseWarmLease();
          return;
        }
        if (entered == null || entered.isEmpty) {
          session.releaseWarmLease();
          session.error = DocumentStudioError(
            code: DocumentStudioErrorCode.passwordRequired,
            message: e.toString(),
            cause: e,
          );
          session.validating = false;
          if (mounted) setState(() {});
          return;
        }
        resolved = entered;
      } on PdfException catch (e) {
        session.releaseWarmLease();
        final msg = e.toString().toLowerCase();
        session.error = DocumentStudioError(
          code: msg.contains('password')
              ? DocumentStudioErrorCode.passwordRequired
              : DocumentStudioErrorCode.invalidPdf,
          message: e.toString(),
          cause: e,
        );
        session.validating = false;
        if (mounted) setState(() {});
        return;
      } catch (e) {
        session.releaseWarmLease();
        session.error = DocumentStudioError(
          code: DocumentStudioErrorCode.renderFailed,
          message: e.toString(),
          cause: e,
        );
        session.validating = false;
        if (mounted) setState(() {});
        return;
      }
    }

    if (!mounted) {
      session.releaseWarmLease();
      return;
    }

    // Recents must track the user's file, never a session temp working copy.
    final recent = tab.session.sourceFile;
    if (!recent.path.contains('${Platform.pathSeparator}ds_sess_')) {
      await ref.read(recentsProvider.notifier).addRecent(recent);
    }
    if (!mounted) {
      session.releaseWarmLease();
      return;
    }
    session.validated = true;
    session.resolvedPassword = resolved;
    session.error = null;
    session.validating = false;
    if (resolved != null &&
        resolved.isNotEmpty &&
        (tab.password == null || tab.password!.isEmpty)) {
      tab.session.password = resolved;
    }
    if (mounted) setState(() {});
  }

  Future<void> _openAnotherPdfInTab() async {
    final storage = ref.read(fileStorageProvider);
    try {
      final picked = await storage.pickOpenFile(allowedExtensions: ['pdf']);
      if (picked == null || !mounted) return;
      ref.read(documentTabsControllerProvider).openDocument(picked);
      final active = ref.read(documentTabsControllerProvider).activeTab;
      if (active != null) {
        await _validateTab(active);
      }
    } on DocumentStudioError catch (e) {
      if (!mounted) return;
      showDocumentStudioErrorSnackBar(context, e);
    }
  }

  Future<void> _pickAnotherFileForViewer() async {
    final active = _activeTab;
    if (active == null) return;
    final storage = ref.read(fileStorageProvider);
    try {
      final picked = await storage.pickOpenFile(allowedExtensions: ['pdf']);
      if (picked == null || !mounted) return;
      _openSessions.remove(active.id);
      ref.read(documentTabsControllerProvider).replaceActiveDocument(picked);
      final replaced = ref.read(documentTabsControllerProvider).activeTab;
      if (replaced != null) {
        await _validateTab(replaced);
      }
    } on DocumentStudioError catch (e) {
      if (!mounted) return;
      showDocumentStudioErrorSnackBar(context, e);
    }
  }

  Future<void> _unlockCurrentFile() async {
    if (_activeTab == null || !mounted) return;
    openViewerToolPanel(context, ViewerToolId.unlock);
  }

  Future<void> _promptPasswordAndRetry() async {
    final active = _activeTab;
    if (active == null) return;
    final password = await promptPdfPassword(context);
    if (password == null || !mounted) return;
    final session = _sessionFor(active);
    session.resolvedPassword = password;
    session.validated = false;
    session.error = null;
    ref
        .read(documentTabsControllerProvider)
        .openDocument(active.file, password: password);
    await _validateTab(active);
  }

  void _onTabsChanged() {
    _pruneOpenSessions();
    final active = _boundTab(ref.read(documentTabsControllerProvider));
    if (active != null) {
      final session = _sessionFor(active);
      if (!session.validated && !session.validating) {
        _validateTab(active);
      }
    }
    _consumePendingViewerToolPanel();
    if (!mounted || _tabsRebuildScheduled) return;
    _tabsRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tabsRebuildScheduled = false;
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant PdfViewerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shellEmbedded) {
      if (oldWidget.foreground != widget.foreground) {
        _registeredShortcutsFilePath = null;
        // Live page tools share one overlay session across viewers.
        if (!widget.foreground &&
            _activeViewerTool != ViewerToolId.markupBurn &&
            viewerToolUsesLivePageOverlay(_activeViewerTool)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !widget.foreground) _closeActiveToolPanel();
          });
        }
      }
      return;
    }
    if (oldWidget.file?.path != widget.file?.path && widget.file != null) {
      _registeredShortcutsFilePath = null;
      _searcher?.dispose();
      _searcher = null;
      _searchPagePaintCallbacks = null;
      _searchUiVisible = false;
      _controller = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(documentTabsControllerProvider)
            .openDocument(widget.file!, password: widget.password);
        final tab = ref.read(documentTabsControllerProvider).activeTab;
        if (tab != null) {
          _validateTab(tab);
        }
      });
    }
  }

  @override
  void dispose() {
    // Do not clear viewerShortcutActionsProvider here — shell may still need
    // Ctrl+F / Save until another viewer registers or the tab shell clears.
    _tabsController?.removeListener(_onTabsChanged);
    _markup.removeListener(_onMarkupChanged);
    _markup.onMultiplyChanged = null;
    final markup = _markup;
    // Listeners may belong to widgets unmounting in this same frame.
    scheduleMicrotask(() {
      markup.exitEditMode();
      unawaited(markup.flush());
    });
    _detachControllerListener();
    _searcher?.dispose();
    _findFocusNode.dispose();
    _backgroundOcr?.cancel();
    for (final s in _openSessions.values) {
      s.releaseWarmLease();
    }
    super.dispose();
  }

  void _onPdfLinkTap(PdfLink link) {
    final controller = _controller;
    if (controller == null || !mounted) return;
    handlePdfViewerLinkTap(
      context: context,
      controller: controller,
      link: link,
    );
  }

  void _closeSearch() {
    setState(() {
      _searchUiVisible = false;
      _searchQuery = '';
      _ocrFindPages = const [];
      _ocrFindIndex = 0;
    });
    _searcher?.resetTextSearch();
    _syncSearchPagePaintCallbacks();
  }

  void _clearOcrFindHits() {
    if (_ocrFindPages.isEmpty) return;
    _ocrFindPages = const [];
    _ocrFindIndex = 0;
    _syncSearchPagePaintCallbacks();
  }

  void _syncSearchPagePaintCallbacks() {
    final searcher = _searcher;
    if (searcher == null) {
      _searchPagePaintCallbacks = null;
      return;
    }
    _searchPagePaintCallbacks = [
      searcher.pageTextMatchPaintCallback,
      paintOcrFindPageHits(
        hitPages1Based: _ocrFindPages,
        currentPage1Based: _ocrFindPages.isEmpty
            ? null
            : _ocrFindPages[_ocrFindIndex],
      ),
    ];
  }

  void _goToNextFindMatch() {
    final searcher = _searcher;
    if (searcher != null && searcher.matches.isNotEmpty) {
      searcher.goToNextMatch();
      return;
    }
    if (_ocrFindPages.isEmpty) return;
    setState(() {
      _ocrFindIndex = (_ocrFindIndex + 1) % _ocrFindPages.length;
      _syncSearchPagePaintCallbacks();
    });
    unawaited(
      _controller?.goToPage(pageNumber: _ocrFindPages[_ocrFindIndex]) ??
          Future<void>.value(),
    );
  }

  void _goToPrevFindMatch() {
    final searcher = _searcher;
    if (searcher != null && searcher.matches.isNotEmpty) {
      searcher.goToPrevMatch();
      return;
    }
    if (_ocrFindPages.isEmpty) return;
    setState(() {
      _ocrFindIndex =
          (_ocrFindIndex - 1 + _ocrFindPages.length) % _ocrFindPages.length;
      _syncSearchPagePaintCallbacks();
    });
    unawaited(
      _controller?.goToPage(pageNumber: _ocrFindPages[_ocrFindIndex]) ??
          Future<void>.value(),
    );
  }

  Future<void> _applyOcrFindForQuery(String query) async {
    final pages = _backgroundOcr?.findAllPageNumbers(query) ?? const <int>[];
    if (!mounted) return;
    if (pages.isNotEmpty) {
      setState(() {
        _ocrFindPages = pages;
        _ocrFindIndex = 0;
        _syncSearchPagePaintCallbacks();
      });
      await _controller?.goToPage(pageNumber: pages.first);
      return;
    }
    _clearOcrFindHits();
    if (_backgroundOcr?.isRunning == true) {
      if (mounted) setState(() {});
      return;
    }
    final ocr = PdfOcrPageSearcher();
    if (!await ocr.isAvailable()) return;
    final active = _activeTab;
    if (active == null) return;
    final hit = await ocr.findNearPage(
      file: active.file,
      centerPage1: _currentPage1Safe(),
      query: query,
      password: _sessionFor(active).resolvedPassword ?? active.password,
    );
    if (!mounted || hit == null) return;
    setState(() {
      _ocrFindPages = [hit.pageIndex1Based];
      _ocrFindIndex = 0;
      _syncSearchPagePaintCallbacks();
    });
    await _controller?.goToPage(pageNumber: hit.pageIndex1Based);
  }

  void _toggleThumbnailSidebar() {
    setState(() {
      _sidebarEnabled = !_sidebarEnabled;
      if (_sidebarEnabled) {
        _sidebarContent = PdfViewerSidebarContent.thumbnails;
      }
    });
  }

  void _onSidebarContentChanged(PdfViewerSidebarContent content) {
    setState(() => _sidebarContent = content);
  }

  Widget _buildThumbnailToggleButton() {
    return IconButton(
      key: const Key('pdf_viewer_thumbnail_toggle'),
      tooltip: _sidebarEnabled ? 'Hide side panel' : 'Show page thumbnails',
      icon: Icon(_sidebarEnabled ? Icons.view_sidebar : Icons.view_agenda),
      onPressed: _toggleThumbnailSidebar,
    );
  }

  void _onControllerReady(PdfViewerController controller) {
    if (_controller == controller && _searcher != null) return;
    // Defer detach/attach so we never mutate listeners during notifyListeners
    // (pdfrx layout/zoom → ConcurrentModificationError).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_controller == controller && _searcher != null) return;
      _detachControllerListener();
      _searcher?.dispose();
      _searcher = null;
      _searchPagePaintCallbacks = null;
      _controller = controller;
      // Viewer holds its own cache lease now; drop the validation pin.
      final tab = _activeTab;
      if (tab != null) _sessionFor(tab).releaseWarmLease();
      void syncSearcher() {
        if (!mounted || !controller.isReady) return;
        if (_searcher != null) return;
        final searcher = PdfTextSearcher(controller);
        _searcher = searcher;
        _syncSearchPagePaintCallbacks();
        if (_searchPaintCallbacksRebuildScheduled) return;
        _searchPaintCallbacksRebuildScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _searchPaintCallbacksRebuildScheduled = false;
          if (mounted) setState(() {});
        });
      }

      _controllerReadyListener = syncSearcher;
      controller.addListener(syncSearcher);
      if (controller.isReady) {
        syncSearcher();
      }
    });
  }

  VoidCallback? _controllerReadyListener;

  void _detachControllerListener() {
    final listener = _controllerReadyListener;
    final controller = _controller;
    if (listener != null && controller != null) {
      controller.removeListener(listener);
    }
    _controllerReadyListener = null;
  }

  PdfViewerTab? get _activeTab =>
      _boundTab(ref.watch(documentTabsControllerProvider));

  PdfViewerTab? _boundTab(DocumentTabsController tabs) {
    final id = widget.tabId;
    if (id == null) return tabs.activeTab;
    for (final t in tabs.tabs) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _toggleReadMode() {
    if (_presentationMode) return;
    setState(() {
      _readMode = !_readMode;
      if (_readMode) {
        _markup.exitEditMode();
        _searchUiVisible = false;
        _activeViewerTool = null;
      }
    });
  }

  void _exitReadMode() {
    if (!_readMode) return;
    setState(() => _readMode = false);
  }

  Future<void> _togglePresentationMode() async {
    if (_presentationMode) {
      await _exitPresentationMode();
      return;
    }
    _markup.exitEditMode();
    final controller = _controller;
    final snapshot = controller != null && controller.isReady
        ? PdfViewerPresentationSnapshot(
            page1Based: controller.pageNumber ?? 1,
            zoom: controller.currentZoom,
            center: controller.centerPosition,
            scrollLayoutModeName: _scrollLayoutMode.name,
          )
        : null;
    setState(() {
      _presentationSnapshot = snapshot;
      _presentationMode = true;
      _readMode = false;
      _searchUiVisible = false;
      _activeViewerTool = null;
    });
    // Fit the single page after layout settles (no document reload).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final c = _controller;
      if (!mounted || c == null || !c.isReady || !_presentationMode) return;
      await pdfViewerApplyFitPage(c);
    });
  }

  Future<void> _exitPresentationMode() async {
    if (!_presentationMode) return;
    final snapshot = _presentationSnapshot;
    setState(() {
      _presentationMode = false;
      _presentationSnapshot = null;
    });
    final controller = _controller;
    if (controller == null || !controller.isReady || snapshot == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !controller.isReady) return;
      try {
        final page = snapshot.page1Based.clamp(1, controller.pageCount);
        await controller.goToPage(pageNumber: page, duration: Duration.zero);
        final center = snapshot.center ?? controller.centerPosition;
        await controller.setZoom(
          center,
          snapshot.zoom,
          duration: Duration.zero,
        );
      } catch (_) {}
    });
  }

  Future<void> _showInfo(
    BuildContext context,
    LocalFileRef file, {
    String? password,
  }) {
    return showDocumentProperties(
      context: context,
      pdf: ref.read(pdfRenderPortProvider),
      file: file,
      password: password,
    );
  }

  int _currentPage1Safe() {
    final c = _controller;
    if (c == null) return 1;
    final snap = PdfViewerControllerNavSnapshot.of(c);
    if (!snap.isReady) return 1;
    return snap.pageNumber ?? 1;
  }

  int? _readyPageCount() {
    final c = _controller;
    if (c == null) return null;
    final snap = PdfViewerControllerNavSnapshot.of(c);
    return snap.isReady ? snap.pageCount : null;
  }

  String? _passwordForTab(PdfViewerTab tab) {
    return _sessionFor(tab).resolvedPassword ?? tab.password;
  }

  void _openViewerContextMenu(Offset globalPosition) {
    final active = _activeTab;
    if (active == null) return;
    final password = _passwordForTab(active);
    final handoff = PdfViewerDocumentHandoff(
      file: active.file,
      password: password,
      currentPage1: _currentPage1Safe(),
    );
    showPdfViewerCanvasContextMenu(
      context: context,
      globalPosition: globalPosition,
      handoff: handoff,
      onDocumentInfo: () => _showInfo(context, active.file, password: password),
      onPrint: () => _printActive(active.file),
      onCompress: () {
        // Menu context sits above the tool-panel scope, so open the rail
        // directly on this document instead of the file-picker route.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _openViewerTool(ViewerToolId.compress);
        });
      },
    );
  }

  Future<void> _printActive(LocalFileRef file) async {
    final service = ref.read(printServiceProvider);
    final active = _activeTab;
    final password = active != null && active.file.path == file.path
        ? _passwordForTab(active)
        : null;
    try {
      await service.printPdf(file, password: password);
    } on PrintException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Print failed: $e')));
    }
  }

  void _registerViewerShortcuts(LocalFileRef file) {
    if (!widget.foreground) {
      _registeredShortcutsFilePath = null;
      return;
    }
    if (_registeredShortcutsFilePath == file.path) return;
    _registeredShortcutsFilePath = file.path;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _viewerShortcutsNotifier?.setActions(
        ViewerShortcutActions(
          onPrint: file.isPdf ? () => _printActive(file) : null,
          onFind: () => _showSearch(context),
          onOpen: _openAnotherPdfInTab,
          onUndo: _undoActiveSession,
          onRedo: _redoActiveSession,
          onSave: _saveActiveSession,
          onAddText: () => _openMarkup(MarkupTool.text),
          onCrop: _openCropForCurrentPage,
          onRotatePageRight: () => unawaited(_rotateCurrentPage(90)),
          onRotatePageLeft: () => unawaited(_rotateCurrentPage(-90)),
          onPlaceImage: () => _openMarkup(MarkupTool.image),
          onPlaceSignature: () => _openViewerTool(ViewerToolId.visualSign),
          onDraw: () => _openMarkup(MarkupTool.pen),
          onHighlight: () => _openMarkup(MarkupTool.highlight),
          onUnderline: () => _openMarkup(MarkupTool.underline),
          onStickyNote: () => _openMarkup(MarkupTool.note),
          onRectangle: () => _openMarkup(MarkupTool.rectangle),
          onLine: () => _openMarkup(MarkupTool.line),
          onAddLink: () => _openMarkup(MarkupTool.link),
          onToggleRulers: () {
            ref.read(viewerRulersVisibleProvider.notifier).toggle();
          },
          onCancelTool: () {
            if (_markup.editMode && _markup.selection.isNotEmpty) {
              _markup.clearSelection();
              return;
            }
            final live = ref.read(viewerLiveToolSessionProvider);
            if (live.toolId == ViewerToolId.ink && live.cancelCurrentStroke()) {
              return;
            }
            _closeActiveToolPanel();
          },
        ),
      );
    });
  }

  void _invokeViewerToolShortcut(ViewerToolShortcutId id) {
    if (viewerToolShortcutsBlockedByFocus() &&
        id != ViewerToolShortcutId.cancelTool) {
      return;
    }
    final a = ref.read(viewerShortcutActionsProvider);
    switch (id) {
      case ViewerToolShortcutId.addText:
        a.onAddText?.call();
      case ViewerToolShortcutId.crop:
        a.onCrop?.call();
      case ViewerToolShortcutId.rotateRight:
        a.onRotatePageRight?.call();
      case ViewerToolShortcutId.rotateLeft:
        a.onRotatePageLeft?.call();
      case ViewerToolShortcutId.placeImage:
        a.onPlaceImage?.call();
      case ViewerToolShortcutId.placeSignature:
        a.onPlaceSignature?.call();
      case ViewerToolShortcutId.draw:
        a.onDraw?.call();
      case ViewerToolShortcutId.highlight:
        a.onHighlight?.call();
      case ViewerToolShortcutId.underline:
        a.onUnderline?.call();
      case ViewerToolShortcutId.stickyNote:
        a.onStickyNote?.call();
      case ViewerToolShortcutId.rectangle:
        a.onRectangle?.call();
      case ViewerToolShortcutId.line:
        a.onLine?.call();
      case ViewerToolShortcutId.addLink:
        a.onAddLink?.call();
      case ViewerToolShortcutId.toggleRulers:
        a.onToggleRulers?.call();
      case ViewerToolShortcutId.cancelTool:
        a.onCancelTool?.call();
    }
  }

  Map<ShortcutActivator, VoidCallback> get _viewerToolShortcutBindings {
    return {
      for (final e in viewerToolShortcutMap.entries)
        e.key: () => _invokeViewerToolShortcut(e.value),
    };
  }

  Future<void> _undoActiveSession() async {
    // Marks not yet written into the PDF undo first (no document revision).
    if (ref.read(viewerLiveToolSessionProvider).undoPendingDraw()) return;
    if (_markup.undo()) return;
    await _markup.flush();
    final session = ref.read(documentTabsControllerProvider).activeSession;
    if (session == null || !session.canUndo) return;
    final c = _controller;
    final snap = c == null ? null : PdfViewerControllerNavSnapshot.of(c);
    final page = snap?.isReady == true ? snap!.pageNumber : null;
    final zoom = c != null && snap?.isReady == true ? c.currentZoom : null;
    final center = c != null && snap?.isReady == true ? c.centerPosition : null;
    final ok = await session.undo();
    if (!ok) return;
    ref.read(documentTabsControllerProvider).syncActiveTabFromSession();
    await _softReloadPreservingView(
      preferredPage: page,
      preferredZoom: zoom,
      preferredCenter: center,
    );
  }

  Future<void> _redoActiveSession() async {
    if (ref.read(viewerLiveToolSessionProvider).redoPendingDraw()) return;
    if (_markup.redo()) return;
    await _markup.flush();
    final session = ref.read(documentTabsControllerProvider).activeSession;
    if (session == null || !session.canRedo) return;
    final c = _controller;
    final snap = c == null ? null : PdfViewerControllerNavSnapshot.of(c);
    final page = snap?.isReady == true ? snap!.pageNumber : null;
    final zoom = c != null && snap?.isReady == true ? c.currentZoom : null;
    final center = c != null && snap?.isReady == true ? c.centerPosition : null;
    final ok = await session.redo();
    if (!ok) return;
    ref.read(documentTabsControllerProvider).syncActiveTabFromSession();
    await _softReloadPreservingView(
      preferredPage: page,
      preferredZoom: zoom,
      preferredCenter: center,
    );
  }

  Future<void> _softReloadPreservingView({
    int? preferredPage,
    double? preferredZoom,
    Offset? preferredCenter,
  }) async {
    final c = _controller;
    if (c == null || !c.isReady) return;
    if (_softReloadInFlight) return;
    _softReloadInFlight = true;
    try {
      await softReloadPdfViewerDocument(
        c,
        preferredPage: preferredPage,
        preferredZoom: preferredZoom,
        preferredCenter: preferredCenter,
      );
      final session = ref.read(documentTabsControllerProvider).activeSession;
      if (session != null) {
        _lastSoftReloadRevision = session.revision;
        _lastSoftReloadPath = session.sourcePath;
      }
    } finally {
      _softReloadInFlight = false;
      // Bytes changed in place — drop stale OCR text without remounting PdfViewer.
      // Re-index only if Find is open so ink strokes don't thrash tesseract.
      _backgroundOcr?.clear();
      if (_searchUiVisible) {
        _ocrIndexedPath = null;
        final session = ref.read(documentTabsControllerProvider).activeSession;
        if (session != null) {
          _startBackgroundOcr(session.file, session.password);
        }
      }
    }
  }

  void _closeActiveToolPanel() {
    ref.read(viewerLiveToolSessionProvider).deactivate();
    _markup.exitEditMode();
    setState(() => _activeViewerTool = null);
  }

  void _openViewerTool(ViewerToolId tool, {LiveDrawTool? drawTool}) {
    if (_isMarkupTool(tool)) {
      _openMarkup(_markupToolFor(tool, drawTool));
      return;
    }
    _markup.exitEditMode();
    if (_markup.hasUnsavedChanges || _markup.saving) {
      // Other tools read the file: write pending markup first.
      unawaited(
        _markup.flush().then((_) {
          if (mounted) _openOtherViewerTool(tool, drawTool: drawTool);
        }),
      );
      return;
    }
    _openOtherViewerTool(tool, drawTool: drawTool);
  }

  void _openOtherViewerTool(ViewerToolId tool, {LiveDrawTool? drawTool}) {
    final live = ref.read(viewerLiveToolSessionProvider);
    final page = _currentPage1Safe();
    if (viewerToolUsesLivePageOverlay(tool)) {
      live.activate(tool, pageIndex1Based: page, drawTool: drawTool);
    } else {
      live.deactivate();
    }
    setState(() {
      _activeViewerTool = tool;
      _toolsRailEnabled = true;
    });
  }

  void _startBackgroundOcr(LocalFileRef file, String? password) {
    // Idempotent: one schedule/index per open path. Mark the path immediately
    // so a rebuild cannot queue a second post-frame OCR for the same file.
    // Never write Riverpod (setIndex) synchronously from build.
    if (_ocrIndexedPath == file.path) {
      return;
    }
    _ocrIndexedPath = file.path;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Path changed again before this frame (or cleared for a soft path switch).
      if (_ocrIndexedPath != file.path) return;
      _backgroundOcr?.cancel();
      final index = PdfBackgroundOcrIndex(ocr: ref.read(ocrPortProvider));
      _backgroundOcr = index;
      // Provider write only after the frame — not during build.
      ref.read(viewerBackgroundOcrIndexProvider.notifier).setIndex(index);
      unawaited(
        index.indexFile(
          file: file,
          password: password,
          onStatus: (_) {},
          onDone: () {
            if (!mounted) return;
            // Re-run OCR find once the index is ready (no remount).
            if (_searchUiVisible &&
                _searchQuery.trim().isNotEmpty &&
                (_searcher?.matches.isEmpty ?? true)) {
              unawaited(_applyOcrFindForQuery(_searchQuery));
            }
          },
        ),
      );
    });
  }

  Future<void> _saveActiveSession() async {
    // Flush any pending 6s autosave first so Save is not lost.
    await documentSessionAutosave.flush();
    await _markup.flush();
    final session = ref.read(documentTabsControllerProvider).activeSession;
    if (session == null) return;
    final storage = ref.read(fileStorageProvider);
    final outcome = await session.save();
    if (!mounted) return;
    if (outcome == DocumentSaveOutcome.needsSaveAs) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save in place (read-only or locked). Choose a new location.',
          ),
        ),
      );
      final saved = await session.saveAs(storage);
      if (saved != null) {
        ref.read(documentTabsControllerProvider).syncActiveTabFromSession();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Saved as ${saved.displayName}')),
          );
        }
      }
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved')));
  }

  Future<void> _rotateCurrentPage(int deltaDegrees) async {
    await _rotatePageAt(_currentPage1Safe(), deltaDegrees);
  }

  Future<void> _rotatePageAt(int page1, int deltaDegrees) async {
    final tabs = ref.read(documentTabsControllerProvider);
    final session = tabs.activeSession;
    final total = _readyPageCount();
    if (session == null || total == null || total < 1) return;
    final page = page1.clamp(1, total);
    try {
      final organize = ref.read(pageOrganizeServiceProvider);
      final pages = pagesForRotate(session.file, total, {page}, deltaDegrees);
      final assembled = await organize.assembleWorkspaceExport(
        pages: pages,
        passwordsByPath: session.password == null || session.password!.isEmpty
            ? null
            : {session.file.path: session.password!},
      );
      if (!mounted) return;
      await commitBytesToSession(
        context: context,
        storage: ref.read(fileStorageProvider),
        tabs: tabs,
        session: session,
        bytes: Uint8List.fromList(assembled.bytes),
        successMessage: 'Rotated page $page.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _commitOrganizePageList({
    required List<OrganizePageRef> pages,
    required String successMessage,
  }) async {
    final tabs = ref.read(documentTabsControllerProvider);
    final session = tabs.activeSession;
    if (session == null) return;
    final organize = ref.read(pageOrganizeServiceProvider);
    final assembled = await organize.assembleWorkspaceExport(
      pages: pages,
      passwordsByPath: session.password == null || session.password!.isEmpty
          ? null
          : {session.file.path: session.password!},
    );
    if (!mounted) return;
    await commitBytesToSession(
      context: context,
      storage: ref.read(fileStorageProvider),
      tabs: tabs,
      session: session,
      bytes: Uint8List.fromList(assembled.bytes),
      successMessage: successMessage,
    );
  }

  Future<void> _deletePageAt(int page1) async {
    final session = ref.read(documentTabsControllerProvider).activeSession;
    final total = _readyPageCount();
    if (session == null || total == null || total < 1) return;
    if (total <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete the only page.')),
      );
      return;
    }
    try {
      await _commitOrganizePageList(
        pages: pagesForDelete(session.file, total, {page1}),
        successMessage: 'Deleted page $page1.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _duplicatePageAt(int page1) async {
    final session = ref.read(documentTabsControllerProvider).activeSession;
    final total = _readyPageCount();
    if (session == null || total == null || total < 1) return;
    try {
      await _commitOrganizePageList(
        pages: pagesForDuplicate(session.file, total, {page1}),
        successMessage: 'Duplicated page $page1.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _insertBlankAfterPage(int page1) async {
    final session = ref.read(documentTabsControllerProvider).activeSession;
    final total = _readyPageCount();
    if (session == null || total == null || total < 1) return;
    try {
      final blank = await ref.read(blankPageFactoryProvider).blankPageFile();
      if (!mounted) return;
      await _commitOrganizePageList(
        pages: pagesForBlankInsertAfter(session.file, total, {page1}, blank),
        successMessage: 'Inserted blank after page $page1.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _extractPageAt(int page1, {bool deleteAfter = false}) async {
    final tabs = ref.read(documentTabsControllerProvider);
    final session = tabs.activeSession;
    final total = _readyPageCount();
    if (session == null || total == null || total < 1) return;
    try {
      final organize = ref.read(pageOrganizeServiceProvider);
      final extractPages = pagesForExtract(session.file, {page1});
      final assembled = await organize.assembleWorkspaceExport(
        pages: extractPages,
        passwordsByPath: session.password == null || session.password!.isEmpty
            ? null
            : {session.file.path: session.password!},
      );
      if (!mounted) return;
      final storage = ref.read(fileStorageProvider);
      final bytes = Uint8List.fromList(assembled.bytes);
      final stem = session.file.displayName.replaceAll(
        RegExp(r'\.pdf$', caseSensitive: false),
        '',
      );
      final savePath = await storage.pickSavePath(
        suggestedName: '${stem}_extract.pdf',
        bytes: bytes,
        allowedExtensions: const ['pdf'],
        mimeType: 'application/pdf',
      );
      if (savePath == null) return;
      await storage.writeAtomic(
        destinationPath: savePath,
        writeToTemp: (temp) async {
          await File(temp).writeAsBytes(bytes, flush: true);
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Extracted page $page1 saved.')));
      if (!deleteAfter) return;
      if (total <= 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kept the only page in the open document.'),
          ),
        );
        return;
      }
      await _commitOrganizePageList(
        pages: pagesForDelete(session.file, total, {page1}),
        successMessage: 'Removed page $page1 from the open document.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _onThumbnailPageAction(
    int page1,
    PdfThumbnailPageAction action,
  ) async {
    await _controller?.goToPage(pageNumber: page1);
    if (!mounted) return;
    switch (action) {
      case PdfThumbnailPageAction.rotateLeft:
        await _rotatePageAt(page1, -90);
      case PdfThumbnailPageAction.rotateRight:
        await _rotatePageAt(page1, 90);
      case PdfThumbnailPageAction.duplicate:
        await _duplicatePageAt(page1);
      case PdfThumbnailPageAction.delete:
        await _deletePageAt(page1);
      case PdfThumbnailPageAction.insertBlankAfter:
        await _insertBlankAfterPage(page1);
      case PdfThumbnailPageAction.extract:
        final deleteAfter = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Extract page $page1'),
            content: const Text(
              'Save this page as a new PDF. Optionally remove it from the open document after saving.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Extract only'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Extract & delete'),
              ),
            ],
          ),
        );
        if (!mounted || deleteAfter == null) return;
        await _extractPageAt(page1, deleteAfter: deleteAfter);
    }
  }

  void _openCropForCurrentPage() {
    _openViewerTool(ViewerToolId.crop);
  }

  Future<void> _reorderViewerPages(int fromIndex0, int toIndex0) async {
    final tabs = ref.read(documentTabsControllerProvider);
    final session = tabs.activeSession;
    final total = _readyPageCount();
    if (session == null || total == null || total < 2) return;
    if (fromIndex0 == toIndex0 || fromIndex0 == toIndex0 - 1) return;
    try {
      final organize = ref.read(pageOrganizeServiceProvider);
      final pages = pagesForReorder(session.file, total, fromIndex0, toIndex0);
      final assembled = await organize.assembleWorkspaceExport(
        pages: pages,
        passwordsByPath: session.password == null || session.password!.isEmpty
            ? null
            : {session.file.path: session.password!},
      );
      if (!mounted) return;
      await commitBytesToSession(
        context: context,
        storage: ref.read(fileStorageProvider),
        tabs: tabs,
        session: session,
        bytes: Uint8List.fromList(assembled.bytes),
        successMessage: 'Pages reordered.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _navigatePage(PdfViewerPageStep step) {
    final controller = _controller;
    if (controller == null) return;
    navigatePdfViewerPage(controller: controller, step: step);
  }

  Future<void> _applyFit(PdfViewerFitDisplay mode) async {
    final controller = _controller;
    if (controller == null || !controller.isReady) return;
    switch (mode) {
      case PdfViewerFitDisplay.fitPage:
        await pdfViewerApplyFitPage(controller);
      case PdfViewerFitDisplay.fitWidth:
        await pdfViewerApplyFitWidth(controller);
      case PdfViewerFitDisplay.fitHeight:
        await pdfViewerApplyFitHeight(controller);
      case PdfViewerFitDisplay.custom:
        break;
    }
  }

  void _showSearch(BuildContext context) {
    final controller = _controller;
    final searcher = _searcher;
    if (controller == null || searcher == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document is still loading')),
      );
      return;
    }
    final alreadyOpen = _searchUiVisible;
    final active = _activeTab;
    if (active != null) {
      _startBackgroundOcr(
        active.file,
        _sessionFor(active).resolvedPassword ?? active.password,
      );
    }
    setState(() => _searchUiVisible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _findFocusNode.requestFocus();
    });
    if (_searchQuery.isNotEmpty) {
      applyPdfSearchQuery(searcher: searcher, query: _searchQuery);
      if (alreadyOpen && searcher.matches.isEmpty) {
        unawaited(_applyOcrFindForQuery(_searchQuery));
      }
    }
  }

  Widget? _buildSearchMatchBar() {
    final searcher = _searcher;
    if (!_searchUiVisible ||
        searcher == null ||
        !pdfViewerShowsSearchBar(presentationMode: _presentationMode)) {
      return null;
    }
    return ListenableBuilder(
      listenable: searcher,
      builder: (context, _) {
        final liveTextHits = searcher.matches.length;
        final liveUsingOcr = liveTextHits == 0 && _ocrFindPages.isNotEmpty;
        final liveCount = liveUsingOcr ? _ocrFindPages.length : liveTextHits;
        final liveIndex = liveUsingOcr ? _ocrFindIndex : searcher.currentIndex;
        return PdfSearchMatchBar(
          initialQuery: _searchQuery,
          focusNode: _findFocusNode,
          matchCount: liveCount,
          currentIndex: liveIndex,
          isSearching:
              searcher.isSearching ||
              (_backgroundOcr?.isRunning == true && liveCount == 0),
          ocrIndexing: _backgroundOcr?.isRunning == true && liveCount == 0,
          fromOcrIndex: liveUsingOcr,
          onPrevious: _goToPrevFindMatch,
          onNext: _goToNextFindMatch,
          onClose: _closeSearch,
          onSearch: (query) async {
            _searchQuery = query;
            if (query.trim().isEmpty) {
              _clearOcrFindHits();
              applyPdfSearchQuery(searcher: searcher, query: query);
              if (mounted) setState(() {});
              return;
            }
            applyPdfSearchQuery(searcher: searcher, query: query);
            await Future<void>.delayed(const Duration(milliseconds: 350));
            if (!mounted) return;
            if (searcher.matches.isNotEmpty) {
              _clearOcrFindHits();
              if (mounted) setState(() {});
              return;
            }
            await _applyOcrFindForQuery(query);
            if (mounted) setState(() {});
          },
        );
      },
    );
  }

  PreferredSizeWidget? _tabBarOrNull(DocumentTabsController tabs) {
    if (widget.shellEmbedded || !tabs.hasTabs) return null;
    if (dsHideDocumentTabStrip(context)) return null;
    return PdfDocumentTabBar(
      controller: tabs,
      onOpenAnother: _openAnotherPdfInTab,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(documentTabsControllerProvider);
    final active = _activeTab;
    if (active == null) {
      return const Scaffold(body: Center(child: Text('No document open')));
    }
    final session = _sessionFor(active);

    if (session.validating && !session.validated) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _leaveViewer,
          ),
          title: Text(active.file.displayName),
          bottom: _tabBarOrNull(tabs),
        ),
        body: PdfViewerLoadingPlaceholder(
          key: const Key('pdf_viewer_loading'),
          fileName: active.file.displayName,
        ),
      );
    }

    if (session.error != null) {
      final error = session.error!;
      final passwordIssue =
          error.code == DocumentStudioErrorCode.passwordRequired ||
          error.code == DocumentStudioErrorCode.wrongPassword;
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _leaveViewer,
          ),
          title: Text(active.file.displayName),
          bottom: _tabBarOrNull(tabs),
        ),
        body: DocumentOpenErrorPanel(
          error: error,
          onBack: _leaveViewer,
          onPickAnotherFile: _pickAnotherFileForViewer,
          onUnlock: passwordIssue
              ? _promptPasswordAndRetry
              : _unlockCurrentFile,
          onRetry: passwordIssue ? null : () => _validateTab(active),
        ),
      );
    }

    final wideLayout =
        MediaQuery.sizeOf(context).width >=
        kPdfViewerThumbnailSidebarBreakpoint;
    final compactWidth =
        MediaQuery.sizeOf(context).width < DsSpacing.breakpointCompact;
    // Android (incl. tablets): no document tab strip; viewer uses app back.
    final hideDocumentTabs = compactWidth || dsHideDocumentTabStrip(context);
    final signPlacement = ref.read(signPlacementControllerProvider);
    final activePassword = session.resolvedPassword ?? active.password;
    _registerViewerShortcuts(active.file);
    _bindMarkup(active.session);
    // Soft-reload when bytes change in place (Apply / undo) without remounting PdfViewer.
    // Track by source path so working-copy materialization (path change) still soft-reloads.
    final rev = active.session.revision;
    final identityPath = active.session.sourcePath;
    if (_lastSoftReloadPath == identityPath &&
        _lastSoftReloadRevision != rev &&
        (MarkupOwnRevisions.isOwn(active.file.path, rev) ||
            PageLabelOwnRevisions.isOwn(active.file.path, rev))) {
      // Markup saves only touch annotations the overlay already draws.
      _lastSoftReloadRevision = rev;
    } else if (_lastSoftReloadPath == identityPath &&
        _lastSoftReloadRevision != null &&
        _lastSoftReloadRevision != rev &&
        !_softReloadInFlight) {
      _lastSoftReloadRevision = rev;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _softReloadInFlight) return;
        unawaited(_softReloadPreservingView());
      });
    } else if (_lastSoftReloadPath != identityPath) {
      _lastSoftReloadPath = identityPath;
      _lastSoftReloadRevision = rev;
      _ocrIndexedPath = null;
      // Do not start background OCR on open — competing with first paint on
      // large books. OCR starts when the user opens Find.
    }

    return GuardedCallbackShortcuts(
      bindings: {
        ..._viewerToolShortcutBindings,
        pdfViewerReadModeActivator(): () {
          if (_presentationMode) return;
          _toggleReadMode();
        },
        pdfViewerPresentationActivator: () {
          unawaited(_togglePresentationMode());
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_presentationMode) {
            unawaited(_exitPresentationMode());
            return;
          }
          if (_readMode) {
            _exitReadMode();
            return;
          }
          final sign = ref.read(signPlacementControllerProvider);
          if (sign.isPageInteractionActive) {
            sign.cancelPageInteraction();
            return;
          }
          if (_markup.editMode && _markup.selection.isNotEmpty) {
            _markup.clearSelection();
            return;
          }
          if (_activeViewerTool != null) {
            final live = ref.read(viewerLiveToolSessionProvider);
            if (live.cancelCurrentStroke()) return;
            _closeActiveToolPanel();
          }
        },
      },
      child: PdfViewerToolPanelScope(
        openViewerToolPanel: _openViewerTool,
        closeViewerToolPanel: _closeActiveToolPanel,
        child: PdfViewerPresentationEscapeScope(
          presentationMode: _presentationMode,
          readMode: _readMode,
          onExit: () => unawaited(_exitPresentationMode()),
          onExitReadMode: _exitReadMode,
          child: PdfViewerReadShortcuts(
            findBarVisible: _searchUiVisible,
            onFitPage: () => _applyFit(PdfViewerFitDisplay.fitPage),
            onFitWidth: () => _applyFit(PdfViewerFitDisplay.fitWidth),
            onFitHeight: () => _applyFit(PdfViewerFitDisplay.fitHeight),
            onFindNext: _goToNextFindMatch,
            onFindPrevious: _goToPrevFindMatch,
            child: PdfViewerPageShortcuts(
              onNavigate: _navigatePage,
              child: ListenableBuilder(
                listenable: signPlacement,
                builder: (context, _) {
                  final signActive = signPlacement.isPageInteractionActive;
                  final toolsCover =
                      _toolsRailEnabled &&
                      MediaQuery.sizeOf(context).width <
                          kPdfViewerAcrobatToolsRailBreakpoint &&
                      _activeViewerTool == null;
                  final VoidCallback? chromeBack;
                  if (_activeViewerTool != null) {
                    chromeBack = _closeActiveToolPanel;
                  } else if (toolsCover) {
                    chromeBack = () =>
                        setState(() => _toolsRailEnabled = false);
                  } else if (widget.shellEmbedded && !hideDocumentTabs) {
                    chromeBack = null;
                  } else {
                    chromeBack = _leaveViewer;
                  }
                  final showMarkup =
                      !signActive && !_presentationMode && !_readMode;
                  final wideTools =
                      MediaQuery.sizeOf(context).width >=
                      kPdfViewerAcrobatToolsRailBreakpoint;
                  final layersOpen =
                      !_presentationMode &&
                      !_readMode &&
                      wideLayout &&
                      _annotationsPanelEnabled &&
                      _controller != null;
                  var markupRightInset = 8.0;
                  if (layersOpen) markupRightInset += 280;
                  if (showMarkup && wideTools && _toolsRailEnabled) {
                    final paneWidth = _activeViewerTool != null
                        // ignore: invalid_use_of_visible_for_testing_member
                        ? ViewerToolPanelChrome.panelWidth
                        // ignore: invalid_use_of_visible_for_testing_member
                        : PdfViewerAllToolsRail.railWidth;
                    markupRightInset += paneWidth + 1;
                  }
                  final markupBottomInset =
                      !wideTools && _activeViewerTool != null && showMarkup
                      ? PdfViewerAcrobatShellState.phoneToolPanelHeight + 8
                      : 8.0;
                  final showMarkupBar = showMarkup && !toolsCover;
                  return Scaffold(
                    appBar:
                        pdfViewerShowsAppBar(
                          presentationMode: _presentationMode,
                          readMode: _readMode,
                        )
                        ? PdfViewerAcrobatTopChrome(
                            tabs: tabs,
                            documentTitle: active.file.displayName,
                            viewerController: _controller,
                            // Shell embeds tabs in desktop chrome. Phone and
                            // Android have no document tab strip.
                            showDocumentTabs:
                                !compactWidth &&
                                !widget.shellEmbedded &&
                                !hideDocumentTabs,
                            showFind: !compactWidth,
                            // A tool or the Tools sheet: Back closes it and
                            // stays on this document. Otherwise phone / Android
                            // app back returns to Home.
                            onBack: chromeBack,
                            backTooltip: _activeViewerTool != null || toolsCover
                                ? 'Back to document'
                                : 'Back',
                            onOpenAnother: _openAnotherPdfInTab,
                            onGoToPage: () {
                              final c = _controller;
                              if (c == null) return;
                              showPdfGoToPageDialog(
                                context: context,
                                controller: c,
                              );
                            },
                            onFind: () => _showSearch(context),
                            onFitWidth: () =>
                                _applyFit(PdfViewerFitDisplay.fitWidth),
                            onFitPage: () =>
                                _applyFit(PdfViewerFitDisplay.fitPage),
                            signPlacementActive: signActive,
                            onSignCancel: _onSignPlacementCancel,
                            onSignDone: _onSignPlacementDone,
                            signStatusLabel: signActive
                                ? _signPlacementStatusLabel(signPlacement)
                                : null,
                            toolRow: signActive
                                ? null
                                : PdfViewerToolRow(
                                    enabled: _controller?.isReady ?? false,
                                    markup: _markup,
                                    allToolsOpen: _toolsRailEnabled,
                                    onArmMarkup: _armPageMarkup,
                                    onAllTools: () => setState(
                                      () => _toolsRailEnabled =
                                          !_toolsRailEnabled,
                                    ),
                                  ),
                          )
                        : null,
                    body: MarkupKeyboardScope(
                      controller: _markup,
                      currentPage: _currentPage1Safe,
                      onUndo: () => unawaited(_undoActiveSession()),
                      onRedo: () => unawaited(_redoActiveSession()),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ?_buildSearchMatchBar(),
                              Expanded(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    PdfViewerAcrobatShell(
                                      key: _acrobatShellKeyFor(active.id),
                                      documentTabId: active.id,
                                      file: active.file,
                                      viewerIdentityPath:
                                          active.session.sourcePath,
                                      handoff: PdfViewerDocumentHandoff(
                                        file: active.file,
                                        password: activePassword,
                                        currentPage1: _currentPage1Safe(),
                                      ),
                                      password: activePassword,
                                      presentationMode: _presentationMode,
                                      readMode: _readMode,
                                      leftRailEnabled: pdfViewerSidebarVisible(
                                        presentationMode: _presentationMode,
                                        readMode: _readMode,
                                        userSidebarEnabled:
                                            _sidebarEnabled && !signActive,
                                      ),
                                      toolsRailEnabled: pdfViewerShowsToolsRail(
                                        presentationMode: _presentationMode,
                                        readMode: _readMode,
                                        // Hide Edit/Pages/Protect/Tools panel while
                                        // placing so drag/resize is not covered.
                                        userToolsRailEnabled:
                                            _toolsRailEnabled && !signActive,
                                      ),
                                      activeToolPanel: _activeViewerTool,
                                      onCloseToolPanel: _closeActiveToolPanel,
                                      pageCount: () {
                                        final c = _controller;
                                        if (c == null) return null;
                                        final snap =
                                            PdfViewerControllerNavSnapshot.of(
                                              c,
                                            );
                                        return snap.isReady
                                            ? snap.pageCount
                                            : null;
                                      }(),
                                      selectedPages1Based: const {},
                                      sidebarContent: _sidebarContent,
                                      onSidebarContentChanged:
                                          _onSidebarContentChanged,
                                      onLeftRailEnabledChanged: (enabled) =>
                                          setState(
                                            () => _sidebarEnabled = enabled,
                                          ),
                                      onToolsRailEnabledChanged: (enabled) =>
                                          setState(
                                            () => _toolsRailEnabled = enabled,
                                          ),
                                      scrollLayoutMode: _scrollLayoutMode,
                                      viewRotation: _viewRotation,
                                      pagePaintCallbacks: _pagePaintCallbacks,
                                      linkHandlerParams:
                                          viewerToolUsesLivePageOverlay(
                                                _activeViewerTool,
                                              ) ||
                                              _isMarkupTool(_activeViewerTool)
                                          ? _linkHandlerParamsUnderTools
                                          : _linkHandlerParams,
                                      pageOverlaysBuilder:
                                          (context, pageRect, page) {
                                            return [
                                              if (identical(
                                                _markup.session,
                                                active.session,
                                              ))
                                                buildMarkupPageLayer(
                                                  controller: _markup,
                                                  page: page,
                                                  pageRect: pageRect,
                                                  actions: _markupActions,
                                                  viewerController: _controller,
                                                ),
                                              ...buildViewerLivePageOverlays(
                                                context: context,
                                                pageRect: pageRect,
                                                page: page,
                                                session: ref.read(
                                                  viewerLiveToolSessionProvider,
                                                ),
                                                showRulers: ref.watch(
                                                  viewerRulersVisibleProvider,
                                                ),
                                                controller: _controller,
                                              ),
                                            ];
                                          },
                                      onReorderPages: _reorderViewerPages,
                                      onPageAction: _onThumbnailPageAction,
                                      onControllerReady: _onControllerReady,
                                      onOpenContextMenu: _presentationMode
                                          ? null
                                          : _openViewerContextMenu,
                                      annotationsPanel:
                                          !_presentationMode &&
                                              !_readMode &&
                                              wideLayout &&
                                              _annotationsPanelEnabled &&
                                              _controller != null
                                          ? MarkupLayersPanel(
                                              controller: _markup,
                                              onReveal: (page, bounds) =>
                                                  unawaited(
                                                    _revealMarkup(page, bounds),
                                                  ),
                                              onClose: () => setState(
                                                () => _annotationsPanelEnabled =
                                                    false,
                                              ),
                                            )
                                          : null,
                                    ),
                                    if (showMarkupBar)
                                      PdfViewerMarkupPalette(
                                        enabled: _controller?.isReady ?? false,
                                        markup: _markup,
                                        onSelect: _armPageMarkup,
                                        pageRightInset: markupRightInset,
                                        pageBottomInset: markupBottomInset,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (_presentationMode)
                            SafeArea(
                              child: Align(
                                alignment: Alignment.topRight,
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Material(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withValues(alpha: 0.92),
                                    elevation: 2,
                                    borderRadius: BorderRadius.circular(8),
                                    child: IconButton(
                                      tooltip: 'Exit presentation',
                                      icon: const Icon(Icons.fullscreen_exit),
                                      onPressed: () =>
                                          unawaited(_exitPresentationMode()),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (!wideLayout &&
                              !_presentationMode &&
                              !_readMode &&
                              !signActive)
                            SafeArea(
                              child: Align(
                                alignment: Alignment.bottomLeft,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    left: 8,
                                    bottom: 8,
                                  ),
                                  child: Material(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withValues(alpha: 0.92),
                                    elevation: 2,
                                    borderRadius: BorderRadius.circular(24),
                                    child: _buildThumbnailToggleButton(),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
