import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:flutter/material.dart';

/// Lazy document rows inside a single rounded border (home recents / favorites).
class HomeDocumentListSliver extends StatelessWidget {
  const HomeDocumentListSliver({
    super.key,
    required this.isDark,
    required this.itemCount,
    required this.itemBuilder,
  });

  final bool isDark;
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    if (itemCount == 0) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final border = isDark ? DsColors.borderDark : DsColors.borderLight;
    final fill = isDark ? DsColors.groupedCellDark : DsColors.groupedCellLight;
    final radius = BorderRadius.circular(DsSpacing.radiusGrouped);

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final isFirst = index == 0;
          final isLast = index == itemCount - 1;
          return DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: border, width: isDark ? 1 : 0.5),
                right: BorderSide(color: border, width: isDark ? 1 : 0.5),
                top: isFirst
                    ? BorderSide(color: border, width: isDark ? 1 : 0.5)
                    : BorderSide.none,
                bottom: isLast
                    ? BorderSide(color: border, width: isDark ? 1 : 0.5)
                    : BorderSide.none,
              ),
              borderRadius: BorderRadius.vertical(
                top: isFirst ? radius.topLeft : Radius.zero,
                bottom: isLast ? radius.bottomLeft : Radius.zero,
              ),
              boxShadow: isFirst && isLast && !isDark
                  ? DsSpacing.cardShadowLight(opacity: 0.04)
                  : null,
            ),
            child: Material(
              color: fill,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  itemBuilder(context, index),
                  if (!isLast) Divider(height: 1, thickness: 1, color: border),
                ],
              ),
            ),
          );
        },
        childCount: itemCount,
        addRepaintBoundaries: true,
      ),
    );
  }
}
