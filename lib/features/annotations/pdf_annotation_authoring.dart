import 'package:document_studio/features/annotations/annotation_port.dart';
import 'package:document_studio/features/annotations/markup/markup_providers.dart';
import 'package:document_studio/features/annotations/markup/markup_tool.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_tool_panel_scope.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Markup entry points: open the viewer's markup editor with a tool armed.
/// Marks are saved as real, editable PDF annotations.
class PdfAnnotationAuthoring {
  PdfAnnotationAuthoring._();

  static final PdfAnnotationCapabilities capabilities =
      const PdfAnnotationCapabilities(
    canList: true,
    canAuthor: true,
    canPersist: true,
    listLimitation:
        'Markup made in Document Studio stays editable. Annotations from '
        'other apps are listed and can be deleted.',
  );

  static void open(BuildContext context, MarkupTool tool) {
    final scope = PdfViewerToolPanelScope.maybeOf(context);
    if (scope == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Open a PDF tab to add markup.')),
      );
      return;
    }
    ProviderScope.containerOf(context, listen: false)
        .read(markupEditorProvider)
        .setTool(tool);
    scope.openViewerToolPanel(ViewerToolId.markupBurn);
  }

  static void highlight(BuildContext context) =>
      open(context, MarkupTool.highlight);

  static void underline(BuildContext context) =>
      open(context, MarkupTool.underline);

  static void strikeOut(BuildContext context) =>
      open(context, MarkupTool.strikeout);

  static void note(BuildContext context) => open(context, MarkupTool.note);

  static void textBox(BuildContext context) => open(context, MarkupTool.text);

  static void ink(BuildContext context) => open(context, MarkupTool.pen);

  static void stamp(BuildContext context) => open(context, MarkupTool.image);
}
