import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Handlers registered by the active [PdfViewerScreen] for global shortcuts.
class ViewerShortcutActions {
  const ViewerShortcutActions({
    this.onPrint,
    this.onFind,
    this.onOpen,
    this.onUndo,
    this.onRedo,
    this.onSave,
    this.onAddText,
    this.onCrop,
    this.onRotatePageRight,
    this.onRotatePageLeft,
    this.onPlaceImage,
    this.onPlaceSignature,
    this.onDraw,
    this.onHighlight,
    this.onUnderline,
    this.onStickyNote,
    this.onRectangle,
    this.onLine,
    this.onAddLink,
    this.onToggleRulers,
    this.onCancelTool,
  });

  final VoidCallback? onPrint;
  final VoidCallback? onFind;
  final VoidCallback? onOpen;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onSave;
  final VoidCallback? onAddText;
  final VoidCallback? onCrop;
  final VoidCallback? onRotatePageRight;
  final VoidCallback? onRotatePageLeft;
  final VoidCallback? onPlaceImage;
  final VoidCallback? onPlaceSignature;
  final VoidCallback? onDraw;
  final VoidCallback? onHighlight;
  final VoidCallback? onUnderline;
  final VoidCallback? onStickyNote;
  final VoidCallback? onRectangle;
  final VoidCallback? onLine;
  final VoidCallback? onAddLink;
  final VoidCallback? onToggleRulers;
  final VoidCallback? onCancelTool;
}

class ViewerShortcutActionsNotifier extends Notifier<ViewerShortcutActions> {
  @override
  ViewerShortcutActions build() => const ViewerShortcutActions();

  void setActions(ViewerShortcutActions actions) => state = actions;

  void clear() => state = const ViewerShortcutActions();
}

final viewerShortcutActionsProvider =
    NotifierProvider<ViewerShortcutActionsNotifier, ViewerShortcutActions>(
  ViewerShortcutActionsNotifier.new,
);
