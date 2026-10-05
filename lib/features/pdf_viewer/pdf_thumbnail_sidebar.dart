import 'dart:async';

import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/features/page_management/interaction/organize_insertion_indicator.dart';
import 'package:document_studio/features/page_management/page_thumb_render_gate.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_params_config.dart';
import 'package:document_studio/features/pdf_viewer/pdf_approach_pages.dart';
import 'package:document_studio/features/pdf_viewer/pdf_thumbnail_page_action.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_thumb_cell.dart';
import 'package:document_studio/design_system/widgets/ds_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:pdfrx/pdfrx.dart';

/// Mobile / narrow horizontal thumbnail strip height.
const kPdfViewerMobileThumbnailStripHeight =
    PdfThumbnailSidebar.mobileStripHeight;

/// Page thumbnails using pdfrx [PdfPageView] (page render).
class PdfThumbnailSidebar extends StatefulWidget {
  const PdfThumbnailSidebar({
    super.key,
    required this.controller,
    required this.onPageSelected,
    this.scrollAxis = Axis.vertical,
    this.onReorderPages,
    this.onPageAction,
  });

  final PdfViewerController controller;
  final ValueChanged<int> onPageSelected;
  final Axis scrollAxis;

  /// When set, thumbnails can be dragged to reorder pages.
  /// Args are 0-based from/to indices (insert before [to] after removal).
  final void Function(int fromIndex0, int toIndex0)? onReorderPages;

  /// Optional per-page context actions (rotate, delete, extract, …).
  final void Function(int pageNumber1Based, PdfThumbnailPageAction action)?
      onPageAction;

  static const sidebarWidth = 168.0;

  /// Mobile / narrow horizontal thumbnail strip height.
  static const double mobileStripHeight = 112.0;

  /// Design-system spacing scale (4dp base): 8, 12.
  static const _listPaddingVertical = 12.0;
  static const _listPaddingHorizontal = 8.0;
  static const _tileGap = 8.0;
  static const _tileRadius = 8.0;

  @override
  State<PdfThumbnailSidebar> createState() => _PdfThumbnailSidebarState();
}

