import 'package:document_studio/design_system/ds_colors.dart';
import 'package:flutter/material.dart';

/// Contextual status for page-level tools (selection, review before export).
class OrganizeWorkflowStrip extends StatelessWidget {
  const OrganizeWorkflowStrip({
    super.key,
    required this.message,
    this.tone = OrganizeWorkflowTone.neutral,
    this.trailing,
  });

  final String message;
  final OrganizeWorkflowTone tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bg;
    final Color fg;
    switch (tone) {
      case OrganizeWorkflowTone.neutral:
        bg = isDark
            ? DsColors.surfaceContainerDark
            : DsColors.surfaceContainerLight;
        fg = isDark ? DsColors.textSecondaryDark : DsColors.textSecondaryLight;
      case OrganizeWorkflowTone.info:
        bg = theme.colorScheme.primaryContainer.withValues(alpha: 0.35);
        fg = theme.colorScheme.onPrimaryContainer;
      case OrganizeWorkflowTone.warning:
        bg = theme.colorScheme.errorContainer.withValues(alpha: 0.35);
        fg = theme.colorScheme.onErrorContainer;
    }

    return Material(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(color: fg),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

enum OrganizeWorkflowTone { neutral, info, warning }

/// Acrobat-style numbered steps for multi-phase organize tools.
class OrganizeToolStepStrip extends StatelessWidget {
  const OrganizeToolStepStrip({
    super.key,
    required this.steps,
    required this.activeIndex,
  });

  final List<String> steps;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;
    final secondary = isDark
        ? DsColors.textSecondaryDark
        : DsColors.textSecondaryLight;

    return Material(
      color: isDark
          ? DsColors.surfaceContainerDark
          : DsColors.surfaceContainerLight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: border)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < steps.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: secondary,
                      ),
                    ),
                  _StepChip(
                    index: i + 1,
                    label: steps[i],
                    active: i == activeIndex,
                    done: i < activeIndex,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.index,
    required this.label,
    required this.active,
    required this.done,
  });

  final int index;
  final String label;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;

    final Color bg;
    final Color fg;
    if (active) {
      bg = theme.colorScheme.primaryContainer.withValues(alpha: 0.55);
      fg = theme.colorScheme.onPrimaryContainer;
    } else if (done) {
      bg = isDark ? DsColors.surfaceDark : DsColors.surfaceLight;
      fg = theme.colorScheme.primary;
    } else {
      bg = isDark ? DsColors.surfaceDark : DsColors.surfaceLight;
      fg = isDark ? DsColors.textSecondaryDark : DsColors.textSecondaryLight;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: active ? theme.colorScheme.primary : border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$index',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: fg)),
        ],
      ),
    );
  }
}
