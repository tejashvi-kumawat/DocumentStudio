import 'dart:async';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_scaffold.dart';
import 'package:document_studio/features/pdf_viewer/pdf_page_labels.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_tool_panel_scope.dart';
import 'package:document_studio/infrastructure/pdf/pdf_page_label_writer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Page labels for the open PDF: scope, style, prefix, start, and a preview.
///
/// OK writes `/PageLabels` into the session working copy. The original file
/// changes only when the user Saves. The viewer is not remounted.
class PdfPageLabelsEditor extends ConsumerStatefulWidget {
  const PdfPageLabelsEditor({
    super.key,
    required this.handoff,
    this.pageCount,
    this.selectedPages1Based = const {},
  });

  final PdfViewerDocumentHandoff handoff;

  /// Viewer page count when already known. Null does not open the file’s
  /// pages; a catalog probe fills it in.
  final int? pageCount;
  final Set<int> selectedPages1Based;

  @override
  ConsumerState<PdfPageLabelsEditor> createState() =>
      _PdfPageLabelsEditorState();
}

class _PdfPageLabelsEditorState extends ConsumerState<PdfPageLabelsEditor> {
  late final TextEditingController _from;
  late final TextEditingController _to;
  late final TextEditingController _prefix;
  late final TextEditingController _start;
  late bool _allPages;
  bool _beginNew = true;
  String _style = 'D';
  bool _busy = false;
  String? _error;
  int? _probedPages;

  int get _pages {
    final given = widget.pageCount;
    if (given != null && given >= 1) return given;
    final probed = _probedPages;
    if (probed != null && probed >= 1) return probed;
    return 0;
  }

  int _clampPage(int page) {
    final n = _pages;
    if (page < 1) return 1;
    if (n < 1) return page;
    return page.clamp(1, n);
  }

  @override
  void initState() {
    super.initState();
    final limit = _pages;
    final selected = widget.selectedPages1Based
        .where((p) => p >= 1 && (limit < 1 || p <= limit))
        .toList()
      ..sort();
    _allPages = selected.isEmpty;
    final from = selected.isEmpty
        ? widget.handoff.currentPage1
        : selected.first;
    final to = selected.isEmpty ? widget.handoff.currentPage1 : selected.last;
    _from = TextEditingController(text: '${_clampPage(from)}');
    _to = TextEditingController(text: '${_clampPage(to)}');
    _prefix = TextEditingController();
    _start = TextEditingController(text: '1');
    for (final c in [_from, _to, _prefix, _start]) {
      c.addListener(_refresh);
    }
    if (limit < 1) unawaited(_probePages());
  }

