import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:flutter/material.dart';

/// Acrobat options column. Wide windows stay in this band; compact uses
/// the full sheet width. Same on Android, Windows, and macOS.
const double viewerAcrobatOptionsWidth = 380;

/// The width of the resizable tools pane, so forms use it when it is dragged
/// wider than the default [viewerAcrobatOptionsWidth].
class ViewerOptionsWidthScope extends InheritedWidget {
  const ViewerOptionsWidthScope({
    super.key,
    required this.width,
    required super.child,
  });

  final double width;

  static double? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ViewerOptionsWidthScope>()
      ?.width;

  @override
  bool updateShouldNotify(ViewerOptionsWidthScope old) => old.width != width;
}

/// Full-width stacking when the window or the column is compact (&lt; 600).
bool viewerToolFormStacks(BuildContext context, [double? maxWidth]) {
  final width = maxWidth ?? MediaQuery.sizeOf(context).width;
  return width < DsSpacing.breakpointCompact;
}

/// Scrollable Acrobat options: 16dp padding and a 48dp primary.
///
/// The column never grows past [viewerAcrobatOptionsWidth], so a tool
/// stays a side box and the open PDF keeps the rest of the window.
class ViewerToolFormScaffold extends StatelessWidget {
  const ViewerToolFormScaffold({
    super.key,
    required this.children,
    required this.primaryLabel,
    required this.onPrimary,
    this.primaryIcon = Icons.check,
    this.primaryEnabled = true,
    this.primaryBusy = false,
    this.primaryKey,
    this.notice,
    this.secondaryLabel,
    this.onSecondary,
    this.secondaryIcon = Icons.save_as_outlined,
    this.secondaryEnabled = true,
    this.secondaryBusy = false,
    this.secondaryKey,
  });

  final List<Widget> children;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final IconData primaryIcon;
  final bool primaryEnabled;
  final bool primaryBusy;
  final Key? primaryKey;
  final Widget? notice;

  /// Optional second action. Omitted tools keep a single primary button.
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final IconData secondaryIcon;
  final bool secondaryEnabled;
  final bool secondaryBusy;
  final Key? secondaryKey;

  @override
  Widget build(BuildContext context) {
    final compact = viewerToolFormStacks(context);
    final pad = DsSpacing.pagePaddingCompact;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;

    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );

    final bar = _ApplyBar(
      compact: compact,
      pad: pad,
      border: border,
      primaryLabel: primaryLabel,
      onPrimary: onPrimary,
      primaryIcon: primaryIcon,
      primaryEnabled: primaryEnabled,
      primaryBusy: primaryBusy,
      primaryKey: primaryKey,
      notice: notice,
      secondaryLabel: secondaryLabel,
      onSecondary: onSecondary,
      secondaryIcon: secondaryIcon,
      secondaryEnabled: secondaryEnabled,
      secondaryBusy: secondaryBusy,
      secondaryKey: secondaryKey,
    );

    return Theme(
      data: _acrobatOptionsTheme(theme),
      child: LayoutBuilder(
      builder: (context, constraints) {
        final centered = _center(
          context: context,
          compact: compact ||
              (constraints.maxWidth.isFinite &&
                  constraints.maxWidth < DsSpacing.breakpointCompact),
          padding: EdgeInsets.fromLTRB(pad, pad, pad, DsSpacing.sm),
          child: form,
        );
        if (!constraints.hasBoundedHeight) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [centered, bar],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [centered],
              ),
            ),
            bar,
          ],
        );
      },
    ),
    );
  }
}

/// Dense fields and tiles so every panel that uses this shell stays compact.
ThemeData _acrobatOptionsTheme(ThemeData theme) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
    borderSide: BorderSide(color: DsColors.border(theme.brightness)),
  );
  return theme.copyWith(
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    listTileTheme: const ListTileThemeData(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: DsColors.primary, width: 1.5),
      ),
    ),
  );
}

class _ApplyBar extends StatelessWidget {
  const _ApplyBar({
    required this.compact,
    required this.pad,
    required this.border,
    required this.primaryLabel,
    required this.onPrimary,
    required this.primaryIcon,
    required this.primaryEnabled,
    required this.primaryBusy,
    required this.primaryKey,
    required this.notice,
    required this.secondaryLabel,
    required this.onSecondary,
    required this.secondaryIcon,
    required this.secondaryEnabled,
    required this.secondaryBusy,
    required this.secondaryKey,
  });

  final bool compact;
  final double pad;
  final Color border;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final IconData primaryIcon;
  final bool primaryEnabled;
  final bool primaryBusy;
  final Key? primaryKey;
  final Widget? notice;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final IconData secondaryIcon;
  final bool secondaryEnabled;
  final bool secondaryBusy;
  final Key? secondaryKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controlH = DsSpacing.controlHeightComfortable;
    final locked = primaryBusy || secondaryBusy;
    final button = FilledButton.icon(
      key: primaryKey,
      onPressed: primaryEnabled && !locked ? onPrimary : null,
      style: FilledButton.styleFrom(
        backgroundColor: DsColors.primary,
        foregroundColor: DsColors.onPrimary,
        disabledBackgroundColor: DsColors.primary.withValues(alpha: 0.35),
        minimumSize: Size(
          secondaryLabel != null ? 0 : (compact ? double.infinity : 160),
          controlH,
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: theme.textTheme.labelLarge?.copyWith(
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
      label: Text(
        primaryLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    final secondary = secondaryLabel == null
        ? null
        : OutlinedButton.icon(
            key: secondaryKey,
            onPressed: secondaryEnabled && !locked ? onSecondary : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: DsColors.primary,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            icon: secondaryBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: DsColors.primary,
                    ),
                  )
                : Icon(secondaryIcon, size: 20),
            label: Text(
              secondaryLabel!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
    final Widget actions;
    if (secondary == null) {
      actions = compact
          ? SizedBox(
              width: double.infinity,
              height: controlH,
              child: button,
            )
          : Align(
              alignment: Alignment.centerRight,
              child: SizedBox(height: controlH, child: button),
            );
    } else if (compact) {
      actions = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: controlH, child: button),
          const SizedBox(height: DsSpacing.sm),
          SizedBox(height: controlH, child: secondary),
        ],
      );
    } else {
      actions = Row(
        children: [
          Expanded(child: SizedBox(height: controlH, child: secondary)),
          const SizedBox(width: DsSpacing.sm),
          Expanded(child: SizedBox(height: controlH, child: button)),
        ],
      );
    }

    return Material(
      color: theme.colorScheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: border)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, DsSpacing.sm, pad, DsSpacing.sm),
            child: _center(
          context: context,
              compact: compact,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (notice != null) ...[
                    notice!,
                    const SizedBox(height: DsSpacing.sm),
                  ],
                  actions,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _center({
  required BuildContext context,
  required bool compact,
  EdgeInsetsGeometry? padding,
  required Widget child,
}) {
  return Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: compact
            ? double.infinity
            : (ViewerOptionsWidthScope.maybeOf(context) ??
                viewerAcrobatOptionsWidth),
      ),
      child: padding == null ? child : Padding(padding: padding, child: child),
    ),
  );
}

/// Section title plus body. Fields inside should stack on Android.
class ViewerToolFormSection extends StatelessWidget {
  const ViewerToolFormSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.first = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : DsSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                color: secondary,
              ),
            ),
          ],
          const SizedBox(height: DsSpacing.sm),
          child,
        ],
      ),
    );
  }
}
