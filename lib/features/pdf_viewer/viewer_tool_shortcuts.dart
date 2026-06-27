import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// Viewer tool shortcut ids (PDF tab focused).
enum ViewerToolShortcutId {
  addText,
  crop,
  rotateRight,
  rotateLeft,
  placeImage,
  placeSignature,
  draw,
  highlight,
  underline,
  stickyNote,
  rectangle,
  line,
  addLink,
  toggleRulers,
  cancelTool,
}

/// Human-readable activator labels for tooltips.
String viewerToolShortcutTooltip(ViewerToolShortcutId id) {
  final meta = defaultTargetPlatform == TargetPlatform.macOS;
  final mod = meta ? '⌘' : 'Ctrl';
  return switch (id) {
    ViewerToolShortcutId.addText => 'T',
    ViewerToolShortcutId.crop => 'Alt+C',
    ViewerToolShortcutId.rotateRight => '$mod+R',
    ViewerToolShortcutId.rotateLeft => '$mod+L',
    ViewerToolShortcutId.placeImage => 'I',
    ViewerToolShortcutId.placeSignature => 'S',
    ViewerToolShortcutId.draw => 'D',
    ViewerToolShortcutId.highlight => 'H',
    ViewerToolShortcutId.underline => 'U',
    ViewerToolShortcutId.stickyNote => 'K',
    ViewerToolShortcutId.rectangle => 'R',
    ViewerToolShortcutId.line => 'Shift+L',
    ViewerToolShortcutId.addLink => 'L',
    ViewerToolShortcutId.toggleRulers => 'Alt+R',
    ViewerToolShortcutId.cancelTool => 'Esc',
  };
}

ShortcutActivator _primary(LogicalKeyboardKey key, {bool shift = false}) {
  final useMeta = defaultTargetPlatform == TargetPlatform.macOS;
  return SingleActivator(
    key,
    control: !useMeta,
    meta: useMeta,
    shift: shift,
  );
}

/// Canonical map: activator → shortcut id (for tests and CallbackShortcuts).
Map<ShortcutActivator, ViewerToolShortcutId> get viewerToolShortcutMap => {
      const SingleActivator(LogicalKeyboardKey.keyT):
          ViewerToolShortcutId.addText,
      const SingleActivator(LogicalKeyboardKey.keyC, alt: true):
          ViewerToolShortcutId.crop,
      // Fallback when Alt+C is eaten by the compositor / IME.
      const SingleActivator(LogicalKeyboardKey.keyC, control: true, alt: true):
          ViewerToolShortcutId.crop,
      _primary(LogicalKeyboardKey.keyR): ViewerToolShortcutId.rotateRight,
      _primary(LogicalKeyboardKey.keyL): ViewerToolShortcutId.rotateLeft,
      const SingleActivator(LogicalKeyboardKey.keyI):
          ViewerToolShortcutId.placeImage,
      const SingleActivator(LogicalKeyboardKey.keyS):
          ViewerToolShortcutId.placeSignature,
      const SingleActivator(LogicalKeyboardKey.keyD): ViewerToolShortcutId.draw,
      const SingleActivator(LogicalKeyboardKey.keyH):
          ViewerToolShortcutId.highlight,
      const SingleActivator(LogicalKeyboardKey.keyU):
          ViewerToolShortcutId.underline,
      const SingleActivator(LogicalKeyboardKey.keyK):
          ViewerToolShortcutId.stickyNote,
      const SingleActivator(LogicalKeyboardKey.keyR):
          ViewerToolShortcutId.rectangle,
      const SingleActivator(LogicalKeyboardKey.keyL, shift: true):
          ViewerToolShortcutId.line,
      const SingleActivator(LogicalKeyboardKey.escape):
          ViewerToolShortcutId.cancelTool,
    };

/// True when character tool keys should be ignored (typing in a field).
bool viewerToolShortcutsBlockedByFocus() {
  final focus = FocusManager.instance.primaryFocus;
  if (focus == null) return false;
  final ctx = focus.context;
  if (ctx == null) return false;
  return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
}
