import 'dart:async';

import 'package:document_studio/app/keyboard/app_shortcuts.dart';
import 'package:document_studio/app/keyboard/text_input_guard.dart';
import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/storage/linux_document_portal.dart';
import 'package:document_studio/design_system/shell/ds_shell_page.dart';
import 'package:document_studio/design_system/shell/ds_status_bar.dart';
import 'package:document_studio/design_system/shell/ds_toolbar.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/command_palette/ds_command_palette.dart';
import 'package:document_studio/features/document_workspace/workspace_document_tool_launch.dart';
import 'package:document_studio/features/document_workspace/workspace_inspector_panel.dart';
import 'package:document_studio/features/document_workspace/workspace_page_grid.dart';
import 'package:document_studio/features/document_workspace/workspace_landing.dart';
import 'package:document_studio/features/document_workspace/workspace_sidebar.dart';
import 'package:document_studio/features/document_workspace/workspace_toolbar.dart';
import 'package:document_studio/features/page_management/organize_pdf_import.dart';
import 'package:document_studio/features/page_management/organize_workspace_notifier.dart';
import 'package:document_studio/features/page_management/pdf_password_prompt.dart';
import 'package:document_studio/features/page_management/shared/organize_busy_overlay.dart';
import 'package:document_studio/features/page_management/shared/organize_document_source_chips.dart';
import 'package:document_studio/features/page_management/widgets/organize_drop_target.dart';
import 'package:document_studio/features/pdf_viewer/shell_pdf_open.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Document and page browser: list PDFs, show page thumbnails, open the viewer.
///
/// Page tools (rotate, crop, delete, reorder, …) open in the PDF viewer.
/// This screen does not run a second copy of those tools.
class DocumentWorkspaceScreen extends ConsumerStatefulWidget {
  const DocumentWorkspaceScreen({
    super.key,
    this.initialFiles = const [],
    this.initialPasswordsByPath = const {},
    this.returnToViewer = false,
  });

  final List<LocalFileRef> initialFiles;
  final Map<String, String> initialPasswordsByPath;
  final bool returnToViewer;

  @override
  ConsumerState<DocumentWorkspaceScreen> createState() =>
      _DocumentWorkspaceScreenState();
}

