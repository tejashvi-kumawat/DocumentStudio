import 'package:document_studio/domain/pdf_markup/pdf_markup_models.dart';
import 'package:flutter/material.dart';

/// Live template preview + validation hints for markup tools.
class PdfMarkupPreviewPanel extends StatelessWidget {
  const PdfMarkupPreviewPanel({
    super.key,
    required this.previewLines,
    this.validationIssues = const [],
  });

  final List<PdfMarkupPreviewLine> previewLines;
  final List<String> validationIssues;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasErrors = validationIssues.isNotEmpty;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Preview (sample 12-page doc)', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            if (hasErrors)
              ...validationIssues.map(
                (issue) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    issue,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              )
            else if (previewLines.isEmpty)
              Text(
                'Enter templates to see a preview.',
                style: theme.textTheme.bodySmall,
              )
            else
              ...previewLines.map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 108,
                        child: Text(
                          line.label,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          line.text,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
