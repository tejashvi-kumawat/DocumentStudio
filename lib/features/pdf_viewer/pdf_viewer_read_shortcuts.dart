import 'package:document_studio/app/keyboard/text_input_guard.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Zoom/fit intents for the PDF viewer ([DS-READ-004-A/B/C], [DS-SHELL-003] partial).
class PdfViewerFitPageIntent extends Intent {
  const PdfViewerFitPageIntent();
}

class PdfViewerFitWidthIntent extends Intent {
  const PdfViewerFitWidthIntent();
}

class PdfViewerFitHeightIntent extends Intent {
  const PdfViewerFitHeightIntent();
}

class PdfViewerFindNextIntent extends Intent {
  const PdfViewerFindNextIntent();
}

class PdfViewerFindPreviousIntent extends Intent {
  const PdfViewerFindPreviousIntent();
}

ShortcutActivator _viewerPrimary(LogicalKeyboardKey key) {
  final useMeta = defaultTargetPlatform == TargetPlatform.macOS;
  return SingleActivator(key, control: !useMeta, meta: useMeta);
}

/// Viewer zoom + in-document find navigation (Ctrl/⌘+0 fit page, etc.).
Map<ShortcutActivator, Intent> pdfViewerReadShortcutBindings({
  required bool findBarVisible,
}) {
  return {
    _viewerPrimary(LogicalKeyboardKey.digit0): const PdfViewerFitPageIntent(),
    _viewerPrimary(LogicalKeyboardKey.numpad0): const PdfViewerFitPageIntent(),
    // Acrobat: Ctrl+1 actual size, Ctrl+2 fit width (Ctrl+3 fit height here).
    _viewerPrimary(LogicalKeyboardKey.digit2): const PdfViewerFitWidthIntent(),
    _viewerPrimary(LogicalKeyboardKey.numpad2): const PdfViewerFitWidthIntent(),
    _viewerPrimary(LogicalKeyboardKey.digit3): const PdfViewerFitHeightIntent(),
    _viewerPrimary(LogicalKeyboardKey.numpad3):
        const PdfViewerFitHeightIntent(),
    if (findBarVisible) ...{
      const SingleActivator(LogicalKeyboardKey.f3):
          const PdfViewerFindNextIntent(),
      const SingleActivator(LogicalKeyboardKey.f3, shift: true):
          const PdfViewerFindPreviousIntent(),
      _viewerPrimary(LogicalKeyboardKey.keyG): const PdfViewerFindNextIntent(),
      SingleActivator(
        LogicalKeyboardKey.keyG,
        control: defaultTargetPlatform != TargetPlatform.macOS,
        meta: defaultTargetPlatform == TargetPlatform.macOS,
        shift: true,
      ): const PdfViewerFindPreviousIntent(),
    },
  };
}

/// Wraps [child] with fit + find-next/prev shortcuts when the viewer has focus.
class PdfViewerReadShortcuts extends StatelessWidget {
  const PdfViewerReadShortcuts({
    super.key,
    required this.child,
    required this.findBarVisible,
    this.onFitPage,
    this.onFitWidth,
    this.onFitHeight,
    this.onFindNext,
    this.onFindPrevious,
  });

  final Widget child;
  final bool findBarVisible;
  final VoidCallback? onFitPage;
  final VoidCallback? onFitWidth;
  final VoidCallback? onFitHeight;
  final VoidCallback? onFindNext;
  final VoidCallback? onFindPrevious;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: pdfViewerReadShortcutBindings(findBarVisible: findBarVisible),
      child: Actions(
        actions: {
          PdfViewerFitPageIntent: GuardedCallbackAction<PdfViewerFitPageIntent>(
            onInvoke: (_) {
              onFitPage?.call();
              return null;
            },
          ),
          PdfViewerFitWidthIntent:
              GuardedCallbackAction<PdfViewerFitWidthIntent>(
                onInvoke: (_) {
                  onFitWidth?.call();
                  return null;
                },
              ),
          PdfViewerFitHeightIntent:
              GuardedCallbackAction<PdfViewerFitHeightIntent>(
                onInvoke: (_) {
                  onFitHeight?.call();
                  return null;
                },
              ),
          PdfViewerFindNextIntent:
              GuardedCallbackAction<PdfViewerFindNextIntent>(
                onInvoke: (_) {
                  onFindNext?.call();
                  return null;
                },
              ),
          PdfViewerFindPreviousIntent:
              GuardedCallbackAction<PdfViewerFindPreviousIntent>(
                onInvoke: (_) {
                  onFindPrevious?.call();
                  return null;
                },
              ),
        },
        child: child,
      ),
    );
  }
}
