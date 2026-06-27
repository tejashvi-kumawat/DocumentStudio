import 'package:document_studio/design_system/ds_colors.dart';
import 'package:flutter/material.dart';

/// Compact status strip height (desktop / tablet landscape).
const double kDsStatusBarHeightCompact = 32;

/// Taller status strip for touch-first layouts.
const double kDsStatusBarHeightComfortable = 40;

/// Breakpoint matching document workspace dense chrome.
const double kDsStatusBarCompactBreakpoint = 600;

/// Bottom (or top) metadata strip for the document workspace — page, zoom, job state.
///
/// Uses label typography and secondary text per [docs/DESIGN-SYSTEM.md].
class DsStatusBar extends StatelessWidget {
  const DsStatusBar({
    super.key,
    this.leading = const <Widget>[],
    this.center,
    this.trailing = const <Widget>[],
    this.message,
    this.compact,
  });

  final List<Widget> leading;
  final Widget? center;
  final List<Widget> trailing;

  /// Optional transient status (save, sync, error hint) shown before [trailing].
  final String? message;

  /// When null, compact mode is used if layout width ≥ [kDsStatusBarCompactBreakpoint].
  final bool? compact;

  static bool _isCompact(BuildContext context, bool? compact) {
    if (compact != null) return compact;
    return MediaQuery.sizeOf(context).width >= kDsStatusBarCompactBreakpoint;
  }

  static double heightFor(BuildContext context, {bool? compact}) {
    return _isCompact(context, compact)
        ? kDsStatusBarHeightCompact
        : kDsStatusBarHeightComfortable;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isCompact = _isCompact(context, compact);
    final height = isCompact
        ? kDsStatusBarHeightCompact
        : kDsStatusBarHeightComfortable;
    final background = isDark
        ? DsColors.surfaceContainerDark
        : DsColors.surfaceContainerLight;
    final borderColor = isDark ? DsColors.borderDark : DsColors.borderLight;
    final horizontalPadding = isCompact ? 12.0 : 16.0;
    final gap = isCompact ? 12.0 : 16.0;

    return Material(
      color: background,
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: borderColor)),
        ),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Row(
              children: [
                if (leading.isNotEmpty)
                  _SegmentGroup(spacing: gap, children: leading),
                if (center != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.center,
                      child: DefaultTextStyle(
                        style: theme.textTheme.bodySmall!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        child: center!,
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
                if (message != null) ...[
                  Flexible(
                    child: Text(
                      message!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  SizedBox(width: gap),
                ],
                if (trailing.isNotEmpty)
                  _SegmentGroup(spacing: gap, children: trailing),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SegmentGroup extends StatelessWidget {
  const _SegmentGroup({required this.spacing, required this.children});

  final double spacing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: spacing),
          children[i],
        ],
      ],
    );
  }
}

/// Label + value pair for status metrics (e.g. page index, zoom).
class DsStatusMetric extends StatelessWidget {
  const DsStatusMetric({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.semanticsLabel,
    this.compact = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final String? semanticsLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = isDark
        ? DsColors.textSecondaryDark
        : DsColors.textSecondaryLight;
    final iconSize = compact ? 16.0 : 18.0;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(color: secondary);
    final valueStyle = theme.textTheme.labelSmall;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: iconSize, color: secondary),
          const SizedBox(width: 4),
        ],
        Text('$label ', style: labelStyle),
        Text(value, style: valueStyle),
      ],
    );

    if (semanticsLabel != null) {
      return Semantics(
        label: semanticsLabel,
        child: content,
      );
    }
    return content;
  }
}

/// Dot + short text for save / progress / error hints in the status bar.
class DsStatusIndicator extends StatelessWidget {
  const DsStatusIndicator({
    super.key,
    required this.label,
    this.tone = DsStatusIndicatorTone.neutral,
    this.showDot = true,
  });

  final String label;
  final DsStatusIndicatorTone tone;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (tone) {
      DsStatusIndicatorTone.success => DsColors.success,
      DsStatusIndicatorTone.warning => DsColors.warning,
      DsStatusIndicatorTone.error => theme.colorScheme.error,
      DsStatusIndicatorTone.neutral => theme.brightness == Brightness.dark
          ? DsColors.textSecondaryDark
          : DsColors.textSecondaryLight,
    };

    return Semantics(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

enum DsStatusIndicatorTone { neutral, success, warning, error }
