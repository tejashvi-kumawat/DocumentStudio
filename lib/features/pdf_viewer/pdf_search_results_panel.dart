import 'package:document_studio/design_system/ds_colors.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Acrobat-style search results: every hit across the whole document, grouped
/// by page, with the surrounding words. Click a row to jump to that match.
class PdfSearchResultsPanel extends StatelessWidget {
  const PdfSearchResultsPanel({super.key, required this.searcher});

  final PdfTextSearcher? searcher;

  @override
  Widget build(BuildContext context) {
    final s = searcher;
    final theme = Theme.of(context);
    if (s == null) {
      return const Center(child: Text('Open a document to search'));
    }
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final matches = s.matches;
        final rows = _rows(matches);
        final progress = s.searchProgress;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Text(
                matches.isEmpty
                    ? (s.isSearching ? 'Searching…' : 'No results')
                    : '${matches.length} result${matches.length == 1 ? '' : 's'}'
                          ' in ${rows.where((r) => r.header).length} page'
                          '${rows.where((r) => r.header).length == 1 ? '' : 's'}',
                style: theme.textTheme.labelLarge,
              ),
            ),
            if (s.isSearching)
              LinearProgressIndicator(value: progress, minHeight: 2),
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final r = rows[i];
                  if (r.header) {
                    return Container(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: Text(
                        'Page ${r.page}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  }
                  final selected = s.currentIndex == r.index;
                  return InkWell(
                    onTap: () => s.goToMatchOfIndex(r.index),
                    child: Container(
                      color: selected
                          ? DsColors.primary.withValues(alpha: 0.10)
                          : null,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: _Snippet(range: matches[r.index]),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  static List<_Row> _rows(List<PdfPageTextRange> matches) {
    final out = <_Row>[];
    int? page;
    for (var i = 0; i < matches.length; i++) {
      final p = matches[i].pageNumber;
      if (p != page) {
        page = p;
        out.add(_Row.header(p));
      }
      out.add(_Row.match(p, i));
    }
    return out;
  }
}

class _Row {
  const _Row.header(this.page) : header = true, index = -1;
  const _Row.match(this.page, this.index) : header = false;

  final bool header;
  final int page;
  final int index;
}

class _Snippet extends StatelessWidget {
  const _Snippet({required this.range});

  final PdfPageTextRange range;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = range.pageText.fullText;
    final start = range.start.clamp(0, text.length);
    final end = range.end.clamp(start, text.length);
    final from = (start - 40).clamp(0, start);
    final to = (end + 60).clamp(end, text.length);
    String clean(String v) => v.replaceAll(RegExp(r'\s+'), ' ');
    final style = theme.textTheme.bodySmall?.copyWith(fontSize: 12);
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(
            text: (from > 0 ? '…' : '') + clean(text.substring(from, start)),
          ),
          TextSpan(
            text: clean(text.substring(start, end)),
            style: style?.copyWith(
              fontWeight: FontWeight.w800,
              backgroundColor: DsColors.warning.withValues(alpha: 0.35),
            ),
          ),
          TextSpan(
            text:
                clean(text.substring(end, to)) + (to < text.length ? '…' : ''),
          ),
        ],
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}
