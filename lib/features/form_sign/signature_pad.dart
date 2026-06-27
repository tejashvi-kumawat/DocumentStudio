import 'dart:math' as math;

import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/form_sign/signature_appearance_raster.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Ink colors offered for signatures (black, blue, dark red).
const kSignatureInkColors = <({String label, Color color})>[
  (label: 'Black', color: Color(0xFF1A1A1A)),
  (label: 'Blue', color: Color(0xFF1F3A93)),
  (label: 'Dark red', color: Color(0xFF8B1A1A)),
];

/// Pen thickness presets (base width in logical px).
const kSignaturePenWidths = <({String label, double width})>[
  (label: 'Fine', width: 1.8),
  (label: 'Medium', width: 2.6),
  (label: 'Bold', width: 3.8),
];

const double _minMoveDistance = 1.0;
const double _minWidthFactor = 0.6;
const double _maxWidthFactor = 1.25;

/// Stroke state for [SignaturePad]. Notifies on committed changes (stroke end,
/// undo, clear, color, width); the in-progress stroke uses [liveStroke].
class SignaturePadController extends ChangeNotifier {
  SignaturePadController({
    this._color = const Color(0xFF1A1A1A),
    this._baseWidth = 2.6,
  });

  final List<SignatureStroke> _strokes = [];
  final _live = _LiveStrokeNotifier();
  final ValueNotifier<bool> _blank = ValueNotifier(true);
  Size _padSize = Size.zero;
  Color _color;
  double _baseWidth;

  List<Offset>? _curPoints;
  List<double>? _curFactors;
  Duration? _lastTime;
  double _smoothedVelocity = 0;

  List<SignatureStroke> get strokes => List.unmodifiable(_strokes);
  Listenable get liveStroke => _live;

  /// False once the user starts drawing (drives the "Sign here" hint).
  ValueListenable<bool> get blank => _blank;
  bool get isEmpty => _strokes.isEmpty && _curPoints == null;
  bool get canUndo => _strokes.isNotEmpty;
  Size get padSize => _padSize;
  Color get color => _color;
  double get baseWidth => _baseWidth;

  SignatureStroke? get currentStroke {
    final pts = _curPoints;
    final f = _curFactors;
    if (pts == null || f == null) return null;
    return SignatureStroke(points: pts, widthFactors: f);
  }

  set color(Color value) {
    if (_color == value) return;
    _color = value;
    notifyListeners();
    _live.tick();
  }

  set baseWidth(double value) {
    if (_baseWidth == value) return;
    _baseWidth = value;
    notifyListeners();
    _live.tick();
  }

  void _setPadSize(Size size) {
    if (_strokes.isEmpty && _curPoints == null) _padSize = size;
  }

  void _begin(Offset p, Duration time) {
    _curPoints = [p];
    _curFactors = [0.95];
    _lastTime = time;
    _smoothedVelocity = 0;
    _blank.value = false;
    _live.tick();
  }

  void _extend(Offset p, Duration time) {
    final pts = _curPoints;
    final factors = _curFactors;
    if (pts == null || factors == null) return;
    final dist = (p - pts.last).distance;
    if (dist < _minMoveDistance) return;
    final dtMs = math.max(
      1.0,
      (time - (_lastTime ?? time)).inMicroseconds / 1000.0,
    );
    _lastTime = time;
    final velocity = dist / dtMs;
    _smoothedVelocity = _smoothedVelocity * 0.7 + velocity * 0.3;
    final target = (_maxWidthFactor - _smoothedVelocity * 0.45).clamp(
      _minWidthFactor,
      _maxWidthFactor,
    );
    final prev = factors.last;
    pts.add(p);
    factors.add(prev * 0.75 + target * 0.25);
    _live.tick();
  }

  void _end() {
    final pts = _curPoints;
    final factors = _curFactors;
    _curPoints = null;
    _curFactors = null;
    if (pts != null && factors != null && pts.isNotEmpty) {
      if (factors.length > 2) {
        factors[factors.length - 1] *= 0.7;
        factors[factors.length - 2] *= 0.85;
      }
      _strokes.add(SignatureStroke(points: pts, widthFactors: factors));
    }
    _blank.value = _strokes.isEmpty;
    notifyListeners();
    _live.tick();
  }

