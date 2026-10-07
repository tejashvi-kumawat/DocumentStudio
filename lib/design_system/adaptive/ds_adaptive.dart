import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Platform-adaptive controls: Apple-native (Cupertino / macOS-style) on
/// iOS and macOS, Material elsewhere. Prefer these over raw Material widgets
/// so the whole app picks up the platform look.
bool dsIsApplePlatform(TargetPlatform platform) =>
    platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

extension DsAdaptiveContext on BuildContext {
  bool get dsIsApple => dsIsApplePlatform(Theme.of(this).platform);
  bool get dsIsMacOS => Theme.of(this).platform == TargetPlatform.macOS;
  bool get dsIsIOS => Theme.of(this).platform == TargetPlatform.iOS;
  bool get dsIsAndroid => Theme.of(this).platform == TargetPlatform.android;
}

/// Whether [platform] is Android ([TargetPlatform.android]).
bool dsIsAndroidPlatform(TargetPlatform platform) =>
    platform == TargetPlatform.android;

/// Scroll feel: rubber-band bounce on Apple, clamping elsewhere.
ScrollPhysics dsAdaptiveScrollPhysics(BuildContext context) => context.dsIsApple
    ? const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics())
    : const ClampingScrollPhysics();

/// App-wide scroll behavior: Apple bounce + overlay scrollbars on macOS/iOS,
/// mouse-drag scrolling on desktop (trackpads and touch screens alike).
class DsScrollBehavior extends MaterialScrollBehavior {
  const DsScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      dsAdaptiveScrollPhysics(context);
}

/// On/off toggle: `CupertinoSwitch` look on Apple, Material elsewhere.
class DsAdaptiveSwitch extends StatelessWidget {
  const DsAdaptiveSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Switch.adaptive(
      value: value,
      onChanged: onChanged,
      activeTrackColor: context.dsIsApple ? DsColors.primary : null,
    );
  }
}

/// Settings-style row with a trailing [DsAdaptiveSwitch]; the whole row is
/// tappable.
class DsAdaptiveSwitchTile extends StatelessWidget {
  const DsAdaptiveSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.leading,
    this.dense = true,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onChanged != null;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: dense ? 6 : 10),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Opacity(
                  opacity: enabled ? 1 : 0.5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              DsAdaptiveSwitch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// Continuous / stepped value: `CupertinoSlider` look on Apple.
class DsAdaptiveSlider extends StatelessWidget {
  const DsAdaptiveSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.onChangeEnd,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Slider.adaptive(
      value: value.clamp(min, max),
      min: min,
      max: max,
      divisions: divisions,
      label: label,
      activeColor: DsColors.primary,
      onChanged: onChanged,
      onChangeEnd: onChangeEnd,
    );
  }
}

/// One button in [showDsAdaptiveDialog].
class DsDialogAction<T> {
  const DsDialogAction({
    required this.label,
    this.value,
    this.primary = false,
    this.destructive = false,
  });

  final String label;
  final T? value;
  final bool primary;
  final bool destructive;
}

/// General dialog with arbitrary [content]: `CupertinoAlertDialog` on Apple,
/// animated [AlertDialog] elsewhere. Resolves to the chosen action's value.
Future<T?> showDsAdaptiveDialog<T>(
  BuildContext context, {
  required String title,
  Widget? content,
  required List<DsDialogAction<T>> actions,
}) {
  if (context.dsIsApple) {
    return showCupertinoDialog<T>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: content == null
            ? null
            : Material(type: MaterialType.transparency, child: content),
        actions: [
          for (final a in actions)
            CupertinoDialogAction(
              isDefaultAction: a.primary,
              isDestructiveAction: a.destructive,
              onPressed: () => Navigator.of(ctx).pop(a.value),
              child: Text(a.label),
            ),
        ],
      ),
    );
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    transitionDuration: DsMotion.dialogDuration,
    transitionBuilder: (ctx, a, _, child) =>
        DsMotion.fadeScaleTransition(a, child),
    pageBuilder: (ctx, _, _) => AlertDialog(
      title: Text(title),
      content: content,
      actions: [
        for (final a in actions)
          if (a.primary || a.destructive)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: a.destructive
                    ? DsColors.error
                    : DsColors.primary,
              ),
              onPressed: () => Navigator.of(ctx).pop(a.value),
              child: Text(a.label),
            )
          else
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(a.value),
              child: Text(a.label),
            ),
      ],
    ),
  );
}

