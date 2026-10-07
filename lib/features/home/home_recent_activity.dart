import 'package:document_studio/core/settings/app_prefs.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/design_system/widgets/ds_reveal.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/home/home_document_thumbnail.dart';
import 'package:document_studio/features/home/home_thumbnail_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Timeline of recent file changes, derived from recents + file metadata.
class HomeRecentActivity extends ConsumerStatefulWidget {
  const HomeRecentActivity({
    super.key,
    required this.recents,
    required this.onOpen,
    this.maxItems = 6,
  });

  final List<LocalFileRef> recents;
  final void Function(LocalFileRef file) onOpen;
  final int maxItems;

  @override
  ConsumerState<HomeRecentActivity> createState() => _HomeRecentActivityState();
}

typedef _Entry = ({LocalFileRef file, HomeThumbnail meta});

class _HomeRecentActivityState extends ConsumerState<HomeRecentActivity> {
  Future<List<_Entry>>? _future;
  List<String> _paths = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(HomeRecentActivity oldWidget) {
    super.didUpdateWidget(oldWidget);
    final paths = [for (final f in widget.recents) f.path];
    if (paths.join('\n') != _paths.join('\n')) _refresh();
  }

  void _refresh() {
    _paths = [for (final f in widget.recents) f.path];
    final cache = ref.read(homeThumbnailCacheProvider);
    final files = widget.recents.take(AppPrefs.recentCount).toList();
    _future = Future.wait([for (final f in files) cache.load(f)]).then((all) {
      final entries = <_Entry>[
        for (var i = 0; i < files.length; i++)
          if (all[i] case final meta?) (file: files[i], meta: meta),
      ]..sort((a, b) => b.meta.modified.compareTo(a.meta.modified));
      return entries.take(widget.maxItems).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = DsColors.border(theme.brightness);

    return Container(
      decoration: BoxDecoration(
        color: DsColors.groupedCell(theme.brightness),
        borderRadius: BorderRadius.circular(DsSpacing.radiusCard),
        border: Border.all(
          color: border,
          width: theme.brightness == Brightness.dark ? 1 : 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<List<_Entry>>(
        future: _future,
        builder: (context, snap) {
          final entries = snap.data;
          if (entries == null) {
            return const SizedBox(height: 120);
          }
          if (entries.isEmpty) {
            return const DsEmptyState(
              compact: true,
              icon: Icons.history_rounded,
              title: 'No activity yet',
              subtitle: 'Files you open and edit show up here.',
            );
          }
          return Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++)
                  DsStaggeredReveal(
                    index: i,
                    child: _ActivityRow(
                      entry: entries[i],
                      isLast: i == entries.length - 1,
                      onTap: () => widget.onOpen(entries[i].file),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.entry,
    required this.isLast,
    required this.onTap,
  });

  final _Entry entry;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);
    final meta = entry.meta;
    final fresh = DateTime.now().difference(meta.modified).inHours < 24;

    return InkWell(
      onTap: onTap,
      hoverColor: DsColors.primary.withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DsSpacing.md,
          vertical: DsSpacing.sm,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: DsMotion.hoverDuration,
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: fresh
                          ? DsColors.primary
                          : secondary.withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: DsSpacing.sm),
            SizedBox(
              width: 28,
              height: 36,
              child: Center(
                child: HomePagePreview(
                  file: entry.file,
                  thumbnail: meta,
                  iconSize: 14,
                  radius: 2,
                ),
              ),
            ),
            const SizedBox(width: DsSpacing.sm + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.file.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    [
                      'Modified ${homeRelativeTime(meta.modified).toLowerCase()}',
                      homeFileSize(meta.sizeBytes),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: secondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: secondary),
          ],
        ),
      ),
    );
  }
}
