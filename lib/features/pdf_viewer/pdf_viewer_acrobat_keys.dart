import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What the viewer does for each Acrobat keyboard shortcut. A null handler
/// leaves that key unbound.
class PdfViewerAcrobatKeyHandlers {
  const PdfViewerAcrobatKeyHandlers({
    this.onActualSize,
    this.onZoomIn,
    this.onZoomOut,
    this.onGoToPage,
    this.onCloseDocument,
    this.onNextTab,
    this.onPreviousTab,
    this.onReopenTab,
    this.onSaveAs,
    this.onProperties,
    this.onReadMode,
    this.onFullScreen,
    this.onRotateClockwise,
    this.onRotateCounterclockwise,
    this.onToggleEdit,
    this.onToggleComment,
    this.onFirstPage,
    this.onLastPage,
    this.onToggleSidebar,
    this.onEscape,
  });

  final VoidCallback? onActualSize;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback? onGoToPage;
  final VoidCallback? onCloseDocument;
  final VoidCallback? onNextTab;
  final VoidCallback? onPreviousTab;
  final VoidCallback? onReopenTab;
  final VoidCallback? onSaveAs;
  final VoidCallback? onProperties;
  final VoidCallback? onReadMode;
  final VoidCallback? onFullScreen;
  final VoidCallback? onRotateClockwise;
  final VoidCallback? onRotateCounterclockwise;
  final VoidCallback? onToggleEdit;
  final VoidCallback? onToggleComment;
  final VoidCallback? onFirstPage;
  final VoidCallback? onLastPage;
  final VoidCallback? onToggleSidebar;
  final VoidCallback? onEscape;
}

/// One shortcut for the help dialog.
class AcrobatShortcutInfo {
  const AcrobatShortcutInfo(this.keys, this.action);

  final String keys;
  final String action;
}

/// Everything in the keyboard-shortcuts dialog, grouped like Acrobat's help.
const Map<String, List<AcrobatShortcutInfo>> kAcrobatShortcutHelp = {
  'Documents & tabs': [
    AcrobatShortcutInfo('Ctrl+O', 'Open a PDF'),
    AcrobatShortcutInfo('Ctrl+S', 'Save'),
    AcrobatShortcutInfo('Ctrl+Shift+S', 'Save as…'),
    AcrobatShortcutInfo('Ctrl+W', 'Close the document (tab)'),
    AcrobatShortcutInfo('Ctrl+Tab', 'Next tab'),
    AcrobatShortcutInfo('Ctrl+Shift+Tab', 'Previous tab'),
    AcrobatShortcutInfo('Ctrl+Shift+T', 'Reopen the last closed tab'),
    AcrobatShortcutInfo('Ctrl+P', 'Print'),
    AcrobatShortcutInfo('Ctrl+D', 'Document properties'),
  ],
  'Navigate': [
    AcrobatShortcutInfo('Ctrl+Shift+N', 'Go to page'),
    AcrobatShortcutInfo('Home / End', 'First / last page'),
    AcrobatShortcutInfo('Page Up / Page Down', 'Previous / next page'),
    AcrobatShortcutInfo('Ctrl+F', 'Find'),
    AcrobatShortcutInfo('F3 / Shift+F3', 'Next / previous match'),
  ],
  'View': [
    AcrobatShortcutInfo('Ctrl+0', 'Fit page'),
    AcrobatShortcutInfo('Ctrl+1', 'Actual size (100%)'),
    AcrobatShortcutInfo('Ctrl+2', 'Fit width'),
    AcrobatShortcutInfo('Ctrl++ / Ctrl+−', 'Zoom in / out'),
    AcrobatShortcutInfo('Ctrl+Wheel · pinch', 'Zoom at the pointer'),
    AcrobatShortcutInfo('Ctrl+H', 'Reading mode'),
    AcrobatShortcutInfo('Ctrl+L', 'Full screen'),
    AcrobatShortcutInfo('Ctrl+Shift++ / −', 'Rotate pages clockwise / counter'),
    AcrobatShortcutInfo('F4', 'Show / hide the page panel'),
  ],
  'Edit & comment': [
    AcrobatShortcutInfo('Ctrl+E', 'Edit PDF on / off'),
    AcrobatShortcutInfo('Ctrl+Shift+C', 'Comment bar on / off'),
    AcrobatShortcutInfo('Ctrl+Z / Ctrl+Y', 'Undo / redo'),
    AcrobatShortcutInfo('Ctrl+G / Ctrl+Shift+G', 'Group / ungroup objects'),
    AcrobatShortcutInfo('Delete', 'Delete the selected object or image'),
    AcrobatShortcutInfo('Arrow keys', 'Nudge the selected object'),
    AcrobatShortcutInfo('Esc', 'Leave the current tool'),
  ],
  'Tools (Alt+Shift+letter, never a bare key)': [
    AcrobatShortcutInfo('Alt+Shift+V', 'Select'),
    AcrobatShortcutInfo('Alt+Shift+T', 'Text box'),
    AcrobatShortcutInfo('Alt+Shift+N', 'Sticky note'),
    AcrobatShortcutInfo('Alt+Shift+H / U', 'Highlight / underline'),
    AcrobatShortcutInfo('Alt+Shift+D', 'Draw'),
    AcrobatShortcutInfo('Alt+Shift+R / L', 'Rectangle / line'),
    AcrobatShortcutInfo('Alt+Shift+K / I', 'Link / image'),
    AcrobatShortcutInfo('Alt+Shift+S', 'Sign'),
    AcrobatShortcutInfo('Alt+Shift+C', 'Crop'),
  ],
  'Everywhere': [
    AcrobatShortcutInfo('Ctrl+K', 'Command palette'),
  ],
};