class _DocumentWorkspaceScreenState
    extends ConsumerState<DocumentWorkspaceScreen> {
  final _passwordsByPath = <String, String>{};
  bool _loadingDoc = false;

  /// Phone master–detail: documents list first; true after opening a doc.
  bool _compactPagesOpen = false;

  OrganizeWorkspaceNotifier get _ws =>
      ref.read(documentWorkspaceProvider.notifier);

  @override
  void initState() {
    super.initState();
    _passwordsByPath.addAll(widget.initialPasswordsByPath);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _ws.reset();
      for (final f in widget.initialFiles) {
        await _importFile(
          f,
          replace: ref.read(documentWorkspaceProvider).pages.isEmpty,
        );
      }
    });
  }

  Future<int?> _loadPageCount(LocalFileRef file) async {
    if (!mounted) return null;
    final pdf = ref.read(pdfRenderPortProvider);
    return loadOrganizeImportPageCount(
      file: file,
      passwordsByPath: _passwordsByPath,
      loadInfo: pdf.loadInfo,
      promptPassword: () => promptPdfPassword(context),
      onPasswordRejected: (message) {
        if (mounted) _snack(message);
      },
    );
  }

  Future<void> _importFile(LocalFileRef file, {required bool replace}) async {
    setState(() => _loadingDoc = true);
    try {
      // Host path before page count, so the grid's cache key is not the
      // portal FUSE path. Page count is pages.length on a progressive open
      // (loadAllPages stays false). Failed portal lookups are not cached.
      final host = await LinuxDocumentPortal.resolve(file.path);
      final resolved = host == file.path ? file : file.copyWithPath(host);
      final pw = _passwordsByPath[file.path];
      if (pw != null && pw.isNotEmpty && resolved.path != file.path) {
        _passwordsByPath[resolved.path] = pw;
      }
      final count = await _loadPageCount(resolved);
      if (count == null || count < 1 || !mounted) return;
      if (replace || ref.read(documentWorkspaceProvider).pages.isEmpty) {
        _ws.loadPagesFromFile(resolved, count);
      } else {
        _ws.appendAllPagesFromFile(resolved, count);
      }
      setState(() => _compactPagesOpen = true);
    } on DocumentStudioError catch (e) {
      if (!mounted) return;
      _snack(e.recoveryHint ?? e.message);
    } finally {
      if (mounted) setState(() => _loadingDoc = false);
    }
  }

  Future<void> _pickPdf({required bool replace}) async {
    final picked = await ref
        .read(fileStorageProvider)
        .pickOpenFile(allowedExtensions: ['pdf']);
    if (picked == null) return;
    await _importFile(picked, replace: replace);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  List<LocalFileRef> get _importedFiles =>
      ref.read(documentWorkspaceProvider).importedFiles;

  LocalFileRef? get _primaryFile =>
      _importedFiles.isNotEmpty ? _importedFiles.first : null;

  LocalFileRef? _fileToOpen() {
    final state = ref.read(documentWorkspaceProvider);
    final preview = state.previewPage;
    if (preview != null && state.selectedIds.contains(preview.id)) {
      return preview.file;
    }
    final highlighted = state.highlightSourcePath;
    if (highlighted != null) {
      for (final file in state.importedFiles) {
        if (file.path == highlighted) return file;
      }
    }
    return _primaryFile;
  }

  void _openFile(LocalFileRef file, {ViewerToolId? tool}) {
    if (tool != null) {
      unawaited(
        launchWorkspaceDocumentTool(
          context: context,
          ref: ref,
          file: file,
          tool: tool,
          password: _passwordsByPath[file.path],
        ),
      );
      return;
    }
    unawaited(
      openPdfInShellViewer(
        context,
        ref,
        file,
        password: _passwordsByPath[file.path],
      ),
    );
  }

  void _openCurrent({ViewerToolId? tool}) {
    final file = _fileToOpen();
    if (file == null) {
      _snack('Add a PDF first');
      return;
    }
    _openFile(file, tool: tool);
  }

  Future<void> _insertBlank() async {
    final blank = await ref.read(blankPageFactoryProvider).blankPageFile();
    if (!mounted) return;
    _ws.insertBlankAfterSelection(blank);
  }

  void _moveSelected(int delta) {
    final st = ref.read(documentWorkspaceProvider);
    final idx = [
      for (var i = 0; i < st.pages.length; i++)
        if (st.selectedIds.contains(st.pages[i].id)) i,
    ];
    if (idx.isEmpty) return;
    // Move the group as one: step the first (or last) element repeatedly.
    final ordered = delta < 0 ? idx : idx.reversed.toList();
    for (final i in ordered) {
      _ws.moveByDelta(i, delta);
    }
  }

  /// Writes the workspace (or just the selected pages) as a new PDF.
  Future<void> _save({required bool selectionOnly}) async {
    final st = ref.read(documentWorkspaceProvider);
    final pages = selectionOnly
        ? [
            for (final p in st.pages)
              if (st.selectedIds.contains(p.id)) p,
          ]
        : st.pages;
    if (pages.isEmpty) return;
    final base = st.importedFiles.isEmpty
        ? 'workspace'
        : st.importedFiles.first.displayName.replaceFirst(
            RegExp(r'\.pdf$', caseSensitive: false),
            '',
          );
    _ws.setBusy(true, message: 'Preparing PDF…', fraction: 0.05);
    try {
      final out = await ref
          .read(pageOrganizeServiceProvider)
          .exportWorkspace(
            pages: pages,
            suggestedName: selectionOnly
                ? '$base-selection.pdf'
                : '$base-new.pdf',
            passwordsByPath: _passwordsByPath,
            onProgress: (p) =>
                _ws.setBusy(true, message: p.message, fraction: p.fraction),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved ${out.displayName}'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => _openFile(out),
          ),
        ),
      );
    } on DocumentStudioError catch (e) {
      if (mounted) _snack(e.recoveryHint ?? e.message);
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      _ws.setBusy(false);
    }
  }

  void _onSidebar(WorkspaceSidebarAction action) {
    switch (action) {
      case WorkspaceSidebarAction.addPdf:
        _pickPdf(replace: ref.read(documentWorkspaceProvider).pages.isEmpty);
    }
  }

  void _openCompactDocument(LocalFileRef file) {
    _ws.selectPagesFromSource(file.path);
    setState(() => _compactPagesOpen = true);
  }

  Future<void> _openCommandPalette() async {
    final pagesEmpty = ref.read(documentWorkspaceProvider).pages.isEmpty;
    await showDocumentStudioCommandPalette(
      context,
      leadingItems: [
        CommandPaletteItem(
          id: 'workspace_add_pdf',
          label: pagesEmpty ? 'Add PDF' : 'Add another PDF',
          subtitle: 'List the document and its pages',
          keywords: ['import', 'open', 'browse', 'workspace'],
          onInvoke: () => _pickPdf(replace: pagesEmpty),
        ),
        CommandPaletteItem(
          id: 'workspace_open_pdf',
          label: 'Open PDF',
          subtitle: 'Open the current document in the viewer',
          keywords: ['viewer', 'read'],
          onInvoke: () => _openCurrent(),
        ),
      ],
    );
  }

  List<WorkspaceDocumentToolItem> get _documentTools => [
    WorkspaceDocumentToolItem(
      id: 'watermark',
      label: 'Watermark',
      icon: Icons.branding_watermark_outlined,
      onPressed: () => _openCurrent(tool: ViewerToolId.watermark),
    ),
    WorkspaceDocumentToolItem(
      id: 'compress',
      label: 'Compress',
      icon: Icons.compress,
      onPressed: () => _openCurrent(tool: ViewerToolId.compress),
    ),
    WorkspaceDocumentToolItem(
      id: 'protect',
      label: 'Encrypt',
      icon: Icons.lock_outline,
      onPressed: () => _openCurrent(tool: ViewerToolId.protect),
    ),
    WorkspaceDocumentToolItem(
      id: 'unlock',
      label: 'Decrypt',
      icon: Icons.lock_open_outlined,
      onPressed: () => _openCurrent(tool: ViewerToolId.unlock),
    ),
    WorkspaceDocumentToolItem(
      id: 'sign',
      label: 'Sign',
      icon: Icons.draw_outlined,
      onPressed: () => _openCurrent(tool: ViewerToolId.visualSign),
    ),
    WorkspaceDocumentToolItem(
      id: 'place_image',
      label: 'Image',
      icon: Icons.image_outlined,
      onPressed: () => _openCurrent(tool: ViewerToolId.placeImage),
    ),
    WorkspaceDocumentToolItem(
      id: 'edit_text',
      label: 'Text',
      icon: Icons.text_fields,
      onPressed: () => _openCurrent(tool: ViewerToolId.editText),
    ),
    WorkspaceDocumentToolItem(
      id: 'ink',
      label: 'Draw',
      icon: Icons.gesture,
      onPressed: () => _openCurrent(tool: ViewerToolId.ink),
    ),
    WorkspaceDocumentToolItem(
      id: 'fill_form',
      label: 'Fill form',
      icon: Icons.checklist_outlined,
      onPressed: () => _openCurrent(tool: ViewerToolId.fillForm),
    ),
    WorkspaceDocumentToolItem(
      id: 'ocr',
      label: 'OCR',
      icon: Icons.document_scanner_outlined,
      onPressed: () => _openCurrent(tool: ViewerToolId.searchablePdf),
    ),
    WorkspaceDocumentToolItem(
      id: 'office_convert',
      label: 'Office',
      icon: Icons.swap_horiz,
      onPressed: () => _openCurrent(tool: ViewerToolId.officeConvert),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final wsState = ref.watch(documentWorkspaceProvider);
    final ws = _ws;
    final width = MediaQuery.sizeOf(context).width;
    final sizeClass = dsWindowSizeClassForWidth(width);
    final compact = sizeClass == DsWindowSizeClass.compact;
    final showSidebar = sizeClass != DsWindowSizeClass.compact;
    final showInspector = sizeClass == DsWindowSizeClass.expanded;
    final showCompactDocList = compact && !_compactPagesOpen;
    final busy = wsState.busy || _loadingDoc;
    final hasPages = wsState.pageCount > 0;

    final docLabel = wsState.importedFiles.isEmpty
        ? 'Document workspace'
        : wsState.importedFiles.length == 1
        ? wsState.importedFiles.first.displayName
        : '${wsState.importedFiles.length} documents · ${wsState.pageCount} pages';

    void handleBack() {
      if (compact && _compactPagesOpen) {
        setState(() => _compactPagesOpen = false);
        return;
      }
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    }

    final scaffold = Scaffold(
      appBar: DsToolbar(
        dense: compact,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: compact && _compactPagesOpen ? 'Documents' : 'Back',
          onPressed: handleBack,
        ),
        title: compact && _compactPagesOpen ? 'Pages' : 'Workspace',
        subtitle: docLabel,
        actions: [
          if (widget.returnToViewer && _primaryFile != null)
            IconButton(
              tooltip: 'Back to viewer',
              onPressed: busy ? null : () => _openFile(_primaryFile!),
              icon: const Icon(Icons.menu_book_outlined),
            ),
          IconButton(
            tooltip: hasPages ? 'Add another PDF' : 'Add PDF',
            onPressed: busy
                ? null
                : () => _pickPdf(replace: wsState.pages.isEmpty),
            icon: const Icon(Icons.add),
          ),
          if (hasPages)
            compact
                ? IconButton(
                    tooltip: 'Open PDF',
                    onPressed: busy ? null : () => _openCurrent(),
                    icon: const Icon(Icons.open_in_new),
                  )
                : Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: FilledButton.tonalIcon(
                      onPressed: busy ? null : () => _openCurrent(),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Open'),
                    ),
                  ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: showCompactDocList
                ? _buildCompactDocumentsPane(wsState: wsState, busy: busy)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showSidebar)
                        WorkspaceSidebar(
                          onAction: _onSidebar,
                          importedFiles: wsState.importedFiles,
                          pages: wsState.pages,
                          busy: busy,
                          highlightSourcePath: wsState.highlightSourcePath,
                          onDocumentTap: (file) {
                            ws.toggleHighlightSource(file.path);
                            ws.selectPagesFromSource(file.path);
                          },
                          onOpenDocument: _openFile,
                        ),
                      Expanded(
                        child: OrganizeDropTarget(
                          enabled: !wsState.busy,
                          onFilesDropped: (files) async {
                            for (var i = 0; i < files.length; i++) {
                              await _importFile(
                                files[i],
                                replace: i == 0 && wsState.pages.isEmpty,
                              );
                            }
                          },
                          child: wsState.pages.isEmpty && !_loadingDoc
                              ? WorkspaceLanding(
                                  compact: compact,
                                  onBrowse: () => _pickPdf(replace: true),
                                  onPickRecent: (f) =>
                                      _importFile(f, replace: true),
                                )
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    WorkspaceToolbar(
                                      pageCount: wsState.pageCount,
                                      selectedCount: wsState.selectedIds.length,
                                      busy: busy,
                                      canUndo: ws.canUndo,
                                      canRedo: ws.canRedo,
                                      onAddPdf: () => _pickPdf(replace: false),
                                      onSelectAll: ws.selectAll,
                                      onClearSelection: ws.clearSelection,
                                      onRotateLeft: () =>
                                          ws.rotateSelected(clockwise: false),
                                      onRotateRight: () =>
                                          ws.rotateSelected(clockwise: true),
                                      onDuplicate: ws.duplicateSelected,
                                      onDelete: ws.deleteSelected,
                                      onBlank: _insertBlank,
                                      onMoveEarlier: () => _moveSelected(-1),
                                      onMoveLater: () => _moveSelected(1),
                                      onReverse: ws.reverseAll,
                                      onUndo: ws.undo,
                                      onRedo: ws.redo,
                                      onSave: () => _save(selectionOnly: false),
                                      onSaveSelection: () =>
                                          _save(selectionOnly: true),
                                      documentTools: _documentTools,
                                    ),
                                    if (compact)
                                      OrganizeDocumentSourceChips(
                                        sources: wsState.importedFiles,
                                        pages: wsState.pages,
                                        highlightSourcePath:
                                            wsState.highlightSourcePath,
                                        enabled: !wsState.busy,
                                        onShowAll: ws.clearHighlightSource,
                                        onSourceTap: (source) {
                                          ws.toggleHighlightSource(source.path);
                                          ws.selectPagesFromSource(source.path);
                                        },
                                      ),
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: WorkspacePageGrid(
                                              pages: wsState.pages,
                                              selectedIds: wsState.selectedIds,
                                              passwordsByPath: _passwordsByPath,
                                              highlightSourcePath:
                                                  wsState.highlightSourcePath,
                                              singleTapOpens: compact,
                                              onOpenPage: (page, index) {
                                                ws.selectOnly(page.id);
                                                ws.setPreviewIndex(index);
                                                _openFile(page.file);
                                              },
                                              onSelectPage: (page, index) {
                                                ws.selectOnly(page.id);
                                                ws.setPreviewIndex(index);
                                              },
                                            ),
                                          ),
                                          if (showInspector &&
                                              wsState.previewPage != null)
                                            WorkspaceInspectorPanel(
                                              page: wsState.previewPage!,
                                              selectionCount:
                                                  wsState.selectedIds.length,
                                              passwordsByPath: _passwordsByPath,
                                              showPagePreview: false,
                                              workspaceIndex1Based:
                                                  wsState.focusPreviewIndex + 1,
                                              workspacePageCount:
                                                  wsState.pageCount,
                                              workspacePages: wsState.pages,
                                              selectedPageIds:
                                                  wsState.selectedIds,
                                              documentTools: _documentTools,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
          ),
          DsStatusBar(
            compact: true,
            leading: hasPages
                ? [
                    DsStatusMetric(
                      label: 'Pages',
                      value: '${wsState.pageCount}',
                      icon: Icons.grid_view_outlined,
                      compact: true,
                    ),
                  ]
                : const [],
            message:
                wsState.statusMessage ??
                (showCompactDocList
                    ? (wsState.importedFiles.isEmpty
                          ? 'Add a PDF to begin'
                          : 'Tap a document to see pages')
                    : (hasPages
                          ? (compact
                                ? 'Tap a page to open the PDF'
                                : 'Double-click a page to open it')
                          : 'Add a PDF to begin')),
          ),
        ],
      ),
    );

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyK, control: true):
            OpenCommandPaletteIntent(),
        SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            OpenCommandPaletteIntent(),
      },
      child: Actions(
        actions: {
          OpenCommandPaletteIntent:
              GuardedCallbackAction<OpenCommandPaletteIntent>(
                allowWhileTyping: true,
                onInvoke: (_) {
                  _openCommandPalette();
                  return null;
                },
              ),
        },
        child: Focus(
          autofocus: true,
          child: PopScope(
            canPop: !(compact && _compactPagesOpen),
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              if (compact && _compactPagesOpen) {
                setState(() => _compactPagesOpen = false);
              }
            },
            child: Stack(
              children: [
                SafeArea(child: scaffold),
                OrganizeBusyOverlay(
                  visible:
                      wsState.busy || (_loadingDoc && wsState.pages.isEmpty),
                  message: _loadingDoc && !wsState.busy
                      ? 'Opening PDF…'
                      : wsState.statusMessage,
                  progress: wsState.progressFraction,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactDocumentsPane({
    required OrganizeWorkspaceState wsState,
    required bool busy,
  }) {
    if (wsState.importedFiles.isEmpty && !_loadingDoc) {
      return WorkspaceLanding(
        compact: true,
        onBrowse: () => _pickPdf(replace: true),
        onPickRecent: (f) => _importFile(f, replace: true),
      );
    }

    return OrganizeDropTarget(
      enabled: !busy,
      onFilesDropped: (files) async {
        for (var i = 0; i < files.length; i++) {
          await _importFile(files[i], replace: i == 0 && wsState.pages.isEmpty);
        }
      },
      child: WorkspaceSidebar(
        fullWidth: true,
        onAction: _onSidebar,
        importedFiles: wsState.importedFiles,
        pages: wsState.pages,
        busy: busy,
        highlightSourcePath: wsState.highlightSourcePath,
        onDocumentTap: _openCompactDocument,
        onOpenDocument: _openFile,
      ),
    );
  }
}
