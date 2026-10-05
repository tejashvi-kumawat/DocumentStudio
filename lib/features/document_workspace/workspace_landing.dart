import 'package:document_studio/app/providers.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Empty-state of the Workspace: a clear drop target, recent files you can
/// click to load, and what the Workspace is for.
class WorkspaceLanding extends ConsumerWidget {
  const WorkspaceLanding({
    super.key,
    required this.onBrowse,
    required this.onPickRecent,
    this.compact = false,
  });

  final VoidCallback onBrowse;
  final void Function(LocalFileRef file) onPickRecent;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final recents =
        ref.watch(recentsProvider).asData?.value ?? const <LocalFileRef>[];
    final muted = DsColors.textSecondary(theme.brightness);

    final drop = Material(
      color: dark ? DsColors.groupedCellDark : DsColors.groupedCellLight,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onBrowse,
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: compact ? 28 : 44,
            horizontal: 24,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: DsColors.primary.withValues(alpha: 0.45),
              width: 1.6,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: DsColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.dashboard_customize_rounded,
                  size: 30,
                  color: DsColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text('Drop PDFs here', style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Combine, reorder, rotate, extract and delete pages from one '
                'or many files — then save a new PDF.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onBrowse,
                icon: const Icon(Icons.folder_open),
                label: const Text('Choose PDFs'),
              ),
            ],
          ),
        ),
      ),
    );

    final recentList = recents.isEmpty
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8, top: 4),
                child: Text(
                  'RECENT',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 0.7,
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
              ),
              for (final f in recents.take(6))
                Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: DsColors.border(theme.brightness)),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.picture_as_pdf_rounded,
                      color: DsColors.primary,
                    ),
                    title: Text(
                      f.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      f.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: const Icon(Icons.add_circle_outline, size: 20),
                    onTap: () => onPickRecent(f),
                  ),
                ),
            ],
          );

    return ColoredBox(
      color: DsColors.groupedBackground(theme.brightness),
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(compact ? 16 : 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                drop,
                if (recentList != null) ...[
                  const SizedBox(height: 20),
                  recentList,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
