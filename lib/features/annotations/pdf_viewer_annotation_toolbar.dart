import 'package:document_studio/design_system/shell/ds_toolbar.dart';
import 'package:document_studio/features/annotations/markup/markup_providers.dart';
import 'package:document_studio/features/annotations/markup/markup_tool.dart';
import 'package:document_studio/features/annotations/pdf_annotation_authoring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const List<MarkupTool> _kToolbarTools = [
  MarkupTool.select,
  MarkupTool.text,
  MarkupTool.highlight,
  MarkupTool.underline,
  MarkupTool.strikeout,
  MarkupTool.pen,
  MarkupTool.rectangle,
  MarkupTool.arrow,
  MarkupTool.note,
  MarkupTool.link,
  MarkupTool.image,
];

/// Markup tool strip for the PDF viewer toolbar. Arms a tool in the markup
/// editor; the armed tool shows as selected while the editor is open.
class PdfViewerAnnotationToolbar extends ConsumerWidget {
  const PdfViewerAnnotationToolbar({
    super.key,
    required this.enabled,
    this.compact = false,
  });

  final bool enabled;

  /// Fewer tools (medium widths); the rest live in the Markup panel.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final markup = ref.watch(markupEditorProvider);
    final tools = compact
        ? const [
            MarkupTool.text,
            MarkupTool.highlight,
            MarkupTool.pen,
            MarkupTool.note,
          ]
        : _kToolbarTools;
    return ListenableBuilder(
      listenable: markup,
      builder: (context, _) => DsToolbarLabeledGroup(
        label: 'Markup',
        dense: true,
        children: [
          for (final t in tools)
            DsToolbarIconButton(
              dense: true,
              key: Key('pdf_viewer_markup_${t.name}'),
              icon: t.icon,
              tooltip: t.shortcutHint == null
                  ? t.label
                  : '${t.label} (${t.shortcutHint})',
              selected: markup.editMode && markup.tool == t,
              onPressed: enabled
                  ? () => PdfAnnotationAuthoring.open(context, t)
                  : null,
            ),
        ],
      ),
    );
  }
}
