import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/shell/ds_toolbar.dart';
import 'package:document_studio/features/page_management/organize_tool_catalog.dart';
import 'package:document_studio/features/page_management/shared/organize_compact_tool_row.dart';
import 'package:document_studio/features/page_management/shared/organize_recent_row.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Compact professional tool hub — not oversized marketing cards.
class OrganizeHubScreen extends StatefulWidget {
  const OrganizeHubScreen({super.key});

  @override
  State<OrganizeHubScreen> createState() => _OrganizeHubScreenState();
}

class _OrganizeHubScreenState extends State<OrganizeHubScreen> {
  String _query = '';

  Iterable<OrganizeToolDefinition> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return OrganizeToolCatalog.tools;
    return OrganizeToolCatalog.tools.where(
      (t) =>
          t.label.toLowerCase().contains(q) ||
          t.description.toLowerCase().contains(q),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;
    final maxWidth = MediaQuery.sizeOf(context).width;
    final contentWidth = maxWidth > 960 ? 960.0 : maxWidth;
    final useTwoCol = maxWidth > 820;

    return Scaffold(
      appBar: DsToolbar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: 'Organize',
        subtitle: 'Manage, rearrange, and transform PDF pages',
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentWidth),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              OrganizeRecentPdfsSection(borderColor: border),
              TextField(
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search tools (⌘/Ctrl+K for commands)',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 16),
              if (useTwoCol)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          for (final group in [
                            OrganizeToolGroup.composition,
                            OrganizeToolGroup.extraction,
                          ])
                            _GroupBlock(
                              group: group,
                              borderColor: border,
                              tools: _filtered
                                  .where((t) => t.group == group)
                                  .toList(),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        children: [
                          for (final group in [
                            OrganizeToolGroup.arrangement,
                            OrganizeToolGroup.format,
                          ])
                            _GroupBlock(
                              group: group,
                              borderColor: border,
                              tools: _filtered
                                  .where((t) => t.group == group)
                                  .toList(),
                            ),
                        ],
                      ),
                    ),
                  ],
                )
              else
                for (final group in OrganizeToolGroup.values) ...[
                  _GroupBlock(
                    group: group,
                    borderColor: border,
                    tools: _filtered.where((t) => t.group == group).toList(),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupBlock extends StatelessWidget {
  const _GroupBlock({
    required this.group,
    required this.borderColor,
    required this.tools,
  });

  final OrganizeToolGroup group;
  final Color borderColor;
  final List<OrganizeToolDefinition> tools;

  @override
  Widget build(BuildContext context) {
    if (tools.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
          child: Text(
            OrganizeToolCatalog.groupTitle(group).toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              for (var i = 0; i < tools.length; i++) ...[
                if (i > 0) Divider(height: 1, color: borderColor),
                OrganizeCompactToolRow(tool: tools[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