  void undo() {
    if (_strokes.isEmpty) return;
    _strokes.removeLast();
    _blank.value = _strokes.isEmpty;
    notifyListeners();
  }

  void clear() {
    if (_strokes.isEmpty && _curPoints == null) return;
    _strokes.clear();
    _curPoints = null;
    _curFactors = null;
    _blank.value = true;
    notifyListeners();
    _live.tick();
  }

  /// Snapshot for [rasterizeDrawnSignature].
  SignatureInk toInk() => SignatureInk(
    strokes: List.of(_strokes),
    padSize: _padSize,
    color: _color,
    baseWidth: _baseWidth,
  );

  @override
  void dispose() {
    _live.dispose();
    _blank.dispose();
    super.dispose();
  }
}

class _LiveStrokeNotifier extends ChangeNotifier {
  void tick() => notifyListeners();
}

/// Smooth freehand signature pad with baseline guide, hint, undo/clear,
/// ink color and thickness choices.
class SignaturePad extends StatefulWidget {
  const SignaturePad({
    super.key,
    required this.controller,
    this.height = 150,
    this.enabled = true,
    this.showToolbar = true,
    this.hintText = 'Sign here',
  });

  final SignaturePadController controller;
  final double height;
  final bool enabled;
  final bool showToolbar;
  final String hintText;

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  int? _pointer;

  SignaturePadController get _c => widget.controller;

  Offset _clamp(Offset p, Size size) =>
      Offset(p.dx.clamp(0.0, size.width), p.dy.clamp(0.0, size.height));

  void _down(PointerDownEvent e, Size size) {
    if (!widget.enabled || _pointer != null) return;
    if (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryMouseButton) {
      return;
    }
    _pointer = e.pointer;
    _c._setPadSize(size);
    _c._begin(_clamp(e.localPosition, size), e.timeStamp);
  }

