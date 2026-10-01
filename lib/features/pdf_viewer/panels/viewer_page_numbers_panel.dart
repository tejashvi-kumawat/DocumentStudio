import 'package:document_studio/features/pdf_viewer/pdf_page_labels_dialog.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:flutter/material.dart';

/// Page labels for the open PDF (scope, style, prefix, start, preview).
class ViewerPageNumbersPanel extends StatelessWidget {
  const ViewerPageNumbersPanel({
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
    return PdfPageLabelsEditor(
      key: ValueKey(handoff.file.path),
      handoff: handoff,
      pageCount: pageCount,
      selectedPages1Based: selectedPages1Based,
    );
  }
}
