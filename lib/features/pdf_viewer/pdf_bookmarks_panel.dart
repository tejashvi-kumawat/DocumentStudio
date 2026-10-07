import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_outline_writer.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Real PDF bookmarks you can edit (Acrobat's Bookmarks panel): add at the
/// current page, rename, delete, nest, reorder. Every change is written into
/// the document's outline and can be undone with the rest of the edits.
class PdfBookmarksPanel extends StatefulWidget {
  const PdfBookmarksPanel({
    super.key,
    required this.controller,
    required this.readBytes,
    required this.commit,
    required this.reloadToken,
  });

  final PdfViewerController controller;
  final Future<Uint8List> Function() readBytes;
  final Future<void> Function(Uint8List bytes) commit;

  /// Changes whenever the document content does (re-reads the outline).
  final Object reloadToken;

  @override
  State<PdfBookmarksPanel> createState() => _PdfBookmarksPanelState();
}

class _Flat {
  _Flat(this.entry, this.siblings, this.index, this.depth);

  final OutlineEntry entry;
  final List<OutlineEntry> siblings;
  final int index;
  final int depth;
}

class _PdfBookmarksPanelState extends State<PdfBookmarksPanel> {
  List<OutlineEntry> _tree = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant PdfBookmarksPanel old) {
    super.didUpdateWidget(old);
    if (old.reloadToken != widget.reloadToken && !_busy) unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final bytes = await widget.readBytes();
      if (bytes.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final tree = await Isolate.run(() => readPdfOutline(bytes));
      if (!mounted) return;
      setState(() {
        _tree = tree;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _write(List<OutlineEntry> next) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await widget.readBytes();
      if (bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bookmarks cannot be edited on very large files.'),
            ),
          );
        }
        return;
      }
      final out = await Isolate.run(() => writePdfOutline(bytes, next));
      if (out == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This document cannot store bookmarks.'),
            ),
          );
        }
        return;
      }
      await widget.commit(out);
      if (mounted) setState(() => _tree = next);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<OutlineEntry> _copy() => [for (final e in _tree) e.copy()];

  Iterable<_Flat> _flatten(List<OutlineEntry> l, [int depth = 0]) sync* {
    for (var i = 0; i < l.length; i++) {
      yield _Flat(l[i], l, i, depth);
      yield* _flatten(l[i].children, depth + 1);
    }
  }

  /// Locates [target] (by position in the flat order) inside a fresh copy.
  _Flat _inCopy(List<OutlineEntry> copy, int flatIndex) =>
      _flatten(copy).elementAt(flatIndex);

  Future<String?> _askTitle(String initial, String title) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Bookmark name'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  int get _currentPage =>
      widget.controller.isReady ? (widget.controller.pageNumber ?? 1) : 1;

  Future<void> _add({int? underFlat}) async {
    final page = _currentPage;
    final name = await _askTitle('Page $page', 'New bookmark');
    if (name == null || name.trim().isEmpty) return;
    final copy = _copy();
    final entry = OutlineEntry(title: name.trim(), page: page);
    if (underFlat == null) {
      copy.add(entry);
    } else {
      _inCopy(copy, underFlat).entry.children.add(entry);
    }
    await _write(copy);
  }

  Future<void> _rename(int flatIndex) async {
    final copy = _copy();
    final f = _inCopy(copy, flatIndex);
    final name = await _askTitle(f.entry.title, 'Rename bookmark');
    if (name == null || name.trim().isEmpty) return;
    f.entry.title = name.trim();
    await _write(copy);
  }

  Future<void> _delete(int flatIndex) async {
    final copy = _copy();
    final f = _inCopy(copy, flatIndex);
    f.siblings.removeAt(f.index);
    await _write(copy);
  }

  Future<void> _move(int flatIndex, int delta) async {
    final copy = _copy();
    final f = _inCopy(copy, flatIndex);
    final to = f.index + delta;
    if (to < 0 || to >= f.siblings.length) return;
    final e = f.siblings.removeAt(f.index);
    f.siblings.insert(to, e);
    await _write(copy);
  }

  Future<void> _setHere(int flatIndex) async {
    final copy = _copy();
    _inCopy(copy, flatIndex).entry.page = _currentPage;
    await _write(copy);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final rows = _flatten(_tree).toList();
    return Material(
      color: dark
          ? DsColors.surfaceContainerDark
          : DsColors.surfaceContainerLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text('Bookmarks', style: theme.textTheme.titleSmall),
                ),
                IconButton(
                  tooltip: 'Add bookmark for this page',
                  visualDensity: VisualDensity.compact,
                  onPressed: _busy ? null : () => _add(),
                  icon: const Icon(Icons.bookmark_add_outlined, size: 20),
                ),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'No bookmarks yet',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 10),
                          FilledButton.tonal(
                            onPressed: _busy ? null : () => _add(),
                            child: const Text('Add one for this page'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      return InkWell(
                        onTap: () => widget.controller.isReady
                            ? widget.controller.goToPage(
                                pageNumber: r.entry.page.clamp(
                                  1,
                                  widget.controller.pageCount,
                                ),
                              )
                            : null,
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: 10.0 + r.depth * 14,
                            right: 0,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.bookmark_outline,
                                size: 15,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Text(
                                    r.entry.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                              ),
                              Text(
                                '${r.entry.page}',
                                style: theme.textTheme.labelSmall,
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'Bookmark options',
                                iconSize: 16,
                                padding: EdgeInsets.zero,
                                onSelected: (v) {
                                  switch (v) {
                                    case 'rename':
                                      _rename(i);
                                    case 'delete':
                                      _delete(i);
                                    case 'child':
                                      _add(underFlat: i);
                                    case 'up':
                                      _move(i, -1);
                                    case 'down':
                                      _move(i, 1);
                                    case 'here':
                                      _setHere(i);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'rename',
                                    child: Text('Rename…'),
                                  ),
                                  PopupMenuItem(
                                    value: 'child',
                                    child: Text('Add sub-bookmark here…'),
                                  ),
                                  PopupMenuItem(
                                    value: 'here',
                                    child: Text('Point to current page'),
                                  ),
                                  PopupMenuItem(
                                    value: 'up',
                                    child: Text('Move up'),
                                  ),
                                  PopupMenuItem(
                                    value: 'down',
                                    child: Text('Move down'),
                                  ),
                                  PopupMenuDivider(),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
