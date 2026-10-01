import 'package:document_studio/design_system/adaptive/ds_adaptive.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_shell_page.dart';
import 'package:document_studio/design_system/widgets/ds_page_busy_bar.dart';
import 'package:flutter/material.dart';

/// Wide-layout breakpoint for legacy two-column tool bodies.
const kDsToolFormWideBreakpoint = 880.0;

/// Standalone tool page: gray canvas, title + one-line blurb, one white card,
/// primary action pinned bottom-right of the card, 200ms fade/rise on open.
class DsToolPage extends StatelessWidget {
  const DsToolPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.leading,
    this.primaryLabel,
    this.onPrimary,
    this.primaryEnabled = true,
    this.primaryBusy = false,
    this.primaryIcon = Icons.check,
    this.onCancel,
    this.cancelLabel = 'Cancel',
    this.busy = false,
    this.busyMessage,
    this.busyProgress,
    this.footer,
    this.maxWidth = DsSpacing.formMaxWidth,
    this.icon,
    this.iconColor,
    this.headerTrailing,
  });

  final String title;
  final String subtitle;
  final Widget child;

  /// Replaces the automatic back button (shown when the route can pop).
  final Widget? leading;

  /// Tinted badge shown before the title.
  final IconData? icon;
  final Color? iconColor;

  /// Widget aligned to the end of the title row (e.g. engine status chip).
  final Widget? headerTrailing;

  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final bool primaryEnabled;
  final bool primaryBusy;
  final IconData primaryIcon;
  final VoidCallback? onCancel;
  final String cancelLabel;

  final bool busy;
  final String? busyMessage;
  final double? busyProgress;

  /// Extra footer under the primary row (e.g. related links).
  final Widget? footer;

  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pageBg = DsColors.groupedBackground(theme.brightness);
    final secondary = DsColors.textSecondary(theme.brightness);
    final compact = dsUseCompactToolLayout(context);
    final pagePad = compact ? DsSpacing.pagePaddingCompact : DsSpacing.lg;
    // Phone / Android: ~48dp full-width primary (not a giant card control).
    final controlH = DsSpacing.controlHeightComfortable;
    // Readable form column on desktop; full bleed on phone/Android (minus pad).
    final formCap = compact
        ? double.infinity
        : (maxWidth > 0 ? maxWidth : DsSpacing.formMaxWidth);

    final resolvedLeading = leading ??
        (Navigator.of(context).canPop()
            ? IconButton(
                tooltip: 'Back',
                icon: Icon(
                  context.dsIsApple
                      ? Icons.arrow_back_ios_new
                      : Icons.arrow_back,
                  size: 20,
                ),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null);

    Widget primaryButton() {
      if (primaryLabel == null) return const SizedBox.shrink();
      final button = FilledButton.icon(
        onPressed: primaryEnabled && !primaryBusy ? onPrimary : null,
        style: FilledButton.styleFrom(
          backgroundColor: DsColors.primary,
          foregroundColor: DsColors.onPrimary,
          disabledBackgroundColor: DsColors.primary.withValues(alpha: 0.35),
          minimumSize: Size(0, controlH),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(
            horizontal: DsSpacing.lg,
            vertical: DsSpacing.sm,
          ),
          textStyle: theme.textTheme.labelLarge?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        icon: primaryBusy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: DsColors.onPrimary,
                ),
              )
            : Icon(primaryIcon, size: 18),
        label: Text(primaryLabel!),
      );
      if (!compact) return button;
      return SizedBox(width: double.infinity, height: controlH, child: button);
    }

    Widget cancelButton() {
      if (onCancel == null) return const SizedBox.shrink();
      final button = TextButton(
        onPressed: primaryBusy ? null : onCancel,
        style: TextButton.styleFrom(
          foregroundColor: secondary,
          minimumSize: Size(0, controlH),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
        ),
        child: Text(cancelLabel),
      );
      if (!compact) return button;
      return SizedBox(width: double.infinity, height: controlH, child: button);
    }

    final actions = primaryLabel != null || onCancel != null || footer != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: DsSpacing.lg),
              const Divider(height: 1),
              const SizedBox(height: DsSpacing.md),
              if (footer != null) ...[
                footer!,
                const SizedBox(height: DsSpacing.md),
              ],
              if (compact) ...[
                if (primaryLabel != null) primaryButton(),
                if (onCancel != null) ...[
                  const SizedBox(height: DsSpacing.sm),
                  cancelButton(),
                ],
              ] else
                Row(
                  children: [
                    if (onCancel != null) cancelButton(),
                    const Spacer(),
                    if (primaryLabel != null) primaryButton(),
                  ],
                ),
            ],
          )
        : const SizedBox.shrink();

    final card = _DsToolFormCard(
      padding: EdgeInsets.all(compact ? DsSpacing.md : DsSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          actions,
        ],
      ),
    );

    final body = ColoredBox(
      color: pageBg,
      child: SafeArea(
        child: DsMotion.fadeRiseIn(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  pagePad,
                  compact ? DsSpacing.md : DsSpacing.md,
                  pagePad,
                  DsSpacing.shellPageBottom,
                ),
                sliver: SliverToBoxAdapter(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: formCap),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (resolvedLeading != null) ...[
                                resolvedLeading,
                                const SizedBox(width: DsSpacing.sm),
                              ],
                              if (icon != null) ...[
                                _ToolIconBadge(
                                  icon: icon!,
                                  color: iconColor ?? DsColors.primary,
                                  size: compact ? 40 : 44,
                                ),
                                const SizedBox(width: DsSpacing.md),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: compact ? 2 : 3,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.3,
                                        height: 1.2,
                                        fontSize: compact ? 20 : null,
                                      ),
                                    ),
                                    const SizedBox(height: DsSpacing.xs),
                                    Text(
                                      subtitle,
                                      maxLines: compact ? 2 : 4,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        fontSize: 13,
                                        color: secondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (headerTrailing != null && !compact) ...[
                                const SizedBox(width: DsSpacing.sm),
                                headerTrailing!,
                              ],
                            ],
                          ),
                          if (headerTrailing != null && compact) ...[
                            const SizedBox(height: DsSpacing.sm),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: headerTrailing!,
                            ),
                          ],
                          const SizedBox(height: DsSpacing.lg),
                          card,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: pageBg,
      body: DsPageBusyHost(
        busy: busy,
        message: busyMessage,
        progress: busyProgress,
        child: body,
      ),
    );
  }
}

