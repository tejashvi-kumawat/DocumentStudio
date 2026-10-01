import 'dart:async';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/page_management/pdf_password_prompt.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_page_organize_export.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_page_organize_logic.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_scaffold.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Replace pages in the open document with pages from another PDF.
///
/// Apply writes the session working copy. Save writes the original file.
class ViewerReplacePagesPanel extends ConsumerStatefulWidget {
  const ViewerReplacePagesPanel({
    super.key,
    required this.handoff,
    this.pageCount,
    this.selectedPages1Based = const {},
  });

  final PdfViewerDocumentHandoff handoff;
  final int? pageCount;
  final Set<int> selectedPages1Based;

  @override
  ConsumerState<ViewerReplacePagesPanel> createState() =>
      _ViewerReplacePagesPanelState();
}

class _ViewerReplacePagesPanelState
    extends ConsumerState<ViewerReplacePagesPanel> {
  LocalFileRef? _source;
  int? _sourcePages;
  String? _sourcePassword;
  bool _busy = false;
  String? _error;

  Future<void> _pick() async {
    final picked = await ref.read(fileStorageProvider).pickOpenFile(
          allowedExtensions: const ['pdf'],
        );
    if (picked == null || !mounted) return;
    final openPath = ref
            .read(documentTabsControllerProvider)
            .activeSession
            ?.file
            .path ??
        widget.handoff.file.path;
    if (picked.path == openPath) {
      setState(() => _error = 'Choose a different PDF.');
      return;
    }
    setState(() {
      _source = picked;
      _sourcePages = null;
      _sourcePassword = null;
      _error = null;
      _busy = true;
    });
    try {
      await _loadSource(picked);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadSource(LocalFileRef picked) async {
    try {
      final info = await ref.read(pdfRenderPortProvider).loadInfo(
            picked,
            password: _sourcePassword,
          );
      if (!mounted) return;
      setState(() => _sourcePages = info.pageCount);
    } on DocumentStudioError catch (e) {
      if (e.code == DocumentStudioErrorCode.passwordRequired ||
          e.code == DocumentStudioErrorCode.wrongPassword) {
        if (!mounted) return;
        final password = await promptPdfPassword(context);
        if (!mounted) return;
        if (password == null || password.isEmpty) {
          setState(() {
            _source = null;
            _sourcePassword = null;
            _error = 'Password required to read that PDF.';
          });
          return;
        }
        _sourcePassword = password;
        await _loadSource(picked);
        return;
      }
      if (!mounted) return;
      setState(() {
        _source = null;
        _sourcePassword = null;
        _error = e.recoveryHint ?? e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _source = null;
        _sourcePassword = null;
        _error = '$e';
      });
    }
  }

  List<int> _slots(int total, int sourceCount) {
    final selected = widget.selectedPages1Based
        .where((n) => n >= 1 && n <= total)
        .toList()
      ..sort();
    if (selected.isNotEmpty) return selected;
    final start = widget.handoff.currentPage1.clamp(1, total);
    final end = start + sourceCount - 1;
    final last = end < total ? end : total;
    return [for (var n = start; n <= last; n++) n];
  }

  Future<void> _replace() async {
    final source = _source;
    final sourcePages = _sourcePages;
    final total = widget.pageCount;
    if (source == null || sourcePages == null || sourcePages < 1) return;
    if (total == null || total < 1) {
      setState(() => _error = 'Page count is not ready yet.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = ref.read(documentTabsControllerProvider).activeSession;
      if (session == null) {
        setState(() => _error = 'No open document to update.');
        return;
      }
      final slots = _slots(total, sourcePages);
      final pages = pagesForReplaceFromFile(
        file: session.file,
        totalPages: total,
        slots1Based: slots,
        source: source,
        sourceCount: sourcePages,
      );
      if (pages.isEmpty) {
        setState(() => _error = 'A PDF needs at least one page.');
        return;
      }
      final sourcePassword = _sourcePassword;
      await commitOrganizePagesInSession(
        ref: ref,
        context: context,
        handoff: widget.handoff,
        pages: pages,
        passwordsByPath: sourcePassword == null || sourcePassword.isEmpty
            ? null
            : {source.path: sourcePassword},
        unlockMismatchedPasswords: true,
        successMessage: 'Replaced pages from ${source.displayName}.',
      );
    } on DocumentStudioError catch (e) {
      if (mounted) setState(() => _error = e.recoveryHint ?? e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = _source;
    final ready = source != null && (_sourcePages ?? 0) > 0 && !_busy;
    final sourceLabel = source == null
        ? 'No PDF chosen'
        : _sourcePages == null
            ? source.displayName
            : '${source.displayName} · $_sourcePages pages';
    final selected = widget.selectedPages1Based.isNotEmpty;
    return ViewerToolFormScaffold(
      primaryKey: const Key('viewer_replace_pages_apply'),
      primaryLabel: _busy ? 'Replacing…' : 'Replace',
      primaryIcon: Icons.find_replace_outlined,
      primaryEnabled: ready,
      primaryBusy: _busy,
      onPrimary: ready ? () => unawaited(_replace()) : null,
      notice: _error == null
          ? null
          : Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                color: theme.colorScheme.error,
              ),
            ),
      children: [
        Text(
          selected
              ? 'Replaces the selected pages, in order, with pages from another PDF. '
                  'Extra source pages are added after the last replaced page. '
                  'The open copy updates. Save writes the original file.'
              : 'Replaces pages starting at the current page with pages from another PDF. '
                  'Extra source pages are added after those. '
                  'The open copy updates. Save writes the original file.',
          style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
        ),
        const SizedBox(height: 8),
        Text(
          sourceLabel,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : () => unawaited(_pick()),
            icon: const Icon(Icons.add, size: 18),
            label: Text(source == null ? 'Choose PDF' : 'Change PDF'),
          ),
        ),
      ],
    );
  }
}
