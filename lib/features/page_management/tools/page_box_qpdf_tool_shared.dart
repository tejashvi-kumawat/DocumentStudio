import 'dart:io';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/jobs/job_models.dart';

import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/pdf_document_route_args.dart';
import 'package:document_studio/domain/organize/organize_page_ref.dart';

import 'package:document_studio/features/page_management/organize_workspace_notifier.dart';
import 'package:document_studio/features/page_management/organize_pdf_import.dart';
import 'package:document_studio/features/page_management/pdf_password_prompt.dart';
import 'package:document_studio/design_system/shell/ds_status_bar.dart';
import 'package:document_studio/design_system/widgets/ds_active_document_strip.dart';
import 'package:document_studio/features/page_management/shared/organize_drop_zone.dart';
import 'package:document_studio/features/page_management/shared/organize_tool_scaffold.dart';
import 'package:document_studio/features/page_management/shared/organize_tool_source_bar.dart';
import 'package:document_studio/features/page_management/shared/organize_workflow_strip.dart';
import 'package:document_studio/features/page_management/widgets/organize_drop_target.dart';
import 'package:document_studio/features/page_management/widgets/organize_page_grid.dart';
import 'package:document_studio/infrastructure/pdf/pdf_page_box_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:document_studio/features/page_management/tools/page_box_qpdf_tool_logic.dart';

export 'page_box_qpdf_tool_logic.dart'
    show PageBoxQpdfToolMode, pageBoxQpdfCanApply, pageBoxSelectedSourcePages1Based;

/// Route `extra` for crop/resize when opened from document workspace or viewer.
class PageBoxQpdfToolLaunch {
  const PageBoxQpdfToolLaunch({
    required this.file,
    this.initialSelectedPages1Based = const {},
  });

  final LocalFileRef file;
  final Set<int> initialSelectedPages1Based;

  static PageBoxQpdfToolLaunch? fromExtra(Object? extra) {
    if (extra is PageBoxQpdfToolLaunch) return extra;
    final doc = PdfDocumentRouteArgs.tryParse(extra);
    if (doc != null) return PageBoxQpdfToolLaunch(file: doc.file);
    if (extra is LocalFileRef) return PageBoxQpdfToolLaunch(file: extra);
    return null;
  }

  /// Preload for qpdf crop/resize: first imported PDF + workspace selection on that file.
  static PageBoxQpdfToolLaunch? fromDocumentWorkspace({
    required List<OrganizePageRef> pages,
    required List<LocalFileRef> importedFiles,
    required Set<String> selectedIds,
  }) {
    if (pages.isEmpty && importedFiles.isEmpty) return null;
    final file =
        importedFiles.isNotEmpty ? importedFiles.first : pages.first.file;
    final initialSelectedPages1Based = selectedIds.isEmpty
        ? const <int>{}
        : {
            for (final p in pages)
              if (p.file.path == file.path && selectedIds.contains(p.id))
                p.pageNumber1Based,
          };
    return PageBoxQpdfToolLaunch(
      file: file,
      initialSelectedPages1Based: initialSelectedPages1Based,
    );
  }
}

class PageBoxQpdfToolScreen extends ConsumerStatefulWidget {
  const PageBoxQpdfToolScreen({
    super.key,
    required this.mode,
    this.launch,
  });

  final PageBoxQpdfToolMode mode;
  final PageBoxQpdfToolLaunch? launch;

  @override
  ConsumerState<PageBoxQpdfToolScreen> createState() =>
      _PageBoxQpdfToolScreenState();
}

class _PageBoxQpdfToolScreenState extends ConsumerState<PageBoxQpdfToolScreen> {
  final _passwordsByPath = <String, String>{};
  bool _loadingDoc = false;
  bool _busy = false;
  JobHandle<LocalFileRef>? _activeJob;
  PdfCropMarginPreset _margin = PdfCropMarginPreset.small;
  PdfPaperSize _paperSize = PdfPaperSize.letter;
  String get _title => widget.mode == PageBoxQpdfToolMode.crop
      ? 'Crop pages'
      : 'Resize pages';

