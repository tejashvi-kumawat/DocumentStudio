import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/domain/organize/organize_page_ref.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_scaffold.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_page_organize_export.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_page_organize_logic.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_rotate_pages_panel.dart';
import 'package:document_studio/features/pdf_viewer/pdf_page_scope.dart';
import 'package:document_studio/features/pdf_viewer/widgets/pdf_page_scope_field.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

enum ViewerScopedOrganizeMode {
  extract,
  delete,
  duplicate,
  rotate,
  insertBlank,
}

/// Page organize for the open document: this page, thumbnail selection, all,
/// or a range (`1-3, 8-`, `odd`, `even`). Extract saves a new file; the other
/// modes commit in place (undoable).
class ViewerScopedPageOrganizePanel extends ConsumerStatefulWidget {
  const ViewerScopedPageOrganizePanel({
    super.key,
    required this.mode,
    required this.handoff,
    this.pageCount,
    this.selectedPages1Based = const {},
  });

  final ViewerScopedOrganizeMode mode;
  final PdfViewerDocumentHandoff handoff;
  final int? pageCount;
  final Set<int> selectedPages1Based;

  /// Range the next panel opens with (e.g. `odd` from "Extract odd pages").
  static String? pendingRange;

  @override
  ConsumerState<ViewerScopedPageOrganizePanel> createState() =>
      _ViewerScopedPageOrganizePanelState();
}

