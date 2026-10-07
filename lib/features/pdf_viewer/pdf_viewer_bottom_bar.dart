import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_acrobat_page_field.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_scroll_layout.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_zoom_controls.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Acrobat-style bottom bar: page navigation, zoom and reading view.
///
/// Replaces the title row that used to repeat the file name above the page
/// (the tab already shows it).
final ValueNotifier<int> _idle = ValueNotifier<int>(0);

class PdfViewerBottomBar extends StatelessWidget {
  const PdfViewerBottomBar({
    super.key,
    required this.controller,
    required this.scrollMode,
    required this.onScrollModeChanged,
    required this.onGoToPage,
    required this.onFind,
    required this.onFitPage,
    required this.onFitWidth,
    required this.onReadMode,
    required this.onPresentation,
    this.vertical = false,
  });

  /// Rail layout: the same controls stacked for the left icon rail.
  final bool vertical;

  static const height = 36.0;

  final PdfViewerController? controller;
  final PdfViewerScrollLayoutMode scrollMode;
  final ValueChanged<PdfViewerScrollLayoutMode> onScrollModeChanged;
  final VoidCallback onGoToPage;
  final VoidCallback onFind;
  final VoidCallback onFitPage;
  final VoidCallback onFitWidth;
  final VoidCallback onReadMode;
  final VoidCallback onPresentation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final c = controller;
    Widget icon(
      IconData i,
      String tip,
      VoidCallback? onTap, {
      bool on = false,
    }) {
      return IconButton(
        tooltip: tip,
        onPressed: onTap,
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          minimumSize: const Size(30, 30),
          foregroundColor: on ? DsColors.primary : null,
          backgroundColor: on ? DsColors.primary.withValues(alpha: 0.12) : null,
        ),
        icon: Icon(i),
      );
    }

    if (vertical) return _rail(context, icon);
    return Material(
      color: dark
          ? DsColors.surfaceContainerDark
          : DsColors.surfaceContainerLight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: DsColors.border(theme.brightness)),
          ),
        ),
        child: SizedBox(
          height: height,
          child: ListenableBuilder(
            listenable: c ?? _idle,
            builder: (context, _) {
              final ready = c != null && c.isReady;
              final page = ready ? (c.pageNumber ?? 1) : 1;
              final total = ready ? c.pageCount : 1;
              final zoom = ready ? (c.currentZoom * 100).round() : 100;
              return ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  Center(
                    child: icon(
                      Icons.keyboard_arrow_up,
                      'Previous page',
                      ready && page > 1
                          ? () => c.goToPage(pageNumber: page - 1)
                          : null,
                    ),
                  ),
                  Center(
                    child: PdfViewerAcrobatPageField(
                      controller: c,
                      onGoToPage: onGoToPage,
                      fieldHeight: 26,
                    ),
                  ),
                  Center(
                    child: icon(
                      Icons.keyboard_arrow_down,
                      'Next page',
                      ready && page < total
                          ? () => c.goToPage(pageNumber: page + 1)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Center(
                    child: icon(
                      Icons.remove,
                      'Zoom out',
                      ready ? () => pdfViewerZoomOut(c) : null,
                    ),
                  ),
                  Center(
                    child: MenuAnchor(
                      menuChildren: [
                        for (final z in const [50, 75, 100, 125, 150, 200, 300])
                          MenuItemButton(
                            onPressed: ready
                                ? () => c.setZoom(
                                    c.centerPosition,
                                    z / 100,
                                    duration: Duration.zero,
                                  )
                                : null,
                            child: Text('$z%'),
                          ),
                        const Divider(height: 8),
                        MenuItemButton(
                          onPressed: ready ? onFitPage : null,
                          child: const Text('Fit page'),
                        ),
                        MenuItemButton(
                          onPressed: ready ? onFitWidth : null,
                          child: const Text('Fit width'),
                        ),
                      ],
                      builder: (context, menu, _) => TextButton(
                        onPressed: ready
                            ? () => menu.isOpen ? menu.close() : menu.open()
                            : null,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(60, 28),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: Text(
                          '$zoom% ▾',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: icon(
                      Icons.add,
                      'Zoom in',
                      ready ? () => pdfViewerZoomIn(c) : null,
                    ),
                  ),
                  Center(
                    child: icon(
                      Icons.fit_screen_outlined,
                      'Fit page',
                      ready ? onFitPage : null,
                    ),
                  ),
                  Center(
                    child: icon(
                      Icons.width_normal_outlined,
                      'Fit width',
                      ready ? onFitWidth : null,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Center(
                    child: MenuAnchor(
                      menuChildren: [
                        _view(
                          PdfViewerScrollLayoutMode.continuous,
                          'Continuous scrolling',
                          Icons.view_day_outlined,
                        ),
                        _view(
                          PdfViewerScrollLayoutMode.singlePage,
                          'Single page view',
                          Icons.crop_portrait,
                        ),
                        _view(
                          PdfViewerScrollLayoutMode.twoPage,
                          'Two-page view',
                          Icons.menu_book_outlined,
                        ),
                        const Divider(height: 8),
                        MenuItemButton(
                          leadingIcon: const Icon(
                            Icons.chrome_reader_mode_outlined,
                            size: 18,
                          ),
                          onPressed: onReadMode,
                          child: const Text('Reading mode'),
                        ),
                        MenuItemButton(
                          leadingIcon: const Icon(Icons.slideshow, size: 18),
                          onPressed: onPresentation,
                          child: const Text('Full screen'),
                        ),
                      ],
                      builder: (context, menu, _) => Tooltip(
                        message: 'Page display / reading view',
                        child: TextButton.icon(
                          onPressed: () =>
                              menu.isOpen ? menu.close() : menu.open(),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(40, 28),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          icon: const Icon(
                            Icons.auto_stories_outlined,
                            size: 18,
                          ),
                          label: Text(
                            scrollMode.statusLabel,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Center(child: icon(Icons.search, 'Find (Ctrl+F)', onFind)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Page / zoom / view controls stacked vertically (left rail).
  Widget _rail(
    BuildContext context,
    Widget Function(IconData, String, VoidCallback?, {bool on}) icon,
  ) {
    final c = controller;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: c ?? _idle,
      builder: (context, _) {
        final ready = c != null && c.isReady;
        final page = ready ? (c.pageNumber ?? 1) : 1;
        final total = ready ? c.pageCount : 1;
        final zoom = ready ? (c.currentZoom * 100).round() : 100;
        final small = theme.textTheme.labelSmall?.copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon(
              Icons.keyboard_arrow_up,
              'Previous page',
              ready && page > 1 ? () => c.goToPage(pageNumber: page - 1) : null,
            ),
            Tooltip(
              message: 'Go to page (Ctrl+G)',
              child: InkWell(
                onTap: ready ? onGoToPage : null,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 3,
                    horizontal: 2,
                  ),
                  child: Column(
                    children: [
                      Text('$page', style: small?.copyWith(fontSize: 12)),
                      Text(
                        '/ $total',
                        style: small?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            icon(
              Icons.keyboard_arrow_down,
              'Next page',
              ready && page < total
                  ? () => c.goToPage(pageNumber: page + 1)
                  : null,
            ),
            const Divider(height: 10, indent: 8, endIndent: 8),
            icon(Icons.add, 'Zoom in', ready ? () => pdfViewerZoomIn(c) : null),
            MenuAnchor(
              menuChildren: [
                for (final z in const [50, 75, 100, 125, 150, 200, 300])
                  MenuItemButton(
                    onPressed: ready
                        ? () => c.setZoom(
                            c.centerPosition,
                            z / 100,
                            duration: Duration.zero,
                          )
                        : null,
                    child: Text('$z%'),
                  ),
                const Divider(height: 8),
                MenuItemButton(
                  onPressed: ready ? onFitPage : null,
                  child: const Text('Fit page'),
                ),
                MenuItemButton(
                  onPressed: ready ? onFitWidth : null,
                  child: const Text('Fit width'),
                ),
              ],
              builder: (context, menu, _) => Tooltip(
                message: 'Zoom',
                child: InkWell(
                  onTap: ready
                      ? () => menu.isOpen ? menu.close() : menu.open()
                      : null,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '$zoom%',
                      style: small?.copyWith(color: DsColors.primary),
                    ),
                  ),
                ),
              ),
            ),
            icon(
              Icons.remove,
              'Zoom out',
              ready ? () => pdfViewerZoomOut(c) : null,
            ),
            icon(
              Icons.fit_screen_outlined,
              'Fit page',
              ready ? onFitPage : null,
            ),
            icon(
              Icons.width_normal_outlined,
              'Fit width',
              ready ? onFitWidth : null,
            ),
            const Divider(height: 10, indent: 8, endIndent: 8),
            MenuAnchor(
              menuChildren: [
                _view(
                  PdfViewerScrollLayoutMode.continuous,
                  'Continuous scrolling',
                  Icons.view_day_outlined,
                ),
                _view(
                  PdfViewerScrollLayoutMode.singlePage,
                  'Single page view',
                  Icons.crop_portrait,
                ),
                _view(
                  PdfViewerScrollLayoutMode.twoPage,
                  'Two-page view',
                  Icons.menu_book_outlined,
                ),
                const Divider(height: 8),
                MenuItemButton(
                  leadingIcon: const Icon(
                    Icons.chrome_reader_mode_outlined,
                    size: 18,
                  ),
                  onPressed: onReadMode,
                  child: const Text('Reading mode'),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.slideshow, size: 18),
                  onPressed: onPresentation,
                  child: const Text('Full screen'),
                ),
              ],
              builder: (context, menu, _) => icon(
                Icons.auto_stories_outlined,
                'Page display: ${scrollMode.statusLabel}',
                () => menu.isOpen ? menu.close() : menu.open(),
              ),
            ),
            icon(Icons.search, 'Find (Ctrl+F)', onFind),
          ],
        );
      },
    );
  }

  Widget _view(PdfViewerScrollLayoutMode m, String label, IconData i) =>
      MenuItemButton(
        leadingIcon: Icon(i, size: 18),
        trailingIcon: scrollMode == m
            ? const Icon(Icons.check, size: 16)
            : null,
        onPressed: () => onScrollModeChanged(m),
        child: Text(label),
      );
}
