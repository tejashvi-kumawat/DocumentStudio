import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_shell_page.dart';
import 'package:document_studio/design_system/widgets/ds_search_field.dart';
import 'package:document_studio/features/home/home_shell_action_bar.dart';
import 'package:document_studio/features/home/home_tool.dart';
import 'package:document_studio/features/home/home_tool_catalog.dart';
import 'package:document_studio/features/home/home_tool_category_sections.dart';
import 'package:document_studio/features/home/home_tool_grid_layout.dart';
import 'package:document_studio/features/home/home_tools_hub_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Full tools catalog (Tools rail / tab destination).
class ToolsHubScreen extends ConsumerStatefulWidget {
  const ToolsHubScreen({super.key});

  @override
  ConsumerState<ToolsHubScreen> createState() => _ToolsHubScreenState();
}

class _ToolsHubScreenState extends ConsumerState<ToolsHubScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final contentInset = dsShellContentHorizontalPadding(width);
    final theme = Theme.of(context);
    final compact = width < DsSpacing.breakpointCompact;
    final allTools = buildHomeToolCatalog(context, ref);
    final filtered = allTools
        .where(
          (t) => homeToolMatchesQuery(
            label: t.label,
            subtitle: t.subtitle,
            query: _query,
          ),
        )
        .toList();
    final toolsByCategory = {
      for (final c in HomeToolCategory.values)
        c: homeToolsInCategory(filtered, c),
    };
    final searching = _query.trim().isNotEmpty;
    final featured = homeToolsHubFeatured(searching ? filtered : allTools);

    return ColoredBox(
      color: DsColors.groupedBackground(theme.brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HomeShellActionBar(),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    contentInset,
                    compact ? DsSpacing.md : DsSpacing.lg,
                    contentInset,
                    DsSpacing.sm,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: DsShellPageFrame(
                      padding: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const DsShellPageHeader(
                            title: 'Tools',
                            compactTitle: true,
                          ),
                          DsSearchField(
                            fieldKey: const Key('tools_hub_search'),
                            hintText: 'Search tools',
                            onChanged: (v) => setState(() => _query = v),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    contentInset,
                    compact ? DsSpacing.sm : DsSpacing.md,
                    contentInset,
                    DsSpacing.shellPageBottom,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: DsShellPageFrame(
                      padding: EdgeInsets.zero,
                      child: AnimatedSwitcher(
                        duration: DsMotion.switchDuration,
                        switchInCurve: DsMotion.switchCurve,
                        layoutBuilder: (current, _) =>
                            current ?? const SizedBox.shrink(),
                        child: filtered.isEmpty
                            ? Align(
                                key: const ValueKey('tools_hub_empty'),
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'No tools match your search.',
                                  style: theme.textTheme.bodySmall,
                                ),
                              )
                            : Column(
                                key: ValueKey('tools_hub_${filtered.length}'),
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (!searching)
                                    HomeToolsHubGrid(
                                      tools: featured,
                                      width: width,
                                    ),
                                  if (searching) ...[
                                    HomeToolsHubGrid(
                                      tools: filtered,
                                      width: width,
                                    ),
                                  ] else ...[
                                    const SizedBox(
                                      height: DsSpacing.shellSectionGap,
                                    ),
                                    HomeToolCategorySections(
                                      toolsByCategory: toolsByCategory,
                                      width: width,
                                    ),
                                  ],
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