class _ToolIconBadge extends StatelessWidget {
  const _ToolIconBadge({
    required this.icon,
    required this.color,
    this.size = 44,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.22),
            color.withValues(alpha: 0.10),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

class _DsToolFormCard extends StatelessWidget {
  const _DsToolFormCard({
    required this.child,
    this.padding = const EdgeInsets.all(DsSpacing.lg),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? DsColors.groupedCellDark : DsColors.surfaceLight,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DsSpacing.radiusCard),
        side: BorderSide(
          color: isDark ? DsColors.borderDark : DsColors.borderLight,
          width: isDark ? 1 : 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

/// Section block inside a tool card (title + body, no nested card chrome).
class DsToolSection extends StatelessWidget {
  const DsToolSection({
    super.key,
    this.title,
    this.subtitle,
    required this.child,
    this.topPadding = true,
  });

  final String? title;
  final String? subtitle;
  final Widget child;
  final bool topPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);

    return Padding(
      padding: EdgeInsets.only(top: topPadding ? DsSpacing.lg : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: theme.textTheme.labelLarge?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: DsSpacing.xs),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: secondary,
                ),
              ),
            ],
            const SizedBox(height: DsSpacing.md),
          ],
          child,
        ],
      ),
    );
  }
}

/// Acrobat-style bottom action bar for tool screens (sticky above safe area).
///
/// Prefer [DsToolPage] card-footer primary for new standalone tool pages.
class DsToolStickyActionBar extends StatelessWidget {
  const DsToolStickyActionBar({
    super.key,
    required this.primaryLabel,
    required this.onPrimary,
    this.onCancel,
    this.primaryEnabled = true,
    this.primaryBusy = false,
    this.primaryIcon = Icons.check,
  });

  final String primaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback? onCancel;
  final bool primaryEnabled;
  final bool primaryBusy;
  final IconData primaryIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;
    final surface = isDark
        ? DsColors.surfaceContainerDark
        : DsColors.surfaceLight;
    final compact = dsUseCompactToolLayout(context);
    final controlH = DsSpacing.controlHeightComfortable;

