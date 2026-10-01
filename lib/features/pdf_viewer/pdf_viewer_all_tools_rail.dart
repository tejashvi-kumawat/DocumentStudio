import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_acrobat_tool_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_acrobat_tool_catalog.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Right **All tools** panel (Acrobat-style list + search).
class PdfViewerAllToolsRail extends ConsumerStatefulWidget {
  const PdfViewerAllToolsRail({
    super.key,
    required this.handoff,
    this.selectedBlockedToolId,
    this.onSelectedBlockedToolIdChanged,
    this.onClose,
    this.onToolInvoked,
  });

  final PdfViewerDocumentHandoff handoff;
  final String? selectedBlockedToolId;
  final ValueChanged<String?>? onSelectedBlockedToolIdChanged;
  final VoidCallback? onClose;

  /// Called after a working tool starts. Phone sheet uses this to dismiss.
  final VoidCallback? onToolInvoked;

  @visibleForTesting
  static const railWidth = 300.0;

  @override
  ConsumerState<PdfViewerAllToolsRail> createState() =>
      _PdfViewerAllToolsRailState();
}

class _PdfViewerAllToolsRailState extends ConsumerState<PdfViewerAllToolsRail> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark ? DsColors.borderDark : DsColors.borderLight;
    final tools = buildPdfViewerAcrobatToolCatalog(ref);
    final filtered = _filterTools(tools, _query);
    final groups = _railSections(filtered);
    PdfViewerAcrobatToolDefinition? blockedSelection;
    final blockedId = widget.selectedBlockedToolId;
    if (blockedId != null) {
      for (final t in tools) {
        if (t.id == blockedId) {
          blockedSelection = t;
          break;
        }
      }
    }

    return Material(
      color: isDark
          ? DsColors.surfaceContainerDark
          : DsColors.surfaceContainerLight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final railW = constraints.maxWidth.isFinite && constraints.maxWidth > 0
              ? constraints.maxWidth
              : PdfViewerAllToolsRail.railWidth;
          return SizedBox(
            width: railW,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(
                    DsSpacing.sm,
                    DsSpacing.sm,
                    DsSpacing.sm,
                    DsSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: borderColor)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Tools',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (widget.onClose != null)
                            IconButton(
                              key: const Key('acrobat_tools_rail_close'),
                              tooltip: 'Close tools',
                              icon: const Icon(Icons.close, size: 20),
                              onPressed: widget.onClose,
                            ),
                        ],
                      ),
                      TextField(
                        key: const Key('acrobat_tools_search_field'),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Search tools',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        onChanged: (v) => setState(() => _query = v.trim()),
                      ),
                    ],
                  ),
                ),
            if (blockedSelection != null &&
                blockedSelection.availability ==
                    PdfViewerAcrobatToolAvailability.blocked)
              _BlockedToolCard(
                tool: blockedSelection,
                handoff: widget.handoff,
                onDismiss: () =>
                    widget.onSelectedBlockedToolIdChanged?.call(null),
              ),
            Expanded(
              child: ListView(
                key: const Key('acrobat_tools_list'),
                scrollCacheExtent: const ScrollCacheExtent.pixels(2400),
                padding: const EdgeInsets.only(bottom: DsSpacing.lg),
                children: [
                  for (var i = 0; i < groups.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, thickness: 1, color: borderColor),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        DsSpacing.md,
                        10,
                        DsSpacing.md,
                        2,
                      ),
                      child: Text(
                        groups[i].title,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    ...groups[i].tools.map(
                      (tool) => _ToolTile(
                        tool: tool,
                        onTap: () => _onToolTap(tool),
                      ),
                    ),
                  ],
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(DsSpacing.lg),
                      child: Text(
                        'No tools match "$_query"',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<_RailSection> _railSections(List<PdfViewerAcrobatToolDefinition> tools) {
    return [
      for (final group in pdfViewerAcrobatToolGroupsInOrder(tools))
        _RailSection(
          title: pdfViewerAcrobatRailSectionTitle(group),
          tools: pdfViewerAcrobatToolsInGroup(tools, group),
        ),
    ];
  }

  List<PdfViewerAcrobatToolDefinition> _filterTools(
    List<PdfViewerAcrobatToolDefinition> tools,
    String query,
  ) {
    if (query.isEmpty) return tools;
    final q = query.toLowerCase();
    return tools
        .where(
          (t) =>
              t.label.toLowerCase().contains(q) ||
              t.subtitle.toLowerCase().contains(q) ||
              t.id.toLowerCase().contains(q),
        )
        .toList();
  }

  void _onToolTap(PdfViewerAcrobatToolDefinition tool) {
    widget.onSelectedBlockedToolIdChanged?.call(null);
    runPdfViewerAcrobatTool(
      context: context,
      handoff: widget.handoff,
      toolId: tool.id,
      availability: tool.availability,
    );
    if (tool.availability != PdfViewerAcrobatToolAvailability.blocked) {
      widget.onToolInvoked?.call();
    }
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.tool, required this.onTap});

  final PdfViewerAcrobatToolDefinition tool;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocked =
        tool.availability == PdfViewerAcrobatToolAvailability.blocked;
    final color = blocked
        ? theme.colorScheme.onSurface.withValues(alpha: 0.45)
        : theme.colorScheme.onSurface;
    final iconColor = blocked ? color : DsColors.primary;

    return InkWell(
      key: tool.handoffKey,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DsSpacing.md,
            vertical: 6,
          ),
          child: Row(
            children: [
              Icon(tool.icon, size: 20, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tool.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                    Text(
                      tool.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              if (blocked)
                Icon(
                  Icons.block,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailSection {
  const _RailSection({required this.title, required this.tools});

  final String title;
  final List<PdfViewerAcrobatToolDefinition> tools;
}

class _BlockedToolCard extends StatelessWidget {
  const _BlockedToolCard({
    required this.tool,
    required this.handoff,
    required this.onDismiss,
  });

  final PdfViewerAcrobatToolDefinition tool;
  final PdfViewerDocumentHandoff handoff;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(DsSpacing.sm),
      child: Card(
        key: Key('acrobat_blocked_${tool.id}'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(DsSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tool.label,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onDismiss,
                  ),
                ],
              ),
              Text(
                tool.blockedReason ?? 'This capability is not available yet.',
                style: theme.textTheme.bodySmall,
              ),
              if (tool.alternativeActionLabel != null) ...[
                const SizedBox(height: DsSpacing.sm),
                TextButton(
                  onPressed: () {
                    runPdfViewerAcrobatToolAlternative(
                      context: context,
                      handoff: handoff,
                      tool: tool,
                    );
                  },
                  child: Text(tool.alternativeActionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
