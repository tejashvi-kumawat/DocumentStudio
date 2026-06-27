import 'package:document_studio/features/pdf_viewer/pdf_search_match_bar.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Debounce for in-document find (keeps scroll/repaint smooth while searching).
const kPdfSearchQueryDebounce = Duration(milliseconds: 280);

/// Applies [query] to [searcher] (clears when empty).
void applyPdfSearchQuery({
  required PdfTextSearcher searcher,
  required String query,
}) {
  final q = query.trim();
  if (q.isEmpty) {
    searcher.resetTextSearch();
    return;
  }
  searcher.startTextSearch(q, searchImmediately: true);
}

/// Prompts for query text, runs [PdfTextSearcher], then shows match navigation.
Future<void> showPdfSearchFlow({
  required BuildContext context,
  required PdfViewerController controller,
  required PdfTextSearcher searcher,
}) async {
  final query = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final c = TextEditingController();
      return AlertDialog(
        title: const Text('Find in document'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(hintText: 'Search text'),
          autofocus: true,
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Find'),
          ),
        ],
      );
    },
  );
  if (query == null || query.isEmpty || !context.mounted) return;

  searcher.startTextSearch(query, searchImmediately: true);

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return ListenableBuilder(
        listenable: searcher,
        builder: (context, _) {
          return PdfSearchMatchBar(
            matchCount: searcher.matches.length,
            currentIndex: searcher.currentIndex,
            isSearching: searcher.isSearching,
            onPrevious: () => searcher.goToPrevMatch(),
            onNext: () => searcher.goToNextMatch(),
            onClose: () => Navigator.pop(ctx),
            onSearch: (q) =>
                searcher.startTextSearch(q, searchImmediately: true),
          );
        },
      );
    },
  );
}
