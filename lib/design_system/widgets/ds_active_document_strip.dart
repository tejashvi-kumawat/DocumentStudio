import 'package:document_studio/design_system/ds_colors.dart';
import 'package:flutter/material.dart';

/// Top-of-screen context for the active PDF in tool workflows.
class DsActiveDocumentStrip extends StatelessWidget {
  const DsActiveDocumentStrip({
    super.key,
    required this.fileName,
    this.pageCount,
    this.onChangeFile,
    this.busy = false,
  });

  final String fileName;
  final int? pageCount;
  final VoidCallback? onChangeFile;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;
    final background =
        isDark ? DsColors.surfaceContainerDark : DsColors.surfaceContainerLight;
    final secondary =
        isDark ? DsColors.textSecondaryDark : DsColors.textSecondaryLight;

    final pagesLabel = pageCount == null
        ? null
        : '$pageCount page${pageCount == 1 ? '' : 's'}';

    return Material(
      color: background,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: border)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(
                Icons.picture_as_pdf_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    if (pagesLabel != null)
                      Text(
                        pagesLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (onChangeFile != null)
                TextButton(
                  onPressed: busy ? null : onChangeFile,
                  child: const Text('Change file'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
