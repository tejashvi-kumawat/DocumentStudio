import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:flutter/material.dart';

/// Calm loading state while open validation / first paint runs.
class PdfViewerLoadingPlaceholder extends StatelessWidget {
  const PdfViewerLoadingPlaceholder({super.key, this.fileName});

  final String? fileName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(DsSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (fileName != null) ...[
                Text(
                  fileName!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: DsSpacing.lg),
              ],
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: const LinearProgressIndicator(minHeight: 3),
              ),
              const SizedBox(height: DsSpacing.lg),
              _SkeletonBlock(height: 120),
              const SizedBox(height: DsSpacing.sm),
              _SkeletonBlock(height: 14, widthFactor: 0.55),
              const SizedBox(height: DsSpacing.xs),
              _SkeletonBlock(height: 14, widthFactor: 0.72),
              const SizedBox(height: DsSpacing.md),
              Text(
                'Opening document…',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: secondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.height, this.widthFactor = 1});

  final double height;
  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? DsColors.borderDark : DsColors.borderLight;

    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: base.withValues(alpha: isDark ? 0.35 : 0.45),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}
