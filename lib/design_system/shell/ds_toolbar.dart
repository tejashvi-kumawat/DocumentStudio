import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:flutter/material.dart';

/// Default height for the document workspace toolbar (non-dense).
const double kDsToolbarHeight = 52;

/// Dense desktop toolbar height (icon row + group caption).
/// Room for dense icon row + Acrobat-style group caption without overflow.
const double kDsToolbarHeightDense = 60;

/// Acrobat-style icon toolbar row height (icons + File/Navigate group captions).
const double kDsToolbarHeightAcrobat = kDsToolbarHeightDense;

/// Document workspace top bar: title, actions, optional tab strip below.
///
/// Matches [docs/DESIGN-SYSTEM.md] — surface container, flat with bottom border,
/// Material Symbols Outlined at 24dp (20dp when [dense]).
class DsToolbar extends StatelessWidget implements PreferredSizeWidget {
  const DsToolbar({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    this.bottom,
    this.dense = false,
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;
  final bool dense;

  @override
  Size get preferredSize {
    var height = dense ? kDsToolbarHeightDense : kDsToolbarHeight;
    if (bottom != null) {
      height += bottom!.preferredSize.height;
    }
    return Size.fromHeight(height);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final background = isDark
        ? DsColors.surfaceContainerDark.withValues(alpha: 0.92)
        : DsColors.surfaceContainerLight.withValues(alpha: 0.94);
    final borderColor = isDark ? DsColors.borderDark : DsColors.borderLight;
    final barHeight = dense ? kDsToolbarHeightDense : kDsToolbarHeight;

    return Material(
      color: background,
      elevation: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: SizedBox(
              height: barHeight,
              child: NavigationToolbar(
                leading: leading,
                middle: _TitleBlock(
                  title: title,
                  subtitle: subtitle,
                  dense: dense,
                ),
                trailing: actions.isEmpty
                    ? null
                    : OverflowBar(
                        spacing: 0,
                        overflowSpacing: 0,
                        alignment: MainAxisAlignment.end,
                        children: actions,
                      ),
                centerMiddle: false,
              ),
            ),
          ),
          ?bottom,
        ],
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.title, this.subtitle, required this.dense});

  final String title;
  final String? subtitle;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = dense
        ? theme.textTheme.titleSmall
        : theme.textTheme.titleMedium;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: titleStyle,
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}

/// Icon-only control for [DsToolbar] with semantics and touch targets.
class DsToolbarIconButton extends StatelessWidget {
  const DsToolbarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.dense = false,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool dense;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconSize = dense ? 18.0 : 22.0;
    final minSide = dense ? 32.0 : 44.0;
    final isDark = theme.brightness == Brightness.dark;
    final selectedFill = theme.colorScheme.primary.withValues(alpha: 0.14);

    return Semantics(
      button: true,
      label: tooltip,
      selected: selected,
      child: Tooltip(
        message: tooltip,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: iconSize),
          iconSize: iconSize,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(minWidth: minSide, minHeight: minSide),
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            backgroundColor: selected ? selectedFill : null,
            foregroundColor: selected
                ? theme.colorScheme.primary
                : (isDark
                      ? DsColors.textPrimaryDark
                      : DsColors.textPrimaryLight),
          ),
        ),
      ),
    );
  }
}

/// macOS-style segmented control for compact toolbar clusters (zoom / layout).
class DsToolbarSegmentedControl<T extends Object> extends StatelessWidget {
  const DsToolbarSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
    this.dense = true,
  });

  final List<DsToolbarSegment<T>> segments;
  final T selected;
  final ValueChanged<T>? onSelected;
  final bool enabled;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final track = isDark
        ? DsColors.borderDark.withValues(alpha: 0.55)
        : DsColors.borderLight.withValues(alpha: 0.9);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < segments.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              _SegmentButton<T>(
                segment: segments[i],
                selected: segments[i].value == selected,
                enabled: enabled && onSelected != null,
                dense: dense,
                onTap: onSelected == null
                    ? null
                    : () => onSelected!(segments[i].value),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class DsToolbarSegment<T extends Object> {
  const DsToolbarSegment({
    required this.value,
    required this.icon,
    required this.tooltip,
    this.key,
  });

  final T value;
  final IconData icon;
  final String tooltip;
  final Key? key;
}

class _SegmentButton<T extends Object> extends StatelessWidget {
  const _SegmentButton({
    required this.segment,
    required this.selected,
    required this.enabled,
    required this.dense,
    required this.onTap,
  });

  final DsToolbarSegment<T> segment;
  final bool selected;
  final bool enabled;
  final bool dense;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final iconSize = dense ? 16.0 : 18.0;
    final fill = selected
        ? (isDark ? DsColors.surfaceContainerDark : DsColors.surfaceLight)
        : Colors.transparent;
    final fg = selected
        ? theme.colorScheme.primary
        : DsColors.textSecondary(theme.brightness);

    return Semantics(
      button: true,
      label: segment.tooltip,
      selected: selected,
      child: Tooltip(
        message: segment.tooltip,
        child: Material(
          key: segment.key,
          color: fill,
          elevation: selected ? (isDark ? 0 : 0.5) : 0,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(DsSpacing.radiusButton - 2),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(DsSpacing.radiusButton - 2),
            child: SizedBox(
              width: dense ? 32 : 36,
              height: dense ? 24 : 28,
              child: Icon(segment.icon, size: iconSize, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

/// Labeled cluster (File / View / Tools) in a dense toolbar row.
class DsToolbarLabeledGroup extends StatelessWidget {
  const DsToolbarLabeledGroup({
    super.key,
    required this.label,
    required this.children,
    this.dense = false,
  });

  final String label;
  final List<Widget> children;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);

    final row = Row(mainAxisSize: MainAxisSize.min, children: children);
    if (label.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: dense ? 1 : DsSpacing.xs),
        child: row,
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: dense ? 1 : DsSpacing.xs),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          row,
          const SizedBox(height: 1),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 9,
              height: 1,
              letterSpacing: 0.35,
              fontWeight: FontWeight.w600,
              color: secondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Flat icon-only toolbar row for PDF viewer (tabs sit above this bar).
class DsAcrobatIconToolbar extends StatelessWidget {
  const DsAcrobatIconToolbar({super.key, this.leading, required this.actions});

  final Widget? leading;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final background = isDark
        ? DsColors.surfaceContainerDark.withValues(alpha: 0.92)
        : const Color(0xFFEBEBEB);

    return Material(
      color: background,
      elevation: 0,
      child: SizedBox(
        height: kDsToolbarHeightAcrobat,
        child: Row(
          children: [
            ?leading,
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: DsSpacing.xs),
                child: actions,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vertical divider between toolbar action groups.
class DsToolbarDivider extends StatelessWidget {
  const DsToolbarDivider({super.key, this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final height = dense ? 18.0 : 22.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DsSpacing.xs),
      child: SizedBox(
        height: height,
        child: VerticalDivider(
          width: 1,
          color: isDark ? DsColors.borderDark : DsColors.borderLight,
        ),
      ),
    );
  }
}
