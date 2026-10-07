import 'package:document_studio/app/providers.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/page_management/shared/organize_accessible_files.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Compact row for a recent PDF on the Organize hub.
class OrganizeRecentPdfRow extends StatelessWidget {
  const OrganizeRecentPdfRow({super.key, required this.file});

  final LocalFileRef file;

  static const reorderPath = '/organize/reorder';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = isDark
        ? DsColors.textSecondaryDark
        : DsColors.textSecondaryLight;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push(reorderPath, extra: file),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.picture_as_pdf_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  file.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Reorder',
                style: theme.textTheme.labelSmall?.copyWith(color: secondary),
              ),
              Icon(Icons.chevron_right, color: secondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Recent PDFs block (max 5) at the top of the Organize hub.
class OrganizeRecentPdfsSection extends ConsumerWidget {
  const OrganizeRecentPdfsSection({super.key, required this.borderColor});

  final Color borderColor;

  static const _maxItems = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentsAsync = ref.watch(recentsProvider);

    return recentsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (recents) {
        final pdfs = recents
            .where((r) => r.isPdf)
            .take(_maxItems)
            .toList(growable: false);
        if (pdfs.isEmpty) return const SizedBox.shrink();

        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
              child: Text(
                'RECENT PDFS',
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: borderColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < pdfs.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: borderColor),
                    OrganizeRecentPdfRow(file: pdfs[i]),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            OrganizeAccessibleFilesList(
              onOpen: (file) =>
                  context.push(OrganizeRecentPdfRow.reorderPath, extra: file),
              maxRecents: 0,
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}
