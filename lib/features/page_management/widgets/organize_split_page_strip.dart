import 'package:document_studio/app/providers.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef SplitPageStripTap = void Function(
  int pageNumber1Based,
  int index, {
  required bool shift,
  required bool ctrlOrMeta,
});

/// Horizontal thumbnail strip for split-by-selection (compact).
class OrganizeSplitPageStrip extends ConsumerWidget {
  const OrganizeSplitPageStrip({
    super.key,
    required this.file,
    required this.pageCount,
    required this.selectedPages1Based,
    required this.onPageTap,
    this.password,
    this.enabled = true,
    this.thumbWidth = 56,
    this.thumbHeight = 72,
  });

  final LocalFileRef file;
  final int pageCount;
  final Set<int> selectedPages1Based;
  final SplitPageStripTap onPageTap;
  final String? password;
  final bool enabled;
  final double thumbWidth;
  final double thumbHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cache = ref.read(organizeThumbCacheProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Pages', style: theme.textTheme.labelLarge),
            const Spacer(),
            Text(
              '${selectedPages1Based.length} of $pageCount selected',
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark
                    ? DsColors.textSecondaryDark
                    : DsColors.textSecondaryLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Tap to select · Shift+tap range · Ctrl/Cmd toggles',
          style: theme.textTheme.bodySmall?.copyWith(
            color: isDark
                ? DsColors.textSecondaryDark
                : DsColors.textSecondaryLight,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: thumbHeight + 22,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: pageCount,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final page1 = index + 1;
              final selected = selectedPages1Based.contains(page1);
              final border = selected
                  ? theme.colorScheme.primary
                  : (isDark ? DsColors.borderDark : DsColors.borderLight);
              final fill = selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.12)
                  : (isDark
                        ? DsColors.surfaceContainerDark
                        : DsColors.surfaceContainerLight);

              return GestureDetector(
                onTap: enabled
                    ? () {
                        final keys =
                            HardwareKeyboard.instance.logicalKeysPressed;
                        final meta =
                            keys.contains(LogicalKeyboardKey.metaLeft) ||
                            keys.contains(LogicalKeyboardKey.metaRight) ||
                            keys.contains(LogicalKeyboardKey.controlLeft) ||
                            keys.contains(LogicalKeyboardKey.controlRight);
                        final shift =
                            keys.contains(LogicalKeyboardKey.shiftLeft) ||
                            keys.contains(LogicalKeyboardKey.shiftRight);
                        onPageTap(page1, index, shift: shift, ctrlOrMeta: meta);
                      }
                    : null,
                child: SizedBox(
                  width: thumbWidth,
                  child: Column(
                    children: [
                      Material(
                        color: fill,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                          side: BorderSide(
                            color: border,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: SizedBox(
                          width: thumbWidth,
                          height: thumbHeight,
                          child: FutureBuilder<Uint8List?>(
                            future: cache.render(
                              file,
                              page1,
                              password: password,
                            ),
                            builder: (context, snap) {
                              if (snap.hasData && snap.data != null) {
                                return Image.memory(
                                  snap.data!,
                                  fit: BoxFit.contain,
                                );
                              }
                              if (snap.hasError) {
                                return Icon(
                                  Icons.broken_image_outlined,
                                  size: 20,
                                  color: theme.colorScheme.error,
                                );
                              }
                              return const Center(
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$page1',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: selected ? theme.colorScheme.primary : null,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
