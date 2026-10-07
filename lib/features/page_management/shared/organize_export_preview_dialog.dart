import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/domain/organize/organize_page_ref.dart';
import 'package:document_studio/features/page_management/page_thumbnail_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:document_studio/app/providers.dart';

/// DS-ORG-014 — preview export payload before save dialog / assembly.
Future<bool> showOrganizeExportPreview({
  required BuildContext context,
  required String title,
  required List<OrganizePageRef> pages,
  required Map<String, String> passwordsByPath,
  String? subtitle,
  String? footnote,
}) async {
  final compact = MediaQuery.sizeOf(context).width < 600;
  if (compact) {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (_, scrollController) => _ExportPreviewBody(
          title: title,
          subtitle: subtitle,
          footnote: footnote,
          pages: pages,
          passwordsByPath: passwordsByPath,
          scrollController: scrollController,
          embedded: true,
        ),
      ),
    );
    return result == true;
  }

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
        child: _ExportPreviewBody(
          title: title,
          subtitle: subtitle,
          footnote: footnote,
          pages: pages,
          passwordsByPath: passwordsByPath,
          embedded: false,
        ),
      ),
    ),
  );
  return result == true;
}

class _ExportPreviewBody extends ConsumerWidget {
  const _ExportPreviewBody({
    required this.title,
    required this.pages,
    required this.passwordsByPath,
    required this.embedded,
    this.subtitle,
    this.footnote,
    this.scrollController,
  });

  final String title;
  final String? subtitle;
  final String? footnote;
  final List<OrganizePageRef> pages;
  final Map<String, String> passwordsByPath;
  final ScrollController? scrollController;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cache = ref.read(organizeThumbCacheProvider);
    final first = pages.first;
    final last = pages.length > 1 ? pages.last : null;
    final pageLabels = [for (var i = 0; i < pages.length; i++) '${i + 1}'];

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(title, style: theme.textTheme.titleMedium),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
        Flexible(
          child: SingleChildScrollView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(20, embedded ? 8 : 4, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(subtitle!, style: theme.textTheme.bodySmall),
                if (subtitle != null && subtitle!.isNotEmpty)
                  const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.picture_as_pdf_outlined,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${pages.length} page${pages.length == 1 ? '' : 's'} to export',
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _Thumb(
                        cache: cache,
                        page: first,
                        passwords: passwordsByPath,
                        caption: pages.length == 1 ? 'Only page' : 'First',
                        outputIndex: 1,
                      ),
                    ),
                    if (last != null) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Thumb(
                          cache: cache,
                          page: last,
                          passwords: passwordsByPath,
                          caption: 'Last',
                          outputIndex: pages.length,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Page order in output',
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(height: 6),
                _PageOrderList(labels: pageLabels),
                if (footnote != null && footnote!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    footnote!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirm export'),
              ),
            ],
          ),
        ),
      ],
    );

    if (embedded) {
      return SafeArea(child: content);
    }
    return content;
  }
}

class _PageOrderList extends StatelessWidget {
  const _PageOrderList({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;
    final fill = isDark
        ? DsColors.surfaceContainerDark
        : DsColors.surfaceContainerLight;

    if (labels.length <= 24) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final label in labels)
            _PageChip(label: label, border: border, fill: fill, theme: theme),
        ],
      );
    }

    final head = labels.take(10).toList();
    final tail = labels.skip(labels.length - 6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final label in head)
              _PageChip(label: label, border: border, fill: fill, theme: theme),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Text('…', style: theme.textTheme.bodySmall),
            ),
            for (final label in tail)
              _PageChip(label: label, border: border, fill: fill, theme: theme),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Pages 1–${labels.length} (${labels.length} total)',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _PageChip extends StatelessWidget {
  const _PageChip({
    required this.label,
    required this.border,
    required this.fill,
    required this.theme,
  });

  final String label;
  final Color border;
  final Color fill;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.cache,
    required this.page,
    required this.passwords,
    required this.caption,
    required this.outputIndex,
  });

  final PageThumbnailCache cache;
  final OrganizePageRef page;
  final Map<String, String> passwords;
  final String caption;
  final int outputIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$caption · #$outputIndex',
          style: theme.textTheme.labelSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        AspectRatio(
          aspectRatio: 0.72,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: FutureBuilder(
                future: cache.render(
                  page.file,
                  page.pageNumber1Based,
                  password: passwords[page.file.path],
                ),
                builder: (context, snap) {
                  Widget img;
                  if (snap.hasData && snap.data != null) {
                    img = Image.memory(snap.data!, fit: BoxFit.contain);
                  } else {
                    img = const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  if (page.rotationDegrees != 0) {
                    img = RotatedBox(
                      quarterTurns: (page.rotationDegrees ~/ 90) % 4,
                      child: img,
                    );
                  }
                  return img;
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
