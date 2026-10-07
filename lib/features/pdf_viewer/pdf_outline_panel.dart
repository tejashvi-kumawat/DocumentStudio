import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/features/pdf_viewer/pdf_session_bookmarks.dart';
import 'package:document_studio/features/pdf_viewer/pdf_thumbnail_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// DS-READ-010 — outline from the PDF, plus Document Studio session bookmarks.
class PdfOutlinePanel extends StatefulWidget {
  const PdfOutlinePanel({
    super.key,
    required this.controller,
    this.scrollAxis = Axis.vertical,
    this.pdfPath,
  });

  final PdfViewerController controller;
  final Axis scrollAxis;

  /// When set, empty outlines can add session bookmarks persisted beside the file.
  final String? pdfPath;

  @override
  State<PdfOutlinePanel> createState() => _PdfOutlinePanelState();
}

class _PdfOutlinePanelState extends State<PdfOutlinePanel> {
  List<PdfOutlineNode>? _outline;
  List<PdfSessionBookmark> _session = const [];
  Object? _loadError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadOutline();
  }

  @override
  void didUpdateWidget(covariant PdfOutlinePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.pdfPath != widget.pdfPath) {
      _outline = null;
      _loadError = null;
      _loading = true;
      _session = const [];
      _loadOutline();
    }
  }

  Future<void> _loadOutline() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await widget.controller.useDocument((document) async {
        final nodes = await document.loadOutline();
        if (!mounted) return;
        setState(() {
          _outline = nodes;
          _loading = false;
        });
      });
      final path = widget.pdfPath;
      if (path != null) {
        final session = await loadPdfSessionBookmarks(path);
        if (!mounted) return;
        setState(() => _session = session);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
        _outline = const [];
      });
    }
  }

  Future<void> _goToNode(PdfOutlineNode node) async {
    final dest = node.dest;
    if (dest == null) return;
    await widget.controller.goToDest(dest);
  }

  Future<void> _goToSession(PdfSessionBookmark bookmark) async {
    if (!widget.controller.isReady) return;
    final total = widget.controller.pageCount;
    final page = bookmark.page1Based.clamp(1, total);
    await widget.controller.goToPage(pageNumber: page);
  }

  Future<void> _addSessionBookmark() async {
    final path = widget.pdfPath;
    if (path == null || !widget.controller.isReady) return;
    final page = widget.controller.pageNumber ?? 1;
    final next = [
      ..._session,
      PdfSessionBookmark(
        title: 'Page $page',
        page1Based: page,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    ];
    await savePdfSessionBookmarks(pdfPath: path, bookmarks: next);
    if (!mounted) return;
    setState(() => _session = next);
  }

  Future<void> _removeSessionBookmark(int index) async {
    final path = widget.pdfPath;
    if (path == null || index < 0 || index >= _session.length) return;
    final next = [..._session]..removeAt(index);
    await savePdfSessionBookmarks(pdfPath: path, bookmarks: next);
    if (!mounted) return;
    setState(() => _session = next);
  }

  Material _panelChrome({required Widget child, required bool isDark}) {
    final horizontal = widget.scrollAxis == Axis.horizontal;
    return Material(
      color: isDark
          ? DsColors.surfaceContainerDark
          : DsColors.surfaceContainerLight,
      elevation: isDark ? 0 : 1,
      child: horizontal
          ? SizedBox(height: 120, width: double.infinity, child: child)
          : SizedBox(width: PdfThumbnailSidebar.sidebarWidth, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_loading) {
      return _panelChrome(
        isDark: isDark,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return _panelChrome(
        isDark: isDark,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Could not load bookmarks',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final nodes = _outline ?? const <PdfOutlineNode>[];
    final hasOutline = nodes.isNotEmpty;
    final canAddSession = widget.pdfPath != null;

    if (!hasOutline && _session.isEmpty) {
      return _panelChrome(
        isDark: isDark,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'No bookmarks',
                key: const Key('pdf_outline_empty_message'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (canAddSession) ...[
                const SizedBox(height: 12),
                FilledButton.tonal(
                  key: const Key('pdf_outline_add_bookmark'),
                  onPressed: _addSessionBookmark,
                  child: const Text('Add bookmark'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Saved in Document Studio',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return _panelChrome(
      isDark: isDark,
      child: ListView(
        key: const Key('pdf_outline_panel_list'),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (hasOutline)
            for (final node in nodes)
              _OutlineTile(node: node, depth: 0, onTap: _goToNode),
          if (_session.isNotEmpty) ...[
            if (hasOutline)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Text(
                  'Saved in Document Studio',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (!hasOutline)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Text(
                  'Saved in Document Studio',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (var i = 0; i < _session.length; i++)
              ListTile(
                key: Key('pdf_session_bookmark_$i'),
                dense: true,
                title: Text(
                  _session[i].title,
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'Page ${_session[i].page1Based}',
                  style: theme.textTheme.labelSmall,
                ),
                onTap: () => _goToSession(_session[i]),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  tooltip: 'Remove bookmark',
                  onPressed: () => _removeSessionBookmark(i),
                ),
              ),
          ],
          if (canAddSession)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: OutlinedButton(
                key: const Key('pdf_outline_add_bookmark'),
                onPressed: _addSessionBookmark,
                child: const Text('Add bookmark'),
              ),
            ),
        ],
      ),
    );
  }
}

class _OutlineTile extends StatelessWidget {
  const _OutlineTile({
    required this.node,
    required this.depth,
    required this.onTap,
  });

  final PdfOutlineNode node;
  final int depth;
  final Future<void> Function(PdfOutlineNode node) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = node.title.trim().isEmpty ? 'Untitled' : node.title.trim();
    final hasDest = node.dest != null;
    final hasChildren = node.children.isNotEmpty;

    if (hasChildren) {
      return Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: Key('pdf_outline_expansion_${depth}_$title'),
          tilePadding: EdgeInsets.only(left: 8 + depth * 12, right: 8),
          childrenPadding: EdgeInsets.zero,
          title: Text(
            title,
            style: theme.textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: hasDest
              ? IconButton(
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  tooltip: 'Go to bookmark',
                  onPressed: () => onTap(node),
                )
              : null,
          initiallyExpanded: depth == 0,
          children: [
            for (final child in node.children)
              _OutlineTile(node: child, depth: depth + 1, onTap: onTap),
          ],
        ),
      );
    }

    return ListTile(
      key: Key('pdf_outline_leaf_${depth}_$title'),
      dense: true,
      contentPadding: EdgeInsets.only(left: 16 + depth * 12, right: 8),
      title: Text(
        title,
        style: theme.textTheme.bodySmall,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      enabled: hasDest,
      onTap: hasDest ? () => onTap(node) : null,
    );
  }
}
