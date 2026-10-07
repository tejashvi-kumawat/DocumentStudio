import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/page_management/pdf_password_prompt.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_merge_split_apply.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_scaffold.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _MergeEntry {
  _MergeEntry({
    required this.file,
    required this.locked,
    this.pageCount,
    this.loading = false,
  });

  final LocalFileRef file;
  final bool locked;
  int? pageCount;
  bool loading;
}

/// Merge other PDFs with the document that is already open.
///
/// Save writes the session working copy only. The original file changes
/// when the user saves the document (Save / Ctrl+S).
/// Save as writes a new PDF and leaves this document alone.
class ViewerMergePanel extends ConsumerStatefulWidget {
  const ViewerMergePanel({super.key, required this.handoff, this.pageCount});

  final PdfViewerDocumentHandoff handoff;
  final int? pageCount;

  @override
  ConsumerState<ViewerMergePanel> createState() => _ViewerMergePanelState();
}

class _ViewerMergePanelState extends ConsumerState<ViewerMergePanel> {
  final _sources = <_MergeEntry>[];
  final _passwordsByPath = <String, String>{};
  bool _busy = false;
  bool _savingAs = false;
  bool _naming = false;

  @override
  void initState() {
    super.initState();
    final password = widget.handoff.password;
    if (password != null && password.isNotEmpty) {
      _passwordsByPath[widget.handoff.file.path] = password;
    }
    _sources.add(
      _MergeEntry(
        file: widget.handoff.file,
        locked: true,
        pageCount: widget.pageCount,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant ViewerMergePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final locked = _sources.indexWhere((s) => s.locked);
    if (locked < 0) return;
    final current = _sources[locked];
    final fileChanged = current.file.path != widget.handoff.file.path;
    final countChanged =
        widget.pageCount != null && widget.pageCount != current.pageCount;
    if (!fileChanged && !countChanged) return;
    final password = widget.handoff.password;
    if (fileChanged && password != null && password.isNotEmpty) {
      _passwordsByPath[widget.handoff.file.path] = password;
    }
    setState(() {
      _sources[locked] = _MergeEntry(
        file: widget.handoff.file,
        locked: true,
        pageCount: widget.pageCount ?? current.pageCount,
      );
    });
  }

  Future<void> _addFiles() async {
    final picked = await ref
        .read(fileStorageProvider)
        .pickOpenFiles(allowedExtensions: const ['pdf']);
    if (picked.isEmpty || !mounted) return;
    final added = <_MergeEntry>[];
    for (final file in picked) {
      if (_sources.any((s) => s.file.path == file.path)) continue;
      added.add(_MergeEntry(file: file, locked: false, loading: true));
    }
    if (added.isEmpty) {
      _snack('Those PDFs are already in the list.');
      return;
    }
    setState(() => _sources.addAll(added));
    for (final entry in added) {
      await _loadPageCount(entry);
    }
  }

  Future<void> _loadPageCount(_MergeEntry entry) async {
    try {
      final info = await ref
          .read(pdfRenderPortProvider)
          .loadInfo(entry.file, password: _passwordsByPath[entry.file.path]);
      if (!mounted) return;
      setState(() {
        entry.pageCount = info.pageCount;
        entry.loading = false;
      });
    } on DocumentStudioError catch (e) {
      if (e.code == DocumentStudioErrorCode.passwordRequired) {
        if (!mounted) return;
        final password = await promptPdfPassword(context);
        if (password != null && password.isNotEmpty) {
          _passwordsByPath[entry.file.path] = password;
          await _loadPageCount(entry);
        } else if (mounted) {
          setState(() => entry.loading = false);
        }
        return;
      }
      if (mounted) setState(() => entry.loading = false);
    } catch (_) {
      if (mounted) setState(() => entry.loading = false);
    }
  }

  Future<void> _save() {
    return _write(newFile: false);
  }

  Future<void> _saveAs() async {
    if (_sources.length < 2 || _busy || _naming) {
      if (_sources.length < 2) _snack('Add at least one other PDF.');
      return;
    }
    setState(() => _naming = true);
    try {
      final typed = await promptMergeSaveAsName(
        context,
        suggestedName: suggestedMergeSaveAsName(
          widget.handoff.file.displayName,
        ),
      );
      if (typed == null || !mounted) return;
      await _write(newFile: true, fileName: typed);
    } finally {
      if (mounted) setState(() => _naming = false);
    }
  }

  Future<void> _write({required bool newFile, String? fileName}) async {
    if (_sources.length < 2) {
      _snack('Add at least one other PDF.');
      return;
    }
    setState(() {
      _busy = true;
      _savingAs = newFile;
    });
    try {
      final inputs = [for (final s in _sources) s.file];
      if (newFile) {
        await saveMergedPdfAsNewFile(
          ref: ref,
          context: context,
          handoff: widget.handoff,
          inputs: inputs,
          fileName: fileName ?? '',
          passwordsByPath: _passwordsByPath,
        );
      } else {
        await applyMergeIntoOpenSession(
          ref: ref,
          context: context,
          handoff: widget.handoff,
          inputs: inputs,
          passwordsByPath: _passwordsByPath,
        );
        if (!mounted) return;
        setState(() {
          _sources.removeWhere((s) => !s.locked);
        });
      }
    } on DocumentStudioError catch (e) {
      if (mounted) _snack(e.recoveryHint ?? e.message);
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _savingAs = false;
        });
      }
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canMerge = _sources.length >= 2 && !_busy && !_naming;

    return ViewerToolFormScaffold(
      primaryKey: const Key('viewer_merge_save'),
      primaryLabel: _busy && !_savingAs ? 'Saving…' : 'Save',
      primaryIcon: Icons.save_outlined,
      primaryEnabled: canMerge,
      primaryBusy: _busy && !_savingAs,
      onPrimary: canMerge ? _save : null,
      secondaryKey: const Key('viewer_merge_save_as'),
      secondaryLabel: _busy && _savingAs ? 'Saving…' : 'Save as',
      secondaryIcon: Icons.save_as_outlined,
      secondaryEnabled: canMerge,
      secondaryBusy: _busy && _savingAs,
      onSecondary: canMerge ? _saveAs : null,
      children: [
        Text(
          'Other PDFs are combined in the order below. '
          'Save updates this open document. Ctrl+S writes the original file. '
          'Save as writes a new PDF and leaves this document unchanged.',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: DsSpacing.sm),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _sources.length,
          onReorderItem: (oldIndex, newIndex) {
            if (_busy) return;
            setState(() {
              final item = _sources.removeAt(oldIndex);
              _sources.insert(newIndex, item);
            });
          },
          itemBuilder: (context, index) {
            final source = _sources[index];
            final pages = source.loading
                ? '…'
                : source.pageCount == null
                ? null
                : '${source.pageCount} pages';
            return ListTile(
              key: ValueKey('${source.locked}:${source.file.path}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: ReorderableDragStartListener(
                index: index,
                child: Icon(
                  Icons.drag_handle,
                  size: 20,
                  color: _busy ? theme.disabledColor : null,
                ),
              ),
              title: Text(
                source.file.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                source.locked
                    ? 'This document${pages == null ? '' : ' · $pages'}'
                    : (pages ?? 'PDF'),
                style: theme.textTheme.bodySmall,
              ),
              trailing: source.locked
                  ? Icon(Icons.lock_outline, size: 18, color: DsColors.primary)
                  : IconButton(
                      tooltip: 'Remove',
                      onPressed: _busy
                          ? null
                          : () => setState(() => _sources.removeAt(index)),
                      icon: const Icon(Icons.close, size: 18),
                    ),
            );
          },
        ),
        const SizedBox(height: DsSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : _addFiles,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add PDFs'),
          ),
        ),
      ],
    );
  }
}
