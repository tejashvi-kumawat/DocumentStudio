import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/jobs/job_models.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/organize/organize_page_ref.dart';
import 'package:document_studio/features/page_management/pdf_password_prompt.dart';
import 'package:document_studio/features/page_management/shared/organize_drop_zone.dart';
import 'package:document_studio/features/page_management/shared/organize_export_preview_dialog.dart';
import 'package:document_studio/features/document_lifecycle/document_save_result_actions.dart';
import 'package:document_studio/design_system/shell/ds_status_bar.dart';
import 'package:document_studio/features/page_management/shared/organize_tool_scaffold.dart';
import 'package:document_studio/features/page_management/shared/organize_workflow_strip.dart';
import 'package:document_studio/features/page_management/widgets/organize_drop_target.dart';
import 'package:document_studio/features/page_management/widgets/organize_page_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Move selected pages from a source PDF into a destination PDF at an index.
class MoveBetweenToolScreen extends ConsumerStatefulWidget {
  const MoveBetweenToolScreen({super.key, this.initialFiles = const []});

  final List<LocalFileRef> initialFiles;

  @override
  ConsumerState<MoveBetweenToolScreen> createState() =>
      _MoveBetweenToolScreenState();
}

class _MoveBetweenToolScreenState extends ConsumerState<MoveBetweenToolScreen> {
  LocalFileRef? _source;
  LocalFileRef? _dest;
  List<OrganizePageRef> _sourcePages = [];
  List<OrganizePageRef> _destPages = [];
  final _selectedSourceIds = <String>{};
  int _insertIndex = 0;
  final _passwords = <String, String>{};
  bool _busy = false;
  String? _status;
  double? _progress;
  JobHandle<LocalFileRef>? _activeJob;

