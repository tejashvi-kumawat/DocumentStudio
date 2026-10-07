import 'dart:math' as math;

import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/design_system/adaptive/ds_adaptive.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/form_sign/sign_placement_bridge.dart';
import 'package:document_studio/features/form_sign/sign_sheet.dart';
import 'package:document_studio/features/form_sign/signature_creator_dialog.dart';
import 'package:document_studio/infrastructure/pdf/saved_visual_signature_store.dart';
import 'package:flutter/material.dart';

/// Placeable for a saved signature / initials at a natural default size.
SignPlaceable placeableForSignature(SavedSignature s) {
  final aspect = s.aspect.clamp(0.4, 12.0);
  final initials = s.isInitials;
  var w = initials ? 64.0 : 170.0;
  var h = w / aspect;
  final maxH = initials ? 44.0 : 64.0;
  if (h > maxH) {
    h = maxH;
    w = h * aspect;
  }
  return SignPlaceable(
    id: 'sig:${s.id}',
    kind: initials ? SignPlaceableKind.initials : SignPlaceableKind.signature,
    png: s.bytes,
    sizePt: Size(w, h),
    label: initials ? 'Initials' : 'Signature',
  );
}

/// Signatures + initials cards: drag onto a page or click to arm.
class SignatureLibraryView extends StatefulWidget {
  const SignatureLibraryView({
    super.key,
    required this.controller,
    required this.store,
    required this.storage,
    required this.userName,
    required this.onMessage,
    this.onLibraryChanged,
  });

  final SignPlacementController controller;
  final SavedVisualSignatureStore store;
  final FileStoragePort storage;
  final String userName;
  final ValueChanged<String> onMessage;
  final ValueChanged<List<SavedSignature>>? onLibraryChanged;

  @override
  State<SignatureLibraryView> createState() => _SignatureLibraryViewState();
}

