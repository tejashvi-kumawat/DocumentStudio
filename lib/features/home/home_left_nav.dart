import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/widgets/ds_search_field.dart';
import 'package:flutter/material.dart';

enum HomeSidebarSection {
  recent('Recent'),
  starred('Starred'),
  yourDocuments('Your documents');

  const HomeSidebarSection(this.label);
  final String label;
}

/// In-page left column for Home (search + document sections).
class HomeLeftNav extends StatelessWidget {
  const HomeLeftNav({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.onSearchChanged,
  });

  final HomeSidebarSection selected;
  final ValueChanged<HomeSidebarSection> onSelected;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;
    final secondary = DsColors.textSecondary(theme.brightness);

    return SizedBox(
      width: 220,
      child: Padding(
        padding: const EdgeInsets.only(
          top: DsSpacing.lg,
          right: DsSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DsSearchField(
              fieldKey: const Key('home_recents_search'),
              hintText: 'Search',
              onChanged: onSearchChanged,
            ),
            const SizedBox(height: DsSpacing.lg),
            Text(
              'Documents',
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 11,
                letterSpacing: 0.3,
                fontWeight: FontWeight.w500,
                color: secondary,
              ),
            ),
            const SizedBox(height: DsSpacing.sm),
            _HomeNavRow(
              label: HomeSidebarSection.recent.label,
              selected: selected == HomeSidebarSection.recent,
              onTap: () => onSelected(HomeSidebarSection.recent),
            ),
            const SizedBox(height: DsSpacing.xs),
            _HomeNavRow(
              label: HomeSidebarSection.starred.label,
              selected: selected == HomeSidebarSection.starred,
              onTap: () => onSelected(HomeSidebarSection.starred),
            ),
            const SizedBox(height: DsSpacing.xs),
            _HomeNavRow(
              label: HomeSidebarSection.yourDocuments.label,
              selected: selected == HomeSidebarSection.yourDocuments,
              onTap: () => onSelected(HomeSidebarSection.yourDocuments),
            ),
            const SizedBox(height: DsSpacing.lg),
            Divider(height: 1, color: border),
          ],
        ),
      ),
    );
  }
}

class _HomeNavRow extends StatelessWidget {
  const _HomeNavRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = DsColors.primary;
    final fill = selected
        ? primary.withValues(alpha: isDark ? 0.18 : 0.10)
        : Colors.transparent;

    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
        hoverColor: primary.withValues(alpha: 0.06),
        child: AnimatedContainer(
          duration: DsMotion.hoverDuration,
          curve: DsMotion.switchCurve,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: DsSpacing.sm),
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected
                  ? primary
                  : (isDark
                      ? DsColors.textPrimaryDark
                      : DsColors.textPrimaryLight),
            ),
          ),
        ),
      ),
    );
  }
}
