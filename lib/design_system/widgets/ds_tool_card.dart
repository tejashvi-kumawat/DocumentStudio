import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/widgets/ds_hover_lift.dart';
import 'package:flutter/material.dart';

enum DsToolCardStatus { available, comingSoon, blocked }

class DsToolCard extends StatelessWidget {
  const DsToolCard({
    super.key,
    required this.icon,
    required this.label,
    required this.description,
    required this.status,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final DsToolCardStatus status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final disabled = status != DsToolCardStatus.available;
    final secondary = DsColors.textSecondary(theme.brightness);
    final primary = theme.colorScheme.primary;
    final radius = BorderRadius.circular(DsSpacing.radiusCard);

    final card = Material(
      color: isDark ? DsColors.groupedCellDark : DsColors.groupedCellLight,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: isDark ? DsColors.borderDark : DsColors.borderLight,
          width: isDark ? 1 : 0.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(DsSpacing.md),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Same pattern as Home suggested tiles: icon + title + subtitle
            // inside SizedBox.expand. Keep text from overflowing short cells.
            final tight = constraints.maxHeight < 72;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: isDark ? 0.18 : 0.08),
                    borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
                  ),
                  child: SizedBox(
                    width: tight
                        ? DsSpacing.iconWellSizeCompact
                        : DsSpacing.iconWellSize,
                    height: tight
                        ? DsSpacing.iconWellSizeCompact
                        : DsSpacing.iconWellSize,
                    child: Icon(
                      icon,
                      color: disabled ? secondary : primary,
                      size: tight ? 16 : 20,
                    ),
                  ),
                ),
                if (tight)
                  const SizedBox(height: DsSpacing.xs)
                else
                  const Spacer(),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                    color: disabled ? secondary : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    height: 1.15,
                    color: secondary,
                  ),
                ),
                if (status == DsToolCardStatus.blocked && !tight) ...[
                  const SizedBox(height: DsSpacing.sm),
                  Text(
                    'Not available on this device',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secondary,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );

    return DsHoverLift(
      enabled: !disabled && onTap != null,
      borderRadius: radius,
      onTap: disabled ? null : onTap,
      child: SizedBox.expand(child: card),
    );
  }
}
