import 'package:document_studio/app/providers.dart';
import 'package:document_studio/design_system/adaptive/ds_adaptive.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/home/home_document_card.dart';
import 'package:document_studio/features/home/home_document_list_tile.dart';
import 'package:document_studio/features/home/home_document_thumbnail.dart';
import 'package:document_studio/features/home/home_left_nav.dart';
import 'package:document_studio/features/home/home_pdf_open_flow.dart';
import 'package:document_studio/features/home/home_pdf_open_mode.dart';
import 'package:document_studio/features/home/home_recents_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef HomeDocumentOpenHandler = Future<void> Function(
  BuildContext context,
  WidgetRef ref,
  LocalFileRef file,
);

enum HomeDocumentsView { grid, list }

/// Recent / starred documents for Home as a thumbnail grid or dense list.
class HomeDocumentsPanel extends ConsumerStatefulWidget {
  const HomeDocumentsPanel({
    super.key,
    required this.section,
    required this.recents,
    required this.favorites,
    required this.favoritePaths,
    required this.query,
    required this.sort,
    required this.onSortChanged,
    required this.onOpenDocument,
    required this.onOpenPdf,
    required this.onToggleFavorite,
    required this.showPath,
    this.view = HomeDocumentsView.list,
    this.onViewChanged,
    this.gridLimit = 12,
  });

  final HomeSidebarSection section;
  final List<LocalFileRef> recents;
  final List<LocalFileRef> favorites;
  final Set<String> favoritePaths;
  final String query;
  final HomeRecentsSort sort;
  final ValueChanged<HomeRecentsSort> onSortChanged;
  final HomeDocumentOpenHandler onOpenDocument;
  final VoidCallback onOpenPdf;
  final void Function(LocalFileRef file) onToggleFavorite;
  final bool showPath;
  final HomeDocumentsView view;
  final ValueChanged<HomeDocumentsView>? onViewChanged;

  /// Grid shows this many cards until "Show all" is pressed.
  final int gridLimit;

  @override
  ConsumerState<HomeDocumentsPanel> createState() => _HomeDocumentsPanelState();
}

class _HomeDocumentsPanelState extends ConsumerState<HomeDocumentsPanel> {
  bool _showAll = false;

  HomeSidebarSection get section => widget.section;
  String get query => widget.query;
  HomeRecentsSort get sort => widget.sort;
  Set<String> get favoritePaths => widget.favoritePaths;

  List<LocalFileRef> get _sourceFiles {
    return switch (section) {
      HomeSidebarSection.starred => widget.favorites,
      HomeSidebarSection.recent ||
      HomeSidebarSection.yourDocuments => widget.recents,
    };
  }

