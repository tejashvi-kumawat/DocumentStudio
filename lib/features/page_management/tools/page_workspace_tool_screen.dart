import 'package:document_studio/app/keyboard/text_input_guard.dart';
import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/jobs/job_models.dart';
import 'package:document_studio/core/storage/persisted_document_access.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/organize/organize_page_ref.dart';
import 'package:document_studio/features/page_management/organize_workspace_notifier.dart';
import 'package:document_studio/features/page_management/organize_pdf_import.dart';
import 'package:document_studio/features/page_management/pdf_password_prompt.dart';
import 'package:document_studio/features/page_management/shared/organize_accessible_files.dart';
import 'package:document_studio/features/page_management/shared/organize_tool_scaffold.dart';
import 'package:document_studio/features/page_management/shared/organize_export_preview_dialog.dart';
import 'package:document_studio/features/page_management/shared/organize_context_toolbar.dart';
import 'package:document_studio/features/page_management/shared/organize_document_source_chips.dart';
import 'package:document_studio/features/page_management/shared/organize_drop_zone.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_shell_page.dart';
import 'package:document_studio/design_system/shell/ds_status_bar.dart';
import 'package:document_studio/design_system/widgets/ds_active_document_strip.dart';
import 'package:document_studio/features/document_lifecycle/document_save_result_actions.dart';
import 'package:document_studio/features/page_management/shared/organize_tool_source_bar.dart';
import 'package:document_studio/features/page_management/shared/organize_workflow_strip.dart';
import 'package:document_studio/features/page_management/widgets/organize_drop_target.dart';
import 'package:document_studio/features/page_management/widgets/organize_page_grid.dart';
import 'package:document_studio/features/document_workspace/workspace_inspector_panel.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Per-tool behavior for thumbnail workspace flows (reorder, delete, extract, etc.).
class PageWorkspaceToolConfig {
  const PageWorkspaceToolConfig({
    required this.title,
    required this.subtitle,
    required this.exportLabel,
    this.allowAddPdf = false,
    this.exportSelectionOnly = false,
    this.showDuplicate = false,
    this.showRotate = false,
    this.showDelete = true,
    this.showExtract = false,
    this.promptReverseBeforeExport = false,
    this.exportOdd = false,
    this.exportEven = false,
    this.confirmRemoveSelected = false,
    this.confirmBeforeExport = false,
    this.showInsertBlank = false,
    this.showReplace = false,
    this.showRotate180 = false,
  });

  final String title;
  final String subtitle;
  final String exportLabel;
  final bool allowAddPdf;
  final bool exportSelectionOnly;
  final bool showDuplicate;
  final bool showRotate;
  final bool showDelete;
  final bool showExtract;
  final bool promptReverseBeforeExport;
  final bool exportOdd;
  final bool exportEven;
  final bool confirmRemoveSelected;
  final bool confirmBeforeExport;
  final bool showInsertBlank;
  final bool showReplace;
  final bool showRotate180;

