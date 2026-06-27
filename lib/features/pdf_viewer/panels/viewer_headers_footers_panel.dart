import 'package:document_studio/features/pdf_markup/headers_footers_screen.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:flutter/material.dart';

/// Viewer side panel for headers & footers — the embedded header/footer editor
/// with the live on-page preview.
class ViewerHeadersFootersPanel extends StatelessWidget {
  const ViewerHeadersFootersPanel({
    super.key,
    required this.handoff,
    this.pageCount,
    this.selectedPages1Based = const {},
  });

  final PdfViewerDocumentHandoff handoff;
  final int? pageCount;
  final Set<int> selectedPages1Based;

  @override
  Widget build(BuildContext context) {
    return HeadersFootersScreen(
      key: ValueKey(handoff.file.path),
      initialFile: handoff.file,
      initialPassword: handoff.password,
      embedInViewerPanel: true,
    );
  }
}
