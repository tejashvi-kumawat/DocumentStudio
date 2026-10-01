import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// DS-READ-008 — copy / select-all via pdfrx [PdfTextSelectionDelegate].
Future<void> copyPdfViewerTextSelection({
  required BuildContext context,
  required PdfViewerController controller,
}) async {
  if (!controller.isReady) {
    _snack(context, 'Document is still loading');
    return;
  }
  final delegate = controller.textSelectionDelegate;
  if (!delegate.hasSelectedText) {
    _snack(context, 'Select text on the page first');
    return;
  }
  if (!delegate.isCopyAllowed) {
    _snack(context, 'Copy is not allowed for this document');
    return;
  }
  await delegate.copyTextSelection();
  if (context.mounted) {
    _snack(context, 'Copied to clipboard');
  }
}

Future<void> selectAllPdfViewerText({
  required BuildContext context,
  required PdfViewerController controller,
}) async {
  if (!controller.isReady) {
    _snack(context, 'Document is still loading');
    return;
  }
  final delegate = controller.textSelectionDelegate;
  try {
    await delegate.selectAllText();
  } catch (_) {
    if (context.mounted) {
      _snack(context, 'Could not select text on this page');
    }
  }
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