class _ViewerScopedPageOrganizePanelState
    extends ConsumerState<ViewerScopedPageOrganizePanel> {
  bool _busy = false;
  bool _deleteAfterExtract = false;
  PdfPageScopeKind _scope = PdfPageScopeKind.thisPage;
  String _range = '';
  String? _rangeError;

  @override
  void initState() {
    super.initState();
    final preset = ViewerScopedPageOrganizePanel.pendingRange;
    ViewerScopedPageOrganizePanel.pendingRange = null;
    if (preset != null) {
      _scope = PdfPageScopeKind.range;
      _range = preset;
    } else if (widget.selectedPages1Based.length > 1) {
      _scope = PdfPageScopeKind.selectedPages;
    }
  }

  int get _page {
    final total = widget.pageCount ?? 1;
    return widget.handoff.currentPage1.clamp(1, total < 1 ? 1 : total);
  }

  /// Target pages, or null (with the error shown) when the scope is invalid.
  Set<int>? _targets() {
    final total = widget.pageCount;
    if (total == null || total < 1) {
      _snack('Page count not ready yet.');
      return null;
    }
    final r = resolvePdfPageScope(
      kind: _scope,
      currentPage1: _page,
      selectedPages1Based: widget.selectedPages1Based,
      totalPages: total,
      rangeExpression: _range,
    );
    setState(() => _rangeError = r.isOk ? null : r.error);
    if (!r.isOk) {
      if (_scope != PdfPageScopeKind.range) _snack(r.error!);
      return null;
    }
    return r.pages;
  }

  String _describe(Set<int> pages) =>
      pages.length == 1 ? 'page ${pages.first}' : '${pages.length} pages';

  String get _applyKey => switch (widget.mode) {
    ViewerScopedOrganizeMode.extract => 'viewer_extract_apply',
    ViewerScopedOrganizeMode.delete => 'viewer_delete_apply',
    ViewerScopedOrganizeMode.duplicate => 'viewer_duplicate_apply',
    ViewerScopedOrganizeMode.rotate => 'viewer_rotate_apply',
    ViewerScopedOrganizeMode.insertBlank => 'viewer_blank_apply',
  };

  Future<void> _commitInPlace(
    List<OrganizePageRef> pages, {
    required String successMessage,
  }) async {
    await exportOrganizePagesAndPromptSave(
      ref: ref,
      context: context,
      handoff: widget.handoff,
      pages: pages,
      suggestedName: widget.handoff.file.displayName,
      successMessage: successMessage,
    );
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() => _busy = true);
    try {
      await work();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final total = widget.pageCount;
    if (total == null || total < 1) {
      _snack('Page count not ready yet.');
      return;
    }
    if (total <= 1) {
      _snack('Cannot delete the only page.');
      return;
    }
    final targets = _targets();
    if (targets == null) return;
    if (targets.length >= total) {
      _snack('A PDF needs at least one page. Leave one page out.');
      return;
    }
    await _run(() async {
      final pages = pagesForDelete(widget.handoff.file, total, targets);
      if (!mounted) return;
      await _commitInPlace(
        pages,
        successMessage: 'Deleted ${_describe(targets)}.',
      );
    });
  }

  Future<void> _duplicate() async {
    final total = widget.pageCount;
    if (total == null || total < 1) {
      _snack('Page count not ready yet.');
      return;
    }
    final targets = _targets();
    if (targets == null) return;
    await _run(() async {
      final pages = pagesForDuplicate(widget.handoff.file, total, targets);
      if (!mounted) return;
      await _commitInPlace(
        pages,
        successMessage: 'Duplicated ${_describe(targets)}.',
      );
    });
  }

  Future<void> _insertBlank() async {
    final total = widget.pageCount;
    if (total == null || total < 1) {
      _snack('Page count not ready yet.');
      return;
    }
    await _run(() async {
      final blank = await ref.read(blankPageFactoryProvider).blankPageFile();
      if (!mounted) return;
      final pages = pagesForBlankInsertAfter(widget.handoff.file, total, {
        _page,
      }, blank);
      await _commitInPlace(
        pages,
        successMessage: 'Inserted blank after page $_page.',
      );
    });
  }

  Future<void> _extract() async {
    final total = widget.pageCount;
    if (total == null || total < 1) {
      _snack('Page count not ready yet.');
      return;
    }
    final targets = _targets();
    if (targets == null) return;
    await _run(() async {
      final file = widget.handoff.file;
      final stem = p.basenameWithoutExtension(file.displayName);
      final extractPages = pagesForExtract(file, targets);
      final organize = ref.read(pageOrganizeServiceProvider);
      final assembled = await organize.assembleWorkspaceExport(
        pages: extractPages,
        passwordsByPath: passwordsMapForHandoff(widget.handoff),
      );
      if (!mounted) return;

      final storage = ref.read(fileStorageProvider);
      final bytes = Uint8List.fromList(assembled.bytes);
      final savePath = await storage.pickSavePath(
        suggestedName: switch (_range.trim().toLowerCase()) {
          'odd' when _scope == PdfPageScopeKind.range => '${stem}_odd.pdf',
          'even' when _scope == PdfPageScopeKind.range => '${stem}_even.pdf',
          _ => '${stem}_extract.pdf',
        },
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
      _snack('Extracted ${_describe(targets)} saved.');

      if (!_deleteAfterExtract) return;
      if (targets.length >= total) {
        _snack('Kept the pages in the open document (a PDF needs one page).');
        return;
      }
      final remaining = pagesForDelete(file, total, targets);
      await _commitInPlace(
        remaining,
        successMessage: 'Removed ${_describe(targets)} from the open document.',
      );
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == ViewerScopedOrganizeMode.rotate) {
      return ViewerRotatePagesPanel(
        handoff: widget.handoff,
        pageCount: widget.pageCount,
      );
    }
    final theme = Theme.of(context);
    final total = widget.pageCount;
    final ready = total != null && total >= 1;

    final applyLabel = _busy
        ? 'Working…'
        : switch (widget.mode) {
            ViewerScopedOrganizeMode.extract => 'Extract',
            ViewerScopedOrganizeMode.delete => 'Delete',
            ViewerScopedOrganizeMode.duplicate => 'Duplicate',
            ViewerScopedOrganizeMode.insertBlank => 'Insert',
            _ => 'Apply',
          };
    return ViewerToolFormScaffold(
      primaryKey: Key(_applyKey),
      primaryLabel: applyLabel,
      primaryEnabled: !_busy && ready,
      primaryBusy: _busy,
      onPrimary: _busy || !ready
          ? null
          : switch (widget.mode) {
              ViewerScopedOrganizeMode.extract => _extract,
              ViewerScopedOrganizeMode.delete => _delete,
              ViewerScopedOrganizeMode.duplicate => _duplicate,
              ViewerScopedOrganizeMode.insertBlank => _insertBlank,
              _ => null,
            },
      children: [
        Text(
          'Page $_page${ready ? ' of $total' : ''}',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: DsSpacing.xs),
        Text(switch (widget.mode) {
          ViewerScopedOrganizeMode.extract => 'Saves the chosen pages as a new PDF. Optionally remove them from the open file.',
          ViewerScopedOrganizeMode.delete =>
            'Removes the chosen pages from the open document (undoable).',
          ViewerScopedOrganizeMode.duplicate =>
            'Copies each chosen page right after itself in the open document.',
          ViewerScopedOrganizeMode.rotate =>
            'Rotates the chosen pages in the open document. '
                '${viewerToolShortcutTooltip(ViewerToolShortcutId.rotateLeft)} / '
                '${viewerToolShortcutTooltip(ViewerToolShortcutId.rotateRight)}.',
          ViewerScopedOrganizeMode.insertBlank =>
            'Inserts one blank page after this page in the open document.',
        }, style: theme.textTheme.bodySmall),
        if (widget.mode != ViewerScopedOrganizeMode.insertBlank) ...[
          const SizedBox(height: DsSpacing.md),
          PdfPageScopeField(
            kind: _scope,
            onKindChanged: (k) => setState(() {
              _scope = k;
              _rangeError = null;
            }),
            rangeExpression: _range,
            onRangeExpressionChanged: (v) => setState(() {
              _range = v;
              _rangeError = null;
            }),
            selectedPageCount: widget.selectedPages1Based.length,
            rangeError: _rangeError,
            enabled: !_busy,
          ),
        ],
        if (widget.mode == ViewerScopedOrganizeMode.extract)
          SwitchListTile(
            key: const Key('viewer_extract_delete_after'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Delete after extract'),
            subtitle: const Text(
              'Remove the extracted pages from the open document after saving',
            ),
            value: _deleteAfterExtract,
            onChanged: _busy
                ? null
                : (v) => setState(() => _deleteAfterExtract = v),
          ),
      ],
    );
  }
}