  String get _title {
    return switch (section) {
      HomeSidebarSection.starred => 'Starred',
      HomeSidebarSection.yourDocuments => 'Your documents',
      HomeSidebarSection.recent => 'Recent',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;
    final source = _sourceFiles;
    final filtered = filterAndSortHomeDocuments(
      files: source,
      query: query,
      sort: sort,
    );
    final grid = widget.view == HomeDocumentsView.grid;
    final shown = grid && !_showAll && filtered.length > widget.gridLimit
        ? filtered.take(widget.gridLimit).toList()
        : filtered;

    return Material(
      color: isDark ? DsColors.groupedCellDark : DsColors.groupedCellLight,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DsSpacing.radiusCard),
        side: BorderSide(color: border, width: isDark ? 1 : 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DsSpacing.md,
              DsSpacing.sm,
              DsSpacing.xs,
              DsSpacing.sm,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 280;
                final muted = DsColors.textSecondary(theme.brightness);
                return SizedBox(
                  height: 32,
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                _title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (source.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(
                                '${filtered.length}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: muted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (widget.onViewChanged != null &&
                          source.isNotEmpty &&
                          !narrow)
                        DsAdaptiveSegmented<HomeDocumentsView>(
                          value: widget.view,
                          onChanged: widget.onViewChanged!,
                          segments: const {
                            HomeDocumentsView.grid: (
                              label: null,
                              icon: Icons.grid_view_rounded,
                              tooltip: 'Thumbnails',
                            ),
                            HomeDocumentsView.list: (
                              label: null,
                              icon: Icons.view_list_rounded,
                              tooltip: 'List',
                            ),
                          },
                        ),
                      if (widget.onViewChanged != null &&
                          source.isNotEmpty &&
                          narrow)
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: IconButton(
                            tooltip: widget.view == HomeDocumentsView.grid
                                ? 'Switch to list'
                                : 'Switch to thumbnails',
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(
                              width: 32,
                              height: 32,
                            ),
                            icon: Icon(
                              widget.view == HomeDocumentsView.grid
                                  ? Icons.view_list_rounded
                                  : Icons.grid_view_rounded,
                              size: 18,
                              color: muted,
                            ),
                            onPressed: () => widget.onViewChanged!(
                              widget.view == HomeDocumentsView.grid
                                  ? HomeDocumentsView.list
                                  : HomeDocumentsView.grid,
                            ),
                          ),
                        ),
                      if (section == HomeSidebarSection.recent &&
                          widget.recents.isNotEmpty)
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: IconButton(
                            tooltip: 'Clear Recents',
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(
                              width: 32,
                              height: 32,
                            ),
                            icon: Icon(
                              Icons.delete_sweep_outlined,
                              size: 18,
                              color: muted,
                            ),
                            onPressed: () => ref
                                .read(recentsProvider.notifier)
                                .clearRecents(),
                          ),
                        ),
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: PopupMenuButton<HomeRecentsSort>(
                          key: const Key('home_recents_sort'),
                          tooltip: 'Sort: ${sort.label}',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 32,
                            height: 32,
                          ),
                          initialValue: sort,
                          onSelected: widget.onSortChanged,
                          itemBuilder: (context) => [
                            for (final s in HomeRecentsSort.values)
                              PopupMenuItem(value: s, child: Text(s.label)),
                          ],
                          icon: Icon(
                            Icons.sort_rounded,
                            size: 18,
                            color: muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Divider(height: 1, color: border),
          if (source.isEmpty)
            Padding(
              padding: const EdgeInsets.all(DsSpacing.lg),
              child: DsEmptyState(
                key: const Key('home_recents_empty'),
                title: section == HomeSidebarSection.starred
                    ? 'No starred documents'
                    : 'No recent documents yet',
                subtitle: section == HomeSidebarSection.starred
                    ? 'Pin a document with its star to keep it here.'
                    : 'Open a PDF to get started.',
                action: section == HomeSidebarSection.starred
                    ? null
                    : DsPrimaryButton(
                        label: 'Open PDF',
                        icon: Icons.folder_open,
                        onPressed: widget.onOpenPdf,
                      ),
              ),
            )
          else if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(DsSpacing.lg),
              child: AnimatedSwitcher(
                duration: DsMotion.switchDuration,
                switchInCurve: DsMotion.switchCurve,
                child: Text(
                  key: const ValueKey('recents_no_match'),
                  'No documents match your search.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            )
          else if (grid) ...[
            HomeDocumentGrid(
              files: shown,
              favoritePaths: favoritePaths,
              onOpen: (file) => widget.onOpenDocument(context, ref, file),
              onToggleStar: widget.onToggleFavorite,
            ),
            if (shown.length < filtered.length || _showAll)
              Padding(
                padding: const EdgeInsets.only(bottom: DsSpacing.sm),
                child: Center(
                  child: TextButton(
                    onPressed: () => setState(() => _showAll = !_showAll),
                    child: Text(
                      _showAll ? 'Show less' : 'Show all ${filtered.length}',
                    ),
                  ),
                ),
              ),
          ] else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: filtered.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: border),
              itemBuilder: (context, i) {
                final file = filtered[i];
                final starred = favoritePaths.contains(file.path);
                final muted = DsColors.textSecondary(theme.brightness);
                return HomeDocumentListTile(
                  file: file,
                  showPath: widget.showPath,
                  leading: SizedBox(
                    width: 22,
                    height: 28,
                    child: HomeThumbnailLoader(
                      file: file,
                      builder: (context, thumb) => Center(
                        child: HomePagePreview(
                          file: file,
                          thumbnail: thumb,
                          iconSize: 12,
                          radius: 2,
                        ),
                      ),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 32,
                            height: 32,
                          ),
                          tooltip: starred
                              ? 'Remove from favorites'
                              : 'Add to favorites',
                          icon: Icon(
                            starred ? Icons.star : Icons.star_border,
                            size: 18,
                            color: starred ? theme.colorScheme.primary : muted,
                          ),
                          onPressed: () => widget.onToggleFavorite(file),
                        ),
                      ),
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: PopupMenuButton<HomePdfOpenMode>(
                          key: Key('home_recent_actions_${file.path}'),
                          tooltip: 'More open options',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 32,
                            height: 32,
                          ),
                          iconSize: 18,
                          icon: Icon(Icons.more_vert, size: 18, color: muted),
                          onSelected: (mode) =>
                              homeOpenPdfWithMode(context, ref, file, mode),
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: HomePdfOpenMode.editPages,
                              child: Text(HomePdfOpenMode.editPages.label),
                            ),
                            PopupMenuItem(
                              value: HomePdfOpenMode.compress,
                              child: Text(HomePdfOpenMode.compress.label),
                            ),
                            PopupMenuItem(
                              value: HomePdfOpenMode.protect,
                              child: Text(HomePdfOpenMode.protect.label),
                            ),
                          ],
                        ),
                      ),
                      if (section != HomeSidebarSection.starred)
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            tooltip: 'Remove from Recents',
                            icon: Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: muted,
                            ),
                            onPressed: () => ref
                                .read(recentsProvider.notifier)
                                .removeRecent(file.path),
                          ),
                        ),
                    ],
                  ),
                  onTap: () => widget.onOpenDocument(context, ref, file),
                );
              },
            ),
        ],
      ),
    );
  }
}
