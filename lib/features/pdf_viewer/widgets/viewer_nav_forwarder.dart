import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

/// Keeps scrolling and zooming alive over page overlays.
///
/// Edit, markup and form layers sit above the viewer, so the viewer's own
/// gesture handling never sees pointers that land on them. This forwards what
/// a reader expects everywhere on the page: mouse wheel (Ctrl = zoom, Shift =
/// sideways), touchpad two-finger pan and pinch, and middle-button drag.
class ViewerNavForwarder extends StatefulWidget {
  const ViewerNavForwarder({
    super.key,
    required this.controller,
    required this.child,
    this.behavior = HitTestBehavior.deferToChild,
  });

  final PdfViewerController? controller;
  final Widget child;
  final HitTestBehavior behavior;

  @override
  State<ViewerNavForwarder> createState() => _ViewerNavForwarderState();
}

class _ViewerNavForwarderState extends State<ViewerNavForwarder> {
  double _lastScale = 1;
  int? _middlePointer;

  PdfViewerController? get _vc {
    final c = widget.controller;
    return c != null && c.isReady ? c : null;
  }

  // While the viewer reloads a just-edited document it is "ready" but has
  // no layout yet; pdfrx then throws from its boundary clamp. Such a frame
  // is skipped instead of surfacing an error.
  void _pan(PdfViewerController vc, Offset d) {
    if (d == Offset.zero) return;
    try {
      final m = vc.value.clone();
      final t = m.getTranslation();
      m.setTranslationRaw(t.x + d.dx, t.y + d.dy, t.z);
      vc.value = m;
    } catch (_) {}
  }

  void _zoomAt(PdfViewerController vc, Offset global, double factor) {
    try {
      final pos = vc.globalToDocument(global);
      if (pos == null || factor == 1) return;
      unawaited(
        vc
            .setZoom(pos, vc.currentZoom * factor, duration: Duration.zero)
            .catchError((Object _) {}),
      );
    } catch (_) {}
  }

  void _signal(PointerSignalEvent e) {
    final vc = _vc;
    if (vc == null || e is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (event) {
      final ev = event as PointerScrollEvent;
      if (HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed) {
        _zoomAt(vc, ev.position, math.pow(1.2, -ev.scrollDelta.dy / 120).toDouble());
        return;
      }
      var d = -ev.scrollDelta * 0.6;
      if (HardwareKeyboard.instance.isShiftPressed && d.dx == 0) {
        d = Offset(d.dy, 0);
      }
      _pan(vc, d);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: widget.behavior,
      onPointerSignal: _signal,
      onPointerPanZoomStart: (_) => _lastScale = 1,
      onPointerPanZoomUpdate: (e) {
        final vc = _vc;
        if (vc == null) return;
        if ((e.scale - 1).abs() > 0.001 || (_lastScale - 1).abs() > 0.001) {
          _zoomAt(vc, e.position, e.scale / _lastScale);
          _lastScale = e.scale;
        }
        _pan(vc, e.panDelta);
      },
      onPointerDown: (e) {
        if (e.buttons == kMiddleMouseButton) _middlePointer = e.pointer;
      },
      onPointerMove: (e) {
        if (e.pointer != _middlePointer) return;
        final vc = _vc;
        if (vc != null) _pan(vc, e.delta);
      },
      onPointerUp: (e) {
        if (e.pointer == _middlePointer) _middlePointer = null;
      },
      onPointerCancel: (e) {
        if (e.pointer == _middlePointer) _middlePointer = null;
      },
      child: widget.child,
    );
  }
}
