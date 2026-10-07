import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/features/page_management/organize_tool_catalog.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Compact list row for Organize hub (desktop-app density, not marketing cards).
class OrganizeCompactToolRow extends StatelessWidget {
  const OrganizeCompactToolRow({super.key, required this.tool});

  final OrganizeToolDefinition tool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = isDark
        ? DsColors.textSecondaryDark
        : DsColors.textSecondaryLight;
    final enabled = tool.availability == OrganizeToolAvailability.available;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled
            ? () => context.push(tool.routePath)
            : () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${tool.label} is not available yet.'),
                  ),
                );
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                tool.icon,
                size: 22,
                color: enabled ? theme.colorScheme.primary : secondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tool.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: enabled ? null : secondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tool.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              if (!enabled)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    'Soon',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secondary,
                    ),
                  ),
                )
              else
                Icon(Icons.chevron_right, color: secondary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
