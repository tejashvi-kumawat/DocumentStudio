import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/jobs/job_models.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/page_management/pdf_password_prompt.dart';
import 'package:document_studio/features/page_management/shared/organize_document_source_list.dart';
import 'package:document_studio/features/page_management/shared/organize_drop_zone.dart';
import 'package:document_studio/features/page_management/shared/organize_tool_scaffold.dart';
import 'package:document_studio/features/page_management/widgets/organize_drop_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _MergeSource {
  _MergeSource(this.file);

  final LocalFileRef file;
  int? pageCount;
  bool loading = true;
}

class MergeToolScreen extends ConsumerStatefulWidget {
  const MergeToolScreen({super.key, this.initialFiles = const []});

  final List<LocalFileRef> initialFiles;

  @override
  ConsumerState<MergeToolScreen> createState() => _MergeToolScreenState();
}

class _MergeToolScreenState extends ConsumerState<MergeToolScreen> {
  final _sources = <_MergeSource>[];
  final _passwordsByPath = <String, String>{};
  int? _previewSourceIndex;
  bool _busy = false;
  String? _status;
  double? _progress;
  JobHandle<LocalFileRef>? _activeJob;

  @override
  void initState() {
    super.initState();
    if (widget.initialFiles.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _appendFiles(widget.initialFiles);
      });
    }
  }

  Future<void> _addFiles() async {
    final picked = await ref
        .read(fileStorageProvider)
        .pickOpenFile(allowedExtensions: ['pdf']);
    if (picked != null) await _appendFiles([picked]);
  }

  Future<void> _appendFiles(List<LocalFileRef> files) async {
    setState(() {
      for (final f in files) {
        if (_sources.any((s) => s.file.path == f.path)) continue;
        _sources.add(_MergeSource(f));
      }
    });
    for (final s in _sources.where((s) => s.loading)) {
      await _loadPageCount(s);
    }
  }

  Future<void> _loadPageCount(_MergeSource source) async {
    try {
      final pdf = ref.read(pdfRenderPortProvider);
      final info = await pdf.loadInfo(
        source.file,
        password: _passwordsByPath[source.file.path],
      );
      if (!mounted) return;
      setState(() {
        source.pageCount = info.pageCount;
        source.loading = false;
      });
    } on DocumentStudioError catch (e) {
      if (e.code == DocumentStudioErrorCode.passwordRequired) {
        if (!mounted) return;
        final password = await promptPdfPassword(context);
        if (password != null && password.isNotEmpty) {
          _passwordsByPath[source.file.path] = password;
          await _loadPageCount(source);
        } else if (mounted) {
          setState(() => source.loading = false);
        }
        return;
      }
      if (!mounted) return;
      setState(() => source.loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => source.loading = false);
    }
  }

  Future<void> _merge() async {
    if (_sources.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least two PDFs to merge')),
      );
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Merging…';
      _progress = 0.1;
    });
    final job = JobHandle<LocalFileRef>();
    setState(() => _activeJob = job);
    try {
      final out = await ref
          .read(pageOrganizeServiceProvider)
          .mergeAndPromptSave(
            handle: job,
            inputs: _sources.map((s) => s.file).toList(),
            suggestedName: 'merged.pdf',
            passwordsByPath: _passwordsByPath,
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
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved ${out.displayName}')));
    } on DocumentStudioError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.recoveryHint ?? e.message)));
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

  int get _totalPages =>
      _sources.fold<int>(0, (n, s) => n + (s.pageCount ?? 0));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return OrganizeToolScaffold(
      title: 'Merge PDFs',
      subtitle: 'Combine multiple documents into one file',
      busy: _busy,
      statusMessage: _status,
      progress: _progress,
      onCancel: _activeJob == null
          ? null
          : () => ref.read(jobRunnerProvider).requestCancel(_activeJob!),
      actions: [
        Text(
          _sources.isEmpty
              ? ''
              : '${_sources.length} files · $_totalPages pages',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: _sources.length < 2 || _busy ? null : _merge,
          child: const Text('Merge & save'),
        ),
      ],
      body: OrganizeDropTarget(
        enabled: !_busy,
        onFilesDropped: _appendFiles,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: _previewSourceIndex != null ? 3 : 1,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  OrganizeDropZone(
                    enabled: !_busy,
                    onBrowse: _addFiles,
                    title: 'Drop PDF files here',
                    subtitle: 'Order in the list is the merge order',
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _busy ? null : _addFiles,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add files'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_sources.isEmpty)
                    Text(
                      'Document-level merge — reorder files below. '
                      'For page-level edits use Reorder or Extract.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? DsColors.textSecondaryDark
                            : DsColors.textSecondaryLight,
                      ),
                    )
                  else
                    OrganizeDocumentSourceList(
                      enabled: !_busy,
                      sources: [
                        for (final s in _sources)
                          OrganizeDocumentSourceEntry(
                            id: s.file.path,
                            displayName: s.file.displayName,
                            loading: s.loading,
                            pageCountLabel: s.pageCount != null
                                ? '${s.pageCount} pages'
                                : null,
                          ),
                      ],
                      onReorder: (oldIndex, newIndex) {
                        setState(() {
                          if (newIndex > oldIndex) newIndex -= 1;
                          final item = _sources.removeAt(oldIndex);
                          _sources.insert(newIndex, item);
                        });
                      },
                      onRemove: (index) =>
                          setState(() => _sources.removeAt(index)),
                      onItemTap: (index) =>
                          setState(() => _previewSourceIndex = index),
                    ),
                ],
              ),
            ),
            if (_previewSourceIndex != null &&
                _previewSourceIndex! < _sources.length)
              Expanded(
                flex: 2,
                child: _MergeDocPreview(
                  source: _sources[_previewSourceIndex!],
                  password:
                      _passwordsByPath[_sources[_previewSourceIndex!]
                          .file
                          .path],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MergeDocPreview extends ConsumerWidget {
  const _MergeDocPreview({required this.source, this.password});

  final _MergeSource source;
  final String? password;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Material(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              source.file.displayName,
              style: theme.textTheme.titleSmall,
            ),
          ),
          if (source.loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (source.pageCount != null && source.pageCount! > 0)
            Expanded(
              child: FutureBuilder(
                future: ref
                    .read(organizeThumbCacheProvider)
                    .render(source.file, 1, password: password),
                builder: (context, snap) {
                  if (snap.hasData && snap.data != null) {
                    return Image.memory(snap.data!, fit: BoxFit.contain);
                  }
                  return const Center(child: CircularProgressIndicator());
                },
              ),
            )
          else
            const Expanded(
              child: Center(child: Text('Could not load preview')),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              source.pageCount != null
                  ? '${source.pageCount} pages — first page shown'
                  : 'Page count unknown',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
