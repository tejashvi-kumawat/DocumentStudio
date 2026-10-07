import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:flutter/material.dart';

/// Phone column for these tools when the window is compact (&lt; 600).
bool viewerPageToolPhoneLayout(BuildContext context) {
  return MediaQuery.sizeOf(context).width < DsSpacing.breakpointCompact;
}

/// Fills the width: 2 columns on a phone, 3 when wider, more on desktop.
int viewerPageGridColumns(double width, {required bool phone}) {
  if (width < 480) return 2;
  if (phone || width < 720) return 3;
  if (width < 960) return 4;
  if (width < 1200) return 5;
  return 6;
}

/// Toolbar action. Lives in a horizontal scroller so long labels never stripe.
Widget viewerPageToolButton({
  Key? key,
  required IconData icon,
  required String label,
  required VoidCallback? onPressed,
}) {
  return TextButton(
    key: key,
    onPressed: onPressed,
    style: TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(40, 40),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 4),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    ),
  );
}

/// Calm toolbar over a thumbnail grid.
///
/// On a phone the primary action is a full-width 48dp button above the
/// system navigation inset. On desktop that action sits in the toolbar.
class ViewerPageGridScaffold extends StatelessWidget {
  const ViewerPageGridScaffold({
    super.key,
    required this.toolbar,
    required this.body,
    required this.applyLabel,
    required this.onApply,
    this.applyKey,
    this.header,
  });

  final List<Widget> toolbar;
  final Widget? header;
  final Widget body;
  final String applyLabel;
  final VoidCallback? onApply;
  final Key? applyKey;

  @override
  Widget build(BuildContext context) {
    final phone = viewerPageToolPhoneLayout(context);
    final theme = Theme.of(context);
    final border = DsColors.border(theme.brightness);
    final bar = theme.brightness == Brightness.dark
        ? DsColors.surfaceContainerDark
        : DsColors.surfaceContainerLight;

    Widget applyButton({required double height, double? width}) {
      return SizedBox(
        width: width,
        height: height,
        child: FilledButton(
          key: applyKey,
          onPressed: onApply,
          style: FilledButton.styleFrom(
            backgroundColor: DsColors.primary,
            foregroundColor: DsColors.onPrimary,
            disabledBackgroundColor: DsColors.primary.withValues(alpha: 0.35),
            disabledForegroundColor: DsColors.onPrimary.withValues(alpha: 0.85),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(applyLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: bar,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: SizedBox(
              height: 48,
              child: Row(
                children: [
                  Expanded(
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      children: [
                        for (final action in toolbar) Center(child: action),
                      ],
                    ),
                  ),
                  if (!phone)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: applyButton(height: 36),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (header != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 168),
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: header,
            ),
          ),
        Expanded(child: body),
        if (phone)
          Material(
            color: theme.colorScheme.surface,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: border)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DsSpacing.lg,
                    DsSpacing.sm,
                    DsSpacing.lg,
                    DsSpacing.sm,
                  ),
                  child: applyButton(height: 48, width: double.infinity),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class ViewerPageThumbnailGrid extends StatelessWidget {
  const ViewerPageThumbnailGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final phone = viewerPageToolPhoneLayout(context);
        final cols = viewerPageGridColumns(constraints.maxWidth, phone: phone);
        return GridView.builder(
          padding: const EdgeInsets.all(DsSpacing.md),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: 0.72,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
      },
    );
  }
}

/// Flat page cell: thumbnail plus one ellipsized label. No hover toolbar.
class ViewerPageThumbTile extends StatelessWidget {
  const ViewerPageThumbTile({
    super.key,
    required this.label,
    required this.child,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final Widget child;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
            border: Border.all(
              color: selected ? DsColors.primary : DsColors.border(brightness),
              width: selected ? 2 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      child,
                      if (selected)
                        const Positioned(
                          top: 4,
                          right: 4,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: DsColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(
                                Icons.check,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: selected ? DsColors.primary : null,
                    fontWeight: selected ? FontWeight.w600 : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