  @override
  void initState() {
    super.initState();
    if (widget.initialFiles.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _loadSource(widget.initialFiles.first);
        if (!mounted || widget.initialFiles.length < 2) return;
        await _loadDest(widget.initialFiles[1]);
      });
    }
  }

  Future<int?> _pageCount(LocalFileRef file) async {
    final pdf = ref.read(pdfRenderPortProvider);
    try {
      return (await pdf.loadInfo(file, password: _passwords[file.path])).pageCount;
    } on DocumentStudioError catch (e) {
      if (e.code != DocumentStudioErrorCode.passwordRequired) rethrow;
      if (!mounted) return null;
      final pw = await promptPdfPassword(context);
      if (pw == null) return null;
      _passwords[file.path] = pw;
      return (await pdf.loadInfo(file, password: pw)).pageCount;
    }
  }

  Future<void> _loadSource(LocalFileRef file) async {
    final n = await _pageCount(file);
    if (n == null || n < 1) return;
    setState(() {
      _source = file;
      _sourcePages = [
        for (var p = 1; p <= n; p++) OrganizePageRef.fromFilePage(file, p),
      ];
      _selectedSourceIds.clear();
    });
  }

  Future<void> _loadDest(LocalFileRef file) async {
    final n = await _pageCount(file);
    if (n == null || n < 1) return;
    setState(() {
      _dest = file;
      _destPages = [
        for (var p = 1; p <= n; p++) OrganizePageRef.fromFilePage(file, p),
      ];
      _insertIndex = _destPages.length;
    });
  }

  List<OrganizePageRef> _buildResultPages() {
    final moving = _sourcePages
        .where((p) => _selectedSourceIds.contains(p.id))
        .toList();
    final dest = List<OrganizePageRef>.of(_destPages);
    final at = _insertIndex.clamp(0, dest.length);
    dest.insertAll(at, moving);
    return dest;
  }

  Future<void> _exportDest() async {
    if (_dest == null || _selectedSourceIds.isEmpty) return;
    final movingCount = _selectedSourceIds.length;
    final pages = _buildResultPages();
    final previewOk = await showOrganizeExportPreview(
      context: context,
      title: 'Move between documents',
      subtitle:
          '$movingCount page(s) into ${_dest!.displayName} at index $_insertIndex',
      pages: pages,
      passwordsByPath: _passwords,
    );
    if (previewOk != true || !mounted) return;
    setState(() {
      _busy = true;
      _status = 'Exporting…';
      _progress = 0.1;
    });
    final job = JobHandle<LocalFileRef>();
    setState(() => _activeJob = job);
    try {
      final out = await ref.read(pageOrganizeServiceProvider).exportWorkspace(
            handle: job,
            pages: pages,
            suggestedName: 'moved-${_dest!.displayName}',
            passwordsByPath: _passwords,
            onProgress: (prog) {
              if (mounted) {
                setState(() {
                  _status = prog.message;
                  _progress = prog.fraction;
                });
              }
            },
          );
      if (!mounted) return;
      await ref.read(recentsProvider.notifier).addRecent(out);
      showDocumentSaveResultActions(
        context,
        file: out,
        password: _passwords[out.path],
        message: 'Saved destination with moved pages',
      );
    } on DocumentStudioError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.recoveryHint ?? e.message)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
          _progress = null;
          _activeJob = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final movingCount = _selectedSourceIds.length;

    return OrganizeToolScaffold(
      title: 'Move between documents',
      subtitle: 'Select pages in source, choose destination and insert position',
      busy: _busy,
      statusMessage: _status,
      progress: _progress,
      onCancel: _activeJob == null
          ? null
          : () => ref.read(jobRunnerProvider).requestCancel(_activeJob!),
      actions: [
        FilledButton(
          onPressed: _dest == null || movingCount == 0 || _busy ? null : _exportDest,
          child: const Text('Save destination PDF'),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: OrganizeDropTarget(
        enabled: !_busy,
        onFilesDropped: (files) async {
          if (files.isEmpty) return;
          if (_source == null) {
            await _loadSource(files.first);
          } else if (_dest == null) {
            await _loadDest(files.first);
          }
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          children: [
            OrganizeToolStepStrip(
              steps: const [
                'Source PDF',
                'Select pages',
                'Destination & save',
              ],
              activeIndex: _source == null
                  ? 0
                  : (movingCount == 0 ? 1 : (_dest == null ? 1 : 2)),
            ),
            if (_source != null || _dest != null)
              OrganizeWorkflowStrip(
                tone: OrganizeWorkflowTone.info,
                message: movingCount > 0 && _dest != null
                    ? '$movingCount page(s) → ${_dest!.displayName} at index $_insertIndex — preview before save'
                    : _source == null
                        ? 'Open source PDF and select pages to move'
                        : 'Select pages in source, then open destination',
              ),
            Text('Source document', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            if (_source == null)
              OrganizeDropZone(
                onBrowse: () async {
                  final f = await ref.read(fileStorageProvider).pickOpenFile(
                        allowedExtensions: ['pdf'],
                      );
                  if (f != null) await _loadSource(f);
                },
                title: 'Open source PDF',
                subtitle: 'Pages to move',
              )
            else
              SizedBox(
                height: 220,
                child: OrganizePageGrid(
                  pages: _sourcePages,
                  selectedIds: _selectedSourceIds,
                  passwordsByPath: _passwords,
                  enableDragReorder: false,
                  onTap: (page, index, {required shift, required ctrlOrMeta}) {
                    setState(() {
                      if (ctrlOrMeta) {
                        if (_selectedSourceIds.contains(page.id)) {
                          _selectedSourceIds.remove(page.id);
                        } else {
                          _selectedSourceIds.add(page.id);
                        }
                      } else {
                        _selectedSourceIds
                          ..clear()
                          ..add(page.id);
                      }
                    });
                  },
                  onReorder: (_, __) {},
                  onMoveDelta: (_, __) {},
                ),
              ),
            const SizedBox(height: 16),
            Text('Destination document', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            if (_dest == null)
              OrganizeDropZone(
                onBrowse: () async {
                  final f = await ref.read(fileStorageProvider).pickOpenFile(
                        allowedExtensions: ['pdf'],
                      );
                  if (f != null) await _loadDest(f);
                },
                title: 'Open destination PDF',
                subtitle: 'Insert moved pages here',
              )
            else ...[
              Text(_dest!.displayName, style: theme.textTheme.titleSmall),
              if (_destPages.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Insert at index (0 = start)', style: theme.textTheme.bodySmall),
                Row(
                  children: [
                    Expanded(
                      child: Slider.adaptive(
                        min: 0,
                        max: _destPages.length.toDouble(),
                        divisions: _destPages.length,
                        value: _insertIndex.toDouble(),
                        label: '$_insertIndex',
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _insertIndex = v.round()),
                      ),
                    ),
                    Text('$_insertIndex'),
                  ],
                ),
              ],
              if (movingCount > 0)
                Text(
                  'Preview: $movingCount page(s) inserted at position $_insertIndex '
                  '→ ${_destPages.length + movingCount} pages total',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ],
        ),
      ),
          ),
          DsStatusBar(
            compact: true,
            leading: [
              if (_sourcePages.isNotEmpty)
                DsStatusMetric(
                  label: 'Source',
                  value: '${_sourcePages.length} pg',
                  icon: Icons.picture_as_pdf_outlined,
                  compact: true,
                ),
              if (movingCount > 0)
                DsStatusMetric(
                  label: 'Moving',
                  value: '$movingCount',
                  icon: Icons.drive_file_move_outline,
                  compact: true,
                ),
            ],
            message: _busy
                ? (_status ?? 'Exporting…')
                : 'Save destination PDF — preview & cancel on export',
          ),
        ],
      ),
    );
  }
}
