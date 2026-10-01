import 'package:document_studio/design_system/ds_colors.dart';
import 'package:flutter/material.dart';

class DsPrimaryButton extends StatelessWidget {
  const DsPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon ?? Icons.arrow_forward),
      label: Text(label),
    );
  }
}

class DsSecondaryButton extends StatelessWidget {
  const DsSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon ?? Icons.open_in_new),
      label: Text(label),
    );
  }
}

class DsEmptyState extends StatelessWidget {
  const DsEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.icon,
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final IconData? icon;

  /// Smaller icon, text and padding for inline panels.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.brightness == Brightness.dark
        ? DsColors.textSecondaryDark
        : DsColors.textSecondaryLight;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon ?? Icons.description_outlined,
              size: compact ? 28 : 48,
              color: secondary,
            ),
            SizedBox(height: compact ? 8 : 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: compact
                  ? theme.textTheme.titleSmall
                  : theme.textTheme.titleLarge,
            ),
            if (subtitle != null) ...[
              SizedBox(height: compact ? 4 : 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: compact
                    ? theme.textTheme.bodySmall?.copyWith(color: secondary)
                    : TextStyle(color: secondary),
              ),
            ],
            if (action != null) ...[
              SizedBox(height: compact ? 12 : 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
