import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/domain/organize/organize_page_ref.dart';
import 'package:document_studio/features/page_management/widgets/organize_page_thumbnail.dart';
import 'package:flutter/material.dart';

/// One document-level action reachable from the workspace inspector.
class WorkspaceDocumentToolItem {
  const WorkspaceDocumentToolItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String id;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

/// Right-hand inspector (wide layouts) or full-width phone sheet/panel.
class WorkspaceInspectorPanel extends StatelessWidget {
  const WorkspaceInspectorPanel({
    super.key,
    required this.page,
    required this.selectionCount,
    required this.passwordsByPath,
    this.workspaceIndex1Based,
    this.workspacePageCount,
    this.workspacePages = const [],
    this.selectedPageIds = const {},
    this.documentTools = const [],
    this.showPagePreview = true,
    this.fullWidth = false,
    this.onClose,
  });

  final OrganizePageRef page;
  final int selectionCount;
  final Map<String, String> passwordsByPath;
  final int? workspaceIndex1Based;
  final int? workspacePageCount;
  final List<OrganizePageRef> workspacePages;
  final Set<String> selectedPageIds;
  final List<WorkspaceDocumentToolItem> documentTools;

  /// When false, this pane is tools and properties only. Workspace keeps a
  /// single thumbnail grid and does not decode a second preview.
  final bool showPagePreview;

  /// Phone: fill parent / bottom sheet (no fixed 260px column).
  final bool fullWidth;

  /// Optional close control for sheet / second-pane layouts.
  final VoidCallback? onClose;

  static const panelWidth = 260.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;
    final pad = fullWidth ? DsSpacing.pagePaddingCompact : DsSpacing.md;

    final showPreview = showPagePreview;
    final header = Padding(
      padding: EdgeInsets.fromLTRB(
        pad,
        DsSpacing.md,
        fullWidth ? DsSpacing.sm : pad,
        DsSpacing.inspectorSectionGap,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Preview',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 0.2,
                fontWeight: FontWeight.w600,
                color: DsColors.textSecondary(theme.brightness),
              ),
            ),
          ),
          if (onClose != null)
            IconButton(
              tooltip: 'Close',
              onPressed: onClose,
              icon: const Icon(Icons.close),
              iconSize: 22,
              constraints: const BoxConstraints(
                minWidth: DsSpacing.compactTouchTarget,
                minHeight: DsSpacing.compactTouchTarget,
              ),
            ),
        ],
      ),
    );

    final thumbnail = Padding(
      padding: EdgeInsets.symmetric(horizontal: fullWidth ? pad : 8),
      child: RepaintBoundary(
        child: OrganizeCachedPageThumbnail(
          key: ValueKey('inspector-${page.id}'),
          file: page.file,
          pageNumber1Based: page.pageNumber1Based,
          password: passwordsByPath[page.file.path],
          rotationDegrees: page.rotationDegrees,
          loadingSize: 24,
        ),
      ),
    );

    final toolsAndProps = <Widget>[
      if (documentTools.isNotEmpty) ...[
        Divider(height: 1, color: border),
        _DocumentToolsStrip(tools: documentTools, fullWidth: fullWidth),
      ],
      Divider(height: 1, color: border),
      _PropertiesStrip(
        page: page,
        selectionCount: selectionCount,
        workspaceIndex1Based: workspaceIndex1Based,
        workspacePageCount: workspacePageCount,
        workspacePages: workspacePages,
        selectedPageIds: selectedPageIds,
        fullWidth: fullWidth,
      ),
    ];

    final columnChildren = !showPreview
        ? <Widget>[...toolsAndProps]
        : fullWidth
        ? <Widget>[
            header,
            SizedBox(height: 200, child: thumbnail),
            ...toolsAndProps,
          ]
        : <Widget>[header, Expanded(child: thumbnail), ...toolsAndProps];

    final body = fullWidth
        ? SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: columnChildren,
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: columnChildren,
          );

    return Material(
      color: isDark
          ? DsColors.surfaceContainerDark
          : DsColors.surfaceContainerLight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: fullWidth ? null : Border(left: BorderSide(color: border)),
        ),
        child: fullWidth
            ? SafeArea(top: false, child: body)
            : SizedBox(width: panelWidth, child: body),
      ),
    );
  }
}