  String get _subtitle => widget.mode == PageBoxQpdfToolMode.crop
      ? 'Select pages, trim margins (CropBox), then save'
      : 'Select pages, set paper size (MediaBox), then save';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(organizeWorkspaceProvider.notifier).reset();
      final launch = widget.launch;
      if (launch != null) {
        _importFile(
          launch.file,
          initialSelectedPages1Based: launch.initialSelectedPages1Based,
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

  Future<void> _importFile(
    LocalFileRef file, {
    Set<int> initialSelectedPages1Based = const {},
  }) async {
    setState(() => _loadingDoc = true);
    try {
      final count = await _loadPageCount(file);
      if (count == null || count < 1) return;
      final ws = ref.read(organizeWorkspaceProvider.notifier);
      ws.loadPagesFromFile(file, count);
      if (initialSelectedPages1Based.isNotEmpty) {
        ws.selectPagesFromFileByNumbers(file.path, initialSelectedPages1Based);
      }
    } on DocumentStudioError catch (e) {
      if (!mounted) return;
      _snack(e.recoveryHint ?? e.message);
    } finally {
      if (mounted) setState(() => _loadingDoc = false);
    }
  }

  Future<void> _pickPdf() async {
    final picked = await ref.read(fileStorageProvider).pickOpenFile(
          allowedExtensions: ['pdf'],
        );
    if (picked != null) await _importFile(picked);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Set<int> _selectedSourcePages(List<OrganizePageRef> pages, Set<String> sel) {
    return pageBoxSelectedSourcePages1Based(pages: pages, selectedIds: sel);
  }

  LocalFileRef? _sourceFile(List<OrganizePageRef> pages) {
    if (pages.isEmpty) return null;
    return pages.first.file;
  }

  Future<void> _applyAndSave() async {
    final ws = ref.read(organizeWorkspaceProvider);
    final pages = ws.pages;
    final file = _sourceFile(pages);
    if (file == null) return;

    final selected = _selectedSourcePages(pages, ws.selectedIds);
    if (selected.isEmpty) {
      _snack('Select at least one page');
      return;
    }
    if (widget.mode == PageBoxQpdfToolMode.crop &&
        _margin == PdfCropMarginPreset.none) {
      _snack('Choose a margin preset other than None');
      return;
    }

    setState(() => _busy = true);

    try {
      final storage = ref.read(fileStorageProvider);
      final structure = ref.read(pdfStructurePortProvider);
      final temp = await storage.createTempFile(
        prefix: widget.mode == PageBoxQpdfToolMode.crop ? 'crop' : 'resize',
        suffix: '.pdf',
      );
      final password = _passwordsByPath[file.path];
      final LocalFileRef out;
      if (widget.mode == PageBoxQpdfToolMode.crop) {
        out = await structure.cropPages(
          input: file,
          pageNumbers1Based: selected,
          margin: _margin,
          outputPath: temp,
          password: password,
        );
      } else {
        out = await structure.setPageSize(
          input: file,
          pageNumbers1Based: selected,
          paperSize: _paperSize,
          outputPath: temp,
          password: password,
        );
      }
      final bytes = await storage.readBytes(out);
      final suffix =
          widget.mode == PageBoxQpdfToolMode.crop ? 'cropped' : 'resized';
      final save = await storage.pickSavePath(
        suggestedName: '$suffix-${file.displayName}',
        bytes: bytes,
        allowedExtensions: ['pdf'],
        mimeType: 'application/pdf',
      );
      if (save == null) return;
      await storage.writeAtomic(
        destinationPath: save,
        writeToTemp: (t) async {
          await File(t).writeAsBytes(bytes, flush: true);
        },
      );
      if (!mounted) return;
      await ref.read(recentsProvider.notifier).addRecent(
            LocalFileRef(
              path: save,
              displayName: p.basename(save),
            ),
          );
      if (!mounted) return;
      await ref.read(recentsProvider.notifier).addRecent(
            LocalFileRef(
              path: save,
              displayName: p.basename(save),
            ),
          );
      if (!mounted) return;
      _snack('Saved PDF.');
    } on DocumentStudioError catch (e) {
      if (!mounted) return;
      _snack(e.recoveryHint ?? e.message);
    } catch (e) {
      if (!mounted) return;
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _engineBanner(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          widget.mode == PageBoxQpdfToolMode.crop
              ? 'Trims the CropBox by the margin preset. Original content outside '
                  'the crop region is hidden, not deleted.'
              : 'Sets MediaBox and CropBox to the chosen size. Content is not scaled '
                  'to fit — layout may clip or show extra whitespace.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(organizeWorkspaceProvider);
    final canRun = pageBoxQpdfCanApply(
      mode: widget.mode,
      engineSupported: true,
      busy: _busy,
      pageCount: ws.pages.length,
      selectedPages1Based: _selectedSourcePages(ws.pages, ws.selectedIds),
      cropMargin: _margin,
    );

    final selectedCount = _selectedSourcePages(ws.pages, ws.selectedIds).length;
    final isCrop = widget.mode == PageBoxQpdfToolMode.crop;
    final exportLabel =
        isCrop ? 'Apply crop & save as' : 'Apply size & save as';

    return OrganizeToolScaffold(
      title: _title,
      subtitle: _subtitle,
      busy: _busy || _loadingDoc,
      statusMessage: _loadingDoc ? 'Opening PDF…' : null,
      onCancel: _activeJob == null
          ? null
          : () => ref.read(jobRunnerProvider).requestCancel(_activeJob!),
      actions: [
        FilledButton(
          onPressed: canRun ? _applyAndSave : null,
          child: Text(exportLabel),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: OrganizeDropTarget(
              onFilesDropped: (files) async {
                final pdfs =
                    files.where((f) => f.path.toLowerCase().endsWith('.pdf'));
                if (pdfs.isEmpty) return;
                await _importFile(pdfs.first);
              },
              child: ws.pages.isEmpty && !_loadingDoc
                  ? ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        OrganizeToolStepStrip(
                          steps: const [
                            'Open PDF',
                            'Select pages',
                            'Preview & save',
                          ],
                          activeIndex: 0,
                        ),
                        if (widget.launch != null)
                          DsActiveDocumentStrip(
                            fileName: widget.launch!.file.displayName,
                            busy: _busy || _loadingDoc,
                          ),
                        OrganizeToolSourceBar(
                          busy: _busy || _loadingDoc,
                          onOpenPdf: widget.launch == null ? _pickPdf : null,
                        ),
                        const SizedBox(height: 12),
                        _engineBanner(context),
                        const SizedBox(height: 12),
                        OrganizeDropZone(
                          onBrowse: _busy ? null : _pickPdf,
                          title: 'Open PDF',
                          subtitle: 'Drop a file here or browse',
                          enabled: !_busy && !_loadingDoc,
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OrganizeToolStepStrip(
                          steps: const [
                            'Open PDF',
                            'Select pages',
                            'Preview & save',
                          ],
                          activeIndex: selectedCount == 0 ? 1 : 2,
                        ),
                        DsActiveDocumentStrip(
                          fileName: ws.pages.first.file.displayName,
                          pageCount: ws.pageCount,
                          busy: _busy || _loadingDoc,
                          onChangeFile:
                              widget.launch == null ? _pickPdf : null,
                        ),
                        OrganizeToolSourceBar(
                          busy: _busy || _loadingDoc,
                          onOpenPdf: widget.launch == null ? _pickPdf : null,
                        ),
                        if (_loadingDoc)
                          const LinearProgressIndicator(minHeight: 2),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            children: [
                              _engineBanner(context),
                              const SizedBox(height: 12),
                              if (isCrop)
                                SegmentedButton<PdfCropMarginPreset>(
                                  segments: PdfCropMarginPreset.values
                                      .map(
                                        (p) => ButtonSegment(
                                          value: p,
                                          label: Text(p.label),
                                        ),
                                      )
                                      .toList(),
                                  selected: {_margin},
                                  onSelectionChanged: _busy
                                      ? null
                                      : (s) => setState(() => _margin = s.first),
                                )
                              else
                                SegmentedButton<PdfPaperSize>(
                                  segments: PdfPaperSize.values
                                      .map(
                                        (p) => ButtonSegment(
                                          value: p,
                                          label: Text(p.name.toUpperCase()),
                                        ),
                                      )
                                      .toList(),
                                  selected: {_paperSize},
                                  onSelectionChanged: _busy
                                      ? null
                                      : (s) =>
                                          setState(() => _paperSize = s.first),
                                ),
                              const SizedBox(height: 8),
                              OrganizeWorkflowStrip(
                                tone: OrganizeWorkflowTone.info,
                                message: selectedCount > 0
                                    ? '$selectedCount page${selectedCount == 1 ? '' : 's'} selected — preview before save'
                                    : 'Select pages to ${isCrop ? 'crop' : 'resize'} (Shift range, Ctrl/Cmd toggle)',
                              ),
                              SizedBox(
                                height: 360,
                                child: OrganizePageGrid(
                                  pages: ws.pages,
                                  selectedIds: ws.selectedIds,
                                  passwordsByPath: _passwordsByPath,
                                  enableDragReorder: false,
                                  onTap: (page, index,
                                      {required shift, required ctrlOrMeta}) {
                                    final notifier = ref
                                        .read(organizeWorkspaceProvider.notifier);
                                    if (shift) {
                                      notifier.selectRangeTo(page.id);
                                    } else {
                                      notifier.selectOnly(
                                        page.id,
                                        additive: ctrlOrMeta,
                                      );
                                    }
                                  },
                                  onReorder: (_, __) {},
                                  onMoveDelta: (_, __) {},
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          DsStatusBar(
            compact: true,
            leading: ws.pages.isNotEmpty
                ? [
                    DsStatusMetric(
                      label: 'Pages',
                      value: '${ws.pages.length}',
                      icon: Icons.view_module_outlined,
                      compact: true,
                    ),
                    if (selectedCount > 0)
                      DsStatusMetric(
                        label: 'Selected',
                        value: '$selectedCount',
                        icon: Icons.check_box_outlined,
                        compact: true,
                      ),
                  ]
                : const [],
            message: _busy
                ? 'Export in progress — Cancel on overlay'
                : 'Ctrl+Enter · $exportLabel · preview before save',
          ),
        ],
      ),
    );
  }
}
