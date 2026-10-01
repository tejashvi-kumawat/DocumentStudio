import 'package:document_studio/features/pdf_viewer/document_tabs_controller.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_markup_burn_panel.dart';
import 'package:document_studio/features/pdf_viewer/pdf_page_labels.dart';
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/infrastructure/ocr/pdf_background_ocr_index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tab state for the PDF viewer feature (scoped to this feature only).
final documentTabsControllerProvider = Provider<DocumentTabsController>((ref) {
  ref.keepAlive();
  final controller = DocumentTabsController();
  ref.onDispose(controller.dispose);
  return controller;
});

/// Live-page tool placement/ink session (handles draw on the visible PdfViewer).
final viewerLiveToolSessionProvider = Provider<ViewerLiveToolSession>((ref) {
  ref.keepAlive();
  final session = ViewerLiveToolSession();
  ref.onDispose(session.dispose);
  return session;
});

class ViewerAutosaveNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void setEnabled(bool value) => state = value;
}

/// Autosave: when on, Apply writes in place with a quiet status (default ON).
final viewerAutosaveEnabledProvider =
    NotifierProvider<ViewerAutosaveNotifier, bool>(ViewerAutosaveNotifier.new);

class ViewerSaveOcrIntoFileNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setEnabled(bool value) => state = value;
}

/// When autosave is on, optionally rewrite OCR text layer into the open file.
final viewerSaveOcrIntoFileProvider =
    NotifierProvider<ViewerSaveOcrIntoFileNotifier, bool>(
      ViewerSaveOcrIntoFileNotifier.new,
    );

class ViewerMarkupBurnKindNotifier extends Notifier<MarkupBurnKind> {
  @override
  MarkupBurnKind build() => MarkupBurnKind.highlight;

  void setKind(MarkupBurnKind kind) => state = kind;
}

/// Initial mark type when opening [ViewerToolId.markupBurn] via shortcuts.
final viewerMarkupBurnKindProvider =
    NotifierProvider<ViewerMarkupBurnKindNotifier, MarkupBurnKind>(
      ViewerMarkupBurnKindNotifier.new,
    );

class ViewerRulersVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;

  void setVisible(bool value) => state = value;
}

/// Page rulers overlay (PDF points). Toggling must not remount PdfViewer.
final viewerRulersVisibleProvider =
    NotifierProvider<ViewerRulersVisibleNotifier, bool>(
      ViewerRulersVisibleNotifier.new,
    );

/// Page labels just written into the working copy, so the status bar can
/// update without reloading the viewer.
class ViewerPageLabelsNotice {
  const ViewerPageLabelsNotice({
    required this.filePath,
    required this.revision,
    required this.ranges,
  });

  final String filePath;
  final int revision;
  final List<PdfPageLabelRange> ranges;
}

class ViewerPageLabelsNotifier extends Notifier<ViewerPageLabelsNotice?> {
  @override
  ViewerPageLabelsNotice? build() => null;

  void publish({
    required String filePath,
    required int revision,
    required List<PdfPageLabelRange> ranges,
  }) {
    state = ViewerPageLabelsNotice(
      filePath: filePath,
      revision: revision,
      ranges: ranges,
    );
  }
}

final viewerPageLabelsProvider =
    NotifierProvider<ViewerPageLabelsNotifier, ViewerPageLabelsNotice?>(
      ViewerPageLabelsNotifier.new,
    );

class ViewerBackgroundOcrIndexNotifier
    extends Notifier<PdfBackgroundOcrIndex?> {
  @override
  PdfBackgroundOcrIndex? build() => null;

  void setIndex(PdfBackgroundOcrIndex? index) => state = index;
}

/// In-memory OCR index used by Find and redact search (no file rewrite).
final viewerBackgroundOcrIndexProvider =
    NotifierProvider<ViewerBackgroundOcrIndexNotifier, PdfBackgroundOcrIndex?>(
      ViewerBackgroundOcrIndexNotifier.new,
    );
