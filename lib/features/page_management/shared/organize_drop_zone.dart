import 'package:document_studio/design_system/ds_colors.dart';
import 'package:flutter/material.dart';

/// Compact drop/browse affordance for document-level tools.
class OrganizeDropZone extends StatelessWidget {
  const OrganizeDropZone({
    super.key,
    required this.onBrowse,
    this.title = 'Drop PDF files here',
    this.subtitle = 'or browse from your device',
    this.enabled = true,
    this.compact = false,
  });

  final VoidCallback? onBrowse;
  final String title;
  final String subtitle;
  final bool enabled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;

    return Material(
      color: isDark
          ? DsColors.surfaceContainerDark
          : DsColors.surfaceContainerLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: border, width: 1),
      ),
      child: InkWell(
        onTap: enabled ? onBrowse : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: compact ? 12 : 20,
            horizontal: compact ? 12 : 16,
          ),
          child: Row(
            children: [
              Icon(
                Icons.upload_file_outlined,
                size: 28,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? DsColors.textSecondaryDark
                            : DsColors.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
              ),
              if (onBrowse != null)
                OutlinedButton(
                  onPressed: enabled ? onBrowse : null,
                  child: const Text('Browse'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
