import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_shell_page.dart';
import 'package:document_studio/features/pdf_markup/header_footer/hf_controller.dart';
import 'package:flutter/material.dart';

/// Shown when the PDF already carries a Document Studio header/footer.
class HfExistingBanner extends StatelessWidget {
  const HfExistingBanner({
    super.key,
    required this.controller,
    required this.onRemove,
    this.noun = 'header & footer',
  });

  final HeaderFooterController controller;
  final VoidCallback onRemove;

  /// What the stamp is called in the copy ("header & footer", "page numbers").
  final String noun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existing = controller.existing;
    return AnimatedSize(
      duration: DsMotion.switchDuration,
      curve: DsMotion.switchCurve,
      alignment: Alignment.topCenter,
      child: !existing.hasExisting
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: DsSpacing.md),
              child: DsMotion.fadeRiseIn(
                child: Container(
                  padding: const EdgeInsets.all(DsSpacing.sm + 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7E6),
                    borderRadius: BorderRadius.circular(DsSpacing.radiusGrouped),
                    border: Border.all(color: const Color(0xFFF5C26B)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.layers_outlined,
                              size: 18, color: Color(0xFFB45309)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Document Studio $noun found on '
                              '${existing.stampedPages.length} '
                              'page${existing.stampedPages.length == 1 ? '' : 's'}',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontSize: 13,
                                color: const Color(0xFF92400E),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Applying replaces it. Load its settings to edit them, '
                        'or remove it entirely.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11.5,
                          color: const Color(0xFF92400E),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (existing.spec != null)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: const Color(0xFF92400E),
                              ),
                              onPressed: controller.busy
                                  ? null
                                  : controller.loadExistingSettings,
                              icon: const Icon(Icons.edit_note, size: 16),
                              label: const Text('Edit existing',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: DsColors.error,
                            ),
                            onPressed: controller.busy ? null : onRemove,
                            icon: const Icon(Icons.delete_sweep_outlined,
                                size: 16),
                            label: const Text('Remove',
                                style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// Pinned bottom bar: Apply (+ save as template).
class HfActionBar extends StatelessWidget {
  const HfActionBar({
    super.key,
    required this.controller,
    required this.onApply,
    this.onSaveTemplate,
    this.applyLabel,
  });

  final HeaderFooterController controller;
  final VoidCallback onApply;

  /// Hidden when null.
  final VoidCallback? onSaveTemplate;
  final String? applyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = dsUseCompactToolLayout(context);
    final controlH = DsSpacing.controlHeightComfortable;
    final pad = compact ? DsSpacing.pagePaddingCompact : DsSpacing.xl;
    final issues = controller.issues;
    final n = controller.targetPageCount;
    final canApply = !controller.busy &&
        !controller.loading &&
        controller.document != null &&
        issues.isEmpty;
    final label = applyLabel ??
        (controller.existing.hasExisting
            ? 'Replace on $n page${n == 1 ? '' : 's'}'
            : 'Apply to $n page${n == 1 ? '' : 's'}');
    final saveEnabled = !controller.busy && controller.spec.hasContent;
    final applyButton = FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: DsColors.primary,
        foregroundColor: DsColors.onPrimary,
        minimumSize: Size(compact ? double.infinity : 180, controlH),
        textStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      onPressed: canApply ? onApply : null,
      child: AnimatedSwitcher(
        duration: DsMotion.switchDuration,
        child: controller.busy
            ? const SizedBox(
                key: ValueKey('busy'),
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                key: ValueKey(label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
      ),
    );
    final saveButton = onSaveTemplate == null
        ? null
        : compact
            ? TextButton.icon(
                onPressed: saveEnabled ? onSaveTemplate : null,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Save as template'),
              )
            : OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(0, controlH),
                ),
                onPressed: saveEnabled ? onSaveTemplate : null,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Save as template'),
              );

    return Material(
      color: theme.colorScheme.surface,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: DsColors.borderLight)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, DsSpacing.sm, pad, DsSpacing.sm),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: compact ? double.infinity : DsSpacing.formMaxWidth,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AnimatedSwitcher(
                      duration: DsMotion.switchDuration,
                      transitionBuilder: (child, anim) =>
                          DsMotion.fadeRiseTransition(anim, child, risePx: 4),
                      child: controller.error != null
                          ? _note(
                              theme,
                              Icons.error_outline,
                              DsColors.error,
                              controller.error!,
                              'err',
                            )
                          : issues.isNotEmpty && !controller.loading
                              ? _note(
                                  theme,
                                  Icons.info_outline,
                                  DsColors.warning,
                                  issues.first,
                                  'issue',
                                )
                              : controller.justApplied
                                  ? _note(
                                      theme,
                                      Icons.check_circle_outline,
                                      DsColors.success,
                                      'Applied. Edit any option to preview again.',
                                      'ok',
                                    )
                                  : const SizedBox.shrink(key: ValueKey('none')),
                    ),
                    if (compact) ...[
                      SizedBox(
                        width: double.infinity,
                        height: controlH,
                        child: applyButton,
                      ),
                      ?saveButton,
                    ] else
                      Row(
                        children: [
                          ?saveButton,
                          const Spacer(),
                          applyButton,
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _note(
    ThemeData theme,
    IconData icon,
    Color color,
    String text,
    String key,
  ) {
    return Padding(
      key: ValueKey('$key-$text'),
      padding: const EdgeInsets.only(bottom: DsSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

Future<String?> showHfSaveTemplateDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const _SaveTemplateDialog(),
  );
}

class _SaveTemplateDialog extends StatefulWidget {
  const _SaveTemplateDialog();

  @override
  State<_SaveTemplateDialog> createState() => _SaveTemplateDialogState();
}

class _SaveTemplateDialogState extends State<_SaveTemplateDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _ctrl.text.trim();
    Navigator.of(context).pop(name.isEmpty ? null : name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save as template'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Template name',
          hintText: 'e.g. Client report footer',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: DsColors.primary),
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

Future<bool> confirmHfRemove(
  BuildContext context, {
  String noun = 'header & footer',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Remove $noun?'),
      content: Text(
        'Removes the $noun that Document Studio added to every page. '
        'Other page content is not touched.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: DsColors.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