class _SignatureLibraryViewState extends State<SignatureLibraryView> {
  List<SavedSignature> _all = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await widget.store.loadAll();
    if (!mounted) return;
    setState(() {
      _all = all;
      _loading = false;
    });
    widget.onLibraryChanged?.call(all);
  }

  Future<void> _create(SavedSignatureKind kind) async {
    final saved = await showSignatureCreator(
      context,
      store: widget.store,
      storage: widget.storage,
      kind: kind,
      defaultName: widget.userName,
    );
    if (saved == null || !mounted) return;
    await _load();
    widget.controller.arm(placeableForSignature(saved));
    widget.onMessage(
      '${saved.isInitials ? 'Initials' : 'Signature'} saved — drag on the page '
      'to place it, or drag the card.',
    );
  }

  Future<void> _delete(SavedSignature s) async {
    final ok = await showDsAdaptiveConfirm(
      context,
      title: s.isInitials ? 'Delete these initials?' : 'Delete this signature?',
      message:
          'It is removed from this device. Documents you already signed '
          'are not affected.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    final armed = widget.controller.armed;
    if (armed?.id == 'sig:${s.id}') widget.controller.arm(null);
    await widget.store.remove(s.id);
    await _load();
  }

  void _toggleArm(SavedSignature s) {
    final p = placeableForSignature(s);
    final c = widget.controller;
    c.arm(c.armed?.id == p.id ? null : p);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(DsSpacing.lg),
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    final sigs = _all.where((s) => !s.isInitials).toList();
    final initials = _all.where((s) => s.isInitials).toList();
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SignSectionLabel(
            'Signatures',
            trailing: _AddButton(
              label: 'New',
              onTap: () => _create(SavedSignatureKind.signature),
            ),
          ),
          _Grid(
            items: sigs,
            controller: widget.controller,
            wide: true,
            emptyLabel: 'Create your signature',
            emptyIcon: Icons.gesture_rounded,
            onCreate: () => _create(SavedSignatureKind.signature),
            onTap: _toggleArm,
            onDelete: _delete,
          ),
          SignSectionLabel(
            'Initials',
            trailing: _AddButton(
              label: 'New',
              onTap: () => _create(SavedSignatureKind.initials),
            ),
          ),
          _Grid(
            items: initials,
            controller: widget.controller,
            wide: false,
            emptyLabel: 'Add initials',
            emptyIcon: Icons.text_fields_rounded,
            onCreate: () => _create(SavedSignatureKind.initials),
            onTap: _toggleArm,
            onDelete: _delete,
          ),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      icon: const Icon(Icons.add_rounded, size: 16),
      label: Text(label),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.items,
    required this.controller,
    required this.wide,
    required this.emptyLabel,
    required this.emptyIcon,
    required this.onCreate,
    required this.onTap,
    required this.onDelete,
  });

  final List<SavedSignature> items;
  final SignPlacementController controller;
  final bool wide;
  final String emptyLabel;
  final IconData emptyIcon;
  final VoidCallback onCreate;
  final ValueChanged<SavedSignature> onTap;
  final ValueChanged<SavedSignature> onDelete;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final target = wide ? 180.0 : 110.0;
        final cols = math.max(1, (constraints.maxWidth / target).floor());
        final w = (constraints.maxWidth - (cols - 1) * DsSpacing.sm) / cols;
        final h = wide ? 78.0 : 64.0;
        return Wrap(
          spacing: DsSpacing.sm,
          runSpacing: DsSpacing.sm,
          children: [
            for (var i = 0; i < items.length; i++)
              SizedBox(
                width: w,
                height: h,
                child: DsMotion.fadeRiseIn(
                  duration:
                      DsMotion.contentReveal +
                      DsMotion.staggerStep * math.min(i, 6),
                  child: _SignatureCard(
                    signature: items[i],
                    controller: controller,
                    onTap: () => onTap(items[i]),
                    onDelete: () => onDelete(items[i]),
                  ),
                ),
              ),
            if (items.isEmpty)
              SizedBox(
                width: constraints.maxWidth,
                height: h,
                child: _EmptyCard(
                  label: emptyLabel,
                  icon: emptyIcon,
                  onTap: onCreate,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SignatureCard extends StatefulWidget {
  const _SignatureCard({
    required this.signature,
    required this.controller,
    required this.onTap,
    required this.onDelete,
  });

  final SavedSignature signature;
  final SignPlacementController controller;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_SignatureCard> createState() => _SignatureCardState();
}

class _SignatureCardState extends State<_SignatureCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeable = placeableForSignature(widget.signature);
    final armed = widget.controller.armed?.id == placeable.id;
    final accent = theme.colorScheme.primary;
    final card = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.grab,
      child: AnimatedContainer(
        duration: DsMotion.hoverDuration,
        curve: DsMotion.switchCurve,
        transform: Matrix4.translationValues(0, _hover && !armed ? -1.5 : 0, 0),
        decoration: BoxDecoration(
          // Paper-white in dark mode too, so ink colors read as on the page.
          color: theme.brightness == Brightness.dark
              ? const Color(0xFFF3F4F6)
              : DsColors.groupedCell(theme.brightness),
          borderRadius: BorderRadius.circular(DsSpacing.radiusGrouped),
          border: Border.all(
            color: armed
                ? accent
                : _hover
                ? accent.withValues(alpha: 0.45)
                : DsColors.border(theme.brightness),
            width: armed ? 1.8 : 1,
          ),
          boxShadow: _hover || armed
              ? DsSpacing.cardShadowLight(opacity: 0.10)
              : DsSpacing.cardShadowLight(opacity: 0.03),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(DsSpacing.radiusGrouped),
            onTap: widget.onTap,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Image.memory(
                      widget.signature.bytes,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
                if (armed)
                  Positioned(
                    left: 6,
                    top: 5,
                    child: DsMotion.fadeRiseIn(
                      duration: DsMotion.switchDuration,
                      risePx: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Drag on page',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: 2,
                  top: 2,
                  child: AnimatedOpacity(
                    opacity: _hover || signIsPhoneWidth(context) ? 1 : 0,
                    duration: DsMotion.hoverDuration,
                    child: IconButton(
                      tooltip: 'Delete',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      onPressed: widget.onDelete,
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: DsColors.textSecondaryLight,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Tooltip(
      message: 'Drag onto the page, or click then drag a box on the page',
      waitDuration: const Duration(milliseconds: 700),
      child: SignLibraryDraggable(
        item: placeable,
        controller: widget.controller,
        child: card,
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Material(
      color: accent.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(DsSpacing.radiusGrouped),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DsSpacing.radiusGrouped),
        child: CustomPaint(
          painter: _DashedBorderPainter(color: accent.withValues(alpha: 0.45)),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: accent),
                const SizedBox(width: DsSpacing.sm),
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(color: accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.75),
      const Radius.circular(DsSpacing.radiusGrouped),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) => old.color != color;
}
