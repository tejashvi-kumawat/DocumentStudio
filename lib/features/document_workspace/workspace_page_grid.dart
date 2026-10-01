import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/domain/organize/organize_page_ref.dart';
import 'package:document_studio/features/page_management/widgets/organize_page_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

/// How many columns a workspace page grid uses for [width].
///
/// Narrow phones get 2 columns; the count grows with the grid's own width so
/// the row fills the pane instead of sitting as a single strip.
int workspacePageColumnCount(double width) {
  if (width >= 1100) return 6;
  if (width >= 900) return 5;
  if (width >= 720) return 4;
  if (width >= 480) return 3;
  return 2;
}

/// Inclusive-exclusive page indexes that may render a thumbnail.
///
/// Visible rows, one row behind, and two rows ahead. Everything else stays a
/// quiet placeholder so opening a long PDF does not render every page.
({int start, int end}) workspaceThumbWindow({
  required int indexCount,
  required int columns,
  required double viewportHeight,
  required double scrollOffset,
  required double rowStride,
}) {
  if (indexCount <= 0 || columns < 1 || rowStride <= 0) {
    return (start: 0, end: 0);
  }
  final height = viewportHeight.isFinite && viewportHeight > 1
      ? viewportHeight
      : rowStride * 2;
  final firstRow = scrollOffset <= 0 ? 0 : (scrollOffset / rowStride).floor();
  var rowsVisible = (height / rowStride).ceil();
  if (rowsVisible < 1) rowsVisible = 1;
  final firstIndex = firstRow * columns;
  final start = firstIndex - columns;
  final end = firstIndex + rowsVisible * columns + columns * 2;
  return (
    start: start < 0 ? 0 : start,
    end: end > indexCount ? indexCount : end,
  );
}

typedef WorkspacePageTap = void Function(OrganizePageRef page, int index);

/// Simple page browser. Visible cells render first, then the next two rows.
/// Page tools (rotate, crop, delete, reorder) live in the PDF viewer.
class WorkspacePageGrid extends StatefulWidget {
  const WorkspacePageGrid({
    super.key,
    required this.pages,
    required this.selectedIds,
    required this.passwordsByPath,
    required this.onOpenPage,
    this.onSelectPage,
    this.highlightSourcePath,
    this.singleTapOpens = false,
  });

  final List<OrganizePageRef> pages;
  final Set<String> selectedIds;
  final Map<String, String> passwordsByPath;
  final WorkspacePageTap onOpenPage;
  final WorkspacePageTap? onSelectPage;
  final String? highlightSourcePath;

  /// Phone: a tap opens the PDF. Wider layouts select on tap and open on
  /// double-tap so the grid can be browsed.
  final bool singleTapOpens;

  @override
  State<WorkspacePageGrid> createState() => _WorkspacePageGridState();
}

class _WorkspacePageGridState extends State<WorkspacePageGrid> {
  final ScrollController _scroll = ScrollController();

  static const _padding = 12.0;
  static const _gap = 12.0;
  static const _aspect = 0.72;

