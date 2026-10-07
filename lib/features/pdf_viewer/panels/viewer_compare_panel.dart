import 'dart:async';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/design_system/widgets/ds_hover_lift.dart';
import 'package:document_studio/domain/compare/compare_models.dart';
import 'package:document_studio/features/compare/compare_controller.dart';
import 'package:document_studio/features/compare/compare_page_painter.dart';
import 'package:document_studio/features/compare/compare_workspace_screen.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _originalAccent = Color(0xFF6B7280);

/// Compare PDFs launcher: pick the second document (file or open tab),
/// choose which is original / revised, then open the compare workspace.
class ViewerComparePanel extends ConsumerStatefulWidget {
  const ViewerComparePanel({super.key, required this.handoff});

  final PdfViewerDocumentHandoff handoff;

  @override
  ConsumerState<ViewerComparePanel> createState() => _ViewerComparePanelState();
}

class _ViewerComparePanelState extends ConsumerState<ViewerComparePanel> {
  CompareSource? _other;

  /// When true the open document is the *revised* version.
  bool _currentIsNew = false;

  CompareSource get _current =>
      CompareSource(widget.handoff.file, password: widget.handoff.password);

  Future<void> _pickOther() async {
    final picked = await ref
        .read(fileStorageProvider)
        .pickOpenFile(allowedExtensions: const ['pdf']);
    if (picked == null || !mounted) return;
    if (picked.path == widget.handoff.file.path) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a different PDF to compare with this one.'),
        ),
      );
      return;
    }
    setState(() => _other = CompareSource(picked));
  }

  void _compare() {
    final other = _other;
    if (other == null) return;
    unawaited(
      openCompareWorkspace(
        context,
        oldSource: _currentIsNew ? other : _current,
        newSource: _currentIsNew ? _current : other,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final secondary = DsColors.textSecondary(brightness);
    final tabs = ref
        .watch(documentTabsControllerProvider)
        .tabs
        .where((t) => t.file.path != widget.handoff.file.path)
        .toList();
    final currentRole = _currentIsNew ? 'REVISED' : 'ORIGINAL';
    final otherRole = _currentIsNew ? 'ORIGINAL' : 'REVISED';
    Color accent(bool revised) =>
        revised ? compareChangedColor : _originalAccent;

    final currentCard = _SlotCard(
      key: const ValueKey('current'),
      role: currentRole,
      title: widget.handoff.file.displayName,
      subtitle: 'Open document',
      icon: Icons.description_outlined,
      accent: accent(_currentIsNew),
    );
    final otherCard = _other == null
        ? _EmptySlot(
            key: const ValueKey('empty'),
            role: otherRole.toLowerCase(),
            onPick: _pickOther,
          )
        : _SlotCard(
            key: ValueKey(_other!.file.path),
            role: otherRole,
            title: _other!.file.displayName,
            subtitle: 'Tap to change',
            icon: Icons.picture_as_pdf_outlined,
            accent: accent(!_currentIsNew),
            onTap: _pickOther,
            onClear: () => setState(() => _other = null),
          );
    final first = _currentIsNew ? otherCard : currentCard;
    final second = _currentIsNew ? currentCard : otherCard;

    return ColoredBox(
      color: DsColors.groupedBackground(brightness),
      child: ListView(
        padding: const EdgeInsets.all(DsSpacing.lg),
        children: [
          Text(
            'Compare two versions of a PDF side by side. Word changes are '
            'highlighted on the pages; formatting, images, annotations and '
            'inserted, deleted or moved pages are listed too.',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 13,
              color: secondary,
            ),
          ),
          const SizedBox(height: DsSpacing.lg),
          AnimatedSwitcher(
            duration: DsMotion.switchDuration,
            transitionBuilder: (c, a) => DsMotion.fadeRiseTransition(a, c),
            child: KeyedSubtree(
              key: ValueKey('a-$_currentIsNew-${_other?.file.path}'),
              child: first,
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: IconButton.filledTonal(
                tooltip: 'Swap original and revised',
                onPressed: () => setState(() => _currentIsNew = !_currentIsNew),
                icon: AnimatedRotation(
                  turns: _currentIsNew ? 0.5 : 0,
                  duration: DsMotion.contentReveal,
                  curve: DsMotion.switchCurve,
                  child: const Icon(Icons.swap_vert_rounded),
                ),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: DsMotion.switchDuration,
            transitionBuilder: (c, a) => DsMotion.fadeRiseTransition(a, c),
            child: KeyedSubtree(
              key: ValueKey('b-$_currentIsNew-${_other?.file.path}'),
              child: second,
            ),
          ),
          if (tabs.isNotEmpty) ...[
            const SizedBox(height: DsSpacing.lg),
            Text(
              'OPEN DOCUMENTS',
              style: theme.textTheme.labelSmall?.copyWith(
                color: secondary,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: DsSpacing.xs),
            for (final t in tabs)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
                ),
                leading: const Icon(Icons.tab_outlined, size: 18),
                title: Text(
                  t.file.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                selected: _other?.file.path == t.file.path,
                onTap: () => setState(
                  () => _other = CompareSource(t.file, password: t.password),
                ),
              ),
          ],
          const SizedBox(height: DsSpacing.lg),
          DsPrimaryButton(
            key: const Key('viewer_compare_apply'),
            label: 'Compare',
            icon: Icons.difference_outlined,
            onPressed: _other == null ? null : _compare,
          ),
          const SizedBox(height: DsSpacing.xl),
          Text(
            'DETECTS',
            style: theme.textTheme.labelSmall?.copyWith(
              color: secondary,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: DsSpacing.sm),
          for (final c in CompareCategory.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(compareCategoryIcon(c), size: 16, color: secondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      c.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: DsSpacing.sm),
          Text(
            'Tip: Overlay mode shows pixel differences — swipe, onion skin '
            'or heatmap.',
            style: theme.textTheme.bodySmall?.copyWith(color: secondary),
          ),
        ],
      ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({
    super.key,
    required this.role,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    this.onTap,
    this.onClear,
  });

  final String role;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return DsHoverLift(
      onTap: onTap,
      enabled: onTap != null,
      child: Container(
        padding: const EdgeInsets.all(DsSpacing.md),
        decoration: BoxDecoration(
          color: DsColors.groupedCell(brightness),
          borderRadius: BorderRadius.circular(DsSpacing.radiusCard),
          border: Border.all(color: accent.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: DsSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    role,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: accent,
                    ),
                  ),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: DsColors.textSecondary(brightness),
                    ),
                  ),
                ],
              ),
            ),
            if (onClear != null)
              IconButton(
                tooltip: 'Clear',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 16),
                onPressed: onClear,
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot({super.key, required this.role, required this.onPick});

  final String role;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return DsHoverLift(
      onTap: onPick,
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: DsColors.groupedCell(brightness).withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(DsSpacing.radiusCard),
          border: Border.all(color: DsColors.border(brightness), width: 1.4),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_circle_outline, color: compareChangedColor),
            const SizedBox(width: DsSpacing.sm),
            Flexible(
              child: Text(
                'Choose the $role PDF…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: compareChangedColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