  @override
  void didUpdateWidget(covariant PdfPageLabelsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageCount != widget.pageCount &&
        widget.pageCount != null &&
        widget.pageCount! >= 1) {
      _probedPages = null;
    }
  }

  Future<void> _probePages() async {
    final n = await probePdfPageCountForLabels(
      widget.handoff.file.path,
      widget.handoff.password,
    );
    if (!mounted || n == null || n < 1) return;
    if (widget.pageCount != null && widget.pageCount! >= 1) return;
    setState(() => _probedPages = n);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_from, _to, _prefix, _start]) {
      c.removeListener(_refresh);
      c.dispose();
    }
    super.dispose();
  }

  int? _parse(TextEditingController c) => int.tryParse(c.text.trim());

  bool get _canExtend {
    if (_allPages) return false;
    final from = _parse(_from);
    return from != null && from > 1;
  }

  String get _sample {
    if (!_beginNew) {
      return 'Continues the numbering from the previous pages.';
    }
    final start = _parse(_start) ?? 1;
    return previewPdfPageLabelRun(
      style: _style,
      prefix: _prefix.text,
      startAt: start < 1 ? 1 : start,
    );
  }

  Future<void> _apply() async {
    if (_pages < 1) {
      setState(() => _error = 'Still reading this PDF.');
      return;
    }
    final start = _parse(_start);
    final from = _allPages ? 1 : _parse(_from);
    final to = _allPages ? _pages : _parse(_to);
    if (from == null ||
        to == null ||
        from < 1 ||
        to < 1 ||
        from > _pages ||
        to > _pages) {
      setState(() => _error = 'Enter a page range from 1 to $_pages.');
      return;
    }
    if (_beginNew && (start == null || start < 1)) {
      setState(() => _error = 'Start must be 1 or greater.');
      return;
    }
    if (!_beginNew && from <= 1) {
      setState(() => _error = 'There is no preceding section to extend.');
      return;
    }
    final tabs = ref.read(documentTabsControllerProvider);
    final session = tabs.activeSession;
    if (session == null) {
      setState(() => _error = 'Open a PDF before numbering its pages.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final edit = PdfPageLabelEdit(
        allPages: _allPages,
        fromPage1: from,
        toPage1: to,
        beginNewSection: _beginNew,
        style: _style,
        prefix: _prefix.text,
        startAt: start ?? 1,
      );
      final written = await writePdfPageLabels(
        inputPath: session.file.path,
        password: widget.handoff.password ?? session.password,
        pageCount: _pages,
        edit: edit,
      );
      if (!mounted) return;
      final saved = await commitBytesToSession(
        context: context,
        storage: ref.read(fileStorageProvider),
        tabs: tabs,
        session: session,
        bytes: written.bytes,
        successMessage: 'Page labels updated. Save to write the original file.',
      );
      if (saved == null || !mounted) return;
      PageLabelOwnRevisions.mark(session.file.path, session.revision);
      ref
          .read(viewerPageLabelsProvider.notifier)
          .publish(
            filePath: session.file.path,
            revision: session.revision,
            ranges: written.ranges,
          );
      closeViewerToolPanel(context);
    } on DocumentStudioError catch (e) {
      if (mounted) {
        setState(() => _error = e.recoveryHint ?? e.message);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not write page labels.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pages = _pages;
    return ViewerToolFormScaffold(
      primaryKey: const Key('pdf_page_labels_ok'),
      primaryLabel: _busy ? 'Applying…' : 'Apply',
      primaryIcon: Icons.tag,
      primaryEnabled: !_busy && pages >= 1,
      primaryBusy: _busy,
      onPrimary: _apply,
      notice: _error == null
          ? null
          : Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
      children: [
        ViewerToolFormSection(
          first: true,
          title: 'Pages',
          subtitle: pages < 1
              ? 'Reading the open PDF…'
              : 'Labels apply to this document. Save writes the original file.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RadioGroup<bool>(
                groupValue: _allPages,
                onChanged: (v) {
                  if (_busy || v == null) return;
                  setState(() {
                    _allPages = v;
                    if (v) _beginNew = true;
                  });
                },
                child: Column(
                  children: [
                    RadioListTile<bool>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      enabled: !_busy,
                      title: const Text('All'),
                      value: true,
                    ),
                    RadioListTile<bool>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      enabled: !_busy,
                      title: const Text('From–to'),
                      value: false,
                    ),
                  ],
                ),
              ),
              if (!_allPages)
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    const Text('From'),
                    _NumBox(controller: _from, enabled: !_busy),
                    const Text('To'),
                    _NumBox(controller: _to, enabled: !_busy),
                    Text(pages < 1 ? 'of …' : 'of $pages'),
                  ],
                ),
            ],
          ),
        ),
        ViewerToolFormSection(
          title: 'Numbering',
          subtitle: 'Decimal or roman, with an optional prefix and start.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RadioGroup<bool>(
                groupValue: _beginNew,
                onChanged: (v) {
                  if (_busy || v == null) return;
                  if (!v && !_canExtend) return;
                  setState(() => _beginNew = v);
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RadioListTile<bool>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      enabled: !_busy,
                      title: const Text('Begin new section'),
                      value: true,
                    ),
                    if (_beginNew) ...[
                      DropdownButtonFormField<String>(
                        key: const Key('pdf_page_labels_style'),
                        initialValue: _style,
                        decoration: const InputDecoration(
                          labelText: 'Style',
                          isDense: true,
                        ),
                        items: [
                          for (final (code, sample) in pdfPageLabelStyleChoices)
                            DropdownMenuItem(value: code, child: Text(sample)),
                        ],
                        onChanged: _busy
                            ? null
                            : (v) {
                                if (v != null) setState(() => _style = v);
                              },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _prefix,
                        enabled: !_busy,
                        decoration: const InputDecoration(
                          labelText: 'Prefix',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _start,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Start',
                          isDense: true,
                        ),
                      ),
                    ],
                    RadioListTile<bool>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      enabled: !_busy && _canExtend,
                      title: const Text(
                        'Extend numbering used in preceding section to selected pages',
                      ),
                      value: false,
                    ),
                  ],
                ),
              ),
              if (!_allPages && !_canExtend)
                Text(
                  'Extending needs a page range that starts after page 1.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: DsColors.textSecondary(theme.brightness),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Sample: $_sample',
                key: const Key('pdf_page_labels_sample'),
                style: theme.textTheme.bodyMedium,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('pdf_page_labels_cancel'),
                  onPressed: _busy ? null : () => closeViewerToolPanel(context),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NumBox extends StatelessWidget {
  const _NumBox({required this.controller, required this.enabled});

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(isDense: true),
      ),
    );
  }
}
