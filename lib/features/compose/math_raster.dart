import 'dart:async';
import 'dart:ui' as ui;

import 'package:document_studio/features/compose/compose_pdf.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// Typesets TeX maths on this device (KaTeX-compatible engine, bundled
/// fonts) and returns a crisp image for the PDF. Results are cached.
class MathRaster {
  MathRaster._();
  static final MathRaster instance = MathRaster._();

  final Map<String, MathImage?> _cache = {};

  /// Pixels per point: formulas stay sharp when zoomed and printed.
  static const _scale = 4.0;

  Future<MathImage?> render(
    String tex, {
    required bool display,
    required double fontSize,
  }) async {
    final key = '$display|$fontSize|$tex';
    if (_cache.containsKey(key)) return _cache[key];
    final math = Math.tex(
      tex.trim(),
      mathStyle: display ? MathStyle.display : MathStyle.text,
      textStyle: TextStyle(fontSize: fontSize, color: const Color(0xFF111111)),
    );
    if (math.parseError != null) {
      _cache[key] = null;
      return null;
    }
    try {
      // Side room: italic letters overhang their boxes (the "c" in a+c).
      final img = await _renderOffscreen(
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: fontSize * 0.12,
            vertical: fontSize * 0.05,
          ),
          child: math,
        ),
      );
      _trim();
      return _cache[key] = img;
    } catch (_) {
      return _cache[key] = null;
    }
  }

  /// The parse error of [tex] (for the editor's problem list), or null.
  static String? errorOf(String tex) =>
      Math.tex(tex.trim()).parseError?.message;

  void _trim() {
    if (_cache.length > 600) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<MathImage> _renderOffscreen(Widget child) async {
    double? baseline;
    final boundary = RenderRepaintBoundary();
    final view =
        WidgetsBinding.instance.platformDispatcher.implicitView ??
        WidgetsBinding.instance.platformDispatcher.views.first;
    final renderView = RenderView(
      view: view,
      configuration: const ViewConfiguration(
        logicalConstraints: BoxConstraints(maxWidth: 6000, maxHeight: 4000),
      ),
      child: RenderPositionedBox(alignment: Alignment.topLeft, child: boundary),
    );
    final pipeline = PipelineOwner()..rootNode = renderView;
    renderView.prepareInitialFrame();
    final buildOwner = BuildOwner(focusManager: FocusManager());
    final root = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: _BaselineProbe(onBaseline: (b) => baseline = b, child: child),
        ),
      ),
    ).attachToRenderTree(buildOwner);
    buildOwner
      ..buildScope(root)
      ..finalizeTree();
    pipeline
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();
    final size = boundary.size;
    final image = await boundary.toImage(pixelRatio: _scale);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    // Tear the tree down.
    RenderObjectToWidgetAdapter<RenderBox>(container: boundary)
        .attachToRenderTree(buildOwner, root);
    buildOwner.finalizeTree();
    final b = baseline ?? size.height * 0.8;
    return MathImage(
      bytes!.buffer.asUint8List(),
      size.width,
      size.height,
      (size.height - b).clamp(0, size.height),
    );
  }
}

/// Reports the child's alphabetic baseline during layout (the only time a
/// render box may be asked for it).
class _BaselineProbe extends SingleChildRenderObjectWidget {
  const _BaselineProbe({required this.onBaseline, super.child});
  final ValueChanged<double?> onBaseline;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBaselineProbe(onBaseline);
}

class _RenderBaselineProbe extends RenderProxyBox {
  _RenderBaselineProbe(this.onBaseline);
  final ValueChanged<double?> onBaseline;

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.smallest;
      return;
    }
    c.layout(constraints.loosen(), parentUsesSize: true);
    size = c.size;
    onBaseline(c.getDistanceToBaseline(TextBaseline.alphabetic));
  }
}
