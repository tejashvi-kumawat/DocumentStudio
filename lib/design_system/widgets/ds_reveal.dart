import 'dart:math' as math;

import 'package:document_studio/design_system/ds_motion.dart';
import 'package:flutter/widgets.dart';

/// One-shot fade + rise, delayed by [index] × [DsMotion.staggerStep] so lists
/// and page sections cascade in. Uses a single controller with an interval
/// (no timers), and honours reduced-motion settings.
class DsStaggeredReveal extends StatefulWidget {
  const DsStaggeredReveal({
    super.key,
    required this.index,
    required this.child,
    this.risePx = DsMotion.revealRisePx,
    this.maxStaggered = 10,
  });

  final int index;
  final Widget child;
  final double risePx;

  /// Items past this index share the last delay (long lists stay snappy).
  final int maxStaggered;

  @override
  State<DsStaggeredReveal> createState() => _DsStaggeredRevealState();
}

class _DsStaggeredRevealState extends State<DsStaggeredReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    final step = DsMotion.staggerStep.inMilliseconds;
    final delay = step * math.min(widget.index, widget.maxStaggered);
    final body = DsMotion.pageIntro.inMilliseconds;
    final total = delay + body;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: total.round()),
    );
    _t = CurvedAnimation(
      parent: _controller,
      curve: Interval(delay / total, 1, curve: DsMotion.switchCurve),
    );
    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) {
        final v = _t.value;
        if (v >= 1) return child!;
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, (1 - v) * widget.risePx),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
