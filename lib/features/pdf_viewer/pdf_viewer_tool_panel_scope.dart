import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:flutter/material.dart';

/// Opens [ViewerToolId] panels on the current viewer tab instead of routing away.
class PdfViewerToolPanelScope extends InheritedWidget {
  const PdfViewerToolPanelScope({
    super.key,
    required this.openViewerToolPanel,
    required this.closeViewerToolPanel,
    required super.child,
  });

  final void Function(ViewerToolId tool) openViewerToolPanel;
  final VoidCallback closeViewerToolPanel;

  static PdfViewerToolPanelScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<PdfViewerToolPanelScope>();
  }

  @override
  bool updateShouldNotify(PdfViewerToolPanelScope oldWidget) => false;
}

void openViewerToolPanel(BuildContext context, ViewerToolId tool) {
  PdfViewerToolPanelScope.maybeOf(context)?.openViewerToolPanel(tool);
}

void closeViewerToolPanel(BuildContext context) {
  PdfViewerToolPanelScope.maybeOf(context)?.closeViewerToolPanel();
}

/// When the viewer panel scope is present, open the panel; otherwise [orPush].
void openViewerToolPanelOr(
  BuildContext context,
  ViewerToolId tool,
  VoidCallback orPush,
) {
  final scope = PdfViewerToolPanelScope.maybeOf(context);
  if (scope != null) {
    scope.openViewerToolPanel(tool);
    return;
  }
  orPush();
}
