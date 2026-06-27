import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:flutter/material.dart';

/// Full-page wait affordance: thin brand-red bar at the top + quiet label.
///
/// Prefer this over blocking gray dialogs or centered [CircularProgressIndicator]
/// on Home / Tools / standalone tool forms.
class DsPageBusyBar extends StatelessWidget {
  const DsPageBusyBar({
    super.key,
    required this.visible,
    this.message,
    this.progress,
    this.onCancel,
    this.cancelLabel = 'Cancel',
  });

  final bool visible;
  final String? message;
  final double? progress;
  final VoidCallback? onCancel;
  final String cancelLabel;

  static const Key barKey = Key('ds_page_busy_bar');
  static const Key labelKey = Key('ds_page_busy_label');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: DsMotion.hoverDuration,
        curve: DsMotion.switchCurve,
        child: Align(
          alignment: Alignment.topCenter,
          child: Material(
            key: barKey,
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 2,
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 2,
                    backgroundColor: DsColors.primary.withValues(alpha: 0.12),
                    color: DsColors.primary,
                  ),
                ),
                if ((message != null && message!.isNotEmpty) ||
                    onCancel != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      DsSpacing.lg,
                      DsSpacing.sm,
                      DsSpacing.lg,
                      0,
                    ),
                    child: Row(
                      children: [
                        if (message != null && message!.isNotEmpty)
                          Expanded(
                            child: Text(
                              message!,
                              key: labelKey,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 13,
                                color: secondary,
                              ),
                            ),
                          )
                        else
                          const Spacer(),
                        if (onCancel != null)
                          TextButton(
                            onPressed: onCancel,
                            style: TextButton.styleFrom(
                              foregroundColor: secondary,
                              textStyle: theme.textTheme.labelLarge?.copyWith(
                                fontSize: 13,
                              ),
                            ),
                            child: Text(cancelLabel),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Stacks [child] under an optional [DsPageBusyBar] (does not dim the page).
class DsPageBusyHost extends StatelessWidget {
  const DsPageBusyHost({
    super.key,
    required this.child,
    required this.busy,
    this.message,
    this.progress,
    this.onCancel,
    this.cancelLabel = 'Cancel',
  });

  final Widget child;
  final bool busy;
  final String? message;
  final double? progress;
  final VoidCallback? onCancel;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        DsPageBusyBar(
          visible: busy,
          message: message,
          progress: progress,
          onCancel: onCancel,
          cancelLabel: cancelLabel,
        ),
      ],
    );
  }
}
