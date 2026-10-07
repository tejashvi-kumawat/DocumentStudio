import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Validates and clamps a 1-based page number for [pageCount].
int clampGoToPageInput(int value, int pageCount) {
  if (pageCount < 1) return 1;
  return value.clamp(1, pageCount);
}

/// DS-READ-009-A — jump dialog content; owns [TextEditingController] for its lifetime.
class PdfGoToPageDialog extends StatefulWidget {
  const PdfGoToPageDialog({
    super.key,
    required this.pageCount,
    required this.initialPage,
  });

  final int pageCount;
  final int initialPage;

  @override
  State<PdfGoToPageDialog> createState() => _PdfGoToPageDialogState();
}

class _PdfGoToPageDialogState extends State<PdfGoToPageDialog> {
  late final TextEditingController _field;

  @override
  void initState() {
    super.initState();
    _field = TextEditingController(text: '${widget.initialPage}');
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = int.tryParse(_field.text.trim());
    if (parsed == null) {
      Navigator.pop(context);
      return;
    }
    Navigator.pop(context, clampGoToPageInput(parsed, widget.pageCount));
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = widget.pageCount;
    return AlertDialog(
      title: const Text('Go to page'),
      content: TextField(
        controller: _field,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'Page number',
          helperText: '1 – $pageCount',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Go')),
      ],
    );
  }
}

/// DS-READ-009-A — jump to a specific page in the open document.
Future<void> showPdfGoToPageDialog({
  required BuildContext context,
  required PdfViewerController controller,
}) async {
  if (!controller.isReady) return;
  final pageCount = controller.pageCount;
  final current = controller.pageNumber ?? 1;

  final result = await showDialog<int>(
    context: context,
    builder: (ctx) =>
        PdfGoToPageDialog(pageCount: pageCount, initialPage: current),
  );

  if (result == null || !context.mounted) return;
  unawaited(controller.goToPage(pageNumber: result));
}