class _PdfThumbnailSidebarState extends State<PdfThumbnailSidebar> {
  PdfDocument? _document;
  int? _pageCount;
  int? _lastSyncedPage;
  int? _paintedPage;
  int _thumbFollowTries = 0;
  final GlobalKey _activeTileKey = GlobalKey();
  final ScrollController _thumbs = ScrollController();
  final PageThumbRenderGate _thumbGate = PageThumbRenderGate(
    concurrency: kPdfThumbMaxDecodes,
  );
  VoidCallback? _controllerReadyListener;
  bool _activePageScrollScheduled = false;
  bool _documentStateRebuildScheduled = false;
  int? _dropHighlightIndex;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onViewerPageChanged);
    _scheduleResolveDocument();
  }

  @override
  void dispose() {
    _detachControllerReadyListener(widget.controller);
    widget.controller.removeListener(_onViewerPageChanged);
    _thumbs.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PdfThumbnailSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onViewerPageChanged);
      _detachControllerReadyListener(oldWidget.controller);
      widget.controller.addListener(_onViewerPageChanged);
      _document = null;
      _pageCount = null;
      _lastSyncedPage = null;
      _thumbFollowTries = 0;
      _scheduleResolveDocument();
    }
  }

  void _detachControllerReadyListener(PdfViewerController controller) {
    final listener = _controllerReadyListener;
    if (listener != null) {
      controller.removeListener(listener);
      _controllerReadyListener = null;
    }
  }

  void _scheduleResolveDocument() {
    final controller = widget.controller;
    if (controller.isReady) {
      unawaited(_resolveDocument());
      return;
    }
    _detachControllerReadyListener(controller);
    void onReady() {
      if (!mounted || !controller.isReady) return;
      // Never removeListener during notifyListeners (ConcurrentModificationError).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _detachControllerReadyListener(controller);
        unawaited(_resolveDocument());
      });
    }

    _controllerReadyListener = onReady;
    // Attach outside any in-flight controller notification.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _controllerReadyListener != onReady) return;
      if (controller.isReady) {
        onReady();
        return;
      }
      controller.addListener(onReady);
    });
  }

  void _onViewerPageChanged() {
    if (!mounted || !widget.controller.isReady) return;
    _scheduleScrollToActivePage();
  }

  void _scheduleScrollToActivePage() {
    if (_activePageScrollScheduled) return;
    _activePageScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activePageScrollScheduled = false;
      if (!mounted || !widget.controller.isReady) return;
      // Page number is updated while the viewer rebuilds, after this
      // controller notification. Read it on the next frame so the highlight
      // and the strip both follow the page the user is actually on.
      final page = widget.controller.pageNumber ?? 1;
      if (_paintedPage != page) setState(() {});
      _syncScrollToActivePage(page);
    });
  }

  void _scheduleDocumentStateRebuild(
    PdfDocument document,
    int pageCount,
  ) {
    if (_documentStateRebuildScheduled) return;
    _documentStateRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _documentStateRebuildScheduled = false;
      if (!mounted) return;
      setState(() {
        _document = document;
        _pageCount = pageCount;
      });
    });
  }

  Future<void> _resolveDocument() async {
    if (!widget.controller.isReady) return;
    await widget.controller.useDocument((document) async {
      if (!mounted) return;
      _scheduleDocumentStateRebuild(document, document.pages.length);
    });
  }

  double _thumbStride(bool horizontal) {
    if (horizontal) {
      final tileHeight = kPdfViewerMobileThumbnailStripHeight - 24;
      return tileHeight * 3 / 4 + PdfThumbnailSidebar._tileGap;
    }
    final tileWidth = PdfThumbnailSidebar.sidebarWidth -
        PdfThumbnailSidebar._listPaddingHorizontal * 2;
    return tileWidth * 4 / 3 + PdfThumbnailSidebar._tileGap;
  }

  /// Moves the strip to [activePage] even when that cell is not built yet.
  ///
  /// [Scrollable.ensureVisible] only works for a tile that already exists.
  /// During a fast scroll the current page is far outside the built range, so
  /// the strip used to stay on page 1.
  void _syncScrollToActivePage(int activePage) {
    if (_lastSyncedPage == activePage) return;
    if (!_thumbs.hasClients) {
      if (_thumbFollowTries < 8) {
        _thumbFollowTries++;
        _scheduleScrollToActivePage();
      }
      return;
    }
    final stride = _thumbStride(widget.scrollAxis == Axis.horizontal);
    final maxScroll = _thumbs.position.maxScrollExtent;
    final pendingLayout =
        maxScroll == 0 && activePage > 1 && (_pageCount ?? 0) > 1;
    if (pendingLayout) {
      if (_thumbFollowTries < 8) {
        _thumbFollowTries++;
        _scheduleScrollToActivePage();
      }
      return;
    }
    _thumbFollowTries = 0;
    _lastSyncedPage = activePage;
    final target = pdfThumbStripOffset(
      pageNumber: activePage,
      stride: stride,
      maxScrollExtent: maxScroll,
    );
    if ((_thumbs.offset - target).abs() > 1) {
      _thumbs.jumpTo(target);
    }
  }

  Material _sidebarChrome({required Widget child, required bool isDark}) {
    final horizontal = widget.scrollAxis == Axis.horizontal;
    return Material(
      color: isDark
          ? DsColors.surfaceContainerDark
          : DsColors.surfaceContainerLight,
      elevation: isDark ? 0 : 1,
      child: horizontal
          ? SizedBox(
              height: kPdfViewerMobileThumbnailStripHeight,
              width: double.infinity,
              child: child,
            )
          : SizedBox(
              width: PdfThumbnailSidebar.sidebarWidth,
              // Parent left-rail Column provides a bounded height via Expanded;
              // expand so ListView gets finite constraints (avoids huge Column overflow).
              height: double.infinity,
              child: child,
            ),
    );
  }

  /// Horizontal strip → vertical edge bar; vertical list → horizontal bar.
  bool get _insertionBarIsHorizontalLine =>
      widget.scrollAxis == Axis.vertical;

  Widget _wrapReorderable({
    required int index,
    required Widget tile,
  }) {
    final onReorder = widget.onReorderPages;
    if (onReorder == null) return tile;

    final horizontal = widget.scrollAxis == Axis.horizontal;
    final highlight = _dropHighlightIndex == index;

    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != index,
      onMove: (_) {
        if (_dropHighlightIndex != index) {
          setState(() => _dropHighlightIndex = index);
        }
      },
      onLeave: (_) {
        if (_dropHighlightIndex == index) {
          setState(() => _dropHighlightIndex = null);
        }
      },
      onAcceptWithDetails: (d) {
        setState(() => _dropHighlightIndex = null);
        onReorder(d.data, index);
      },
      builder: (context, candidate, rejected) {
        final show = highlight || candidate.isNotEmpty;
        final indicator = OrganizeInsertionIndicator(
          listAxis: _insertionBarIsHorizontalLine
              ? Axis.horizontal
              : Axis.vertical,
          active: show,
        );

        final body = Draggable<int>(
          data: index,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: Material(
            elevation: 6,
            borderRadius:
                BorderRadius.circular(PdfThumbnailSidebar._tileRadius),
            child: SizedBox(
              width: horizontal ? 72 : 120,
              height: horizontal ? 96 : 150,
              child: Opacity(opacity: 0.9, child: tile),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: tile),
          child: tile,
          onDragEnd: (_) {
            if (_dropHighlightIndex != null) {
              setState(() => _dropHighlightIndex = null);
            }
          },
        );

        if (horizontal) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (show) indicator,
              Flexible(child: body),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (show) indicator,
            body,
          ],
        );
      },
    );
  }

  void _showPageMenu(int page, Offset at) {
    final act = widget.onPageAction;
    if (act == null) return;
    widget.onPageSelected(page);
    unawaited(showDsContextMenu(context, at, [
      DsMenuItem(
        label: 'Rotate Clockwise',
        icon: Icons.rotate_right,
        onTap: () => act(page, PdfThumbnailPageAction.rotateRight),
      ),
      DsMenuItem(
        label: 'Rotate Counterclockwise',
        icon: Icons.rotate_left,
        onTap: () => act(page, PdfThumbnailPageAction.rotateLeft),
      ),
      const DsMenuDivider(),
      DsMenuItem(
        label: 'Insert Blank Page After',
        icon: Icons.note_add_outlined,
        onTap: () => act(page, PdfThumbnailPageAction.insertBlankAfter),
      ),
      DsMenuItem(
        label: 'Duplicate Page',
        icon: Icons.control_point_duplicate,
        onTap: () => act(page, PdfThumbnailPageAction.duplicate),
      ),
      DsMenuItem(
        label: 'Extract Page…',
        icon: Icons.content_cut,
        onTap: () => act(page, PdfThumbnailPageAction.extract),
      ),
      const DsMenuDivider(),
      DsMenuItem(
        label: 'Delete Page',
        icon: Icons.delete_outline,
        destructive: true,
        onTap: () => act(page, PdfThumbnailPageAction.delete),
      ),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark ? DsColors.borderDark : DsColors.borderLight;
    final selectedFill = theme.colorScheme.primary.withValues(alpha: 0.12);

    final document = _document;
    final pageCount = _pageCount;
    if (document == null || pageCount == null || pageCount == 0) {
      return _sidebarChrome(
        isDark: isDark,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final tileRadius = BorderRadius.circular(PdfThumbnailSidebar._tileRadius);

    final approach = PdfViewerRenderPace.lookup(widget.controller);
    return _sidebarChrome(
      isDark: isDark,
      child: ListenableBuilder(
        listenable: approach == null
            ? widget.controller
            : Listenable.merge([widget.controller, approach]),
        builder: (context, _) {
          if (!widget.controller.isReady) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          final activePage = widget.controller.pageNumber ?? 1;
          _paintedPage = activePage;
          final horizontal = widget.scrollAxis == Axis.horizontal;
          return ListView.builder(
            key: Key(
              horizontal
                  ? 'pdf_mobile_thumbnail_strip'
                  : 'pdf_thumbnail_sidebar',
            ),
            controller: _thumbs,
            scrollCacheExtent: const ScrollCacheExtent.pixels(64),
            scrollDirection: widget.scrollAxis,
            padding: const EdgeInsets.symmetric(
              vertical: PdfThumbnailSidebar._listPaddingVertical,
              horizontal: PdfThumbnailSidebar._listPaddingHorizontal,
            ),
            itemCount: pageCount,
            itemBuilder: (context, index) {
              final pageNumber = index + 1;
              final selected = pageNumber == activePage;
              final tile = InkWell(
                onTap: () => widget.onPageSelected(pageNumber),
                onSecondaryTapUp: widget.onPageAction == null
                    ? null
                    : (d) => _showPageMenu(pageNumber, d.globalPosition),
                borderRadius: tileRadius,
                child: DecoratedBox(
                  key: selected ? _activeTileKey : null,
                  decoration: BoxDecoration(
                    color: selected ? selectedFill : null,
                    border: Border.all(
                      color: selected
                          ? theme.colorScheme.primary
                          : borderColor,
                      width: selected ? 2 : 1,
                    ),
                    borderRadius: tileRadius,
                  ),
                  child: Stack(
                    fit: StackFit.passthrough,
                    children: [
                      AspectRatio(
                        aspectRatio: 3 / 4,
                        child: PdfViewerThumbCell(
                          key: ValueKey('pdf-thumb-$pageNumber'),
                          document: document,
                          pageNumber: pageNumber,
                          gate: _thumbGate,
                          approach: approach,
                        ),
                      ),
                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: selected
                                ? theme.colorScheme.primary
                                : Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            child: Text(
                              '$pageNumber',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white,
                                fontSize: 10,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
              final padded = Padding(
                padding: horizontal
                    ? const EdgeInsets.only(
                        right: PdfThumbnailSidebar._tileGap,
                      )
                    : const EdgeInsets.only(
                        bottom: PdfThumbnailSidebar._tileGap,
                      ),
                child: horizontal
                    ? SizedBox(
                        height: kPdfViewerMobileThumbnailStripHeight - 24,
                        child: tile,
                      )
                    : tile,
              );
              return _wrapReorderable(index: index, tile: padded);
            },
          );
        },
      ),
    );
  }
}
