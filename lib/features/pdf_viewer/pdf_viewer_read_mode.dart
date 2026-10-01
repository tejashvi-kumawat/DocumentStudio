import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// DS-READ — read mode hides tools rail + thumbnails; page fills the canvas.
bool pdfViewerShowsToolsRail({
  required bool presentationMode,
  required bool readMode,
  required bool userToolsRailEnabled,
}) =>
    !presentationMode && !readMode && userToolsRailEnabled;

bool pdfViewerShowsLeftRail({
  required bool presentationMode,
  required bool readMode,
  required bool userSidebarEnabled,
}) =>
    !presentationMode && !readMode && userSidebarEnabled;

class PdfViewerToggleReadModeIntent extends Intent {
  const PdfViewerToggleReadModeIntent();
}

class PdfViewerTogglePresentationIntent extends Intent {
  const PdfViewerTogglePresentationIntent();
}

class PdfViewerExitImmersiveIntent extends Intent {
  const PdfViewerExitImmersiveIntent();
}

ShortcutActivator pdfViewerReadModeActivator() {
  final useMeta = defaultTargetPlatform == TargetPlatform.macOS;
  return SingleActivator(
    LogicalKeyboardKey.keyR,
    control: !useMeta,
    meta: useMeta,
    alt: true,
  );
}

const pdfViewerPresentationActivator = SingleActivator(LogicalKeyboardKey.f5);

/// Snapshot restored when leaving presentation mode.
class PdfViewerPresentationSnapshot {
  const PdfViewerPresentationSnapshot({
    required this.page1Based,
    required this.zoom,
    this.center,
    required this.scrollLayoutModeName,
  });

  final int page1Based;
  final double zoom;
  final Offset? center;
  final String scrollLayoutModeName;
}
