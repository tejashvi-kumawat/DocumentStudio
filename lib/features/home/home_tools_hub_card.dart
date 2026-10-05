import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/features/home/home_tool.dart';
import 'package:flutter/material.dart';

/// Compact tool tile for the Tools hub: tinted icon, name, one-line summary.
/// The whole tile opens the tool (no extra Open button).
class HomeToolsHubCard extends StatefulWidget {
  const HomeToolsHubCard({
    super.key,
    required this.tool,
    this.actionLabel = 'Open',
    this.compact = false,
  });

  final HomeTool tool;
  final String actionLabel;
  final bool compact;

  /// Fixed tile height so grids stay tidy at any width.
  static const height = 64.0;

  @override
  State<HomeToolsHubCard> createState() => _HomeToolsHubCardState();
}

class _HomeToolsHubCardState extends State<HomeToolsHubCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tool = widget.tool;
    final dark = theme.brightness == Brightness.dark;
    final secondary = DsColors.textSecondary(theme.brightness);
    final enabled = tool.availability == HomeToolAvailability.available;
    final accent = enabled ? DsColors.primary : secondary;
    final badge = switch (tool.availability) {
      HomeToolAvailability.available => null,
      HomeToolAvailability.blocked => 'Unavailable',
      HomeToolAvailability.comingSoon => 'Soon',
    };
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: Material(
        color: dark ? DsColors.groupedCellDark : DsColors.groupedCellLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: _hover && enabled
                ? DsColors.primary.withValues(alpha: 0.55)
                : DsColors.border(theme.brightness),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? tool.onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: dark ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(tool.icon, size: 20, color: accent),
                ),
                const SizedBox(width: 12),
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
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: enabled ? null : secondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tool.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11.5,
                          color: secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (badge != null)
                  Text(
                    badge,
                    style: theme.textTheme.labelSmall?.copyWith(color: secondary),
                  )
                else
                  Icon(Icons.chevron_right, size: 18, color: secondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
