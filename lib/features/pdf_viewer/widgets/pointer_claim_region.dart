import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Hit-tests only where [claims] is true.
///
/// Page overlays sit above the viewer scroller. Returning false lets that
/// scroller pan; returning true (with an opaque [Listener] child) keeps the
/// pointer so a selected text box, image, or link can be dragged.
class PointerClaimRegion extends SingleChildRenderObjectWidget {
  const PointerClaimRegion({super.key, required this.claims, super.child});

  final bool Function(Offset local) claims;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderPointerClaimRegion(claims);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderPointerClaimRegion renderObject,
  ) {
    renderObject.claims = claims;
  }
}

class RenderPointerClaimRegion extends RenderProxyBox {
  RenderPointerClaimRegion(this.claims);

  bool Function(Offset local) claims;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!claims(position)) return false;
    return super.hitTest(result, position: position);
  }
}
