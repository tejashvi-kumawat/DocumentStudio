import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/home/home_quick_tool_row.dart';
import 'package:document_studio/features/home/home_tool.dart';
import 'package:document_studio/features/home/home_tool_grid_layout.dart';
import 'package:flutter/material.dart';

/// Bordered tool launch area: single column list on phone, multi-column grid on desktop.
class HomeToolLaunchGrid extends StatelessWidget {
  const HomeToolLaunchGrid({
    super.key,
    required this.tools,
    required this.width,
  });

  final List<HomeTool> tools;
  final double width;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;
    final fill = isDark ? DsColors.groupedCellDark : DsColors.groupedCellLight;
    final columns = homeToolGridCrossAxisCount(width);
    final radius = BorderRadius.circular(DsSpacing.radiusCard);

    BoxDecoration gridDecoration() => BoxDecoration(
      color: fill,
      border: Border.all(color: border, width: isDark ? 1 : 0.5),
      borderRadius: radius,
      boxShadow: isDark ? null : DsSpacing.cardShadowLight(opacity: 0.05),
    );

    if (columns <= 1) {
      return _borderedList(
        decoration: gridDecoration(),
        border: border,
        tools: tools,
      );
    }

    final rows = <List<HomeTool>>[];
    for (var i = 0; i < tools.length; i += columns) {
      final end = (i + columns > tools.length) ? tools.length : i + columns;
      rows.add(tools.sublist(i, end));
    }

    return DecoratedBox(
      decoration: gridDecoration(),
      child: Column(
        children: [
          for (var r = 0; r < rows.length; r++) ...[
            if (r > 0) Divider(height: 1, color: border),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var c = 0; c < columns; c++) ...[
                    if (c > 0) VerticalDivider(width: 1, color: border),
                    Expanded(
                      child: c < rows[r].length
                          ? HomeQuickToolRow(tool: rows[r][c])
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _borderedList({
    required BoxDecoration decoration,
    required Color border,
    required List<HomeTool> tools,
  }) {
    return DecoratedBox(
      decoration: decoration,
      child: Column(
        children: [
          for (var i = 0; i < tools.length; i++) ...[
            if (i > 0) Divider(height: 1, color: border),
            HomeQuickToolRow(tool: tools[i]),
          ],
        ],
      ),
    );
  }
}
