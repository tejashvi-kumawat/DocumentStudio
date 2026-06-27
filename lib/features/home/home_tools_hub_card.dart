import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/home/home_tool.dart';
import 'package:flutter/material.dart';

/// Tool card with a primary Open action (Tools hub grid).
class HomeToolsHubCard extends StatelessWidget {
  const HomeToolsHubCard({
    super.key,
    required this.tool,
    this.actionLabel = 'Open',
    this.compact = false,
  });

  final HomeTool tool;
  final String actionLabel;

  /// Narrow phone density: smaller icon, tighter padding, 40–48dp action.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;
    final secondary = DsColors.textSecondary(theme.brightness);
    final enabled = tool.availability == HomeToolAvailability.available;
    final iconSize = compact ? 28.0 : 48.0;
    final pad = compact
        ? const EdgeInsets.fromLTRB(
            DsSpacing.sm,
            DsSpacing.md,
            DsSpacing.sm,
            DsSpacing.sm,
          )
        : const EdgeInsets.fromLTRB(
            DsSpacing.md,
            DsSpacing.lg,
            DsSpacing.md,
            DsSpacing.md,
          );

    return Material(
      color: isDark ? DsColors.groupedCellDark : DsColors.groupedCellLight,
      elevation: isDark ? 0 : 0.5,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DsSpacing.radiusCard),
        side: BorderSide(color: border, width: isDark ? 1 : 0.5),
      ),
      child: Padding(
        padding: pad,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Center(
                child: Icon(
                  tool.icon,
                  size: iconSize,
                  color: enabled ? theme.colorScheme.primary : secondary,
                ),
              ),
            ),
            Text(
              tool.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: compact
                  ? theme.textTheme.labelLarge?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    )
                  : theme.textTheme.titleSmall,
            ),
            if (!compact) ...[
              const SizedBox(height: DsSpacing.xs),
              Text(
                tool.subtitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: secondary),
              ),
            ],
            SizedBox(height: compact ? DsSpacing.sm : DsSpacing.md),
            OutlinedButton(
              onPressed: tool.onTap,
              style: OutlinedButton.styleFrom(
                minimumSize: Size.fromHeight(compact ? 40 : 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? DsSpacing.sm : DsSpacing.md,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      enabled
                          ? actionLabel
                          : tool.availability == HomeToolAvailability.blocked
                              ? 'Unavailable'
                              : 'Soon',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
