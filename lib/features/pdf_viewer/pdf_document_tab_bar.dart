import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/shell/ds_app_shell.dart';
import 'package:document_studio/features/document_lifecycle/document_close_guard.dart';
import 'package:document_studio/features/pdf_viewer/document_tabs_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tab strip for [DocumentTabsController] — document tabs (name + close).
class PdfDocumentTabBar extends ConsumerWidget implements PreferredSizeWidget {
  const PdfDocumentTabBar({
    super.key,
    required this.controller,
    this.onOpenAnother,
  });

  final DocumentTabsController controller;
  final VoidCallback? onOpenAnother;

  @visibleForTesting
  static const compactMaxLabelWidth = 96.0;

  static const _wideMaxLabelWidth = 180.0;

  static const _tabHeight = 32.0;

  @override
  Size get preferredSize {
    return Size.fromHeight(_barHeightForWidth(800));
  }

  double _barHeightForWidth(double width) {
    return width < DsAppShell.compactBreakpoint ? 34 : 36;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = controller.tabs;
    if (tabs.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < DsAppShell.compactBreakpoint;
    final barHeight = _barHeightForWidth(width);
    final maxLabelWidth =
        compact ? compactMaxLabelWidth : _wideMaxLabelWidth;
    final stripBg = isDark
        ? DsColors.surfaceContainerDark
        : const Color(0xFFD6D6D6);
    final borderColor = isDark ? DsColors.borderDark : const Color(0xFFB8B8B8);

    return Material(
      color: stripBg,
      child: Semantics(
        container: true,
        label: 'Open documents, ${tabs.length} tabs',
        child: SizedBox(
          height: barHeight,
          child: Scrollbar(
            thumbVisibility: compact && tabs.length > 2,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 6, right: 4),
              itemBuilder: (context, index) {
                if (index < tabs.length) {
                  final tab = tabs[index];
                  final selected = index == controller.activeIndex;
                  return _DocumentTab(
                    key: ValueKey<String>('pdf_tab_${tab.id}'),
                    label: tab.file.displayName,
                    maxLabelWidth: maxLabelWidth,
                    selected: selected,
                    compact: compact,
                    stripBg: stripBg,
                    borderColor: borderColor,
                    onActivate: () => controller.activateTab(index),
                    onClose: tabs.length > 1
                        ? () async {
                            final ok = await confirmCloseDocumentTab(
                              context: context,
                              ref: ref,
                              tabs: controller,
                              index: index,
                            );
                            if (ok) controller.closeTab(index);
                          }
                        : null,
                  );
                }
                return _OpenAnotherTabButton(
                  compact: compact,
                  stripBg: stripBg,
                  borderColor: borderColor,
                  onPressed: onOpenAnother,
                );
              },
              itemCount: tabs.length + (onOpenAnother != null ? 1 : 0),
            ),
          ),
        ),
      ),
    );
  }
}

class _DocumentTab extends StatelessWidget {
  const _DocumentTab({
    super.key,
    required this.label,
    required this.maxLabelWidth,
    required this.selected,
    required this.compact,
    required this.stripBg,
    required this.borderColor,
    required this.onActivate,
    this.onClose,
  });

  final String label;
  final double maxLabelWidth;
  final bool selected;
  final bool compact;
  final Color stripBg;
  final Color borderColor;
  final VoidCallback onActivate;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tabBg = selected
        ? (isDark ? DsColors.surfaceDark : Colors.white)
        : stripBg;
    final topBorder = selected ? borderColor : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.only(top: 4, right: 1),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: tabBg,
          elevation: 0,
          child: InkWell(
            onTap: onActivate,
            child: Container(
              height: PdfDocumentTabBar._tabHeight,
              constraints: BoxConstraints(maxWidth: maxLabelWidth + 56),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 10,
              ),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: topBorder, width: 1),
                  left: BorderSide(color: borderColor, width: 1),
                  right: BorderSide(color: borderColor, width: 1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        fontSize: compact ? 12 : 13,
                      ),
                    ),
                  ),
                  if (onClose != null) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: onClose,
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.close,
                          size: compact ? 14 : 15,
                          color: isDark
                              ? DsColors.textSecondaryDark
                              : DsColors.textSecondaryLight,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OpenAnotherTabButton extends StatelessWidget {
  const _OpenAnotherTabButton({
    required this.compact,
    required this.stripBg,
    required this.borderColor,
    this.onPressed,
  });

  final bool compact;
  final Color stripBg;
  final Color borderColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 2),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: stripBg,
          child: InkWell(
            key: const Key('pdf_tab_open_another'),
            onTap: onPressed,
            child: Container(
              height: PdfDocumentTabBar._tabHeight,
              width: compact ? 28 : 32,
              decoration: BoxDecoration(
                border: Border.all(color: borderColor),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.add,
                size: compact ? 16 : 18,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
