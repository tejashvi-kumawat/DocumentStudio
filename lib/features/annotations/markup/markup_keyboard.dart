import 'package:document_studio/app/keyboard/text_input_guard.dart';
import 'package:document_studio/domain/pdf_markup/markup_objects.dart';
import 'package:document_studio/features/annotations/markup/markup_editor_controller.dart';
import 'package:document_studio/features/annotations/markup/markup_format_bar.dart';
import 'package:document_studio/features/annotations/markup/markup_text_layout.dart';
import 'package:document_studio/features/annotations/markup/markup_tool.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Lets the page viewer's own key handler (arrows = page navigation) step
/// aside while the markup editor has a selection to nudge/delete.
abstract final class MarkupKeyRouting {
  static bool Function(LogicalKeyboardKey key)? _claim;

  static void register(bool Function(LogicalKeyboardKey key)? claim) =>
      _claim = claim;

  static bool claims(LogicalKeyboardKey key) => _claim?.call(key) ?? false;
}

bool _primary() {
  final hw = HardwareKeyboard.instance;
  return defaultTargetPlatform == TargetPlatform.macOS
      ? hw.isMetaPressed
      : hw.isControlPressed;
}

final Set<LogicalKeyboardKey> _selectionKeys = {
  LogicalKeyboardKey.delete,
  LogicalKeyboardKey.backspace,
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.escape,
};

/// Toggles bold / italic / underline ([key] B, I or U) on the selected text
/// boxes. Returns false when no text box is selected.
bool toggleMarkupTextStyle(MarkupEditorController c, LogicalKeyboardKey key) {
  final texts = c.selectedObjects.whereType<TextBoxMarkup>().toList();
  if (texts.isEmpty) return false;
  final first = texts.first;
  c.updateSelected((o) {
    if (o is! TextBoxMarkup) return o;
    return relayoutTextBox(switch (key) {
      LogicalKeyboardKey.keyB => o.copyWith(bold: !first.bold),
      LogicalKeyboardKey.keyI => o.copyWith(italic: !first.italic),
      _ => o.copyWith(underline: !first.underline),
    });
  });
  return true;
}

/// Editor keyboard: Delete/Backspace, arrow nudges, Ctrl/⌘ C X V D A Z Y,
/// Enter (finish polygon / edit text), Escape, and single-letter tools.
/// Everything is ignored while a text field has focus.
class MarkupKeyboardScope extends StatefulWidget {
  const MarkupKeyboardScope({
    super.key,
    required this.controller,
    required this.currentPage,
    required this.child,
    this.onUndo,
    this.onRedo,
  });

  final MarkupEditorController controller;
  final int Function() currentPage;
  final Widget child;

  /// Document-level fallbacks when the editor has nothing to undo/redo.
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  @override
  State<MarkupKeyboardScope> createState() => _MarkupKeyboardScopeState();
}

