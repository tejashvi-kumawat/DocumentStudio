import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/features/page_management/interaction/organize_insertion_indicator.dart';
import 'package:document_studio/features/page_management/interaction/organize_marquee_selection.dart';
import 'package:document_studio/domain/organize/organize_page_ref.dart';
import 'package:document_studio/features/page_management/widgets/organize_page_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How page thumbnails are arranged for reorder.
enum OrganizePageLayout {
  /// Multi-column grid (workspace + tool screens). Fills width: 2/3 phone, more on tablet.
  grid,

  /// Horizontal filmstrip (optional compact strip layouts).
  filmstrip,
}

typedef OrganizePageTap = void Function(
  OrganizePageRef page,
  int index, {
  required bool shift,
  required bool ctrlOrMeta,
});

typedef OrganizeMarqueeSelect = void Function(
  Set<String> pageIds, {
  required bool additive,
});

class OrganizePageGrid extends ConsumerStatefulWidget {
  const OrganizePageGrid({
    super.key,
    required this.pages,
    required this.selectedIds,
    required this.onTap,
    required this.onReorder,
    required this.onMoveDelta,
    this.onContextAction,
    this.passwordsByPath = const {},
    this.enableDragReorder = true,
    this.enableMarqueeSelection,
    this.onMarqueeSelect,
    this.highlightSourcePath,
    this.layout = OrganizePageLayout.grid,
  });

  final List<OrganizePageRef> pages;
  final Set<String> selectedIds;
  final OrganizePageTap onTap;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(int index, int delta) onMoveDelta;
  final void Function(String action, int index)? onContextAction;
  final Map<String, String> passwordsByPath;
  final bool enableDragReorder;
  final bool? enableMarqueeSelection;
  final OrganizeMarqueeSelect? onMarqueeSelect;
  final String? highlightSourcePath;
  final OrganizePageLayout layout;

  @override
  ConsumerState<OrganizePageGrid> createState() => _OrganizePageGridState();
}

class _OrganizePageGridState extends ConsumerState<OrganizePageGrid> {
  final ValueNotifier<int?> _dragIndex = ValueNotifier<int?>(null);
  late final ScrollController _scrollController;
  late final OrganizeGridEdgeAutoScroller _edgeAutoScroller;
  final GlobalKey _gridAreaKey = GlobalKey();

  static const _gridPadding = EdgeInsets.all(12);
  static const _crossSpacing = 12.0;
  static const _mainSpacing = 12.0;
  static const _childAspectRatio = 0.68;
  static const _filmstripTileWidth = 112.0;
  static const _filmstripHeight = 168.0;

  bool get _isFilmstrip => widget.layout == OrganizePageLayout.filmstrip;

