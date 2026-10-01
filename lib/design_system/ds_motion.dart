import 'package:flutter/widgets.dart';

/// Short, calm transitions (Apple HIG–aligned durations for utility UI).
abstract final class DsMotion {
  /// Hover lift / press scale on cards and rows.
  static const Duration hoverDuration = Duration(milliseconds: 150);

  static const Duration switchDuration = Duration(milliseconds: 180);
  static const Duration shellDuration = Duration(milliseconds: 180);
  static const Duration dialogDuration = Duration(milliseconds: 200);

  /// Tool page / shell section entrance (fade + slight rise).
  static const Duration pageIntro = Duration(milliseconds: 200);

  /// Home content reveal after cold-start splash.
  static const Duration contentReveal = Duration(milliseconds: 250);

  /// Vertical travel for page / content reveal (px).
  static const double revealRisePx = 8;

  /// Document tab open / close / reorder settle.
  static const Duration tabDuration = Duration(milliseconds: 220);

  /// Delay between items in a staggered list / section reveal.
  static const Duration staggerStep = Duration(milliseconds: 45);

  /// Sidebar collapse / expand and section disclosure.
  static const Duration sidebarDuration = Duration(milliseconds: 260);

  static const Curve switchCurve = Curves.easeOutCubic;
  static const Curve shellCurve = Curves.easeOutCubic;

  /// Spring-like settle for layout changes (sidebar width, tab indicator).
  static const Curve emphasizedCurve = Curves.easeInOutCubicEmphasized;

  /// Subtle scale for sheets and choosers (macOS / iOS modal feel).
  static const double dialogScaleBegin = 0.96;

  /// Fade + slight upward slide for page bodies (once, no loop).
  static Widget fadeRiseTransition(
    Animation<double> animation,
    Widget child, {
    double risePx = revealRisePx,
  }) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: switchCurve,
    );
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, (1 - curved.value) * risePx),
            child: child,
          );
        },
        child: child,
      ),
    );
  }

  /// One-shot fade + rise wrapper for StatelessWidget tool pages.
  static Widget fadeRiseIn({
    required Widget child,
    Duration duration = pageIntro,
    double risePx = revealRisePx,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: switchCurve,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * risePx),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  /// Fade + scale wrapper for [showGeneralDialog] and similar overlays.
  static Widget fadeScaleTransition(
    Animation<double> animation,
    Widget child, {
    double scaleBegin = dialogScaleBegin,
  }) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: switchCurve,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: scaleBegin, end: 1).animate(curved),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}
