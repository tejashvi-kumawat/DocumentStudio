import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:flutter/material.dart';

/// Soft hover lift (+1px) and press scale (0.99) for calm desktop cards.
class DsHoverLift extends StatefulWidget {
  const DsHoverLift({
    super.key,
    required this.child,
    this.enabled = true,
    this.borderRadius,
    this.onTap,
    this.onSecondaryTapUp,
  });

  final Widget child;
  final bool enabled;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;
  final GestureTapUpCallback? onSecondaryTapUp;

  @override
  State<DsHoverLift> createState() => _DsHoverLiftState();
}

class _DsHoverLiftState extends State<DsHoverLift> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius =
        widget.borderRadius ?? BorderRadius.circular(DsSpacing.radiusCard);
    final lift = widget.enabled && _hovered && !_pressed;
    final scale = widget.enabled && _pressed ? 0.99 : 1.0;

    return MouseRegion(
      onEnter: widget.enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: widget.enabled
          ? (_) => setState(() {
                _hovered = false;
                _pressed = false;
              })
          : null,
      cursor: widget.enabled && widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown:
            widget.enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: widget.enabled
            ? (_) {
                setState(() => _pressed = false);
                widget.onTap?.call();
              }
            : null,
        onTapCancel:
            widget.enabled ? () => setState(() => _pressed = false) : null,
        onSecondaryTapUp: widget.enabled ? widget.onSecondaryTapUp : null,
        child: AnimatedContainer(
          duration: DsMotion.hoverDuration,
          curve: DsMotion.switchCurve,
          transform: Matrix4.translationValues(0, lift ? -1 : 0, 0),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: !isDark && lift
                ? DsSpacing.cardShadowLight(opacity: 0.10)
                : null,
          ),
          child: AnimatedScale(
            scale: scale,
            duration: DsMotion.hoverDuration,
            curve: DsMotion.switchCurve,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
