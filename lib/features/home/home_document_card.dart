import 'package:document_studio/app/providers.dart';
import 'package:document_studio/design_system/adaptive/ds_adaptive.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/widgets/ds_hover_lift.dart';
import 'package:document_studio/design_system/widgets/ds_reveal.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/home/home_document_thumbnail.dart';
import 'package:document_studio/features/home/home_pdf_open_flow.dart';
import 'package:document_studio/features/home/home_pdf_open_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double kHomeCardWidth = 184;
const double kHomeCardHeight = 238;

/// Open / open-as / star / copy path actions shared by cards and list rows.
List<DsMenuAction> homeDocumentActions({
  required BuildContext context,
  required WidgetRef ref,
  required LocalFileRef file,
  required bool starred,
  required VoidCallback onOpen,
  required VoidCallback onToggleStar,
}) {
  return [
    DsMenuAction(
      label: 'Open',
      icon: Icons.open_in_new_rounded,
      onSelected: onOpen,
    ),
    if (file.isPdf)
      for (final mode in const [
        HomePdfOpenMode.editPages,
        HomePdfOpenMode.compress,
        HomePdfOpenMode.protect,
      ])
        DsMenuAction(
          label: mode.label,
          dividerBefore: mode == HomePdfOpenMode.editPages,
          icon: switch (mode) {
            HomePdfOpenMode.editPages => Icons.grid_view_rounded,
            HomePdfOpenMode.compress => Icons.compress_rounded,
            _ => Icons.lock_outline_rounded,
          },
          onSelected: () => homeOpenPdfWithMode(context, ref, file, mode),
        ),
    DsMenuAction(
      label: starred ? 'Remove from Pinned' : 'Pin to Home',
      icon: starred ? Icons.star_rounded : Icons.star_outline_rounded,
      dividerBefore: true,
      onSelected: onToggleStar,
    ),
    DsMenuAction(
      label: 'Copy file path',
      icon: Icons.link_rounded,
      onSelected: () => Clipboard.setData(ClipboardData(text: file.path)),
    ),
    DsMenuAction(
      label: 'Remove from Recents',
      icon: Icons.remove_circle_outline_rounded,
      dividerBefore: true,
      onSelected: () =>
          ref.read(recentsProvider.notifier).removeRecent(file.path),
    ),
  ];
}

/// Thumbnail card: first page preview, name, pages + modified time.
class HomeDocumentCard extends ConsumerStatefulWidget {
  const HomeDocumentCard({
    super.key,
    required this.file,
    required this.starred,
    required this.onOpen,
    required this.onToggleStar,
  });

  final LocalFileRef file;
  final bool starred;
  final VoidCallback onOpen;
  final VoidCallback onToggleStar;

  @override
  ConsumerState<HomeDocumentCard> createState() => _HomeDocumentCardState();
}

class _HomeDocumentCardState extends ConsumerState<HomeDocumentCard> {
  bool _hovered = false;

