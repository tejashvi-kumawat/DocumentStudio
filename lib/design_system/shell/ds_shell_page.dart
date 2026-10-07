import 'package:document_studio/design_system/adaptive/ds_adaptive.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:flutter/material.dart';

/// Window size class for shell / tab page layouts.
enum DsWindowSizeClass {
  /// Width &lt; [DsSpacing.breakpointCompact] — phone.
  compact,

  /// [DsSpacing.breakpointCompact] ≤ width &lt; [DsSpacing.breakpointExpanded].
  medium,

  /// Width ≥ [DsSpacing.breakpointExpanded] — tablet / desktop.
  expanded,
}

/// Resolves [DsWindowSizeClass] from a viewport width.
DsWindowSizeClass dsWindowSizeClassForWidth(double width) {
  if (width < DsSpacing.breakpointCompact) return DsWindowSizeClass.compact;
  if (width < DsSpacing.breakpointExpanded) return DsWindowSizeClass.medium;
  return DsWindowSizeClass.expanded;
}

/// Horizontal padding so full-bleed slivers align with the shell content column.
///
/// Compact: fixed [DsSpacing.pagePaddingCompact] (16dp).
/// Wider: ~4% of viewport width (clamped) until the content hits
/// [DsSpacing.contentMaxWidth], then centers the capped column.
double dsShellContentHorizontalPadding(double viewportWidth) {
  if (viewportWidth < DsSpacing.breakpointCompact) {
    return DsSpacing.pagePaddingCompact;
  }
  const maxW = DsSpacing.contentMaxWidth;
  final inset = (viewportWidth * 0.04).clamp(DsSpacing.md, 64.0);
  if (viewportWidth <= maxW + inset * 2) return inset;
  return (viewportWidth - maxW) / 2;
}

/// Max-width column for Home, Tools hub, and Settings (inside [DsAppShell]).
class DsShellPageFrame extends StatelessWidget {
  const DsShellPageFrame({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: DsSpacing.lg),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: DsSpacing.contentMaxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Page-level title + subtitle for shell tabs (distinct from [DsSectionHeader] sections).
class DsShellPageHeader extends StatelessWidget {
  const DsShellPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.compactTitle = false,
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final bool compactTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);
    final titleStyle = compactTitle
        ? theme.textTheme.titleMedium
        : theme.textTheme.titleLarge?.copyWith(
            height: 1.15,
            letterSpacing: -0.2,
          );

    return Padding(
      padding: EdgeInsets.only(
        bottom: compactTitle ? DsSpacing.sm : DsSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: titleStyle),
                if (subtitle != null) ...[
                  const SizedBox(height: DsSpacing.xs),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: DsSpacing.sm), action!],
        ],
      ),
    );
  }
}

/// Whether the shell shows the mobile bottom bar (no in-page brand block needed).
bool dsShellShowsCompactChrome(BuildContext context) {
  return MediaQuery.sizeOf(context).width < DsSpacing.breakpointCompact;
}

/// Phone-style tool forms: narrow width, or any Android device (including tablets).
///
/// Android never gets the desktop side-by-side tool layout — one column, 16dp
/// padding, full-width primary (~48dp). Desktop Linux keeps width-based layout.
bool dsUseCompactToolLayout(BuildContext context) {
  if (context.dsIsAndroid) return true;
  return MediaQuery.sizeOf(context).width < DsSpacing.breakpointCompact;
}

/// Hide Home/document tab strip (Android full-screen viewer + back; desktop keeps tabs).
bool dsHideDocumentTabStrip(BuildContext context) => context.dsIsAndroid;

/// Narrow width where stacked toolbars beat side-by-side controls.
bool dsShellUseStackedControls(double width) => width < 480;