  void _move(PointerMoveEvent e, Size size) {
    if (e.pointer != _pointer) return;
    _c._extend(_clamp(e.localPosition, size), e.timeStamp);
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _c._end();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: widget.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
              border: Border.all(color: DsColors.borderLight),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.biggest;
                  return MouseRegion(
                    cursor: widget.enabled
                        ? SystemMouseCursors.precise
                        : SystemMouseCursors.basic,
                    child: RawGestureDetector(
                      behavior: HitTestBehavior.opaque,
                      gestures: {
                        // Keeps an enclosing scroll view from stealing strokes.
                        EagerGestureRecognizer:
                            GestureRecognizerFactoryWithHandlers<
                              EagerGestureRecognizer
                            >(EagerGestureRecognizer.new, (_) {}),
                      },
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (e) => _down(e, size),
                        onPointerMove: (e) => _move(e, size),
                        onPointerUp: _up,
                        onPointerCancel: _up,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _Guide(controller: _c, hintText: widget.hintText),
                            RepaintBoundary(
                              child: CustomPaint(
                                painter: _CommittedInkPainter(_c),
                              ),
                            ),
                            RepaintBoundary(
                              child: CustomPaint(painter: _LiveInkPainter(_c)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        if (widget.showToolbar) ...[
          const SizedBox(height: DsSpacing.xs),
          ListenableBuilder(
            listenable: _c,
            builder: (context, _) =>
                _Toolbar(controller: _c, enabled: widget.enabled, theme: theme),
          ),
        ],
      ],
    );
  }
}

class _Guide extends StatelessWidget {
  const _Guide({required this.controller, required this.hintText});

  final SignaturePadController controller;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    const guideColor = Color(0xFF94A3B8);
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, c) {
          final baseline = c.maxHeight * 0.72;
          final inset = c.maxWidth * 0.07;
          return ValueListenableBuilder<bool>(
            valueListenable: controller.blank,
            builder: (context, blank, _) => Stack(
              children: [
                Positioned(
                  left: inset,
                  right: inset,
                  top: baseline,
                  child: AnimatedOpacity(
                    opacity: blank ? 0.9 : 0.45,
                    duration: DsMotion.switchDuration,
                    curve: DsMotion.switchCurve,
                    child: Container(height: 1, color: guideColor),
                  ),
                ),
                Positioned(
                  left: inset,
                  top: baseline - 24,
                  child: AnimatedOpacity(
                    opacity: blank ? 1 : 0,
                    duration: DsMotion.switchDuration,
                    curve: DsMotion.switchCurve,
                    child: const Text(
                      '×',
                      style: TextStyle(
                        fontSize: 20,
                        color: guideColor,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: baseline - 44,
                  child: AnimatedOpacity(
                    opacity: blank ? 1 : 0,
                    duration: DsMotion.switchDuration,
                    curve: DsMotion.switchCurve,
                    child: Text(
                      hintText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: guideColor,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.enabled,
    required this.theme,
  });

  final SignaturePadController controller;
  final bool enabled;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final c in kSignatureInkColors)
          SignatureColorDot(
            color: c.color,
            label: c.label,
            selected: controller.color == c.color,
            onTap: enabled ? () => controller.color = c.color : null,
          ),
        const SizedBox(width: DsSpacing.xs),
        for (final w in kSignaturePenWidths)
          _WidthChip(
            width: w.width,
            label: w.label,
            color: controller.color,
            selected: controller.baseWidth == w.width,
            onTap: enabled ? () => controller.baseWidth = w.width : null,
          ),
        const Spacer(),
        Tooltip(
          message: 'Undo last stroke',
          child: IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            icon: const Icon(Icons.undo),
            onPressed: enabled && controller.canUndo ? controller.undo : null,
          ),
        ),
        Tooltip(
          message: 'Clear',
          child: IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            icon: const Icon(Icons.delete_outline),
            onPressed: enabled && !controller.isEmpty ? controller.clear : null,
          ),
        ),
      ],
    );
  }
}

/// Round color swatch with an animated selection ring.
class SignatureColorDot extends StatelessWidget {
  const SignatureColorDot({
    super.key,
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkResponse(
        onTap: onTap,
        radius: 14,
        child: AnimatedContainer(
          duration: DsMotion.hoverDuration,
          curve: DsMotion.switchCurve,
          width: 22,
          height: 22,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? DsColors.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

class _WidthChip extends StatelessWidget {
  const _WidthChip({
    required this.width,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final double width;
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$label pen',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: DsMotion.hoverDuration,
          curve: DsMotion.switchCurve,
          width: 24,
          height: 22,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: selected
                ? DsColors.primary.withValues(alpha: 0.10)
                : Colors.transparent,
            border: Border.all(
              color: selected ? DsColors.primary : Colors.transparent,
            ),
          ),
          child: Container(
            width: 14,
            height: width * 1.2,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(width),
            ),
          ),
        ),
      ),
    );
  }
}

class _CommittedInkPainter extends CustomPainter {
  _CommittedInkPainter(this.controller) : super(repaint: controller);

  final SignaturePadController controller;

  @override
  void paint(Canvas canvas, Size size) {
    paintSignatureStrokes(
      canvas,
      controller._strokes,
      color: controller.color,
      baseWidth: controller.baseWidth,
    );
  }

  @override
  bool shouldRepaint(covariant _CommittedInkPainter old) =>
      old.controller != controller;
}

class _LiveInkPainter extends CustomPainter {
  _LiveInkPainter(this.controller) : super(repaint: controller.liveStroke);

  final SignaturePadController controller;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = controller.currentStroke;
    if (stroke == null) return;
    paintSignatureStrokes(
      canvas,
      [stroke],
      color: controller.color,
      baseWidth: controller.baseWidth,
    );
  }

  @override
  bool shouldRepaint(covariant _LiveInkPainter old) =>
      old.controller != controller;
}
