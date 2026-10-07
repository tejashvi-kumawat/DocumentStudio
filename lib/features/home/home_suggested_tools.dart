import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/widgets/ds_hover_lift.dart';
import 'package:document_studio/features/conversion/conversion_route.dart';
import 'package:document_studio/features/home/home_edit_pages_launch.dart';
import 'package:document_studio/features/home/home_tool.dart';
import 'package:document_studio/features/home/home_tool_catalog.dart';
import 'package:document_studio/features/home/home_tool_route.dart';
import 'package:document_studio/features/ocr/ocr_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HomeSuggestedToolTile {
  const HomeSuggestedToolTile({
    required this.label,
    required this.description,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final String description;
  final IconData icon;
  final VoidCallback? onTap;
  final bool enabled;
}

List<HomeSuggestedToolTile> buildHomeSuggestedTools(
  BuildContext context,
  WidgetRef ref,
) {
  HomeTool? byId(String id) {
    try {
      return buildHomeToolCatalog(context, ref).firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  final compress = byId('compress');
  final protect = byId('protect');
  final export = byId('pdf_to_images');
  final ocr = byId('ocr_image');
  final create = byId('create_pdf');

  return [
    HomeSuggestedToolTile(
      label: 'Create PDF',
      description: create?.subtitle ?? 'From plain text',
      icon: Icons.note_add_outlined,
      onTap: () => pushHomeToolRoute(
        context,
        ref,
        createPdfRoutePath,
        documentEntry: HomeToolDocumentEntry.standalone,
      ),
    ),
    const HomeSuggestedToolTile(
      label: 'Edit pages',
      description: 'Reorder and organize',
      icon: Icons.dashboard_customize_outlined,
      onTap: null, // set below — needs context/ref
    ),
    HomeSuggestedToolTile(
      label: 'Compress',
      description: compress?.subtitle ?? 'Reduce file size',
      icon: compress?.icon ?? Icons.compress,
      enabled: compress?.availability == HomeToolAvailability.available,
      onTap: compress?.onTap,
    ),
    HomeSuggestedToolTile(
      label: 'Encrypt',
      description: protect?.subtitle ?? 'Encrypt with password',
      icon: protect?.icon ?? Icons.lock_outline,
      enabled: protect?.availability == HomeToolAvailability.available,
      onTap: protect?.onTap,
    ),
    HomeSuggestedToolTile(
      label: 'Export',
      description: export?.subtitle ?? 'Export pages as images',
      icon: export?.icon ?? Icons.image_outlined,
      enabled: export?.availability == HomeToolAvailability.available,
      onTap: export?.onTap,
    ),
    HomeSuggestedToolTile(
      label: 'OCR',
      description: ocr?.subtitle ?? 'Recognize text offline',
      icon: ocr?.icon ?? Icons.document_scanner_outlined,
      enabled: ocr?.availability == HomeToolAvailability.available,
      onTap:
          ocr?.onTap ??
          () => pushHomeToolRoute(
            context,
            ref,
            imageOcrRoutePath,
            documentEntry: HomeToolDocumentEntry.pickFile,
          ),
    ),
  ].map((tile) {
    if (tile.label == 'Edit pages') {
      return HomeSuggestedToolTile(
        label: tile.label,
        description: tile.description,
        icon: tile.icon,
        onTap: () => homeLaunchEditPages(context, ref),
      );
    }
    return tile;
  }).toList();
}

/// Equal-height tool cards for Home suggested tools.
class HomeSuggestedToolsRow extends StatelessWidget {
  const HomeSuggestedToolsRow({super.key, required this.tiles});

  final List<HomeSuggestedToolTile> tiles;

  static const _minTileWidth = 148.0;
  static const _maxColumns = 6;
  static const _cardMinHeight = 112.0;

  /// Compact cell: 8+8 padding leaves [mainAxisExtent]-16 for the tile Column.
  /// Was 72 → Column h=56 (overflow). 56px-safe content + this taller cell.
  static const _cardMinHeightCompact = 64.0;

  static int _columnsForWidth(double w) {
    if (w <= 0) return 2;
    if (w < DsSpacing.breakpointCompact) {
      // Phone: always 2 columns of dense chips, not blown-up desktop tiles.
      return 2;
    }
    if (w < DsSpacing.breakpointExpanded) return 3;
    final fit = (w / _minTileWidth).floor();
    return fit.clamp(3, _maxColumns);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final columns = _columnsForWidth(w);
        final compact = w < DsSpacing.breakpointCompact;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: DsSpacing.sm,
            crossAxisSpacing: DsSpacing.sm,
            mainAxisExtent: compact ? _cardMinHeightCompact : _cardMinHeight,
          ),
          itemCount: tiles.length,
          itemBuilder: (context, index) {
            return _SuggestedTile(tile: tiles[index], compact: compact);
          },
        );
      },
    );
  }
}

