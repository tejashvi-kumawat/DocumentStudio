import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/home/home_tool.dart';
import 'package:document_studio/features/home/home_tool_launch_grid.dart';
import 'package:flutter/material.dart';

/// Category-grouped compact tool grids (Acrobat-style tools area).
class HomeToolCategorySections extends StatelessWidget {
  const HomeToolCategorySections({
    super.key,
    required this.toolsByCategory,
    required this.width,
  });

  final Map<HomeToolCategory, List<HomeTool>> toolsByCategory;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = isDark
        ? DsColors.textSecondaryDark
        : DsColors.textSecondaryLight;

    final visibleCategories = [
      for (final category in HomeToolCategory.values)
        if ((toolsByCategory[category] ?? const []).isNotEmpty) category,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < visibleCategories.length; i++) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(
              DsSpacing.xs,
              i == 0 ? DsSpacing.sm : DsSpacing.lg,
              DsSpacing.xs,
              DsSpacing.sm,
            ),
            child: Text(
              visibleCategories[i].title.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 0.6,
                fontWeight: FontWeight.w600,
                color: secondary,
              ),
            ),
          ),
          HomeToolLaunchGrid(
            tools: toolsByCategory[visibleCategories[i]]!,
            width: width,
          ),
        ],
      ],
    );
  }
}
