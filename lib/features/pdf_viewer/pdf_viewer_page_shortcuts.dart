import 'package:document_studio/app/keyboard/text_input_guard.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

/// Page navigation steps for [DS-READ-009-C].
enum PdfViewerPageStep { first, previous, next, last }

/// Keyboard intent for viewer page navigation (see [pdfViewerPageShortcutBindings]).
class PdfViewerPageNavIntent extends Intent {
  const PdfViewerPageNavIntent(this.step);

  final PdfViewerPageStep step;
}

/// Desktop viewer: first / previous / next / last page (PgUp/PgDn, arrows, Home/End).
const Map<ShortcutActivator, Intent> pdfViewerPageShortcutBindings = {
  SingleActivator(LogicalKeyboardKey.pageUp): PdfViewerPageNavIntent(
    PdfViewerPageStep.previous,
  ),
  SingleActivator(LogicalKeyboardKey.pageDown): PdfViewerPageNavIntent(
    PdfViewerPageStep.next,
  ),
  SingleActivator(LogicalKeyboardKey.home): PdfViewerPageNavIntent(
    PdfViewerPageStep.first,
  ),
  SingleActivator(LogicalKeyboardKey.end): PdfViewerPageNavIntent(
    PdfViewerPageStep.last,
  ),
  SingleActivator(LogicalKeyboardKey.arrowLeft): PdfViewerPageNavIntent(
    PdfViewerPageStep.previous,
  ),
  SingleActivator(LogicalKeyboardKey.arrowUp): PdfViewerPageNavIntent(
    PdfViewerPageStep.previous,
  ),
  SingleActivator(LogicalKeyboardKey.arrowRight): PdfViewerPageNavIntent(
    PdfViewerPageStep.next,
  ),
  SingleActivator(LogicalKeyboardKey.arrowDown): PdfViewerPageNavIntent(
    PdfViewerPageStep.next,
  ),
};

/// Maps a key to a page step when handled as page navigation (not canvas scroll).
PdfViewerPageStep? pdfViewerPageStepForKey(LogicalKeyboardKey key) {
  switch (key) {
    case LogicalKeyboardKey.pageUp:
    case LogicalKeyboardKey.arrowLeft:
    case LogicalKeyboardKey.arrowUp:
      return PdfViewerPageStep.previous;
    case LogicalKeyboardKey.pageDown:
    case LogicalKeyboardKey.arrowRight:
    case LogicalKeyboardKey.arrowDown:
      return PdfViewerPageStep.next;
    case LogicalKeyboardKey.home:
      return PdfViewerPageStep.first;
    case LogicalKeyboardKey.end:
      return PdfViewerPageStep.last;
    default:
      return null;
  }
}

/// Resolves the 1-based page index for [step] (clamped to [pageCount]).
int targetPageForViewerStep({
  required PdfViewerPageStep step,
  required int currentPage,
  required int pageCount,
}) {
  if (pageCount < 1) return 1;
  final current = currentPage.clamp(1, pageCount);
  switch (step) {
    case PdfViewerPageStep.first:
      return 1;
    case PdfViewerPageStep.previous:
      return (current - 1).clamp(1, pageCount);
    case PdfViewerPageStep.next:
      return (current + 1).clamp(1, pageCount);
    case PdfViewerPageStep.last:
      return pageCount;
  }
}

/// Jumps the active document to the page for [step] when the controller is ready.
void navigatePdfViewerPage({
  required PdfViewerController controller,
  required PdfViewerPageStep step,
}) {
  if (!controller.isReady) return;
  final current = controller.pageNumber ?? 1;
  final total = controller.pageCount;
  final target = targetPageForViewerStep(
    step: step,
    currentPage: current,
    pageCount: total,
  );
  if (target == current) return;
  unawaited(controller.goToPage(pageNumber: target));
}

/// pdfrx [PdfViewerParams.onKey] hook: return `true` if handled, `null` to fall through.
bool? handlePdfViewerPageNavigationKey(
  PdfViewerController controller,
  LogicalKeyboardKey key,
) {
  final step = pdfViewerPageStepForKey(key);
  if (step == null) return null;
  navigatePdfViewerPage(controller: controller, step: step);
  return true;
}

/// Wraps [child] with page-navigation shortcuts for the PDF viewer screen.
class PdfViewerPageShortcuts extends StatelessWidget {
  const PdfViewerPageShortcuts({
    super.key,
    required this.child,
    required this.onNavigate,
  });

  final Widget child;
  final void Function(PdfViewerPageStep step) onNavigate;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: pdfViewerPageShortcutBindings,
      child: Actions(
        actions: {
          PdfViewerPageNavIntent: GuardedCallbackAction<PdfViewerPageNavIntent>(
            onInvoke: (intent) {
              onNavigate(intent.step);
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}