  static PageWorkspaceToolConfig forToolId(String id) => switch (id) {
    'reorder' => const PageWorkspaceToolConfig(
      title: 'Reorder pages',
      subtitle: 'Drag pages or use arrows, then export',
      exportLabel: 'Save reordered PDF',
      allowAddPdf: false,
      showDelete: false,
    ),
    'delete' => const PageWorkspaceToolConfig(
      title: 'Delete pages',
      subtitle: 'Select pages → remove → review → save remaining pages',
      exportLabel: 'Save PDF without deleted pages',
      showDelete: true,
      confirmRemoveSelected: true,
      confirmBeforeExport: true,
    ),
    'extract' => const PageWorkspaceToolConfig(
      title: 'Extract pages',
      subtitle: 'Select pages → preview → save as a new PDF',
      exportLabel: 'Save extracted pages',
      exportSelectionOnly: true,
      showExtract: true,
      showDelete: false,
      confirmBeforeExport: true,
    ),
    'rotate' => const PageWorkspaceToolConfig(
      title: 'Rotate pages',
      subtitle: 'Select pages and rotate 90°, then export',
      exportLabel: 'Save rotated PDF',
      showRotate: true,
      showRotate180: true,
      showDelete: false,
    ),
    'duplicate' => const PageWorkspaceToolConfig(
      title: 'Duplicate pages',
      subtitle: 'Select pages to duplicate in place, then export',
      exportLabel: 'Save PDF with duplicates',
      showDuplicate: true,
      showDelete: false,
    ),
    'reverse' => const PageWorkspaceToolConfig(
      title: 'Reverse page order',
      subtitle: 'Load a PDF, reverse all pages, then export',
      exportLabel: 'Save reversed PDF',
      showDelete: false,
      promptReverseBeforeExport: true,
    ),
    'odd-pages' => const PageWorkspaceToolConfig(
      title: 'Extract odd pages',
      subtitle: 'Pages 1, 3, 5… from your PDF',
      exportLabel: 'Save odd pages',
      showDelete: false,
      exportOdd: true,
    ),
    'even-pages' => const PageWorkspaceToolConfig(
      title: 'Extract even pages',
      subtitle: 'Pages 2, 4, 6… from your PDF',
      exportLabel: 'Save even pages',
      showDelete: false,
      exportEven: true,
    ),
    'insert' => const PageWorkspaceToolConfig(
      title: 'Insert pages',
      subtitle: 'Open the document to edit, add pages from another PDF, drag thumbnails to position',
      exportLabel: 'Save combined PDF',
      allowAddPdf: true,
      showDelete: false,
    ),
    'replace' => const PageWorkspaceToolConfig(
      title: 'Replace pages',
      subtitle: 'Select pages, choose replacement from another PDF',
      exportLabel: 'Save PDF with replacements',
      showDelete: false,
      showReplace: true,
      confirmBeforeExport: true,
    ),
    'blank-page' => const PageWorkspaceToolConfig(
      title: 'Add blank page',
      subtitle: 'Select position, insert blank pages, export',
      exportLabel: 'Save PDF with blank pages',
      showDelete: false,
      showInsertBlank: true,
    ),
    _ => const PageWorkspaceToolConfig(
      title: 'Page tool',
      subtitle: '',
      exportLabel: 'Export PDF',
    ),
  };

  /// Resolves workspace pages passed to [PageOrganizeService.exportWorkspace].
  List<OrganizePageRef> resolveExportPages(
    OrganizeWorkspaceState wsState, {
    required List<OrganizePageRef> Function({required bool odd}) oddEvenPages,
  }) {
    if (exportOdd) return oddEvenPages(odd: true);
    if (exportEven) return oddEvenPages(odd: false);
    if (exportSelectionOnly) {
      return wsState.pages
          .where((p) => wsState.selectedIds.contains(p.id))
          .toList();
    }
    return wsState.pages;
  }
}

class PageWorkspaceToolScreen extends ConsumerStatefulWidget {
  const PageWorkspaceToolScreen({
    super.key,
    required this.toolId,
    this.initialFile,
    this.initialPassword,
  });

  final String toolId;
  final LocalFileRef? initialFile;
  final String? initialPassword;

  @override
  ConsumerState<PageWorkspaceToolScreen> createState() =>
      _PageWorkspaceToolScreenState();
}