  double _rowStride = 200;
  double _viewportHeight = 600;
  int _builtRow = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant WorkspacePageGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final replaced = oldWidget.pages.length != widget.pages.length ||
        (widget.pages.isNotEmpty &&
            oldWidget.pages.isNotEmpty &&
            oldWidget.pages.first.file.path != widget.pages.first.file.path);
    if (!replaced) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_scroll.offset != 0) _scroll.jumpTo(0);
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || _rowStride <= 0) return;
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final row = offset <= 0 ? 0 : (offset / _rowStride).floor();
    if (row == _builtRow) return;
    setState(() {});
  }

  int _priorityFor(int index, ({int start, int end}) window, int columns) {
    if (index < window.start || index >= window.end) return 0;
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final firstRow = offset <= 0 || _rowStride <= 0
        ? 0
        : (offset / _rowStride).floor();
    final firstIndex = firstRow * columns;
    final height = _viewportHeight.isFinite && _viewportHeight > 1
        ? _viewportHeight
        : _rowStride * 2;
    var rowsVisible = (_rowStride <= 0 ? 1 : (height / _rowStride).ceil());
    if (rowsVisible < 1) rowsVisible = 1;
    final visibleEnd = firstIndex + rowsVisible * columns;
    if (index >= firstIndex && index < visibleEnd) {
      return 3000 - (index - firstIndex);
    }
    return 1000 - (index - window.start);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final canvas = isDark
        ? DsColors.groupedBackgroundDark
        : DsColors.groupedBackgroundLight;
    final multi = widget.pages.length > 1 &&
        widget.pages.any((p) => p.file.path != widget.pages.first.file.path);

    return ColoredBox(
      color: canvas,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final columns = workspacePageColumnCount(width);
          final inner = width - _padding * 2 - (columns - 1) * _gap;
          final cellW = inner > 0 ? inner / columns : width / columns;
          final cellH = cellW / _aspect;
          final rowStride = cellH + _gap;
          _rowStride = rowStride;
          _viewportHeight = constraints.maxHeight;
          final offset = _scroll.hasClients ? _scroll.offset : 0.0;
          _builtRow = offset <= 0 || rowStride <= 0
              ? 0
              : (offset / rowStride).floor();
          final window = workspaceThumbWindow(
            indexCount: widget.pages.length,
            columns: columns,
            viewportHeight: constraints.maxHeight,
            scrollOffset: offset,
            rowStride: rowStride,
          );
          // Two rows outside the viewport. Not the rest of the document.
          final lookahead = rowStride * 2;

          return GridView.builder(
            controller: _scroll,
            primary: false,
            scrollDirection: Axis.vertical,
            addAutomaticKeepAlives: false,
            scrollCacheExtent: ScrollCacheExtent.pixels(lookahead),
            padding: const EdgeInsets.all(_padding),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: _gap,
              mainAxisSpacing: _gap,
              childAspectRatio: _aspect,
            ),
            itemCount: widget.pages.length,
            itemBuilder: (context, index) {
              final page = widget.pages[index];
              final active = index >= window.start && index < window.end;
              final priority = _priorityFor(index, window, columns);
              final selected = widget.selectedIds.contains(page.id);
              final dimmed = widget.highlightSourcePath != null &&
                  page.file.path != widget.highlightSourcePath;
              final label = multi
                  ? '${page.file.displayName} · ${page.pageNumber1Based}'
                  : '${index + 1}';
              return _WorkspacePageTile(
                key: ValueKey(page.id),
                page: page,
                label: label,
                selected: selected,
                dimmed: dimmed,
                password: widget.passwordsByPath[page.file.path],
                cellLogicalWidth: cellW,
                priority: priority,
                active: active,
                onTap: () {
                  if (widget.singleTapOpens) {
                    widget.onOpenPage(page, index);
                  } else {
                    widget.onSelectPage?.call(page, index);
                  }
                },
                onDoubleTap: widget.singleTapOpens
                    ? null
                    : () => widget.onOpenPage(page, index),
              );
            },
          );
        },
      ),
    );
  }
}

class _WorkspacePageTile extends StatelessWidget {
  const _WorkspacePageTile({
    super.key,
    required this.page,
    required this.label,
    required this.selected,
    required this.dimmed,
    required this.password,
    required this.cellLogicalWidth,
    required this.priority,
    required this.active,
    required this.onTap,
    required this.onDoubleTap,
  });

  final OrganizePageRef page;
  final String label;
  final bool selected;
  final bool dimmed;
  final String? password;
  final double cellLogicalWidth;
  final int priority;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = selected
        ? theme.colorScheme.primary
        : (isDark ? DsColors.borderDark : DsColors.borderLight);
    final fill = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.12)
        : (isDark ? DsColors.groupedCellDark : DsColors.groupedCellLight);

    final tile = Material(
      color: fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: border, width: selected ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: OrganizeCachedPageThumbnail(
                file: page.file,
                pageNumber1Based: page.pageNumber1Based,
                password: password,
                rotationDegrees: page.rotationDegrees,
                targetLogicalWidth: cellLogicalWidth,
                priority: priority,
                active: active,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );

    return Opacity(
      opacity: dimmed ? 0.38 : 1,
      child: GestureDetector(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: tile,
      ),
    );
  }
}