bool _mac() => defaultTargetPlatform == TargetPlatform.macOS;

SingleActivator _p(LogicalKeyboardKey k, {bool shift = false}) =>
    SingleActivator(k, control: !_mac(), meta: _mac(), shift: shift);

/// Acrobat keyboard shortcuts for the open viewer (modifier combos only, so
/// they never fight with typing).
class PdfViewerAcrobatKeys extends StatelessWidget {
  const PdfViewerAcrobatKeys({
    super.key,
    required this.handlers,
    required this.child,
  });

  final PdfViewerAcrobatKeyHandlers handlers;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final h = handlers;
    final b = <ShortcutActivator, VoidCallback>{
      if (h.onActualSize != null) ...{
        _p(LogicalKeyboardKey.digit1): h.onActualSize!,
        _p(LogicalKeyboardKey.numpad1): h.onActualSize!,
      },
      if (h.onZoomIn != null) ...{
        _p(LogicalKeyboardKey.equal): h.onZoomIn!,
        _p(LogicalKeyboardKey.numpadAdd): h.onZoomIn!,
        _p(LogicalKeyboardKey.add): h.onZoomIn!,
      },
      if (h.onZoomOut != null) ...{
        _p(LogicalKeyboardKey.minus): h.onZoomOut!,
        _p(LogicalKeyboardKey.numpadSubtract): h.onZoomOut!,
      },
      if (h.onGoToPage != null)
        _p(LogicalKeyboardKey.keyN, shift: true): h.onGoToPage!,
      if (h.onCloseDocument != null) _p(LogicalKeyboardKey.keyW): h.onCloseDocument!,
      if (h.onNextTab != null)
        const SingleActivator(LogicalKeyboardKey.tab, control: true): h.onNextTab!,
      if (h.onPreviousTab != null)
        const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true):
            h.onPreviousTab!,
      if (h.onReopenTab != null)
        _p(LogicalKeyboardKey.keyT, shift: true): h.onReopenTab!,
      if (h.onSaveAs != null) _p(LogicalKeyboardKey.keyS, shift: true): h.onSaveAs!,
      if (h.onProperties != null) _p(LogicalKeyboardKey.keyD): h.onProperties!,
      if (h.onReadMode != null) _p(LogicalKeyboardKey.keyH): h.onReadMode!,
      if (h.onFullScreen != null) _p(LogicalKeyboardKey.keyL): h.onFullScreen!,
      if (h.onRotateClockwise != null) ...{
        _p(LogicalKeyboardKey.equal, shift: true): h.onRotateClockwise!,
        _p(LogicalKeyboardKey.add, shift: true): h.onRotateClockwise!,
      },
      if (h.onRotateCounterclockwise != null)
        _p(LogicalKeyboardKey.minus, shift: true): h.onRotateCounterclockwise!,
      if (h.onToggleEdit != null) _p(LogicalKeyboardKey.keyE): h.onToggleEdit!,
      if (h.onToggleComment != null)
        _p(LogicalKeyboardKey.keyC, shift: true): h.onToggleComment!,
      if (h.onToggleSidebar != null)
        const SingleActivator(LogicalKeyboardKey.f4): h.onToggleSidebar!,
    };
    return CallbackShortcuts(bindings: b, child: child);
  }
}
