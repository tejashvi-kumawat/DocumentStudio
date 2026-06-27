import 'package:document_studio/features/page_management/shared/organize_busy_overlay.dart';
import 'package:flutter/material.dart';

/// Full-screen progress overlay with a short fade-in ([DS-CNV-*] UX).
class ConversionBusyOverlay extends StatelessWidget {
  const ConversionBusyOverlay({
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

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: OrganizeBusyOverlay(
            visible: visible,
            message: message,
            progress: progress,
            onCancel: onCancel,
            cancelLabel: cancelLabel,
            cancelHint: 'Stops the current conversion when supported',
          ),
        ),
      ),
    );
  }
}
