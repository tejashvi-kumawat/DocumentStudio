import 'package:document_studio/app/keyboard/text_input_guard.dart';
import 'package:document_studio/app/keyboard/app_shortcuts.dart';
import 'package:document_studio/features/command_palette/ds_command_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shell-level keyboard scope for tabbed routes inside [DsAppShell].
///
/// Ensures ⌘/Ctrl+K opens the command palette when focus is on Home, Tools,
/// or Settings (nested branch navigators do not inherit the root [AppShortcuts]
/// focus). Global open/print/find remain on [AppShortcuts] at the app root.
class DsShellKeyboardScope extends StatelessWidget {
  const DsShellKeyboardScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            const OpenCommandPaletteIntent(),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            const OpenCommandPaletteIntent(),
      },
      child: Actions(
        actions: {
          OpenCommandPaletteIntent:
              GuardedCallbackAction<OpenCommandPaletteIntent>(
                allowWhileTyping: true,

                onInvoke: (_) {
                  showDocumentStudioCommandPalette(context);
                  return null;
                },
              ),
        },
        child: child,
      ),
    );
  }
}
