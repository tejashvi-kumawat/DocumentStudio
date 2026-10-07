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

/// Tool shortcuts are always Alt+Shift+<letter>. A bare letter never opens a
/// tool (typing, dialogs and text fields stay safe) and these chords do not
/// collide with the Ctrl shortcuts (zoom, tabs, save, find).
const _toolMods = (alt: true, shift: true);

SingleActivator _tool(LogicalKeyboardKey key) =>
    SingleActivator(key, alt: _toolMods.alt, shift: _toolMods.shift);

String _letter(LogicalKeyboardKey key) => key.keyLabel.toUpperCase();

LogicalKeyboardKey _keyFor(ViewerToolShortcutId id) => switch (id) {
  ViewerToolShortcutId.addText => LogicalKeyboardKey.keyT,
  ViewerToolShortcutId.crop => LogicalKeyboardKey.keyC,
  ViewerToolShortcutId.placeImage => LogicalKeyboardKey.keyI,
  ViewerToolShortcutId.placeSignature => LogicalKeyboardKey.keyS,
  ViewerToolShortcutId.draw => LogicalKeyboardKey.keyD,
  ViewerToolShortcutId.highlight => LogicalKeyboardKey.keyH,
  ViewerToolShortcutId.underline => LogicalKeyboardKey.keyU,
  ViewerToolShortcutId.stickyNote => LogicalKeyboardKey.keyN,
  ViewerToolShortcutId.rectangle => LogicalKeyboardKey.keyR,
  ViewerToolShortcutId.line => LogicalKeyboardKey.keyL,
  ViewerToolShortcutId.addLink => LogicalKeyboardKey.keyK,
  ViewerToolShortcutId.toggleRulers => LogicalKeyboardKey.keyM,
  ViewerToolShortcutId.rotateRight ||
  ViewerToolShortcutId.rotateLeft ||
  ViewerToolShortcutId.cancelTool => LogicalKeyboardKey.escape,
};

/// Human-readable activator labels for tooltips (shown on hover).
String viewerToolShortcutTooltip(ViewerToolShortcutId id) {
  final meta = defaultTargetPlatform == TargetPlatform.macOS;
  switch (id) {
    case ViewerToolShortcutId.cancelTool:
      return 'Esc';
    case ViewerToolShortcutId.rotateRight:
      return meta ? '⌘⇧+' : 'Ctrl+Shift++';
    case ViewerToolShortcutId.rotateLeft:
      return meta ? '⌘⇧−' : 'Ctrl+Shift+−';
    default:
      return meta
          ? '⌥⇧${_letter(_keyFor(id))}'
          : 'Alt+Shift+${_letter(_keyFor(id))}';
  }
}

/// Canonical map: activator → shortcut id (for tests and CallbackShortcuts).
Map<ShortcutActivator, ViewerToolShortcutId> get viewerToolShortcutMap => {
  for (final id in ViewerToolShortcutId.values)
    if (id != ViewerToolShortcutId.cancelTool &&
        id != ViewerToolShortcutId.rotateRight &&
        id != ViewerToolShortcutId.rotateLeft)
      _tool(_keyFor(id)): id,
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