  void _showMenu(Offset position) {
    showDsContextMenu(
      context,
      globalPosition: position,
      title: widget.file.displayName,
      actions: homeDocumentActions(
        context: context,
        ref: ref,
        file: widget.file,
        starred: widget.starred,
        onOpen: widget.onOpen,
        onToggleStar: widget.onToggleStar,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = DsColors.textSecondary(theme.brightness);
    final border = DsColors.border(theme.brightness);
    final radius = BorderRadius.circular(DsSpacing.radiusCard);
    final showControls = _hovered || context.dsIsIOS;

    return Semantics(
      button: true,
      label: 'Open ${widget.file.displayName}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onLongPressStart: (d) => _showMenu(d.globalPosition),
          child: DsHoverLift(
            borderRadius: radius,
            onTap: widget.onOpen,
            onSecondaryTapUp: (d) => _showMenu(d.globalPosition),
            child: AnimatedContainer(
              duration: DsMotion.hoverDuration,
              curve: DsMotion.switchCurve,
              decoration: BoxDecoration(
                color: DsColors.groupedCell(theme.brightness),
                borderRadius: radius,
                border: Border.all(
                  color: _hovered
                      ? DsColors.primary.withValues(alpha: 0.35)
                      : border,
                  width: isDark ? 1 : 0.5,
                ),
              ),
              child: HomeThumbnailLoader(
                file: widget.file,
                builder: (context, thumb) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.black.withValues(alpha: 0.25)
                              : const Color(0xFFF1F2F4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  14,
                                  18,
                                  0,
                                ),
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: AnimatedScale(
                                    scale: _hovered ? 1.03 : 1,
                                    duration: DsMotion.hoverDuration,
                                    curve: DsMotion.switchCurve,
                                    alignment: Alignment.bottomCenter,
                                    child: HomePagePreview(
                                      file: widget.file,
                                      thumbnail: thumb,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: AnimatedOpacity(
                                opacity: widget.starred || showControls ? 1 : 0,
                                duration: DsMotion.hoverDuration,
                                child: _CardIconButton(
                                  tooltip: widget.starred
                                      ? 'Remove from Pinned'
                                      : 'Pin to Home',
                                  icon: widget.starred
                                      ? Icons.star_rounded
                                      : Icons.star_outline_rounded,
                                  color: widget.starred
                                      ? const Color(0xFFF5A623)
                                      : secondary,
                                  onPressed: widget.onToggleStar,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 2, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.file.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  thumb == null
                                      ? ' '
                                      : homeThumbnailMeta(thumb),
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
                          AnimatedOpacity(
                            opacity: showControls ? 1 : 0,
                            duration: DsMotion.hoverDuration,
                            child: Builder(
                              builder: (btnContext) => _CardIconButton(
                                tooltip: 'More',
                                icon: Icons.more_horiz_rounded,
                                color: secondary,
                                onPressed: () {
                                  final box =
                                      btnContext.findRenderObject()
                                          as RenderBox;
                                  _showMenu(
                                    box.localToGlobal(
                                      box.size.bottomLeft(Offset.zero),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardIconButton extends StatelessWidget {
  const _CardIconButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, color: color),
        onPressed: onPressed,
      ),
    );
  }
}

/// Responsive thumbnail grid with a staggered entrance.
class HomeDocumentGrid extends StatelessWidget {
  const HomeDocumentGrid({
    super.key,
    required this.files,
    required this.favoritePaths,
    required this.onOpen,
    required this.onToggleStar,
  });

  final List<LocalFileRef> files;
  final Set<String> favoritePaths;
  final void Function(LocalFileRef file) onOpen;
  final void Function(LocalFileRef file) onToggleStar;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(DsSpacing.md),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: kHomeCardWidth + 16,
        mainAxisExtent: kHomeCardHeight,
        crossAxisSpacing: DsSpacing.md,
        mainAxisSpacing: DsSpacing.md,
      ),
      itemCount: files.length,
      itemBuilder: (context, i) {
        final file = files[i];
        return DsStaggeredReveal(
          key: ValueKey(file.path),
          index: i,
          child: HomeDocumentCard(
            file: file,
            starred: favoritePaths.contains(file.path),
            onOpen: () => onOpen(file),
            onToggleStar: () => onToggleStar(file),
          ),
        );
      },
    );
  }
}

/// Horizontal strip of pinned (starred) documents.
class HomePinnedStrip extends StatelessWidget {
  const HomePinnedStrip({
    super.key,
    required this.files,
    required this.onOpen,
    required this.onToggleStar,
  });

  final List<LocalFileRef> files;
  final void Function(LocalFileRef file) onOpen;
  final void Function(LocalFileRef file) onToggleStar;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kHomeCardHeight + 8,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        itemCount: files.length,
        separatorBuilder: (_, _) => const SizedBox(width: DsSpacing.md),
        itemBuilder: (context, i) {
          final file = files[i];
          return SizedBox(
            width: kHomeCardWidth,
            child: DsStaggeredReveal(
              key: ValueKey(file.path),
              index: i,
              child: HomeDocumentCard(
                file: file,
                starred: true,
                onOpen: () => onOpen(file),
                onToggleStar: () => onToggleStar(file),
              ),
            ),
          );
        },
      ),
    );
  }
}
