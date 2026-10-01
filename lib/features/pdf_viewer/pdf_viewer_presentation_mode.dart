import 'package:document_studio/app/keyboard/text_input_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// DS-READ-006 — presentation mode hides viewer chrome for a focused read.
bool pdfViewerShowsAppBar({
  required bool presentationMode,
  bool readMode = false,
}) => !presentationMode;

bool pdfViewerShowsStatusBar({
  required bool presentationMode,
  bool readMode = false,
}) => !presentationMode;

bool pdfViewerShowsSearchBar({required bool presentationMode}) =>
    !presentationMode;

bool pdfViewerSidebarVisible({
  required bool presentationMode,
  required bool userSidebarEnabled,
  bool readMode = false,
}) => !presentationMode && !readMode && userSidebarEnabled;

/// Escape exits presentation / read mode when [onExit] is provided.
class PdfViewerPresentationEscapeScope extends StatelessWidget {
  const PdfViewerPresentationEscapeScope({
    super.key,
    required this.presentationMode,
    required this.onExit,
    required this.child,
    this.readMode = false,
    this.onExitReadMode,
  });

  final bool presentationMode;
  final bool readMode;
  final VoidCallback onExit;
  final VoidCallback? onExitReadMode;
  final Widget child;

  static const _exitActivator = SingleActivator(LogicalKeyboardKey.escape);

  @override
  Widget build(BuildContext context) {
    if (!presentationMode && !readMode) return child;
    return Shortcuts(
      shortcuts: const {_exitActivator: _ExitImmersiveIntent()},
      child: Actions(
        actions: {
          _ExitImmersiveIntent: GuardedCallbackAction<_ExitImmersiveIntent>(
            allowWhileTyping: true,

            onInvoke: (_) {
              if (presentationMode) {
                onExit();
              } else if (readMode) {
                onExitReadMode?.call();
              }
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}

class _ExitImmersiveIntent extends Intent {
  const _ExitImmersiveIntent();
}
