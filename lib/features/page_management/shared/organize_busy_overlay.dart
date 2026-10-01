import 'package:document_studio/design_system/ds_colors.dart';
import 'package:flutter/material.dart';

/// Modal progress overlay for organize jobs (export, merge, crop, …).
class OrganizeBusyOverlay extends StatelessWidget {
  const OrganizeBusyOverlay({
    super.key,
    required this.visible,
    this.message,
    this.progress,
    this.onCancel,
    this.cancelLabel = 'Stop',
    this.cancelHint = 'Cancels the current operation when supported',
  });

  final bool visible;
  final String? message;
  final double? progress;
  final VoidCallback? onCancel;
  final String cancelLabel;
  final String cancelHint;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? DsColors.surfaceDark : DsColors.surfaceLight;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.38),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Material(
            color: surface,
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: border),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    message ?? 'Working…',
                    style: theme.textTheme.titleSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  if (progress != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: progress),
                    )
                  else
                    const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  if (onCancel != null) ...[
                    const SizedBox(height: 14),
                    Tooltip(
                      message: cancelHint,
                      child: OutlinedButton(
                        onPressed: onCancel,
                        child: Text(cancelLabel),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
