import 'package:document_studio/features/pdf_viewer/panels/viewer_page_organize_export.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_scaffold.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_page_organize_logic.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// Reverse all pages and save from the viewer panel.
class ViewerReversePanel extends ConsumerStatefulWidget {
  const ViewerReversePanel({
    super.key,
    required this.handoff,
    this.pageCount,
  });

  final PdfViewerDocumentHandoff handoff;
  final int? pageCount;

  @override
  ConsumerState<ViewerReversePanel> createState() => _ViewerReversePanelState();
}

class _ViewerReversePanelState extends ConsumerState<ViewerReversePanel> {
  bool _busy = false;

  Future<void> _reverse() async {
    final total = widget.pageCount;
    if (total == null || total < 1) {
      _snack('Page count not ready yet.');
      return;
    }
    setState(() => _busy = true);
    try {
      final file = widget.handoff.file;
      final stem = p.basenameWithoutExtension(file.displayName);
      await exportOrganizePagesAndPromptSave(
        ref: ref,
        context: context,
        handoff: widget.handoff,
        pages: pagesForReverse(file, total),
        suggestedName: '${stem}_reversed.pdf',
        successMessage: 'Reversed PDF saved.',
      );
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ViewerToolFormScaffold(
      primaryKey: const Key('viewer_reverse_apply'),
      primaryLabel: _busy ? 'Reversing…' : 'Reverse',
      primaryIcon: Icons.swap_vert,
      primaryEnabled: !_busy,
      primaryBusy: _busy,
      onPrimary: _busy ? null : _reverse,
      children: [
        Text(
          'Flips the entire page sequence. Last page becomes first. '
          'You choose where to save the new file.',
          style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
        ),
      ],
    );
  }
}