class _MarkupKeyboardScopeState extends State<MarkupKeyboardScope> {
  MarkupEditorController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    MarkupKeyRouting.register(_claims);
  }

  @override
  void dispose() {
    MarkupKeyRouting.register(null);
    super.dispose();
  }

  bool _claims(LogicalKeyboardKey key) {
    if (TextInputGuard.isTyping || !c.editMode) return false;
    if (c.pendingPolygon != null) return _selectionKeys.contains(key);
    return c.selection.isNotEmpty && _selectionKeys.contains(key);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final repeat = event is KeyRepeatEvent;
    if (_primary()) {
      final shift = HardwareKeyboard.instance.isShiftPressed;
      if (repeat) return KeyEventResult.ignored;
      switch (key) {
        case LogicalKeyboardKey.keyZ:
          if (!c.editMode && !c.canUndo && !c.canRedo) {
            return KeyEventResult.ignored;
          }
          if (shift) {
            if (!c.redo()) widget.onRedo?.call();
          } else {
            if (!c.undo()) widget.onUndo?.call();
          }
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyY:
          if (!c.redo()) widget.onRedo?.call();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyC:
          if (c.selection.isEmpty) return KeyEventResult.ignored;
          c.copySelection();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyX:
          if (c.selection.isEmpty) return KeyEventResult.ignored;
          c.cutSelection();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyV:
          if (!c.hasClipboard) return KeyEventResult.ignored;
          c.paste(page: c.selectionPage ?? widget.currentPage());
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyD:
          if (c.selection.isEmpty) return KeyEventResult.ignored;
          c.duplicateSelection();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyA:
          if (!c.editMode) return KeyEventResult.ignored;
          c.selectAllOnPage(c.selectionPage ?? widget.currentPage());
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyG:
          if (!c.editMode || c.selection.isEmpty) return KeyEventResult.ignored;
          if (shift) {
            c.ungroupSelection();
          } else {
            c.groupSelection();
          }
          return KeyEventResult.handled;
        case LogicalKeyboardKey.bracketRight:
          if (!c.editMode || c.selection.isEmpty) return KeyEventResult.ignored;
          shift ? c.bringToFront() : c.bringForward();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.bracketLeft:
          if (!c.editMode || c.selection.isEmpty) return KeyEventResult.ignored;
          shift ? c.sendToBack() : c.sendBackward();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyB:
        case LogicalKeyboardKey.keyI:
        case LogicalKeyboardKey.keyU:
          if (!c.editMode) return KeyEventResult.ignored;
          return toggleMarkupTextStyle(c, key)
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
      }
      return KeyEventResult.ignored;
    }
    if (!c.editMode) return KeyEventResult.ignored;

    if (c.pendingPolygon != null) {
      if (key == LogicalKeyboardKey.enter) {
        c.finishPolygon();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        c.cancelPolygon();
        return KeyEventResult.handled;
      }
    }

    final sel = c.selectedObjects;
    switch (key) {
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        if (sel.isEmpty) return KeyEventResult.ignored;
        c.deleteSelected();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        if (sel.isNotEmpty) {
          c.clearSelection();
          return KeyEventResult.handled;
        }
        if (c.tool != MarkupTool.select) {
          c.setTool(MarkupTool.select);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.enter:
        if (sel.length == 1 && sel.first is TextBoxMarkup) {
          c.startEditing(sel.first.id);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.arrowDown:
        if (sel.isEmpty) return KeyEventResult.ignored;
        final step = HardwareKeyboard.instance.isShiftPressed ? 10.0 : 1.0;
        final d = switch (key) {
          LogicalKeyboardKey.arrowLeft => Offset(-step, 0),
          LogicalKeyboardKey.arrowRight => Offset(step, 0),
          LogicalKeyboardKey.arrowUp => Offset(0, -step),
          _ => Offset(0, step),
        };
        c.updateSelected((o) => o.canMove ? o.moved(d) : o);
        return KeyEventResult.handled;
    }
    if (repeat) return KeyEventResult.ignored;
    // Tool keys need Alt+Shift so a bare letter never switches tools.
    final hw = HardwareKeyboard.instance;
    if (!(hw.isAltPressed && hw.isShiftPressed) ||
        hw.isControlPressed ||
        hw.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final tool = switch (key) {
      LogicalKeyboardKey.keyV => MarkupTool.select,
      LogicalKeyboardKey.keyT => MarkupTool.text,
      LogicalKeyboardKey.keyN => MarkupTool.note,
      LogicalKeyboardKey.keyH => MarkupTool.highlight,
      LogicalKeyboardKey.keyU => MarkupTool.underline,
      LogicalKeyboardKey.keyD => MarkupTool.pen,
      LogicalKeyboardKey.keyR => MarkupTool.rectangle,
      LogicalKeyboardKey.keyL => MarkupTool.line,
      LogicalKeyboardKey.keyK => MarkupTool.link,
      LogicalKeyboardKey.keyI => MarkupTool.image,
      LogicalKeyboardKey.keyE => MarkupTool.eraser,
      _ => null,
    };
    if (tool == null) return KeyEventResult.ignored;
    c.setTool(tool);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: c.keyboardFocus,
      onKeyEvent: TextInputGuard.guardFocusHandler(_onKey),
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          Positioned(
            key: const Key('markup_format_bar_dock'),
            left: 0,
            right: 0,
            bottom: markupFormatDockBottom(context),
            child: MarkupFormatDock(controller: c),
          ),
        ],
      ),
    );
  }
}
