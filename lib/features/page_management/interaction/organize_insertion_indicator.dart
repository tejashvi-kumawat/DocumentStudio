import 'package:flutter/material.dart';

/// Which side of the hovered page the drop will insert relative to.
enum OrganizeInsertEdge {
  /// Insert before this page (left of horizontal list / above vertical list).
  before,

  /// Insert after this page (right of horizontal list / below vertical list).
  after,
}

/// Drop marker whose bar is perpendicular to [listAxis].
///
/// Horizontal filmstrip → vertical bar ("to the left/right of this page").
/// Vertical list → horizontal bar ("above/below this page").
class OrganizeInsertionIndicator extends StatelessWidget {
  const OrganizeInsertionIndicator({
    super.key,
    this.listAxis,
    this.horizontal,
    this.edge = OrganizeInsertEdge.before,
    this.active = true,
  }) : assert(listAxis != null || horizontal != null);

  /// Scroll / list axis of the page strip or list.
  final Axis? listAxis;

  /// Legacy: true = vertical list (horizontal bar). Prefer [listAxis].
  final bool? horizontal;

  /// Whether the insert lands before or after the hovered page.
  final OrganizeInsertEdge edge;

  final bool active;

  /// True when the drawn bar runs horizontally (vertical list).
  Axis get _axis =>
      listAxis ?? (horizontal == true ? Axis.vertical : Axis.horizontal);

  bool get drawsHorizontalBar => _axis == Axis.vertical;

  String get semanticsLabel {
    if (_axis == Axis.horizontal) {
      return edge == OrganizeInsertEdge.before
          ? 'Insert to the left of this page'
          : 'Insert to the right of this page';
    }
    return edge == OrganizeInsertEdge.before
        ? 'Insert above this page'
        : 'Insert below this page';
  }

  @override
  Widget build(BuildContext context) {
    if (!active) return const SizedBox.shrink();

    final color = Theme.of(context).colorScheme.primary;
    final bar = drawsHorizontalBar
        ? Container(
            height: 3,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          )
        : Container(
            width: 3,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          );

    return Semantics(
      label: semanticsLabel,
      child: bar,
    );
  }
}
