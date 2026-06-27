import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Single source of truth for "the user is typing — leave the keys alone".
///
/// Every app/viewer keyboard handler (Shortcuts/Actions, CallbackShortcuts,
/// Focus.onKeyEvent, HardwareKeyboard handlers, pdfrx `onKey`) must consult
/// this guard. While a text field has focus, only a small allow-list of
/// document-level chords (Save, Print, Open, Find, Command palette) and
/// Escape reach app commands; letters, Delete/Backspace, arrows, and
/// Ctrl+A/C/V/X/Z/Y stay with the field.
abstract final class TextInputGuard {
  static int _claims = 0;

  /// Custom text surfaces that don't use [EditableText] can claim input while
  /// they are active. Returns a callback that releases the claim.
  static VoidCallback claim() {
    _claims++;
    var released = false;
    return () {
      if (released) return;
      released = true;
      _claims--;
    };
  }

  /// True while a text-accepting widget holds primary focus.
  static bool get isTyping {
    if (_claims > 0) return true;
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  static bool get _primaryPressed {
    final hw = HardwareKeyboard.instance;
    return defaultTargetPlatform == TargetPlatform.macOS
        ? hw.isMetaPressed
        : hw.isControlPressed;
  }

  static final Set<LogicalKeyboardKey> _chordsAllowedWhileTyping = {
    LogicalKeyboardKey.keyS,
    LogicalKeyboardKey.keyP,
    LogicalKeyboardKey.keyO,
    LogicalKeyboardKey.keyF,
    LogicalKeyboardKey.keyK,
  };

  /// Whether an app command bound to [key] may run right now.
  static bool allowsKey(LogicalKeyboardKey key) {
    if (!isTyping) return true;
    if (key == LogicalKeyboardKey.escape) return true;
    return _primaryPressed && _chordsAllowedWhileTyping.contains(key);
  }

  /// Whether an app command bound to [activator] may run right now.
  static bool allowsActivator(ShortcutActivator activator) {
    if (!isTyping) return true;
    if (activator is SingleActivator) {
      if (activator.trigger == LogicalKeyboardKey.escape) return true;
      final primary = defaultTargetPlatform == TargetPlatform.macOS
          ? activator.meta
          : activator.control;
      return primary &&
          !activator.alt &&
          _chordsAllowedWhileTyping.contains(activator.trigger);
    }
    return false;
  }

  /// Whether a key event may be handled by an app-level `onKeyEvent`.
  static bool allowsEvent(KeyEvent event) => allowsKey(event.logicalKey);

  /// Wraps a `Focus.onKeyEvent` handler so typing is never swallowed.
  static FocusOnKeyEventCallback guardFocusHandler(
    FocusOnKeyEventCallback handler,
  ) {
    return (node, event) {
      if (!allowsEvent(event)) return KeyEventResult.ignored;
      return handler(node, event);
    };
  }
}

/// Shorthand kept for older call sites.
bool isTextInputFocused() => TextInputGuard.isTyping;

/// Drop-in replacement for [CallbackShortcuts] that yields to text fields.
///
/// Unlike [CallbackShortcuts], a matched binding returns
/// [KeyEventResult.ignored] while typing, so the character reaches the field.
class GuardedCallbackShortcuts extends StatelessWidget {
  const GuardedCallbackShortcuts({
    super.key,
    required this.bindings,
    required this.child,
  });

  final Map<ShortcutActivator, VoidCallback> bindings;
  final Widget child;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    for (final entry in bindings.entries) {
      if (!entry.key.accepts(event, HardwareKeyboard.instance)) continue;
      if (!TextInputGuard.allowsActivator(entry.key)) {
        return KeyEventResult.ignored;
      }
      entry.value();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: child,
    );
  }
}

/// [CallbackAction] that disables itself while typing (unless [allowWhileTyping]).
///
/// A disabled action makes [Shortcuts] return [KeyEventResult.ignored], so the
/// key event continues to the focused text field.
class GuardedCallbackAction<T extends Intent> extends CallbackAction<T> {
  GuardedCallbackAction({
    required super.onInvoke,
    this.allowWhileTyping = false,
  });

  final bool allowWhileTyping;

  @override
  bool isEnabled(T intent) => allowWhileTyping || !TextInputGuard.isTyping;

  @override
  bool consumesKey(T intent) => isEnabled(intent);
}

/// Wraps a [HardwareKeyboard] handler so it never fires while typing.
KeyEventCallback guardHardwareKeyboardHandler(KeyEventCallback handler) {
  return (event) {
    if (!TextInputGuard.allowsEvent(event)) return false;
    return handler(event);
  };
}