  Axis get _listAxis =>
      _isFilmstrip ? Axis.horizontal : Axis.vertical;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _edgeAutoScroller =
        OrganizeGridEdgeAutoScroller(scrollController: _scrollController);
  }

  @override
  void dispose() {
    _dragIndex.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Phone: 2 columns when narrow, 3 when there is room; tablet/wide: more.
  /// Always fills the available width (not a single lonely row).
  int _crossAxisCount(double width) {
    if (width >= 1100) return 6;
    if (width >= 900) return 5;
    if (width >= 720) return 4;
    if (width >= 480) return 3;
    return 2;
  }

  OrganizeGridLayoutMetrics _metrics(double viewportWidth) {
    return OrganizeGridLayoutMetrics(
      crossAxisCount: _crossAxisCount(viewportWidth),
      crossAxisSpacing: _crossSpacing,
      mainAxisSpacing: _mainSpacing,
      childAspectRatio: _childAspectRatio,
      padding: _gridPadding,
      viewportWidth: viewportWidth,
      itemCount: widget.pages.length,
    );
  }

  void _onAutoScrollTick() {
    _edgeAutoScroller.tick();
    if (_edgeAutoScroller.isActive) {
      _edgeAutoScroller.ensureTicking(_onAutoScrollTick);
    }
  }

  void _updateEdgeScrollFromGlobal(Offset globalPosition) {
    final box = _gridAreaKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(globalPosition);
    if (_isFilmstrip) {
      _edgeAutoScroller.updateFromViewportLocalHorizontal(local, box.size.width);
    } else {
      _edgeAutoScroller.updateFromViewportLocal(local, box.size.height);
    }
    _edgeAutoScroller.ensureTicking(_onAutoScrollTick);
  }

  void _stopEdgeScroll() {
    _edgeAutoScroller.stop();
  }

  bool _marqueeEnabled(bool compact) {
    if (_isFilmstrip) return false;
    final on = widget.onMarqueeSelect;
    if (on == null) return false;
    return widget.enableMarqueeSelection ?? !compact;
  }

  bool _pointerOnTile(OrganizeGridLayoutMetrics metrics, Offset localInViewport) {
    if (!_scrollController.hasClients) return false;
    final offset = _scrollController.offset;
    for (var i = 0; i < widget.pages.length; i++) {
      if (metrics.viewportPointHitsTile(localInViewport, i, offset)) {
        return true;
      }
    }
    return false;
  }

  Widget _buildTile({
    required OrganizePageRef page,
    required int index,
    required bool compact,
    required bool filmstrip,
  }) {
    final selected = widget.selectedIds.contains(page.id);
    final dimmed = widget.highlightSourcePath != null &&
        page.file.path != widget.highlightSourcePath;
    return ValueListenableBuilder<int?>(
      valueListenable: _dragIndex,
      builder: (context, dragIndex, _) {
        return _OrganizePageTile(
          key: ValueKey(page.id),
          page: page,
          index: index,
          selected: selected,
          dimmed: dimmed,
          compact: compact,
          filmstrip: filmstrip,
          listAxis: _listAxis,
          dragging: dragIndex == index,
          password: widget.passwordsByPath[page.file.path],
          onTap: ({required shift, required ctrlOrMeta}) =>
              widget.onTap(page, index, shift: shift, ctrlOrMeta: ctrlOrMeta),
          onMoveDelta: (d) => widget.onMoveDelta(index, d),
          onDragStarted: () => _dragIndex.value = index,
          onDragEnded: () {
            _stopEdgeScroll();
            _dragIndex.value = null;
          },
          onDragGlobalMove: _updateEdgeScrollFromGlobal,
          onAcceptDrop: (from, targetIndex) {
            if (from != targetIndex) widget.onReorder(from, targetIndex);
          },
          onContextAction: widget.onContextAction,
          enableDragReorder: widget.enableDragReorder,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 600;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final canvas = isDark
        ? DsColors.groupedBackgroundDark
        : DsColors.groupedBackgroundLight;

    if (_isFilmstrip) {
      return ColoredBox(
        color: canvas,
        child: KeyedSubtree(
          key: _gridAreaKey,
          child: SizedBox(
            height: _filmstripHeight + 24,
            child: ListView.separated(
              key: const PageStorageKey<String>('organize_page_filmstrip'),
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              itemCount: widget.pages.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                return SizedBox(
                  width: _filmstripTileWidth,
                  child: _buildTile(
                    page: widget.pages[index],
                    index: index,
                    compact: compact,
                    filmstrip: true,
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    final marqueeEnabled = _marqueeEnabled(compact);

    return ColoredBox(
      color: canvas,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layoutWidth = constraints.maxWidth;
          final cross = _crossAxisCount(layoutWidth);
          final metrics = _metrics(layoutWidth);

          Widget grid = GridView.builder(
            key: const PageStorageKey<String>('organize_page_grid'),
            controller: _scrollController,
            padding: _gridPadding,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cross,
              crossAxisSpacing: _crossSpacing,
              mainAxisSpacing: _mainSpacing,
              childAspectRatio: _childAspectRatio,
            ),
            itemCount: widget.pages.length,
            itemBuilder: (context, index) {
              return _buildTile(
                page: widget.pages[index],
                index: index,
                compact: compact,
                filmstrip: false,
              );
            },
          );

          if (marqueeEnabled) {
            grid = _OrganizeGridMarqueeLayer(
              metrics: metrics,
              pages: widget.pages,
              scrollController: _scrollController,
              edgeAutoScroller: _edgeAutoScroller,
              onAutoScrollTick: _onAutoScrollTick,
              onStopEdgeScroll: _stopEdgeScroll,
              pointerOnTile: (local) => _pointerOnTile(metrics, local),
              onMarqueeSelect: widget.onMarqueeSelect!,
              child: grid,
            );
          }

          return KeyedSubtree(
            key: _gridAreaKey,
            child: grid,
          );
        },
      ),
    );
  }
}

/// Marquee rubber-band — isolated [setState] so the grid does not rebuild on pointer move.
class _OrganizeGridMarqueeLayer extends StatefulWidget {
  const _OrganizeGridMarqueeLayer({
    required this.metrics,
    required this.pages,
    required this.scrollController,
    required this.edgeAutoScroller,
    required this.onAutoScrollTick,
    required this.onStopEdgeScroll,
    required this.pointerOnTile,
    required this.onMarqueeSelect,
    required this.child,
  });

  final OrganizeGridLayoutMetrics metrics;
  final List<OrganizePageRef> pages;
  final ScrollController scrollController;
  final OrganizeGridEdgeAutoScroller edgeAutoScroller;
  final VoidCallback onAutoScrollTick;
  final VoidCallback onStopEdgeScroll;
  final bool Function(Offset localInViewport) pointerOnTile;
  final OrganizeMarqueeSelect onMarqueeSelect;
  final Widget child;

  @override
  State<_OrganizeGridMarqueeLayer> createState() => _OrganizeGridMarqueeLayerState();
}

class _OrganizeGridMarqueeLayerState extends State<_OrganizeGridMarqueeLayer> {
  Offset? _marqueeStart;
  Offset? _marqueeEnd;
  bool _marqueeActive = false;

  void _clearMarquee() {
    if (!_marqueeActive && _marqueeStart == null) return;
    setState(() {
      _marqueeActive = false;
      _marqueeStart = null;
      _marqueeEnd = null;
    });
  }

  void _onPointerDown(PointerDownEvent event) {
    if (widget.pointerOnTile(event.localPosition)) return;
    setState(() {
      _marqueeActive = true;
      _marqueeStart = event.localPosition;
      _marqueeEnd = event.localPosition;
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_marqueeActive) return;
    setState(() => _marqueeEnd = event.localPosition);
    final box = context.findRenderObject() as RenderBox?;
    widget.edgeAutoScroller.updateFromViewportLocal(
      event.localPosition,
      box?.size.height ?? 0,
    );
    widget.edgeAutoScroller.ensureTicking(widget.onAutoScrollTick);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!_marqueeActive || _marqueeStart == null || _marqueeEnd == null) {
      _clearMarquee();
      return;
    }
    final scrollOffset = widget.scrollController.hasClients
        ? widget.scrollController.offset
        : 0.0;
    final contentRect = widget.metrics.contentRectFromViewportDrag(
      _marqueeStart!,
      _marqueeEnd!,
      scrollOffset,
    );
    final indices = widget.metrics.indicesIntersectingContentRect(contentRect);
    final ids = {for (final i in indices) widget.pages[i].id};

    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final meta = keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight) ||
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);

    widget.onMarqueeSelect(ids, additive: meta);
    widget.onStopEdgeScroll();
    _clearMarquee();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    OrganizeMarqueeBand? band;
    if (_marqueeActive && _marqueeStart != null && _marqueeEnd != null) {
      band = OrganizeMarqueeBand(_marqueeStart!, _marqueeEnd!);
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: (_) {
        widget.onStopEdgeScroll();
        _clearMarquee();
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (band != null && !band.isEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: OrganizeMarqueeOverlayPainter(
                    band: band,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OrganizePageTile extends StatefulWidget {
  const _OrganizePageTile({
    super.key,
    required this.page,
    required this.index,
    required this.selected,
    this.dimmed = false,
    required this.compact,
    required this.filmstrip,
    required this.listAxis,
    required this.dragging,
    required this.password,
    required this.onTap,
    required this.onMoveDelta,
    required this.onDragStarted,
    required this.onDragEnded,
    required this.onDragGlobalMove,
    required this.onAcceptDrop,
    this.onContextAction,
    this.enableDragReorder = true,
  });

  final OrganizePageRef page;
  final int index;
  final bool selected;
  final bool dimmed;
  final bool compact;
  final bool filmstrip;
  final Axis listAxis;
  final bool dragging;
  final String? password;
  final void Function({required bool shift, required bool ctrlOrMeta}) onTap;
  final void Function(int delta) onMoveDelta;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;
  final void Function(Offset globalPosition) onDragGlobalMove;
  final void Function(int fromIndex, int targetIndex) onAcceptDrop;
  final void Function(String action, int index)? onContextAction;
  final bool enableDragReorder;

  @override
  State<_OrganizePageTile> createState() => _OrganizePageTileState();
}

class _OrganizePageTileState extends State<_OrganizePageTile> {
  OrganizeInsertEdge _edge = OrganizeInsertEdge.before;

  void _updateEdgeFromGlobal(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(global);
    final next = widget.listAxis == Axis.horizontal
        ? (local.dx >= box.size.width / 2
            ? OrganizeInsertEdge.after
            : OrganizeInsertEdge.before)
        : (local.dy >= box.size.height / 2
            ? OrganizeInsertEdge.after
            : OrganizeInsertEdge.before);
    if (next != _edge) {
      setState(() => _edge = next);
    }
  }

  int _targetIndexForEdge() {
    if (_edge == OrganizeInsertEdge.before) return widget.index;
    return widget.index + 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = widget.selected
        ? theme.colorScheme.primary
        : (isDark ? DsColors.borderDark : DsColors.borderLight);
    final fill = widget.selected
        ? theme.colorScheme.primary.withValues(alpha: 0.12)
        : (isDark ? DsColors.groupedCellDark : DsColors.groupedCellLight);

    final thumb = Padding(
      padding: const EdgeInsets.all(6),
      child: OrganizeCachedPageThumbnail(
        file: widget.page.file,
        pageNumber1Based: widget.page.pageNumber1Based,
        password: widget.password,
        rotationDegrees: widget.page.rotationDegrees,
      ),
    );

    final label = Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Row(
        children: [
          if (widget.enableDragReorder && !widget.compact && !widget.filmstrip)
            Icon(Icons.drag_indicator, size: 14, color: theme.hintColor),
          Expanded(
            child: Text(
              '${widget.index + 1}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: widget.filmstrip ? TextAlign.center : TextAlign.start,
              style: theme.textTheme.labelSmall?.copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );

    final content = Material(
      color: fill,
      elevation: widget.dragging ? 4 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: border, width: widget.selected ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.filmstrip)
            Expanded(child: thumb)
          else
            Expanded(child: thumb),
          label,
          if (widget.compact && !widget.filmstrip)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 20,
                  tooltip: 'Move earlier',
                  onPressed: () => widget.onMoveDelta(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  iconSize: 20,
                  tooltip: 'Move later',
                  onPressed: () => widget.onMoveDelta(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
        ],
      ),
    );

    final Widget childLayer = widget.enableDragReorder && !widget.compact
        ? Draggable<int>(
            data: widget.index,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            onDragStarted: widget.onDragStarted,
            onDragUpdate: (details) =>
                widget.onDragGlobalMove(details.globalPosition),
            onDragEnd: (_) => widget.onDragEnded(),
            feedback: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              color: fill,
              child: SizedBox(
                width: widget.filmstrip ? 100 : 100,
                height: widget.filmstrip ? 130 : 130,
                child: Opacity(opacity: 0.92, child: content),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.25, child: content),
            child: content,
          )
        : content;

    final tile = GestureDetector(
      onTap: () {
        final keys = HardwareKeyboard.instance.logicalKeysPressed;
        final meta = keys.contains(LogicalKeyboardKey.metaLeft) ||
            keys.contains(LogicalKeyboardKey.metaRight) ||
            keys.contains(LogicalKeyboardKey.controlLeft) ||
            keys.contains(LogicalKeyboardKey.controlRight);
        final shift = keys.contains(LogicalKeyboardKey.shiftLeft) ||
            keys.contains(LogicalKeyboardKey.shiftRight);
        widget.onTap(shift: shift, ctrlOrMeta: meta);
      },
      onSecondaryTapDown: widget.onContextAction == null
          ? null
          : (details) async {
              final action = await showMenu<String>(
                context: context,
                position: RelativeRect.fromLTRB(
                  details.globalPosition.dx,
                  details.globalPosition.dy,
                  details.globalPosition.dx,
                  details.globalPosition.dy,
                ),
                items: const [
                  PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                  PopupMenuItem(value: 'rotate_cw', child: Text('Rotate 90° CW')),
                ],
              );
              if (action != null) {
                widget.onContextAction!(action, widget.index);
              }
            },
      child: DragTarget<int>(
        onWillAcceptWithDetails: (d) => d.data != widget.index,
        onMove: (details) => _updateEdgeFromGlobal(details.offset),
        onLeave: (_) {
          if (_edge != OrganizeInsertEdge.before) {
            setState(() => _edge = OrganizeInsertEdge.before);
          }
        },
        onAcceptWithDetails: (d) =>
            widget.onAcceptDrop(d.data, _targetIndexForEdge()),
        builder: (context, candidate, rejected) {
          final highlight = candidate.isNotEmpty;
          final indicator = OrganizeInsertionIndicator(
            listAxis: widget.listAxis,
            edge: _edge,
            active: highlight,
          );

          if (widget.listAxis == Axis.horizontal) {
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    decoration: highlight
                        ? BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.2),
                                blurRadius: 8,
                              ),
                            ],
                          )
                        : null,
                    child: childLayer,
                  ),
                ),
                if (highlight)
                  Positioned(
                    left: _edge == OrganizeInsertEdge.before ? -2 : null,
                    right: _edge == OrganizeInsertEdge.after ? -2 : null,
                    top: 0,
                    bottom: 18,
                    child: indicator,
                  ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (highlight && _edge == OrganizeInsertEdge.before) indicator,
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  decoration: highlight
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.25),
                              blurRadius: 8,
                            ),
                          ],
                        )
                      : null,
                  child: childLayer,
                ),
              ),
              if (highlight && _edge == OrganizeInsertEdge.after) indicator,
            ],
          );
        },
      ),
    );
    return widget.dimmed ? Opacity(opacity: 0.38, child: tile) : tile;
  }
}
