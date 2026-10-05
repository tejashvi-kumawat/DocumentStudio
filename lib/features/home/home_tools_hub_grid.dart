import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/home/home_quick_tool_row.dart';
import 'package:document_studio/features/home/home_tool.dart';
import 'package:document_studio/features/home/home_tools_hub_card.dart';
import 'package:flutter/material.dart';

/// Primary Tools hub IDs shown as large cards when not searching.
const kToolsHubPrimaryIds = [
  'create_pdf',
  'organize',
  'pdf_to_images',
  'organize',
  'protect',
  'scan',
];

/// Distinct primary tools for the Tools hub hero grid.
const kToolsHubFeaturedIds = [
  'create_pdf',
  'organize',
  'pdf_to_images',
  'compress',
  'protect',
  'scan',
];

List<HomeTool> homeToolsHubFeatured(List<HomeTool> catalog) {
  final byId = {for (final t in catalog) t.id: t};
  return [
    for (final id in kToolsHubFeaturedIds)
      if (byId[id] != null) byId[id]!,
  ];
}

/// compact (&lt;600): 2 · medium (600–839): 3 · expanded: 3–4
int homeToolsHubCrossAxisCount(double width) {
  if (width >= 1100) return 4;
  if (width >= DsSpacing.breakpointCompact) return 3;
  return 2;
}

double homeToolsHubChildAspectRatio(double width) {
  final columns = homeToolsHubCrossAxisCount(width);
  if (columns >= 4) return 1.05;
  if (columns >= 3) return 1.35;
  // Compact: flatter tiles (not half-screen marketing cards).
  return 1.55;
}

class HomeToolsHubGrid extends StatelessWidget {
  const HomeToolsHubGrid({
    super.key,
    required this.tools,
    required this.width,
  });

  final List<HomeTool> tools;
  final double width;

  @override
  Widget build(BuildContext context) {
    final compact = width < DsSpacing.breakpointCompact;
    // Phone: dense list rows — never giant half-screen tiles.
    if (compact) {
      return _CompactToolsList(tools: tools);
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 340,
        mainAxisExtent: HomeToolsHubCard.height,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: tools.length,
      itemBuilder: (context, index) => HomeToolsHubCard(tool: tools[index]),
    );
  }
}

class _CompactToolsList extends StatelessWidget {
  const _CompactToolsList({required this.tools});

  final List<HomeTool> tools;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;
    final fill = isDark ? DsColors.groupedCellDark : DsColors.groupedCellLight;
    final radius = BorderRadius.circular(DsSpacing.radiusCard);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: border, width: isDark ? 1 : 0.5),
        borderRadius: radius,
        boxShadow: isDark ? null : DsSpacing.cardShadowLight(opacity: 0.05),
      ),
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