class _SuggestedTile extends StatelessWidget {
  const _SuggestedTile({required this.tile, this.compact = false});

  final HomeSuggestedToolTile tile;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;
    final secondary = DsColors.textSecondary(theme.brightness);
    final primary = theme.colorScheme.primary;
    final enabled = tile.enabled && tile.onTap != null;
    final radius = BorderRadius.circular(DsSpacing.radiusCard);

    final card = Material(
      color: isDark ? DsColors.groupedCellDark : DsColors.surfaceLight,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: border, width: isDark ? 1 : 0.5),
      ),
      child: Padding(
        // Compact: 6px so a 64px cell → Column maxH=52; content uses Row fit.
        padding: EdgeInsets.all(compact ? 6 : DsSpacing.md),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // SizedBox.expand / grid may pass h≈56 (or less). Never overflow.
            return _SuggestedTileBody(
              tile: tile,
              compact: compact,
              maxHeight: constraints.maxHeight,
              enabled: enabled,
              primary: primary,
              secondary: secondary,
              isDark: isDark,
              theme: theme,
            );
          },
        ),
      ),
    );

    return DsHoverLift(
      enabled: enabled,
      borderRadius: radius,
      onTap: enabled ? tile.onTap : null,
      child: SizedBox.expand(child: card),
    );
  }
}

/// Icon + title (+ optional subtitle) that always fits [maxHeight].
class _SuggestedTileBody extends StatelessWidget {
  const _SuggestedTileBody({
    required this.tile,
    required this.compact,
    required this.maxHeight,
    required this.enabled,
    required this.primary,
    required this.secondary,
    required this.isDark,
    required this.theme,
  });

  final HomeSuggestedToolTile tile;
  final bool compact;
  final double maxHeight;
  final bool enabled;
  final Color primary;
  final Color secondary;
  final bool isDark;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    // Tall cell (desktop): icon above, spacer, two text lines.
    if (!compact && maxHeight >= 88) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _iconWell(size: DsSpacing.iconWellSize, iconSize: 20),
          const Spacer(),
          Text(
            tile.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.15,
              color: enabled ? null : secondary,
            ),
          ),
          const SizedBox(height: DsSpacing.xs),
          Text(
            tile.description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              height: 1.15,
              color: secondary,
            ),
          ),
        ],
      );
    }

    // Tight height (phone / short grid cell): horizontal chip — fits h=56.
    final well = maxHeight < 40 ? 22.0 : 28.0;
    final showSubtitle = maxHeight >= 36;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _iconWell(size: well, iconSize: well * 0.55),
        const SizedBox(width: DsSpacing.sm),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tile.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                  color: enabled ? null : secondary,
                ),
              ),
              if (showSubtitle)
                Text(
                  tile.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    height: 1.1,
                    color: secondary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _iconWell({required double size, required double iconSize}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: primary.withValues(alpha: isDark ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(
          tile.icon,
          size: iconSize,
          color: enabled ? primary : secondary,
        ),
      ),
    );
  }
}
