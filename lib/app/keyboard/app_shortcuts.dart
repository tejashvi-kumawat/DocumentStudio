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

/// Tab commands (browser / Safari style).
class CloseTabIntent extends Intent {
  const CloseTabIntent();
}

class NewTabIntent extends Intent {
  const NewTabIntent();
}

class ReopenTabIntent extends Intent {
  const ReopenTabIntent();
}

class CycleTabIntent extends Intent {
  const CycleTabIntent(this.delta);
  final int delta;
}

class JumpToTabIntent extends Intent {
  const JumpToTabIntent(this.index); // 0-based; -1 = last
  final int index;
}

class OpenSettingsIntent extends Intent {
  const OpenSettingsIntent();
}

class NewDocumentIntent extends Intent {
  const NewDocumentIntent();
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
  _primaryModifier(LogicalKeyboardKey.keyW): const CloseTabIntent(),
  _primaryModifier(LogicalKeyboardKey.f4): const CloseTabIntent(),
  _primaryModifier(LogicalKeyboardKey.keyT): const NewTabIntent(),
  _primaryModifier(LogicalKeyboardKey.keyT, shift: true):
      const ReopenTabIntent(),
  const SingleActivator(LogicalKeyboardKey.tab, control: true):
      const CycleTabIntent(1),
  const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true):
      const CycleTabIntent(-1),
  _primaryModifier(LogicalKeyboardKey.pageDown): const CycleTabIntent(1),
  _primaryModifier(LogicalKeyboardKey.pageUp): const CycleTabIntent(-1),
  for (var i = 1; i <= 8; i++)
    _primaryModifier(LogicalKeyboardKey(0x00000000030 + i)): JumpToTabIntent(
      i - 1,
    ),
  _primaryModifier(LogicalKeyboardKey.digit9): const JumpToTabIntent(-1),
  _primaryModifier(LogicalKeyboardKey.comma): const OpenSettingsIntent(),
  _primaryModifier(LogicalKeyboardKey.keyN): const NewDocumentIntent(),
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
    this.onCloseTab,
    this.onNewTab,
    this.onReopenTab,
    this.onCycleTab,
    this.onJumpToTab,
    this.onSettings,
    this.onNewDocument,
  });

  final VoidCallback? onCloseTab;
  final VoidCallback? onNewTab;
  final VoidCallback? onReopenTab;
  final ValueChanged<int>? onCycleTab;
  final ValueChanged<int>? onJumpToTab;
  final VoidCallback? onSettings;
  final VoidCallback? onNewDocument;

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
    CloseTabIntent: GuardedCallbackAction<CloseTabIntent>(
      allowWhileTyping: true,
      onInvoke: (_) {
        onCloseTab?.call();
        return null;
      },
    ),
    NewTabIntent: GuardedCallbackAction<NewTabIntent>(
      allowWhileTyping: true,
      onInvoke: (_) {
        onNewTab?.call();
        return null;
      },
    ),
    ReopenTabIntent: GuardedCallbackAction<ReopenTabIntent>(
      allowWhileTyping: true,
      onInvoke: (_) {
        onReopenTab?.call();
        return null;
      },
    ),
    CycleTabIntent: GuardedCallbackAction<CycleTabIntent>(
      allowWhileTyping: true,
      onInvoke: (i) {
        onCycleTab?.call(i.delta);
        return null;
      },
    ),
    JumpToTabIntent: GuardedCallbackAction<JumpToTabIntent>(
      allowWhileTyping: true,
      onInvoke: (i) {
        onJumpToTab?.call(i.index);
        return null;
      },
    ),
    OpenSettingsIntent: GuardedCallbackAction<OpenSettingsIntent>(
      allowWhileTyping: true,
      onInvoke: (_) {
        onSettings?.call();
        return null;
      },
    ),
    NewDocumentIntent: GuardedCallbackAction<NewDocumentIntent>(
      allowWhileTyping: true,
      onInvoke: (_) {
        onNewDocument?.call();
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