class _DocumentToolsStrip extends StatelessWidget {
  const _DocumentToolsStrip({required this.tools, this.fullWidth = false});

  final List<WorkspaceDocumentToolItem> tools;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);
    final pad = fullWidth ? DsSpacing.pagePaddingCompact : DsSpacing.md;
    final minH = fullWidth ? DsSpacing.controlHeightCompact : 0.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(pad, DsSpacing.sm, pad, DsSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Document tools',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.2,
              fontWeight: FontWeight.w600,
              color: secondary,
            ),
          ),
          const SizedBox(height: DsSpacing.xs),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final tool in tools)
                Tooltip(
                  message: '${tool.label} on selected document',
                  child: TextButton.icon(
                    key: Key('workspace_doc_tool_${tool.id}'),
                    onPressed: tool.onPressed,
                    icon: Icon(tool.icon, size: fullWidth ? 18 : 16),
                    label: Text(
                      tool.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall,
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: fullWidth
                          ? VisualDensity.standard
                          : VisualDensity.compact,
                      padding: EdgeInsets.symmetric(
                        horizontal: fullWidth ? 12 : 8,
                      ),
                      minimumSize: Size(0, minH),
                      tapTargetSize: fullWidth
                          ? MaterialTapTargetSize.padded
                          : MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PropertiesStrip extends StatelessWidget {
  const _PropertiesStrip({
    required this.page,
    required this.selectionCount,
    this.workspaceIndex1Based,
    this.workspacePageCount,
    this.workspacePages = const [],
    this.selectedPageIds = const {},
    this.fullWidth = false,
  });

  final OrganizePageRef page;
  final int selectionCount;
  final int? workspaceIndex1Based;
  final int? workspacePageCount;
  final List<OrganizePageRef> workspacePages;
  final Set<String> selectedPageIds;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);
    final pad = fullWidth ? DsSpacing.pagePaddingCompact : DsSpacing.md;

    return Padding(
      padding: EdgeInsets.fromLTRB(pad, DsSpacing.sm, pad, DsSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Page properties',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.2,
              fontWeight: FontWeight.w600,
              color: secondary,
            ),
          ),
          const SizedBox(height: DsSpacing.sm),
          _PropertyRow(label: 'Source', value: page.file.displayName),
          const SizedBox(height: 6),
          _PropertyRow(
            label: 'Original page',
            value: '${page.pageNumber1Based}',
          ),
          if (workspaceIndex1Based != null && workspacePageCount != null) ...[
            const SizedBox(height: 6),
            _PropertyRow(
              label: 'In workspace',
              value: '$workspaceIndex1Based of $workspacePageCount',
            ),
          ],
          if (page.rotationDegrees != 0) ...[
            const SizedBox(height: 6),
            _PropertyRow(label: 'Rotation', value: '${page.rotationDegrees}°'),
          ],
          const SizedBox(height: 6),
          _PropertyRow(
            label: 'Selected',
            value: selectionCount == 0
                ? 'None'
                : '$selectionCount page${selectionCount == 1 ? '' : 's'}',
          ),
          if (selectionCount > 1 && workspacePages.isNotEmpty) ...[
            const SizedBox(height: 6),
            _PropertyRow(
              label: 'Workspace',
              value: _workspaceSelectionSummary(
                workspacePages: workspacePages,
                selectedPageIds: selectedPageIds,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Export order uses workspace position; rotation applies on save.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: secondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

String _workspaceSelectionSummary({
  required List<OrganizePageRef> workspacePages,
  required Set<String> selectedPageIds,
}) {
  final indices = <int>[];
  for (var i = 0; i < workspacePages.length; i++) {
    if (selectedPageIds.contains(workspacePages[i].id)) {
      indices.add(i + 1);
    }
  }
  if (indices.isEmpty) return '—';
  if (indices.length <= 6) {
    return indices.join(', ');
  }
  return '${indices.first}–${indices.last} (${indices.length} pages)';
}

class _PropertyRow extends StatelessWidget {
  const _PropertyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: secondary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
