import 'package:document_studio/design_system/adaptive/ds_adaptive.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_shell_page.dart';
import 'package:document_studio/design_system/shell/ds_tool_chrome.dart';
import 'package:document_studio/design_system/widgets/ds_page_busy_bar.dart';
import 'package:flutter/material.dart';

/// Wide-layout breakpoint for legacy two-column tool bodies.
const kDsToolFormWideBreakpoint = 880.0;

/// Standalone tool page: header bar (back, icon, title, one line of help),
/// scrolling content aligned to the left, and a pinned action bar. Every
/// tool uses the same chrome ([DsToolHeader] / [DsToolFooter]) so none of
/// them looks different from the next.
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
    this.headerTrailing,
    this.preview,
    this.formWidth = 440,
  });

  final String title;
  final String subtitle;
  final Widget child;

  /// Replaces the automatic back button (shown when the route can pop).
  final Widget? leading;

  /// The tool's icon in the header (same tint on every tool).
  final IconData? icon;

  /// Widget at the end of the header (e.g. engine status chip).
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

  /// Extra content under the form (e.g. related links).
  final Widget? footer;

  /// Widest the content grows; it stays left-aligned.
  final double maxWidth;

  /// Workbench layout: on a wide window the form keeps a fixed column
  /// ([formWidth]) and this fills the rest of the screen (a preview of the
  /// document, results…), so the page is never a thin column next to
  /// emptiness. On a narrow window it goes above the form.
  final Widget? preview;
  final double formWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final compact = dsUseCompactToolLayout(context);
    final pagePad = compact ? DsSpacing.pagePaddingCompact : DsSpacing.xl;
    final cap = compact
        ? double.infinity
        : (maxWidth > 0 ? maxWidth : DsSpacing.formMaxWidth);

    final resolvedLeading =
        leading ??
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

    final width = MediaQuery.sizeOf(context).width;
    final workbench = preview != null && !compact && width >= 980;

    Widget scrollForm(double cap, {Widget? above}) => CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            pagePad,
            DsSpacing.lg,
            pagePad,
            DsSpacing.xxl,
          ),
          sliver: SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: cap),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ?above,
                    // Sections run one under the other; the first has no gap.
                    child,
                    if (footer != null) ...[
                      const SizedBox(height: DsSpacing.xl),
                      footer!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    final Widget body;
    if (workbench) {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: formWidth + pagePad * 2,
            child: scrollForm(formWidth),
          ),
          VerticalDivider(width: 1, color: DsColors.border(theme.brightness)),
          Expanded(
            child: ColoredBox(
              color: isDark
                  ? DsColors.groupedBackgroundDark
                  : DsColors.groupedBackgroundLight,
              child: preview!,
            ),
          ),
        ],
      );
    } else {
      body = scrollForm(
        cap,
        above: preview == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(bottom: DsSpacing.lg),
                child: SizedBox(
                  height: compact ? 300 : 380,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(DsSpacing.radiusCard),
                    child: ColoredBox(
                      color: isDark
                          ? DsColors.groupedBackgroundDark
                          : DsColors.groupedBackgroundLight,
                      child: preview,
                    ),
                  ),
                ),
              ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? DsColors.surfaceDark : DsColors.surfaceLight,
      body: DsPageBusyHost(
        busy: busy,
        message: busyMessage,
        progress: busyProgress,
        child: Column(
          children: [
            DsToolHeader(
              title: title,
              subtitle: subtitle,
              icon: icon,
              leading: resolvedLeading,
              compact: compact,
              actions: [
                if (headerTrailing != null && !compact) headerTrailing!,
              ],
            ),
            if (headerTrailing != null && compact)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    pagePad,
                    DsSpacing.sm,
                    pagePad,
                    0,
                  ),
                  child: headerTrailing!,
                ),
              ),
            Expanded(child: DsMotion.fadeRiseIn(child: body)),
            DsToolFooter(
              primaryLabel: primaryLabel,
              onPrimary: onPrimary,
              primaryEnabled: primaryEnabled,
              primaryBusy: primaryBusy,
              primaryIcon: primaryIcon,
              onCancel: onCancel,
              cancelLabel: cancelLabel,
              compact: compact,
            ),
          ],
        ),
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
      padding: EdgeInsets.only(top: topPadding ? DsSpacing.xl : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: theme.textTheme.titleSmall?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
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
                : Row(children: [?cancel, const Spacer(), primary]),
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

    final surface = isDark ? DsColors.groupedCellDark : DsColors.surfaceLight;
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
  const DsToolHubHeader({super.key, required this.title, this.subtitle});

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