    final cancel = onCancel == null
        ? null
        : TextButton(
            onPressed: primaryBusy ? null : onCancel,
            style: TextButton.styleFrom(
              minimumSize: Size(0, controlH),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Cancel'),
          );
    final primary = FilledButton.icon(
      onPressed: primaryEnabled && !primaryBusy ? onPrimary : null,
      style: FilledButton.styleFrom(
        backgroundColor: DsColors.primary,
        foregroundColor: DsColors.onPrimary,
        minimumSize: Size(0, controlH),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: theme.textTheme.labelLarge?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      icon: primaryBusy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: DsColors.onPrimary,
              ),
            )
          : Icon(primaryIcon, size: 20),
      label: Text(primaryLabel),
    );

    return Material(
      elevation: 0,
      color: surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: border, width: isDark ? 1 : 0.5),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? DsSpacing.pagePaddingCompact : DsSpacing.lg,
              vertical: DsSpacing.sm,
            ),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: controlH,
                        child: primary,
                      ),
                      if (cancel != null) ...[
                        const SizedBox(height: DsSpacing.sm),
                        SizedBox(
                          width: double.infinity,
                          height: controlH,
                          child: cancel,
                        ),
                      ],
                    ],
                  )
                : Row(
                    children: [
                      if (cancel != null) cancel,
                      const Spacer(),
                      primary,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Bordered panel for tool inputs (legacy multi-panel layouts).
///
/// Prefer [DsToolSection] inside [DsToolPage] for new screens.
class DsToolPanel extends StatelessWidget {
  const DsToolPanel({
    super.key,
    this.title,
    this.subtitle,
    required this.child,
    this.padding = const EdgeInsets.all(DsSpacing.lg),
  });

  final String? title;
  final String? subtitle;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;

    final surface =
        isDark ? DsColors.groupedCellDark : DsColors.surfaceLight;
    return Material(
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DsSpacing.radiusCard),
        side: BorderSide(color: border, width: isDark ? 1 : 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null) ...[
              Text(
                title!,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: DsSpacing.xs),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: DsColors.textSecondary(theme.brightness),
                  ),
                ),
              ],
              const SizedBox(height: DsSpacing.md),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Tool screen body: main workflow column + optional options sidebar on wide layouts.
class DsToolFormLayout extends StatelessWidget {
  const DsToolFormLayout({
    super.key,
    required this.primary,
    this.sidebar,
    this.sidebarWidth = 280,
    this.breakpoint = kDsToolFormWideBreakpoint,
    this.padding = const EdgeInsets.fromLTRB(
      DsSpacing.lg,
      DsSpacing.lg,
      DsSpacing.lg,
      DsSpacing.xxxl,
    ),
    this.animateEntrance = true,
    this.maxWidth = DsSpacing.formMaxWidth,
  });

  final Widget primary;
  final Widget? sidebar;
  final double sidebarWidth;
  final double breakpoint;
  final EdgeInsets padding;
  final bool animateEntrance;

  /// Readable form width on medium/expanded; ignored when viewport is compact.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final compact = dsUseCompactToolLayout(context);
    final wide = !compact && MediaQuery.sizeOf(context).width >= breakpoint;
    final formCap = compact ? double.infinity : maxWidth;
    final resolvedPadding = compact
        ? EdgeInsets.fromLTRB(
            DsSpacing.pagePaddingCompact,
            padding.top > 0 ? DsSpacing.md : 0,
            DsSpacing.pagePaddingCompact,
            padding.bottom > 0 ? DsSpacing.shellPageBottom : 0,
          )
        : padding;

    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: formCap),
        child: Padding(
          padding: resolvedPadding,
          child: wide && sidebar != null
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: primary),
                    const SizedBox(width: DsSpacing.lg),
                    SizedBox(width: sidebarWidth, child: sidebar!),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    primary,
                    if (sidebar != null) ...[
                      const SizedBox(height: DsSpacing.xl),
                      sidebar!,
                    ],
                  ],
                ),
        ),
      ),
    );

    if (!animateEntrance) return content;
    return DsMotion.fadeRiseIn(child: content);
  }
}

/// Centers a single white card for shell tab pages (Home / Tools shared language).
class DsShellCard extends StatelessWidget {
  const DsShellCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(DsSpacing.lg),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? DsColors.groupedCellDark : DsColors.surfaceLight,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DsSpacing.radiusCard),
        side: BorderSide(
          color: isDark ? DsColors.borderDark : DsColors.borderLight,
          width: isDark ? 1 : 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Page header used by Tools hub (13px rhythm, matches Home section titles).
class DsToolHubHeader extends StatelessWidget {
  const DsToolHubHeader({
    super.key,
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return DsShellPageHeader(
      title: title,
      subtitle: subtitle,
      compactTitle: false,
    );
  }
}
