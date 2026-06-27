import 'package:document_studio/app/keyboard/text_input_guard.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Open file (Ctrl+O / ⌘O).
class OpenDocumentIntent extends Intent {
  const OpenDocumentIntent();
}

/// Print active document (Ctrl+P / ⌘P).
class PrintDocumentIntent extends Intent {
  const PrintDocumentIntent();
}

/// Find in document (Ctrl+F / ⌘F).
class FindInDocumentIntent extends Intent {
  const FindInDocumentIntent();
}

/// Command palette (Ctrl+K / ⌘K).
class OpenCommandPaletteIntent extends Intent {
  const OpenCommandPaletteIntent();
}

/// Undo (Ctrl+Z / ⌘Z).
class UndoDocumentIntent extends Intent {
  const UndoDocumentIntent();
}

/// Redo (Ctrl+Shift+Z / ⌘Shift+Z, or Ctrl+Y).
class RedoDocumentIntent extends Intent {
  const RedoDocumentIntent();
}

/// Save (Ctrl+S / ⌘S).
class SaveDocumentIntent extends Intent {
  const SaveDocumentIntent();
}

ShortcutActivator _primaryModifier(
  LogicalKeyboardKey key, {
  bool shift = false,
}) {
  final useMeta = defaultTargetPlatform == TargetPlatform.macOS;
  return SingleActivator(key, control: !useMeta, meta: useMeta, shift: shift);
}

/// Global shortcut bindings for Document Studio (see docs/UI-UX.md).
Map<ShortcutActivator, Intent> get appShortcutBindings => {
  _primaryModifier(LogicalKeyboardKey.keyO): const OpenDocumentIntent(),
  _primaryModifier(LogicalKeyboardKey.keyP): const PrintDocumentIntent(),
  _primaryModifier(LogicalKeyboardKey.keyF): const FindInDocumentIntent(),
  _primaryModifier(LogicalKeyboardKey.keyK): const OpenCommandPaletteIntent(),
  _primaryModifier(LogicalKeyboardKey.keyZ): const UndoDocumentIntent(),
  _primaryModifier(LogicalKeyboardKey.keyZ, shift: true):
      const RedoDocumentIntent(),
  const SingleActivator(LogicalKeyboardKey.keyY, control: true):
      const RedoDocumentIntent(),
  _primaryModifier(LogicalKeyboardKey.keyS): const SaveDocumentIntent(),
};

/// Wraps [child] with [Shortcuts] and [Actions] for shell-level keyboard commands.
///
/// Handlers are optional; when omitted, the shortcut is still registered but
/// has no effect until callbacks are wired by the app root.
class AppShortcuts extends StatelessWidget {
  const AppShortcuts({
    super.key,
    required this.child,
    this.onOpen,
    this.onPrint,
    this.onFind,
    this.onCommandPalette,
    this.onUndo,
    this.onRedo,
    this.onSave,
  });

  final Widget child;
  final VoidCallback? onOpen;
  final VoidCallback? onPrint;
  final VoidCallback? onFind;
  final VoidCallback? onCommandPalette;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onSave;

  Map<Type, Action<Intent>> get _actions => {
    OpenDocumentIntent: GuardedCallbackAction<OpenDocumentIntent>(
      allowWhileTyping: true,
      onInvoke: (_) {
        onOpen?.call();
        return null;
      },
    ),
    PrintDocumentIntent: GuardedCallbackAction<PrintDocumentIntent>(
      allowWhileTyping: true,
      onInvoke: (_) {
        onPrint?.call();
        return null;
      },
    ),
    FindInDocumentIntent: GuardedCallbackAction<FindInDocumentIntent>(
      allowWhileTyping: true,
      onInvoke: (_) {
        onFind?.call();
        return null;
      },
    ),
    OpenCommandPaletteIntent: GuardedCallbackAction<OpenCommandPaletteIntent>(
      allowWhileTyping: true,
      onInvoke: (_) {
        onCommandPalette?.call();
        return null;
      },
    ),
    UndoDocumentIntent: GuardedCallbackAction<UndoDocumentIntent>(
      onInvoke: (_) {
        onUndo?.call();
        return null;
      },
    ),
    RedoDocumentIntent: GuardedCallbackAction<RedoDocumentIntent>(
      onInvoke: (_) {
        onRedo?.call();
        return null;
      },
    ),
    SaveDocumentIntent: GuardedCallbackAction<SaveDocumentIntent>(
      allowWhileTyping: true,
      onInvoke: (_) {
        onSave?.call();
        return null;
      },
    ),
  };

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: appShortcutBindings,
      child: Actions(
        actions: _actions,
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}