/// Spinner: `CupertinoActivityIndicator` on Apple, thin ring elsewhere.
class DsAdaptiveProgress extends StatelessWidget {
  const DsAdaptiveProgress({super.key, this.size = 20, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (context.dsIsApple) {
      return CupertinoActivityIndicator(radius: size / 2, color: color);
    }
    return SizedBox.square(
      dimension: size,
      child: CircularProgressIndicator(
        strokeWidth: size <= 20 ? 2.2 : 3,
        color: color ?? DsColors.primary,
      ),
    );
  }
}

/// Two-to-four option picker: sliding segmented control on Apple,
/// [SegmentedButton] elsewhere.
class DsAdaptiveSegmented<T extends Object> extends StatelessWidget {
  const DsAdaptiveSegmented({
    super.key,
    required this.value,
    required this.segments,
    required this.onChanged,
  });

  final T value;
  final Map<T, ({String? label, IconData? icon, String? tooltip})> segments;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    if (context.dsIsApple) {
      return CupertinoSlidingSegmentedControl<T>(
        groupValue: value,
        onValueChanged: (v) {
          if (v != null) onChanged(v);
        },
        children: {
          for (final e in segments.entries)
            e.key: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: e.value.icon != null && e.value.label == null
                  ? Icon(e.value.icon, size: 16)
                  : Text(
                      e.value.label ?? '',
                      style: const TextStyle(fontSize: 12.5),
                    ),
            ),
        },
      );
    }
    return SegmentedButton<T>(
      showSelectedIcon: false,
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
      style: const ButtonStyle(
        visualDensity: VisualDensity(horizontal: -2, vertical: -2),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: [
        for (final e in segments.entries)
          ButtonSegment<T>(
            value: e.key,
            tooltip: e.value.tooltip,
            icon: e.value.icon == null ? null : Icon(e.value.icon, size: 16),
            label: e.value.label == null ? null : Text(e.value.label!),
          ),
      ],
    );
  }
}

/// Confirmation dialog: `CupertinoAlertDialog` on Apple, [AlertDialog]
/// elsewhere. Resolves to `true` only when confirmed.
Future<bool> showDsAdaptiveConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'OK',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  if (context.dsIsApple) {
    final result = await showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: message == null ? null : Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelLabel),
          ),
          CupertinoDialogAction(
            isDefaultAction: !destructive,
            isDestructiveAction: destructive,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    transitionDuration: DsMotion.dialogDuration,
    transitionBuilder: (ctx, a, _, child) =>
        DsMotion.fadeScaleTransition(a, child),
    pageBuilder: (ctx, _, _) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: destructive ? DsColors.error : DsColors.primary,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// One entry for [showDsContextMenu].
class DsMenuAction {
  const DsMenuAction({
    required this.label,
    required this.onSelected,
    this.icon,
    this.destructive = false,
    this.enabled = true,
    this.dividerBefore = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onSelected;
  final bool destructive;
  final bool enabled;
  final bool dividerBefore;
}

/// Context menu at [globalPosition]: action sheet on iOS, compact
/// macOS-style menu on desktop (tight rows, small icons), Material popup
/// on Android.
Future<void> showDsContextMenu(
  BuildContext context, {
  required Offset globalPosition,
  required List<DsMenuAction> actions,
  String? title,
}) async {
  if (context.dsIsIOS) {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: title == null ? null : Text(title),
        actions: [
          for (final a in actions)
            if (a.enabled)
              CupertinoActionSheetAction(
                isDestructiveAction: a.destructive,
                onPressed: () {
                  Navigator.of(ctx).pop();
                  a.onSelected();
                },
                child: Text(a.label),
              ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
    return;
  }

  final overlay =
      Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
  if (overlay == null) return;
  final local = overlay.globalToLocal(globalPosition);
  final theme = Theme.of(context);
  final compact = theme.platform != TargetPlatform.android;
  final muted = DsColors.textSecondary(theme.brightness);

  final items = <PopupMenuEntry<int>>[];
  for (var i = 0; i < actions.length; i++) {
    final a = actions[i];
    if (a.dividerBefore && items.isNotEmpty) {
      items.add(const PopupMenuDivider(height: 9));
    }
    final color = a.destructive ? DsColors.error : null;
    items.add(
      PopupMenuItem<int>(
        value: i,
        enabled: a.enabled,
        height: compact ? 30 : kMinInteractiveDimension,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            if (a.icon != null) ...[
              Icon(a.icon, size: compact ? 15 : 18, color: color ?? muted),
              const SizedBox(width: 10),
            ],
            Text(
              a.label,
              style: TextStyle(fontSize: compact ? 13 : 14, color: color),
            ),
          ],
        ),
      ),
    );
  }

  final chosen = await showMenu<int>(
    context: context,
    position: RelativeRect.fromRect(
      local & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    popUpAnimationStyle: AnimationStyle(
      duration: const Duration(milliseconds: 140),
      reverseDuration: const Duration(milliseconds: 90),
    ),
    items: items,
  );
  if (chosen != null) actions[chosen].onSelected();
}
