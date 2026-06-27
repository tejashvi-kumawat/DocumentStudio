import 'package:document_studio/app/keyboard/text_input_guard.dart';
import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_toolbar.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/organize/organize_page_ref.dart';
import 'package:document_studio/features/page_management/organize_workspace_notifier.dart';
import 'package:document_studio/features/page_management/pdf_password_prompt.dart';
import 'package:document_studio/features/page_management/widgets/organize_page_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

class OrganizeScreen extends ConsumerStatefulWidget {
  const OrganizeScreen({super.key, this.initialFile});

  final LocalFileRef? initialFile;

  @override
  ConsumerState<OrganizeScreen> createState() => _OrganizeScreenState();
}

class _OrganizeScreenState extends ConsumerState<OrganizeScreen> {
  final _passwordsByPath = <String, String>{};
  bool _loadingDoc = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialFile != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _importFile(widget.initialFile!, replace: true);
      });
    }
  }

  Future<int?> _loadPageCount(LocalFileRef file) async {
    final pdf = ref.read(pdfRenderPortProvider);
    try {
      final info = await pdf.loadInfo(
        file,
        password: _passwordsByPath[file.path],
      );
      return info.pageCount;
    } on DocumentStudioError catch (e) {
      if (e.code != DocumentStudioErrorCode.passwordRequired) rethrow;
      if (!mounted) return null;
      final password = await promptPdfPassword(context);
      if (password == null || password.isEmpty) return null;
      _passwordsByPath[file.path] = password;
      final info = await pdf.loadInfo(file, password: password);
      return info.pageCount;
    }
  }

  Future<void> _importFile(LocalFileRef file, {required bool replace}) async {
    setState(() => _loadingDoc = true);
    ref
        .read(organizeWorkspaceProvider.notifier)
        .setBusy(true, message: 'Loading ${file.displayName}…');
    try {
      final count = await _loadPageCount(file);
      if (count == null || count < 1) return;
      final ws = ref.read(organizeWorkspaceProvider.notifier);
      if (replace || ref.read(organizeWorkspaceProvider).pages.isEmpty) {
        ws.loadPagesFromFile(file, count);
      } else {
        ws.appendAllPagesFromFile(file, count);
      }
    } on DocumentStudioError catch (e) {
      if (!mounted) return;
      _showError(e);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      ref.read(organizeWorkspaceProvider.notifier).setBusy(false);
      if (mounted) setState(() => _loadingDoc = false);
    }
  }

  Future<void> _pickPdf({required bool replace}) async {
    final storage = ref.read(fileStorageProvider);
    final picked = await storage.pickOpenFile(allowedExtensions: ['pdf']);
    if (picked == null) return;
    await _importFile(picked, replace: replace);
  }

  Future<void> _export({required String suggestedName}) async {
    final wsState = ref.read(organizeWorkspaceProvider);
    if (wsState.pages.isEmpty) return;
    final ws = ref.read(organizeWorkspaceProvider.notifier);
    ws.setBusy(true, message: 'Preparing export…', fraction: 0.05);
    try {
      final svc = ref.read(pageOrganizeServiceProvider);
      final out = await svc.exportWorkspace(
        pages: wsState.pages,
        suggestedName: suggestedName,
        passwordsByPath: _passwordsByPath,
        onProgress: (p) {
          ws.setBusy(true, message: p.message, fraction: p.fraction);
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved ${out.displayName}')));
    } on DocumentStudioError catch (e) {
      if (!mounted) return;
      _showError(e);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      ws.setBusy(false);
    }
  }

  Future<void> _splitDialog() async {
    final wsState = ref.read(organizeWorkspaceProvider);
    if (wsState.pages.isEmpty) return;
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) => _SplitEveryNDialog(maxPages: wsState.pageCount),
    );
    if (n == null || n < 1) return;
    final first = wsState.pages.first.file;
    final ws = ref.read(organizeWorkspaceProvider.notifier);
    ws.setBusy(true, message: 'Splitting…', fraction: 0.1);
    try {
      final svc = ref.read(pageOrganizeServiceProvider);
      final parts = await svc.splitEveryNAndPromptSave(
        input: first,
        pagesPerFile: n,
        namePrefix: p.basenameWithoutExtension(first.displayName),
        password: _passwordsByPath[first.path],
        onProgress: (p) =>
            ws.setBusy(true, message: p.message, fraction: p.fraction),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved ${parts.length} files')));
    } on DocumentStudioError catch (e) {
      if (!mounted) return;
      _showError(e);
    } finally {
      ws.setBusy(false);
    }
  }

  void _showError(DocumentStudioError e) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.recoveryHint ?? e.message)));
  }

  void _handlePageTap(
    OrganizePageRef page,
    int index, {
    required bool shift,
    required bool ctrlOrMeta,
  }) {
    final ws = ref.read(organizeWorkspaceProvider.notifier);
    if (shift) {
      ws.selectRangeTo(page.id);
    } else if (ctrlOrMeta) {
      ws.selectOnly(page.id, additive: true);
    } else {
      ws.selectOnly(page.id);
    }
    ws.setPreviewIndex(index);
  }

  Future<void> _exportSelection({required String label}) async {
    final wsState = ref.read(organizeWorkspaceProvider);
    final selected = wsState.pages
        .where((p) => wsState.selectedIds.contains(p.id))
        .toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select one or more pages first')),
      );
      return;
    }
    final ws = ref.read(organizeWorkspaceProvider.notifier);
    ws.setBusy(true, message: label, fraction: 0.1);
    try {
      final svc = ref.read(pageOrganizeServiceProvider);
      final out = await svc.exportWorkspace(
        pages: selected,
        suggestedName: 'extract.pdf',
        passwordsByPath: _passwordsByPath,
        onProgress: (p) =>
            ws.setBusy(true, message: p.message, fraction: p.fraction),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved ${out.displayName}')));
    } on DocumentStudioError catch (e) {
      if (!mounted) return;
      _showError(e);
    } finally {
      ws.setBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wsState = ref.watch(organizeWorkspaceProvider);
    final ws = ref.read(organizeWorkspaceProvider.notifier);
    final wide =
        MediaQuery.sizeOf(context).width >= DsSpacing.breakpointExpanded;
    final preview = wsState.previewPage;

    return Shortcuts(
      shortcuts: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            const _OrganizeUndoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
            const _OrganizeUndoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true):
            const _OrganizeRedoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyA, control: true):
            const _OrganizeSelectAllIntent(),
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
            const _OrganizeSelectAllIntent(),
        const SingleActivator(LogicalKeyboardKey.delete):
            const _OrganizeDeleteIntent(),
      },
      child: Actions(
        actions: {
          _OrganizeUndoIntent: GuardedCallbackAction<_OrganizeUndoIntent>(
            onInvoke: (_) {
              ws.undo();
              return null;
            },
          ),
          _OrganizeRedoIntent: GuardedCallbackAction<_OrganizeRedoIntent>(
            onInvoke: (_) {
              ws.redo();
              return null;
            },
          ),
          _OrganizeSelectAllIntent:
              GuardedCallbackAction<_OrganizeSelectAllIntent>(
                onInvoke: (_) {
                  ws.selectAll();
                  return null;
                },
              ),
          _OrganizeDeleteIntent: GuardedCallbackAction<_OrganizeDeleteIntent>(
            onInvoke: (_) {
              ws.deleteSelected();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            children: [
              Scaffold(
                appBar: DsToolbar(
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.pop(),
                  ),
                  title: 'Organize pages',
                  subtitle: wsState.pages.isEmpty
                      ? 'Import PDFs to begin'
                      : '${wsState.pageCount} pages in workspace',
                  actions: [
                    IconButton(
                      tooltip: 'Undo',
                      icon: const Icon(Icons.undo),
                      onPressed: wsState.busy ? null : ws.undo,
                    ),
                    IconButton(
                      tooltip: 'Redo',
                      icon: const Icon(Icons.redo),
                      onPressed: wsState.busy ? null : ws.redo,
                    ),
                    IconButton(
                      tooltip: 'Export PDF',
                      icon: const Icon(Icons.save_alt),
                      onPressed: wsState.pages.isEmpty || wsState.busy
                          ? null
                          : () => _export(suggestedName: 'organized.pdf'),
                    ),
                    PopupMenuButton<String>(
                      enabled: !wsState.busy && wsState.pages.isNotEmpty,
                      icon: const Icon(Icons.more_vert),
                      onSelected: (v) async {
                        switch (v) {
                          case 'split':
                            await _splitDialog();
                          case 'reverse':
                            ws.reverseAll();
                          case 'odd':
                            await _exportOddEven(odd: true);
                          case 'even':
                            await _exportOddEven(odd: false);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'split',
                          child: Text('Split every N pages…'),
                        ),
                        const PopupMenuItem(
                          value: 'reverse',
                          child: Text('Reverse page order'),
                        ),
                        const PopupMenuItem(
                          value: 'odd',
                          child: Text('Export odd pages'),
                        ),
                        const PopupMenuItem(
                          value: 'even',
                          child: Text('Export even pages'),
                        ),
                      ],
                    ),
                  ],
                ),
                body: wsState.pages.isEmpty && !_loadingDoc
                    ? _EmptyOrganizeWorkspace(
                        onOpen: () => _pickPdf(replace: true),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (wide)
                            SizedBox(
                              width: 220,
                              child: _SourcesPanel(
                                files: wsState.importedFiles,
                                onAdd: () => _pickPdf(replace: false),
                                onOpenReplace: () => _pickPdf(replace: true),
                              ),
                            ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (!wide)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      8,
                                      12,
                                      0,
                                    ),
                                    child: Row(
                                      children: [
                                        DsSecondaryButton(
                                          label: 'Add PDF',
                                          icon: Icons.add,
                                          onPressed: wsState.busy
                                              ? null
                                              : () => _pickPdf(replace: false),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${wsState.selectedIds.length} selected',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                _OrganizeActionBar(
                                  busy: wsState.busy,
                                  hasSelection: wsState.selectedIds.isNotEmpty,
                                  onExtract: () =>
                                      _exportSelection(label: 'Extracting…'),
                                  onDelete: ws.deleteSelected,
                                  onDuplicate: ws.duplicateSelected,
                                  onRotateCw: () =>
                                      ws.rotateSelected(clockwise: true),
                                  onRotateCcw: () =>
                                      ws.rotateSelected(clockwise: false),
                                  onClearSelection: ws.clearSelection,
                                ),
                                Expanded(
                                  child: OrganizePageGrid(
                                    pages: wsState.pages,
                                    selectedIds: wsState.selectedIds,
                                    onTap: _handlePageTap,
                                    onReorder: ws.reorder,
                                    onMoveDelta: ws.moveByDelta,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (wide)
                            SizedBox(
                              width: 280,
                              child: _PreviewPanel(page: preview),
                            ),
                        ],
                      ),
              ),
              if (wsState.busy)
                ColoredBox(
                  color: Colors.black.withValues(alpha: 0.35),
                  child: Center(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (wsState.progressFraction != null)
                              SizedBox(
                                width: 220,
                                child: LinearProgressIndicator(
                                  value: wsState.progressFraction,
                                ),
                              )
                            else
                              const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(wsState.statusMessage ?? 'Working…'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportOddEven({required bool odd}) async {
    final pages = ref
        .read(organizeWorkspaceProvider.notifier)
        .pagesForOddEven(odd: odd);
    if (pages.isEmpty) return;
    final ws = ref.read(organizeWorkspaceProvider.notifier);
    ws.setBusy(true, message: 'Exporting…', fraction: 0.1);
    try {
      final svc = ref.read(pageOrganizeServiceProvider);
      final out = await svc.exportWorkspace(
        pages: pages,
        suggestedName: odd ? 'odd-pages.pdf' : 'even-pages.pdf',
        passwordsByPath: _passwordsByPath,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved ${out.displayName}')));
    } on DocumentStudioError catch (e) {
      if (!mounted) return;
      _showError(e);
    } finally {
      ws.setBusy(false);
    }
  }
}

class _OrganizeActionBar extends StatelessWidget {
  const _OrganizeActionBar({
    required this.busy,
    required this.hasSelection,
    required this.onExtract,
    required this.onDelete,
    required this.onDuplicate,
    required this.onRotateCw,
    required this.onRotateCcw,
    required this.onClearSelection,
  });

  final bool busy;
  final bool hasSelection;
  final VoidCallback onExtract;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback onRotateCw;
  final VoidCallback onRotateCcw;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: isDark
          ? DsColors.surfaceContainerDark
          : DsColors.surfaceContainerLight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            _ActionChip(
              icon: Icons.content_cut,
              label: 'Extract',
              onPressed: !busy && hasSelection ? onExtract : null,
            ),
            _ActionChip(
              icon: Icons.delete_outline,
              label: 'Delete',
              onPressed: !busy && hasSelection ? onDelete : null,
            ),
            _ActionChip(
              icon: Icons.copy_all_outlined,
              label: 'Duplicate',
              onPressed: !busy && hasSelection ? onDuplicate : null,
            ),
            _ActionChip(
              icon: Icons.rotate_right,
              label: 'Rotate CW',
              onPressed: !busy && hasSelection ? onRotateCw : null,
            ),
            _ActionChip(
              icon: Icons.rotate_left,
              label: 'Rotate CCW',
              onPressed: !busy && hasSelection ? onRotateCcw : null,
            ),
            if (hasSelection)
              TextButton(
                onPressed: busy ? null : onClearSelection,
                child: const Text('Clear selection'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

class _SourcesPanel extends StatelessWidget {
  const _SourcesPanel({
    required this.files,
    required this.onAdd,
    required this.onOpenReplace,
  });

  final List<LocalFileRef> files;
  final VoidCallback onAdd;
  final VoidCallback onOpenReplace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: isDark
          ? DsColors.surfaceContainerDark
          : DsColors.surfaceContainerLight,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('Sources', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          DsSecondaryButton(
            label: 'Add PDF',
            icon: Icons.add,
            onPressed: onAdd,
          ),
          const SizedBox(height: 8),
          DsSecondaryButton(
            label: 'Replace workspace',
            icon: Icons.refresh,
            onPressed: onOpenReplace,
          ),
          const SizedBox(height: 16),
          for (final f in files)
            ListTile(
              dense: true,
              leading: const Icon(Icons.picture_as_pdf, size: 20),
              title: Text(
                f.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

class _PreviewPanel extends ConsumerWidget {
  const _PreviewPanel({required this.page});

  final OrganizePageRef? page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    if (page == null) {
      return Material(
        color: isDark
            ? DsColors.surfaceContainerDark
            : DsColors.surfaceContainerLight,
        child: const Center(child: Text('Select a page')),
      );
    }
    final cache = ref.watch(organizeThumbCacheProvider);
    return Material(
      color: isDark
          ? DsColors.surfaceContainerDark
          : DsColors.surfaceContainerLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Preview', style: theme.textTheme.titleSmall),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FutureBuilder(
                future: cache.render(page!.file, page!.pageNumber1Based),
                builder: (context, snap) {
                  if (snap.hasData && snap.data != null) {
                    return Image.memory(snap.data!, fit: BoxFit.contain);
                  }
                  return const Center(child: CircularProgressIndicator());
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '${page!.file.displayName} · page ${page!.pageNumber1Based}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyOrganizeWorkspace extends StatelessWidget {
  const _EmptyOrganizeWorkspace({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: DsEmptyState(
          title: 'Organize workspace',
          subtitle:
              'Import one or more PDFs to reorder, merge, split, rotate, and export. '
              'Drag pages on desktop, or use move controls on phone.',
          action: DsPrimaryButton(
            label: 'Open PDF',
            icon: Icons.folder_open,
            onPressed: onOpen,
          ),
        ),
      ),
    );
  }
}

class _SplitEveryNDialog extends StatefulWidget {
  const _SplitEveryNDialog({required this.maxPages});

  final int maxPages;

  @override
  State<_SplitEveryNDialog> createState() => _SplitEveryNDialogState();
}

class _SplitEveryNDialogState extends State<_SplitEveryNDialog> {
  int _n = 1;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Split every N pages'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Workspace has ${widget.maxPages} pages. Split uses the first source file’s page count for by-file split.',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('N = '),
              Expanded(
                child: Slider.adaptive(
                  min: 1,
                  max: widget.maxPages.clamp(1, 50).toDouble(),
                  divisions: widget.maxPages.clamp(1, 50) - 1,
                  value: _n.toDouble(),
                  label: '$_n',
                  onChanged: (v) => setState(() => _n = v.round()),
                ),
              ),
              Text('$_n'),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _n),
          child: const Text('Split'),
        ),
      ],
    );
  }
}

class _OrganizeUndoIntent extends Intent {
  const _OrganizeUndoIntent();
}

class _OrganizeRedoIntent extends Intent {
  const _OrganizeRedoIntent();
}

class _OrganizeSelectAllIntent extends Intent {
  const _OrganizeSelectAllIntent();
}

class _OrganizeDeleteIntent extends Intent {
  const _OrganizeDeleteIntent();
}

// Import for OrganizePageRef in preview / tap
