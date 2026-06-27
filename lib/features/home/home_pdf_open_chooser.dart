import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/home/home_pdf_open_mode.dart';
import 'package:flutter/material.dart';

/// Desktop action sheet after picking or dropping a PDF on Home.
Future<HomePdfOpenMode?> showHomePdfOpenChooser(
  BuildContext context, {
  required LocalFileRef file,
}) {
  return showGeneralDialog<HomePdfOpenMode>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss open options',
    barrierColor: Colors.black54,
    transitionDuration: DsMotion.switchDuration,
    pageBuilder: (context, animation, secondaryAnimation) {
      return _HomePdfOpenChooserDialog(file: file);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: DsMotion.switchCurve,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          alignment: Alignment.center,
          child: child,
        ),
      );
    },
  );
}

class _HomePdfOpenChooserDialog extends StatelessWidget {
  const _HomePdfOpenChooserDialog({required this.file});

  final LocalFileRef file;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = isDark
        ? DsColors.textSecondaryDark
        : DsColors.textSecondaryLight;

    return Center(
      child: Material(
        key: const Key('home_pdf_open_chooser'),
        color: isDark ? DsColors.surfaceContainerDark : theme.colorScheme.surface,
        elevation: 8,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isDark ? DsColors.borderDark : DsColors.borderLight,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DsSpacing.lg,
                  DsSpacing.lg,
                  DsSpacing.lg,
                  DsSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Open PDF',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: DsSpacing.xs),
                    Text(
                      'View opens the reader. Edit pages opens the workspace '
                      'grid — like Acrobat’s separate View vs Organize paths.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: DsSpacing.sm),
                    Text(
                      file.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              for (final mode in HomePdfOpenMode.values)
                _OpenModeTile(mode: mode),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpenModeTile extends StatelessWidget {
  const _OpenModeTile({required this.mode});

  final HomePdfOpenMode mode;

  IconData get _icon => switch (mode) {
        HomePdfOpenMode.read => Icons.menu_book_outlined,
        HomePdfOpenMode.editPages => Icons.dashboard_customize_outlined,
        HomePdfOpenMode.compress => Icons.compress_outlined,
        HomePdfOpenMode.protect => Icons.lock_outline,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = isDark
        ? DsColors.textSecondaryDark
        : DsColors.textSecondaryLight;

    return InkWell(
      key: Key('home_open_mode_${mode.name}'),
      onTap: () => Navigator.of(context).pop(mode),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DsSpacing.lg,
          vertical: DsSpacing.md,
        ),
        child: Row(
          children: [
            Icon(_icon, size: 22, color: theme.colorScheme.primary),
            const SizedBox(width: DsSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mode.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    mode.subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: secondary),
          ],
        ),
      ),
    );
  }
}
