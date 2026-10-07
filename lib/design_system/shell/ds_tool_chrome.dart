import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:flutter/material.dart';

/// One look for every tool page, whichever layout it uses: a header bar
/// (back, the tool's icon, title and one line of help, then actions) and a
/// pinned action bar at the bottom. The icon badge is the same brand tint
/// for every tool; tools are told apart by their icon and title, not colour.
class DsToolHeader extends StatelessWidget {
  const DsToolHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.leading,
    this.actions = const [],
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? leading;
  final List<Widget> actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: b == Brightness.dark
            ? DsColors.surfaceContainerDark
            : DsColors.surfaceLight,
        border: Border(bottom: BorderSide(color: DsColors.border(b))),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              SizedBox(width: compact ? 4 : 10),
              if (leading != null) leading!,
              SizedBox(width: leading == null ? DsSpacing.lg : DsSpacing.xs),
              if (icon != null) ...[
                DsToolBadge(icon: icon!, size: compact ? 34 : 38),
                const SizedBox(width: DsSpacing.md),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: compact ? 16 : 17,
                        letterSpacing: -0.2,
                        height: 1.2,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12.5,
                            color: DsColors.textSecondary(b),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(width: DsSpacing.md),
                ...actions,
              ],
              SizedBox(width: compact ? DsSpacing.sm : DsSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

/// [DsToolHeader] as an app bar, for tool screens that lay out their own body
/// (`Scaffold(appBar: DsToolAppBar(...))`). The back button pops the route
/// unless [onBack] says otherwise (null with [backEnabled] false disables it).
class DsToolAppBar extends StatelessWidget implements PreferredSizeWidget {
  const DsToolAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actions = const [],
    this.onBack,
    this.backEnabled = true,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final bool backEnabled;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < DsSpacing.breakpointCompact;
    final nav = Navigator.of(context);
    return DsToolHeader(
      title: title,
      subtitle: subtitle,
      icon: icon,
      compact: compact,
      actions: actions,
      leading: nav.canPop() || onBack != null
          ? IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back, size: 20),
              onPressed: backEnabled ? (onBack ?? () => nav.maybePop()) : null,
            )
          : null,
    );
  }
}

/// The tool's icon on a soft brand-tint square; identical on every tool.
class DsToolBadge extends StatelessWidget {
  const DsToolBadge({super.key, required this.icon, this.size = 38});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: DsColors.primary.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, color: DsColors.primary, size: size * 0.54),
  );
}

/// Bottom action bar: Cancel on the left, the one primary action on the
/// right (full-width buttons stacked on a phone). Pinned, with a hairline
/// above it.
class DsToolFooter extends StatelessWidget {
  const DsToolFooter({
    super.key,
    this.primaryLabel,
    this.onPrimary,
    this.primaryEnabled = true,
    this.primaryBusy = false,
    this.primaryIcon = Icons.check,
    this.onCancel,
    this.cancelLabel = 'Cancel',
    this.leading,
    this.compact = false,
  });

  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final bool primaryEnabled;
  final bool primaryBusy;
  final IconData primaryIcon;
  final VoidCallback? onCancel;
  final String cancelLabel;

  /// Status text at the start of the bar ("3 files · 12 pages").
  final Widget? leading;
  final bool compact;

  bool get isEmpty =>
      primaryLabel == null && onCancel == null && leading == null;

  @override
  Widget build(BuildContext context) {
    if (isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final b = theme.brightness;
    final controlH = compact ? DsSpacing.controlHeightComfortable : 42.0;
    final primary = primaryLabel == null
        ? null
        : FilledButton.icon(
            onPressed: primaryEnabled && !primaryBusy ? onPrimary : null,
            style: FilledButton.styleFrom(
              backgroundColor: DsColors.primary,
              foregroundColor: DsColors.onPrimary,
              disabledBackgroundColor: DsColors.primary.withValues(alpha: 0.30),
              disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
              minimumSize: Size(compact ? double.infinity : 0, controlH),
              padding: const EdgeInsets.symmetric(horizontal: DsSpacing.xl),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: theme.textTheme.labelLarge?.copyWith(
                fontSize: 14,
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
    final cancel = onCancel == null
        ? null
        : TextButton(
            onPressed: primaryBusy ? null : onCancel,
            style: TextButton.styleFrom(
              foregroundColor: DsColors.textSecondary(b),
              minimumSize: Size(compact ? double.infinity : 0, controlH),
              padding: const EdgeInsets.symmetric(horizontal: DsSpacing.lg),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: theme.textTheme.labelLarge?.copyWith(fontSize: 14),
            ),
            child: Text(cancelLabel),
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: b == Brightness.dark
            ? DsColors.surfaceContainerDark
            : DsColors.surfaceLight,
        border: Border(top: BorderSide(color: DsColors.border(b))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? DsSpacing.pagePaddingCompact : DsSpacing.xl,
            vertical: DsSpacing.md,
          ),
          child: compact
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (leading != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: DsSpacing.sm),
                        child: leading,
                      ),
                    ?primary,
                    if (cancel != null) ...[
                      const SizedBox(height: DsSpacing.xs),
                      cancel,
                    ],
                  ],
                )
              : Row(
                  children: [
                    if (leading != null)
                      Expanded(child: leading!)
                    else
                      const Spacer(),
                    ?cancel,
                    if (cancel != null && primary != null)
                      const SizedBox(width: DsSpacing.sm),
                    ?primary,
                  ],
                ),
        ),
      ),
    );
  }
}
