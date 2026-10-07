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

  /// Accordion: one category open at a time, like Acrobat's All tools.
  String? _open;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark ? DsColors.borderDark : DsColors.borderLight;
    final tools = buildPdfViewerAcrobatToolCatalog(ref);
    final filtered = _filterTools(tools, _query);
    final entries = _query.isEmpty
        ? buildPdfViewerAcrobatRail(tools)
        : [for (final t in filtered) PdfViewerAcrobatRailEntry.tool(t)];
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
          final railW =
              constraints.maxWidth.isFinite && constraints.maxWidth > 0
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
                      for (final entry in entries)
                        if (entry.isGroup)
                          _SectionAccordion(
                            entry: entry,
                            expanded: _open == entry.title,
                            onToggle: () => setState(
                              () => _open = _open == entry.title
                                  ? null
                                  : entry.title,
                            ),
                            borderColor: borderColor,
                            onToolTap: _onToolTap,
                          )
                        else
                          _ToolTile(
                            tool: entry.tool!,
                            onTap: () => _onToolTap(entry.tool!),
                            indent: 14,
                            bold: true,
                          ),
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

class _SectionAccordion extends StatelessWidget {
  const _SectionAccordion({
    required this.entry,
    required this.expanded,
    required this.onToggle,
    required this.borderColor,
    required this.onToolTap,
  });

  final PdfViewerAcrobatRailEntry entry;
  final bool expanded;
  final VoidCallback onToggle;
  final Color borderColor;
  final void Function(PdfViewerAcrobatToolDefinition tool) onToolTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: Key('acrobat_tool_group_${entry.title}'),
          onTap: onToggle,
          child: SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: DsSpacing.md),
              child: Row(
                children: [
                  Icon(
                    entry.icon,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    '${entry.tools.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: expanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final tool in entry.tools)
                      _ToolTile(tool: tool, onTap: () => onToolTap(tool)),
                    const SizedBox(height: 4),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
        Divider(height: 1, thickness: 1, color: borderColor),
      ],
    );
  }
}

/// Compact tool row; the one-line description is the tooltip.
class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.tool,
    required this.onTap,
    this.indent = 44,
    this.bold = false,
  });

  final PdfViewerAcrobatToolDefinition tool;
  final VoidCallback onTap;
  final double indent;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocked =
        tool.availability == PdfViewerAcrobatToolAvailability.blocked;
    final color = blocked
        ? theme.colorScheme.onSurface.withValues(alpha: 0.45)
        : theme.colorScheme.onSurface;
    final iconColor = blocked ? color : DsColors.primary;

    return Tooltip(
      message: tool.subtitle,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        key: tool.handoffKey,
        onTap: onTap,
        child: SizedBox(
          height: bold ? 36 : 32,
          child: Padding(
            padding: EdgeInsets.only(left: indent, right: DsSpacing.md),
            child: Row(
              children: [
                Icon(tool.icon, size: bold ? 18 : 17, color: iconColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tool.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: color,
                      fontSize: bold ? 13 : 12.5,
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
                if (blocked)
                  Icon(
                    Icons.block,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
                    child: Text(tool.label, style: theme.textTheme.titleSmall),
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
