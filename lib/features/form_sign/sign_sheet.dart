import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_shell_page.dart';
import 'package:flutter/material.dart';

bool signIsPhoneWidth(BuildContext context) => dsUseCompactToolLayout(context);

/// Dialog on wide windows, draggable bottom sheet on phone widths.
Future<T?> showSignSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxWidth = 560,
  bool dismissible = true,
}) {
  if (signIsPhoneWidth(context)) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      isDismissible: dismissible,
      enableDrag: dismissible,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(DsSpacing.radiusDialog + 4),
        ),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.92,
          ),
          child: builder(ctx),
        ),
      ),
    );
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.32),
    transitionDuration: DsMotion.dialogDuration,
    pageBuilder: (ctx, _, _) {
      final size = MediaQuery.sizeOf(ctx);
      return SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: size.height * 0.9,
            ),
            child: Padding(
              padding: const EdgeInsets.all(DsSpacing.lg),
              child: Material(
                color: Theme.of(ctx).colorScheme.surface,
                elevation: 12,
                shadowColor: const Color(0x55000000),
                clipBehavior: Clip.antiAlias,
                borderRadius: BorderRadius.circular(DsSpacing.radiusDialog),
                child: builder(ctx),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim, _, child) =>
        DsMotion.fadeScaleTransition(anim, child),
  );
}

/// Title / scrollable body / action bar layout shared by the sign sheets.
class SignSheetScaffold extends StatelessWidget {
  const SignSheetScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.icon,
    this.actions = const [],
    this.bodyPadding,
    this.scrollable = true,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget body;
  final List<Widget> actions;
  final EdgeInsets? bodyPadding;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = signIsPhoneWidth(context);
    final secondary = DsColors.textSecondary(theme.brightness);
    final edge = phone ? DsSpacing.pagePaddingCompact : DsSpacing.xl;
    final pad = bodyPadding ?? EdgeInsets.fromLTRB(edge, 0, edge, DsSpacing.lg);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            edge,
            phone ? 0 : DsSpacing.lg + 2,
            DsSpacing.sm,
            DsSpacing.md,
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 19, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: DsSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: secondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (!phone)
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
            ],
          ),
        ),
        Flexible(
          child: scrollable
              ? SingleChildScrollView(padding: pad, child: body)
              : Padding(padding: pad, child: body),
        ),
        if (actions.isNotEmpty) ...[
          Divider(height: 1, color: DsColors.border(theme.brightness)),
          Padding(
            padding: EdgeInsets.fromLTRB(
              edge,
              DsSpacing.md,
              edge,
              DsSpacing.md + (phone ? MediaQuery.paddingOf(context).bottom : 0),
            ),
            child: phone
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(height: DsSpacing.sm),
                        SizedBox(
                          width: double.infinity,
                          height: DsSpacing.controlHeightComfortable,
                          child: actions[i],
                        ),
                      ],
                    ],
                  )
                : Wrap(
                    alignment: WrapAlignment.end,
                    spacing: DsSpacing.sm,
                    runSpacing: DsSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actions,
                  ),
          ),
        ],
      ],
    );
  }
}

/// Compact segmented control used inside the sign panel and sheets.
class SignSegmented<T> extends StatelessWidget {
  const SignSegmented({
    super.key,
    required this.value,
    required this.segments,
    required this.onChanged,
  });

  final T value;
  final List<(T, String, IconData?)> segments;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF111A2C) : const Color(0xFFEFF1F4);
    return LayoutBuilder(
      builder: (context, constraints) {
        final n = segments.length;
        final index = segments.indexWhere((s) => s.$1 == value);
        final phone = signIsPhoneWidth(context);
        return Container(
          height: phone ? DsSpacing.controlHeightComfortable : 36,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Stack(
            children: [
              AnimatedAlign(
                duration: DsMotion.tabDuration,
                curve: DsMotion.emphasizedCurve,
                alignment: Alignment(
                  n <= 1 ? 0 : -1 + 2 * (index.clamp(0, n - 1) / (n - 1)),
                  0,
                ),
                child: FractionallySizedBox(
                  widthFactor: 1 / n,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: dark
                          ? DsColors.surfaceContainerDark
                          : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: DsSpacing.cardShadowLight(opacity: 0.10),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final s in segments)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: s.$1 == value,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => onChanged(s.$1),
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: DsMotion.hoverDuration,
                              style: theme.textTheme.labelLarge!.copyWith(
                                fontSize: 12.5,
                                fontWeight: s.$1 == value
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: s.$1 == value
                                    ? theme.colorScheme.onSurface
                                    : DsColors.textSecondary(theme.brightness),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (s.$3 != null) ...[
                                      Icon(
                                        s.$3,
                                        size: 15,
                                        color: s.$1 == value
                                            ? theme.colorScheme.primary
                                            : DsColors.textSecondary(
                                                theme.brightness,
                                              ),
                                      ),
                                      const SizedBox(width: 5),
                                    ],
                                    Text(s.$2),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Small uppercase section label.
class SignSectionLabel extends StatelessWidget {
  const SignSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: DsSpacing.md, bottom: DsSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
                color: DsColors.textSecondary(theme.brightness),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
