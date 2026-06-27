import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/organize/organize_page_ref.dart';
import 'package:flutter/material.dart';

/// Quiet horizontal source tabs for multi-document page workspaces.
class OrganizeDocumentSourceChips extends StatelessWidget {
  const OrganizeDocumentSourceChips({
    super.key,
    required this.sources,
    required this.pages,
    this.highlightSourcePath,
    required this.onSourceTap,
    this.onShowAll,
    this.enabled = true,
  });

  final List<LocalFileRef> sources;
  final List<OrganizePageRef> pages;
  final String? highlightSourcePath;
  final void Function(LocalFileRef source) onSourceTap;
  final VoidCallback? onShowAll;
  final bool enabled;

  int _pageCountFor(String path) =>
      pages.where((p) => p.file.path == path).length;

  @override
  Widget build(BuildContext context) {
    if (sources.length < 2) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;
    final secondary = DsColors.textSecondary(theme.brightness);
    final showAllSelected = highlightSourcePath == null;

    return Material(
      color: isDark
          ? DsColors.surfaceContainerDark
          : DsColors.groupedCellLight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: border)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: DsSpacing.md,
            vertical: DsSpacing.sm,
          ),
          child: Row(
            children: [
              _SourceTab(
                label: 'All (${pages.length})',
                selected: showAllSelected,
                enabled: enabled && onShowAll != null,
                onTap: onShowAll,
                secondary: secondary,
                border: border,
              ),
              const SizedBox(width: DsSpacing.sm),
              for (final source in sources) ...[
                _SourceTab(
                  label:
                      '${source.displayName} (${_pageCountFor(source.path)})',
                  selected: highlightSourcePath == source.path,
                  enabled: enabled,
                  onTap: () => onSourceTap(source),
                  secondary: secondary,
                  border: border,
                ),
                const SizedBox(width: DsSpacing.sm),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceTab extends StatelessWidget {
  const _SourceTab({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.secondary,
    required this.border,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;
  final Color secondary;
  final Color border;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: selected
          ? DsColors.primary.withValues(alpha: isDark ? 0.2 : 0.08)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
        side: BorderSide(
          color: selected ? DsColors.primary : border,
        ),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DsSpacing.sm,
            vertical: DsSpacing.xs,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected
                  ? DsColors.primary
                  : (enabled ? null : secondary),
            ),
          ),
        ),
      ),
    );
  }
}
