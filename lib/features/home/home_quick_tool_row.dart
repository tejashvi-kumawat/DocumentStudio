import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/home/home_tool.dart';
import 'package:flutter/material.dart';

/// Dense home tool row (Acrobat-style list density, not marketing cards).
class HomeQuickToolRow extends StatelessWidget {
  const HomeQuickToolRow({
    super.key,
    required this.tool,
  });

  final HomeTool tool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = isDark
        ? DsColors.textSecondaryDark
        : DsColors.textSecondaryLight;
    final enabled = tool.availability == HomeToolAvailability.available;
    final narrow =
        MediaQuery.sizeOf(context).width < DsSpacing.breakpointCompact;
    final vPad = narrow ? 6.0 : 8.0;
    final hPad = narrow ? 10.0 : 12.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? tool.onTap : tool.onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: narrow
                ? DsSpacing.compactTouchTarget
                : DsSpacing.controlHeightComfortable,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
            child: Row(
              children: [
                Icon(
                  tool.icon,
                  size: narrow ? 18 : 20,
                  color: enabled ? theme.colorScheme.primary : secondary,
                ),
                SizedBox(width: narrow ? 10 : 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tool.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontSize: narrow ? 13 : 14,
                          height: 1.2,
                          color: enabled ? null : secondary,
                        ),
                      ),
                      Text(
                        tool.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                          height: 1.2,
                          fontSize: narrow ? 11.5 : null,
                        ),
                      ),
                    ],
                  ),
                ),
                if (tool.availability == HomeToolAvailability.comingSoon)
                  Text(
                    'Soon',
                    style:
                        theme.textTheme.labelSmall?.copyWith(color: secondary),
                  )
                else if (tool.availability == HomeToolAvailability.blocked)
                  Text(
                    'N/A',
                    style:
                        theme.textTheme.labelSmall?.copyWith(color: secondary),
                  )
                else
                  Icon(Icons.chevron_right, size: 20, color: secondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