class _PageWorkspaceToolScreenState
    extends ConsumerState<PageWorkspaceToolScreen> {
  final _passwordsByPath = <String, String>{};
  bool _loadingDoc = false;
  JobHandle<LocalFileRef>? _activeJob;

  /// Insert-before index for [insert] tool (0..pageCount).
  int _insertAtIndex = 0;

  PageWorkspaceToolConfig get _config =>
      PageWorkspaceToolConfig.forToolId(widget.toolId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(organizeWorkspaceProvider.notifier).reset();
      final seeded = _resolveSeedDocument();
      if (seeded == null) return;
      final (file, password) = seeded;
      if (password != null && password.isNotEmpty) {
        _passwordsByPath[file.path] = password;
      }
      _importFile(file, replace: true);
    });
  }

  /// Prefer the route handoff; otherwise the PDF already open in the viewer.
  (LocalFileRef, String?)? _resolveSeedDocument() {
    final routed = widget.initialFile;
    if (routed != null) {
      return (routed, widget.initialPassword);
    }
    final tab = ref.read(documentTabsControllerProvider).activeTab;
    if (tab == null) return null;
    return (tab.file, tab.password ?? widget.initialPassword);
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
      var resolved = file;
      if (file.contentUri != null || file.path.startsWith('content://')) {
        final materialized =
            await PersistedDocumentAccess.materializeForOpen(file);
        if (materialized == null) {
          if (mounted) {
            _snack('Could not open that document from storage access.');
          }
          return;
        }
        resolved = materialized;
      }
      final count = await _loadPageCount(resolved);
      if (count == null || count < 1) return;
      final ws = ref.read(organizeWorkspaceProvider.notifier);
      if (replace || ref.read(organizeWorkspaceProvider).pages.isEmpty) {
        ws.loadPagesFromFile(resolved, count);
        if (widget.toolId == 'insert' && mounted) {
          setState(() => _insertAtIndex = count);
        }
      } else if (widget.toolId == 'insert') {
        ws.insertPagesFromFileAt(resolved, count, _insertAtIndex);
        if (mounted) {
          final nextCount = ref.read(organizeWorkspaceProvider).pageCount;
          setState(
            () => _insertAtIndex = (_insertAtIndex + count).clamp(0, nextCount),
          );
        }
      } else {
        ws.appendAllPagesFromFile(resolved, count);
      }
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

  String? _exportPreviewFootnote() {
    if (!_config.confirmBeforeExport) return null;
    return switch (widget.toolId) {
      'delete' => 'Removed pages will not appear in the saved file.',
      'extract' => 'The new PDF contains only the pages listed above.',
      'replace' => 'Replacements are applied in the order shown.',
      _ => null,
    };
  }

  Future<void> _insertBlankPage() async {
    final blank = await ref.read(blankPageFactoryProvider).blankPageFile();
    ref
        .read(organizeWorkspaceProvider.notifier)
        .insertBlankAfterSelection(blank);
  }

  Future<void> _replaceFromPdf() async {
    final sel = ref.read(organizeWorkspaceProvider).selectedIds.length;
    if (sel == 0) {
      _snack('Select pages to replace first');
      return;
    }
    final picked = await ref
        .read(fileStorageProvider)
        .pickOpenFile(allowedExtensions: ['pdf']);
    if (picked == null) return;
    final count = await _loadPageCount(picked);
    if (count == null) return;
    if (count < sel && mounted) {
      _snack(
        'Replacement PDF has fewer pages than selection; matching 1:1 in order',
      );
    }
    ref
        .read(organizeWorkspaceProvider.notifier)
        .replaceSelectedFromFile(picked, count);
  }

  Future<void> _removeSelectedWithConfirm() async {
    final count = ref.read(organizeWorkspaceProvider).selectedIds.length;
    if (count == 0) return;
    if (_config.confirmRemoveSelected) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remove selected pages?'),
          content: Text(
            'Remove $count page${count == 1 ? '' : 's'} from the workspace. '
            'You can undo before saving.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    ref.read(organizeWorkspaceProvider.notifier).deleteSelected();
  }

  Future<bool?> _confirmExport(int pageCount) {
    final cfg = _config;
    final message = switch (widget.toolId) {
      'delete' =>
        'Save a new PDF with $pageCount page${pageCount == 1 ? '' : 's'} '
            '(removed pages are not recoverable after export).',
      'extract' =>
        'Create a new PDF containing $pageCount selected '
            'page${pageCount == 1 ? '' : 's'}?',
      _ => 'Export $pageCount page${pageCount == 1 ? '' : 's'}?',
    };
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(cfg.exportLabel),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _setInsertAtIndex(
    int index,
    OrganizeWorkspaceNotifier ws,
    int pageCount,
  ) {
    final at = index.clamp(0, pageCount);
    setState(() => _insertAtIndex = at);
    ws.setPreviewIndex(pageCount == 0 ? 0 : at.clamp(0, pageCount - 1));
  }

  List<OrganizePageRef> _pagesForExport() {
    final wsState = ref.read(organizeWorkspaceProvider);
    final ws = ref.read(organizeWorkspaceProvider.notifier);
    return _config.resolveExportPages(
      wsState,
      oddEvenPages: ws.pagesForOddEven,
    );
  }

  Future<void> _export() async {
    final ws = ref.read(organizeWorkspaceProvider.notifier);
    if (_config.promptReverseBeforeExport) ws.reverseAll();
    final pages = _pagesForExport();
    if (pages.isEmpty) {
      _snack(
        _config.exportSelectionOnly
            ? 'Select one or more pages first'
            : 'Load a PDF first',
      );
      return;
    }
    final previewOk = await showOrganizeExportPreview(
      context: context,
      title: _config.exportLabel,
      subtitle: _config.subtitle,
      footnote: _exportPreviewFootnote(),
      pages: pages,
      passwordsByPath: _passwordsByPath,
    );
    if (previewOk != true || !mounted) return;
    if (_config.confirmBeforeExport) {
      final ok = await _confirmExport(pages.length);
      if (ok != true || !mounted) return;
    }
    ws.setBusy(true, message: 'Exporting…', fraction: 0.1);
    final job = JobHandle<LocalFileRef>();
    setState(() => _activeJob = job);
    try {
      final out = await ref
          .read(pageOrganizeServiceProvider)
          .exportWorkspace(
            handle: job,
            pages: pages,
            suggestedName: '${widget.toolId}-output.pdf',
            passwordsByPath: _passwordsByPath,
            onProgress: (p) =>
                ws.setBusy(true, message: p.message, fraction: p.fraction),
          );
      if (!mounted) return;
      await ref.read(recentsProvider.notifier).addRecent(out);
      if (!context.mounted) return;
      showDocumentSaveResultActions(
        context,
        file: out,
        password: _passwordsByPath[out.path],
        message: 'Saved ${out.displayName}',
      );
    } on DocumentStudioError catch (e) {
      if (!mounted) return;
      _snack(e.recoveryHint ?? e.message);
    } finally {
      ws.setBusy(false);
      if (mounted) setState(() => _activeJob = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wsState = ref.watch(organizeWorkspaceProvider);
    final ws = ref.read(organizeWorkspaceProvider.notifier);
    final cfg = _config;
    final sizeClass =
        dsWindowSizeClassForWidth(MediaQuery.sizeOf(context).width);
    final showInspector = sizeClass == DsWindowSizeClass.expanded;

    return Shortcuts(
      shortcuts: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            const _UndoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
            const _UndoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true):
            const _RedoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyA, control: true):
            const _SelectAllIntent(),
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
            const _SelectAllIntent(),
        const SingleActivator(LogicalKeyboardKey.delete): const _DeleteIntent(),
      },
      child: Actions(
        actions: {
          _UndoIntent: GuardedCallbackAction<_UndoIntent>(
            onInvoke: (_) {
              ws.undo();
              return null;
            },
          ),
          _RedoIntent: GuardedCallbackAction<_RedoIntent>(
            onInvoke: (_) {
              ws.redo();
              return null;
            },
          ),
          _SelectAllIntent: GuardedCallbackAction<_SelectAllIntent>(
            onInvoke: (_) {
              ws.selectAll();
              return null;
            },
          ),
          _DeleteIntent: GuardedCallbackAction<_DeleteIntent>(
            onInvoke: (_) {
              if (cfg.showDelete) _removeSelectedWithConfirm();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: OrganizeToolScaffold(
            title: cfg.title,
            subtitle: wsState.importedFiles.isEmpty
                ? cfg.subtitle
                : '${wsState.importedFiles.first.displayName} · '
                      '${wsState.pageCount} pages',
            busy: wsState.busy || _loadingDoc,
            statusMessage: wsState.statusMessage,
            progress: wsState.progressFraction,
            onCancel: _activeJob == null
                ? null
                : () => ref.read(jobRunnerProvider).requestCancel(_activeJob!),
            actions: [
              IconButton(
                tooltip: 'Undo (Ctrl+Z)',
                icon: const Icon(Icons.undo),
                onPressed: wsState.busy ? null : ws.undo,
              ),
              IconButton(
                tooltip: 'Redo (Ctrl+Y)',
                icon: const Icon(Icons.redo),
                onPressed: wsState.busy ? null : ws.redo,
              ),
              FilledButton(
                onPressed: wsState.pages.isEmpty || wsState.busy
                    ? null
                    : _export,
                child: Text(cfg.exportLabel),
              ),
            ],
            body: OrganizeDropTarget(
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
                  ? _EmptyPrompt(
                      onPick: () => _pickPdf(replace: true),
                      onOpenFile: (file) => _importFile(file, replace: true),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_toolSteps(widget.toolId) != null)
                          OrganizeToolStepStrip(
                            steps: _toolSteps(widget.toolId)!,
                            activeIndex: _activeStepIndex(
                              widget.toolId,
                              selectedCount: wsState.selectedIds.length,
                              pageCount: wsState.pageCount,
                            ),
                          ),
                        if (wsState.importedFiles.isNotEmpty)
                          DsActiveDocumentStrip(
                            fileName: wsState.importedFiles.first.displayName,
                            pageCount: wsState.pageCount,
                            busy: wsState.busy || _loadingDoc,
                            onChangeFile: widget.initialFile == null
                                ? () => _pickPdf(replace: true)
                                : null,
                          ),
                        OrganizeToolSourceBar(
                          busy: wsState.busy,
                          onOpenPdf: widget.initialFile == null
                              ? () => _pickPdf(replace: true)
                              : null,
                          onInsertFromPdf: cfg.allowAddPdf
                              ? () => _pickPdf(replace: false)
                              : null,
                          onReverseAll: cfg.promptReverseBeforeExport
                              ? ws.reverseAll
                              : null,
                        ),
                        if (widget.toolId == 'insert' &&
                            wsState.pages.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Insert at page',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Slider.adaptive(
                                        min: 0,
                                        max: wsState.pageCount.toDouble(),
                                        divisions: wsState.pageCount,
                                        value: _insertAtIndex
                                            .clamp(0, wsState.pageCount)
                                            .toDouble(),
                                        label: '$_insertAtIndex',
                                        onChanged: wsState.busy
                                            ? null
                                            : (v) => _setInsertAtIndex(
                                                v.round(),
                                                ws,
                                                wsState.pageCount,
                                              ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 48,
                                      child: Text(
                                        '$_insertAtIndex',
                                        textAlign: TextAlign.end,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  _insertAtIndex >= wsState.pageCount
                                      ? 'New pages append after page ${wsState.pageCount}'
                                      : 'New pages insert before page ${_insertAtIndex + 1}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        if (cfg.allowAddPdf &&
                            wsState.importedFiles.length >= 2)
                          OrganizeDocumentSourceChips(
                            sources: wsState.importedFiles,
                            pages: wsState.pages,
                            highlightSourcePath: wsState.highlightSourcePath,
                            enabled: !wsState.busy,
                            onShowAll: ws.clearHighlightSource,
                            onSourceTap: (source) {
                              ws.toggleHighlightSource(source.path);
                              ws.selectPagesFromSource(source.path);
                            },
                          ),
                        OrganizeContextToolbar(
                          pageCount: wsState.pages.length,
                          selectionCount: wsState.selectedIds.length,
                          busy: wsState.busy,
                          onSelectAll: ws.selectAll,
                          onClearSelection: ws.clearSelection,
                          onRotateCw: cfg.showRotate
                              ? () => ws.rotateSelected(clockwise: true)
                              : null,
                          onRotateCcw: cfg.showRotate
                              ? () => ws.rotateSelected(clockwise: false)
                              : null,
                          onRotate180: cfg.showRotate180
                              ? () => ws.rotateSelected(
                                  clockwise: true,
                                  degrees: 180,
                                )
                              : null,
                          onDuplicate: cfg.showDuplicate
                              ? ws.duplicateSelected
                              : null,
                          onDelete: cfg.showDelete
                              ? _removeSelectedWithConfirm
                              : null,
                          onInsertBlank: cfg.showInsertBlank
                              ? _insertBlankPage
                              : null,
                          onReplace: cfg.showReplace ? _replaceFromPdf : null,
                        ),
                        if (wsState.pages.isNotEmpty)
                          OrganizeWorkflowStrip(
                            tone: widget.toolId == 'delete'
                                ? OrganizeWorkflowTone.warning
                                : OrganizeWorkflowTone.info,
                            message: _workflowMessage(
                              toolId: widget.toolId,
                              total: wsState.pages.length,
                              selected: wsState.selectedIds.length,
                            ),
                          ),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: OrganizePageGrid(
                                  pages: wsState.pages,
                                  selectedIds: wsState.selectedIds,
                                  passwordsByPath: _passwordsByPath,
                                  highlightSourcePath:
                                      wsState.highlightSourcePath,
                                  enableMarqueeSelection:
                                      cfg.exportSelectionOnly ? true : null,
                                  onTap:
                                      (
                                        page,
                                        index, {
                                        required shift,
                                        required ctrlOrMeta,
                                      }) {
                                        if (shift) {
                                          ws.selectRangeTo(page.id);
                                        } else if (ctrlOrMeta) {
                                          ws.selectOnly(
                                            page.id,
                                            additive: true,
                                          );
                                        } else {
                                          ws.selectOnly(page.id);
                                        }
                                        if (widget.toolId == 'insert') {
                                          _setInsertAtIndex(
                                            index,
                                            ws,
                                            wsState.pages.length,
                                          );
                                        } else {
                                          ws.setPreviewIndex(index);
                                        }
                                      },
                                  onReorder: ws.reorder,
                                  onMoveDelta: ws.moveByDelta,
                                  onMarqueeSelect: (ids, {required additive}) {
                                    ws.applyMarqueeSelection(
                                      ids,
                                      additive: additive,
                                    );
                                  },
                                  onContextAction: (action, index) {
                                    final page = wsState.pages[index];
                                    ws.selectOnly(page.id);
                                    switch (action) {
                                      case 'duplicate':
                                        ws.duplicateSelected();
                                      case 'delete':
                                        ws.deleteSelected();
                                      case 'rotate_cw':
                                        ws.rotateSelected(clockwise: true);
                                    }
                                  },
                                ),
                              ),
                              if (showInspector && wsState.previewPage != null)
                                WorkspaceInspectorPanel(
                                  page: wsState.previewPage!,
                                  selectionCount: wsState.selectedIds.length,
                                  passwordsByPath: _passwordsByPath,
                                  workspaceIndex1Based:
                                      wsState.focusPreviewIndex + 1,
                                  workspacePageCount: wsState.pageCount,
                                  workspacePages: wsState.pages,
                                  selectedPageIds: wsState.selectedIds,
                                ),
                            ],
                          ),
                        ),
                        DsStatusBar(
                          compact: true,
                          leading: [
                            DsStatusMetric(
                              label: 'Pages',
                              value: '${wsState.pageCount}',
                              icon: Icons.view_module_outlined,
                              compact: true,
                            ),
                            if (wsState.selectedIds.isNotEmpty)
                              DsStatusMetric(
                                label: 'Selected',
                                value: '${wsState.selectedIds.length}',
                                icon: Icons.check_box_outlined,
                                compact: true,
                              ),
                          ],
                          message:
                              wsState.statusMessage ??
                              'Ctrl+A · select all · Ctrl+Enter · ${cfg.exportLabel}',
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

List<String>? _toolSteps(String toolId) => switch (toolId) {
  'delete' => const ['Select pages', 'Remove', 'Export PDF'],
  'extract' => const ['Select pages', 'Preview & export'],
  'replace' => const ['Select pages', 'Replace from PDF', 'Export'],
  'rotate' => const ['Select pages', 'Rotate', 'Export'],
  'reorder' => const ['Reorder thumbnails', 'Export PDF'],
  'duplicate' => const ['Select pages', 'Duplicate', 'Export PDF'],
  'reverse' => const ['Open PDF', 'Reverse order', 'Export PDF'],
  'odd-pages' || 'even-pages' => const ['Open PDF', 'Preview & export'],
  'insert' => const ['Add PDFs', 'Position pages', 'Export PDF'],
  'blank-page' => const ['Open PDF', 'Insert blank', 'Export PDF'],
  _ => null,
};

int _activeStepIndex(
  String toolId, {
  required int selectedCount,
  required int pageCount,
}) {
  if (pageCount == 0) return 0;
  if (selectedCount == 0) {
    return switch (toolId) {
      'reverse' || 'insert' => 1,
      'odd-pages' || 'even-pages' => 1,
      _ => 0,
    };
  }
  return switch (toolId) {
    'delete' || 'extract' || 'rotate' || 'replace' || 'duplicate' => 1,
    'reorder' => 1,
    'reverse' => 1,
    'odd-pages' || 'even-pages' => 1,
    'insert' => 1,
    'blank-page' => 1,
    _ => 0,
  };
}

String _workflowMessage({
  required String toolId,
  required int total,
  required int selected,
}) {
  return switch (toolId) {
    'delete' =>
      selected > 0
          ? '$selected of $total pages selected — Remove, then save the rest'
          : '$total pages — select pages to remove, undo available until export',
    'extract' =>
      selected > 0
          ? '$selected page${selected == 1 ? '' : 's'} will go into the new PDF — preview before save'
          : 'Select pages (tap, shift-range, or marquee) — undo until export',
    'rotate' =>
      selected > 0
          ? 'Rotating $selected page${selected == 1 ? '' : 's'} — preview updates on export'
          : 'Select pages to rotate, or use Select all',
    'reorder' => '$total pages — drag thumbnails to reorder, then save',
    'insert' =>
      '$total pages — use Insert from PDF, drag to position, then save',
    'odd-pages' =>
      '$total pages — export saves pages 1, 3, 5…; preview before save',
    'even-pages' =>
      '$total pages — export saves pages 2, 4, 6…; preview before save',
    'duplicate' =>
      selected > 0
          ? 'Duplicating $selected page${selected == 1 ? '' : 's'} in place — preview before save'
          : 'Select pages to duplicate, or use Select all',
    'reverse' =>
      '$total pages — Reverse all applies before export; preview before save',
    'blank-page' =>
      selected > 0
          ? 'Blank page inserts after selection — preview before save'
          : 'Select a page (or tap a thumbnail) for insert position',
    _ => '$total pages${selected > 0 ? ' · $selected selected' : ''}',
  };
}

class _EmptyPrompt extends StatelessWidget {
  const _EmptyPrompt({required this.onPick, required this.onOpenFile});
  final VoidCallback onPick;
  final void Function(LocalFileRef file) onOpenFile;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < DsSpacing.breakpointCompact;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: compact ? double.infinity : DsSpacing.formMaxWidth,
        ),
        child: Padding(
          padding: EdgeInsets.all(
            compact ? DsSpacing.pagePaddingCompact : DsSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OrganizeDropZone(
                onBrowse: onPick,
                title: 'Open a PDF',
                subtitle:
                    'Drop a file here, pick a recent/granted file below, or browse',
                compact: compact,
              ),
              const SizedBox(height: DsSpacing.md),
              OrganizeAccessibleFilesList(onOpen: onOpenFile),
            ],
          ),
        ),
      ),
    );
  }
}

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}

class _SelectAllIntent extends Intent {
  const _SelectAllIntent();
}

class _DeleteIntent extends Intent {
  const _DeleteIntent();
}
