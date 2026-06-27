import 'dart:async';

import 'package:document_studio/app/shell/window/ds_window.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/pdf_viewer/document_tabs_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Browser-style document tabs shown in the window title bar (desktop) or at
/// the top of the shell (mobile / tablet).
///
/// The first, pinned tab represents the current shell page (Home, Tools, …);
/// document tabs follow and can be reordered by dragging, closed with the
/// hover ×, middle-click, or the context menu.
class DsShellDocumentTabBar extends StatefulWidget {
  const DsShellDocumentTabBar({
    super.key,
    required this.controller,
    required this.documentsVisible,
    required this.onActivateStart,
    required this.onActivateDocument,
    this.startLabel = 'Home',
    this.startIcon = Icons.home_rounded,
    this.onOpenAnother,
    this.onRequestCloseTab,
    this.menuContext,
    this.trailingFill,
    this.height = DsSpacing.titleBarHeight,
  });

  final DocumentTabsController controller;

  /// Whether the document viewer is the visible page (vs. a shell page).
  final bool documentsVisible;
  final VoidCallback onActivateStart;
  final ValueChanged<int> onActivateDocument;
  final String startLabel;
  final IconData startIcon;
  final VoidCallback? onOpenAnother;

  /// When set, called instead of closing immediately (e.g. dirty-save prompt).
  /// Should close the tab itself when the user confirms.
  final Future<void> Function(int index)? onRequestCloseTab;

  /// Context under a [Navigator] for tab context menus (title bar lives above
  /// the router's navigator on desktop).
  final BuildContext? Function()? menuContext;

  /// Fills the space after the tabs (e.g. a window drag area).
  final Widget? trailingFill;
  final double height;

  static const compactMaxLabelWidth = 96.0;

  @visibleForTesting
  static const homeTabKey = Key('pdf_tab_home');

  @override
  State<DsShellDocumentTabBar> createState() => _DsShellDocumentTabBarState();
}

class _DsShellDocumentTabBarState extends State<DsShellDocumentTabBar> {
  static const _maxTabWidth = 220.0;
  static const _plusWidth = 34.0;
  static const _minDragReserve = 56.0;

  final _scroll = ScrollController();
  late Set<String> _initialIds;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _initialIds = {for (final t in widget.controller.tabs) t.id};
    _lastCount = widget.controller.tabs.length;
    widget.controller.addListener(_onTabsChanged);
  }

  @override
  void didUpdateWidget(covariant DsShellDocumentTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTabsChanged);
      widget.controller.addListener(_onTabsChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTabsChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onTabsChanged() {
    final count = widget.controller.tabs.length;
    final grew = count > _lastCount;
    _lastCount = count;
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      if (grew) {
        _scroll.animateTo(
          position.maxScrollExtent,
          duration: DsMotion.tabDuration,
          curve: DsMotion.switchCurve,
        );
      }
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    widget.controller.moveTab(oldIndex, newIndex);
  }

  Future<void> _closeTabAt(int index) async {
    final request = widget.onRequestCloseTab;
    if (request != null) {
      await request(index);
      return;
    }
    widget.controller.closeTab(index);
  }

  Future<void> _showTabMenu(int index, Offset globalPosition) async {
    final menuCtx = widget.menuContext?.call() ?? context;
    if (!menuCtx.mounted) return;
    final overlay =
        Navigator.of(menuCtx).overlay?.context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final local = overlay.globalToLocal(globalPosition);
    final tabs = widget.controller.tabs;
    if (index >= tabs.length) return;
    final tab = tabs[index];
    final choice = await showMenu<String>(
      context: menuCtx,
      position: RelativeRect.fromRect(
        local & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(value: 'close', height: 36, child: Text('Close tab')),
        PopupMenuItem(
          value: 'others',
          height: 36,
          enabled: tabs.length > 1,
          child: const Text('Close other tabs'),
        ),
        PopupMenuItem(
          value: 'right',
          height: 36,
          enabled: index < tabs.length - 1,
          child: const Text('Close tabs to the right'),
        ),
        const PopupMenuDivider(height: 8),
        const PopupMenuItem(
          value: 'copy',
          height: 36,
          child: Text('Copy file path'),
        ),
      ],
    );
    final c = widget.controller;
    switch (choice) {
      case 'close':
        final i = c.tabs.indexWhere((t) => t.id == tab.id);
        if (i >= 0) await _closeTabAt(i);
      case 'others':
        final keepId = tab.id;
        while (true) {
          final i = c.tabs.indexWhere((t) => t.id != keepId);
          if (i < 0) break;
          final before = c.tabs.length;
          await _closeTabAt(i);
          if (c.tabs.length == before) break; // user cancelled
        }
        final keep = c.tabs.indexWhere((t) => t.id == keepId);
        if (keep >= 0) widget.onActivateDocument(keep);
      case 'right':
        final keepId = tab.id;
        while (true) {
          final i = c.tabs.indexWhere((t) => t.id == keepId);
          if (i < 0 || i >= c.tabs.length - 1) break;
          final before = c.tabs.length;
          await _closeTabAt(c.tabs.length - 1);
          if (c.tabs.length == before) break;
        }
      case 'copy':
        await Clipboard.setData(
          ClipboardData(text: tab.session.sourcePath),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final tabs = controller.tabs;
    final desktopPointer = DsWindow.isDesktop;
    final tabHeight = widget.height - 10;

    return Semantics(
      container: true,
      label: tabs.isEmpty
          ? widget.startLabel
          : '${widget.startLabel} and open documents, '
              '${tabs.length} document tabs',
      child: SizedBox(
        height: widget.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth;
            final compact = maxW < 560;
            final startW = compact ? 40.0 : 118.0;
            final reserve = widget.trailingFill != null ? _minDragReserve : 0.0;
            final listAvail = (maxW -
                    startW -
                    (widget.onOpenAnother != null ? _plusWidth : 0) -
                    reserve -
                    DsSpacing.sm)
                .clamp(0.0, double.infinity);
            final minTab = compact ? 76.0 : 96.0;
            final n = tabs.length;
            final tabW =
                n == 0 ? 0.0 : (listAvail / n).clamp(minTab, _maxTabWidth);
            final listW = n == 0 ? 0.0 : (n * tabW).clamp(0.0, listAvail);

            return Row(
              children: [
                _DsTab(
                  key: DsShellDocumentTabBar.homeTabKey,
                  label: widget.startLabel,
                  icon: widget.startIcon,
                  iconOnly: compact,
                  width: startW,
                  height: tabHeight,
                  selected: !widget.documentsVisible || !controller.hasTabs,
                  pinned: true,
                  onActivate: widget.onActivateStart,
                ),
                if (n > 0) ...[
                  const SizedBox(width: DsSpacing.xs),
                  AnimatedContainer(
                    duration: DsMotion.tabDuration,
                    curve: DsMotion.switchCurve,
                    width: listW,
                    child: ReorderableListView.builder(
                      scrollController: _scroll,
                      scrollDirection: Axis.horizontal,
                      buildDefaultDragHandles: false,
                      physics: const ClampingScrollPhysics(),
                      itemCount: n,
                      onReorder: _onReorder,
                      proxyDecorator: (child, index, animation) {
                        return AnimatedBuilder(
                          animation: animation,
                          builder: (context, child) {
                            final t = Curves.easeOut.transform(animation.value);
                            return Transform.scale(
                              scale: 1 + 0.03 * t,
                              child: Opacity(opacity: 0.92, child: child),
                            );
                          },
                          child: child,
                        );
                      },
                      itemBuilder: (context, index) {
                        final tab = tabs[index];
                        final selected = widget.documentsVisible &&
                            !controller.isHomeActive &&
                            index == controller.activeIndex;
                        final item = _DsTab(
                          label: tab.file.displayName,
                          icon: Icons.picture_as_pdf_rounded,
                          iconColor: DsColors.primary,
                          width: tabW,
                          height: tabHeight,
                          selected: selected,
                          session: tab,
                          animateIn: !_initialIds.contains(tab.id),
                          onActivate: () => widget.onActivateDocument(index),
                          onClose: () {
                            final i = widget.controller.tabs
                                .indexWhere((t) => t.id == tab.id);
                            if (i >= 0) unawaited(_closeTabAt(i));
                          },
                          onContextMenu: (pos) => _showTabMenu(index, pos),
                        );
                        return KeyedSubtree(
                          key: ValueKey<String>('pdf_tab_${tab.id}'),
                          child: desktopPointer
                              ? ReorderableDragStartListener(
                                  index: index,
                                  child: item,
                                )
                              : ReorderableDelayedDragStartListener(
                                  index: index,
                                  child: item,
                                ),
                        );
                      },
                    ),
                  ),
                ],
                if (widget.onOpenAnother != null)
                  _DsNewTabButton(
                    width: _plusWidth,
                    onPressed: widget.onOpenAnother!,
                  ),
                Expanded(child: widget.trailingFill ?? const SizedBox()),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DsTab extends StatefulWidget {
  const _DsTab({
    super.key,
    required this.label,
    required this.icon,
    required this.width,
    required this.height,
    required this.selected,
    required this.onActivate,
    this.iconColor,
    this.iconOnly = false,
    this.pinned = false,
    this.animateIn = false,
    this.session,
    this.onClose,
    this.onContextMenu,
  });

  final String label;
  final IconData icon;
  final Color? iconColor;
  final double width;
  final double height;
  final bool selected;
  final bool iconOnly;
  final bool pinned;
  final bool animateIn;
  final PdfViewerTab? session;
  final VoidCallback onActivate;
  final VoidCallback? onClose;
  final ValueChanged<Offset>? onContextMenu;

  @override
  State<_DsTab> createState() => _DsTabState();
}

class _DsTabState extends State<_DsTab> with SingleTickerProviderStateMixin {
  late final AnimationController _presence;
  bool _hovered = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _presence = AnimationController(
      vsync: this,
      duration: DsMotion.tabDuration,
      value: widget.animateIn ? 0 : 1,
    );
    if (widget.animateIn) _presence.forward();
  }

  @override
  void dispose() {
    _presence.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing || widget.onClose == null) return;
    setState(() => _closing = true);
    await _presence.reverse();
    if (!mounted) return;
    widget.onClose!();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final isDark = brightness == Brightness.dark;
    final selected = widget.selected;
    final ink = selected
        ? DsColors.textPrimary(brightness)
        : DsColors.textSecondary(brightness);
    final bg = selected
        ? (isDark ? DsColors.surfaceContainerDark : DsColors.surfaceLight)
        : (_hovered
            ? DsColors.textPrimary(brightness).withValues(alpha: 0.06)
            : Colors.transparent);
    final showClose = widget.onClose != null &&
        (_hovered || selected) &&
        widget.width >= 88;
    final curved = CurvedAnimation(
      parent: _presence,
      curve: DsMotion.switchCurve,
      reverseCurve: Curves.easeInCubic,
    );

    Widget label = Text(
      widget.label,
      key: const Key('pdf_tab_label_width'),
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
      style: theme.textTheme.labelLarge?.copyWith(
        fontSize: 12.5,
        height: 1.0,
        leadingDistribution: TextLeadingDistribution.even,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        color: ink,
      ),
    );

    final body = AnimatedContainer(
      duration: DsMotion.tabDuration,
      curve: DsMotion.switchCurve,
      width: widget.width,
      height: widget.height,
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
        border: Border.all(
          color: selected
              ? DsColors.border(brightness).withValues(alpha: isDark ? 1 : 0.9)
              : Colors.transparent,
          width: 0.5,
        ),
        boxShadow: selected && !isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: widget.iconOnly ? 0 : DsSpacing.sm + 2,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: widget.iconOnly
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                _DirtyAwareIcon(
                  tab: widget.session,
                  icon: widget.icon,
                  color: selected
                      ? (widget.iconColor ?? DsColors.primary)
                      : (widget.iconColor?.withValues(alpha: 0.75) ?? ink),
                ),
                if (!widget.iconOnly) ...[
                  const SizedBox(width: 7),
                  Expanded(child: label),
                  if (widget.onClose != null)
                    AnimatedOpacity(
                      duration: DsMotion.hoverDuration,
                      opacity: showClose ? 1 : 0,
                      child: IgnorePointer(
                        ignoring: !showClose,
                        child: _TabCloseButton(onPressed: _close),
                      ),
                    ),
                ],
              ],
            ),
          ),
          // Active indicator: brand hairline that grows from the centre.
          Positioned(
            left: 18,
            right: 18,
            bottom: 2,
            height: 2,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: selected ? 1 : 0),
              duration: DsMotion.tabDuration,
              curve: DsMotion.emphasizedCurve,
              builder: (context, t, _) => Transform(
                alignment: Alignment.center,
                transform: Matrix4.diagonal3Values(t, 1, 1),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: DsColors.primary.withValues(alpha: t),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return SizeTransition(
      sizeFactor: curved,
      axis: Axis.horizontal,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: curved,
        child: IgnorePointer(
          ignoring: _closing,
          child: Tooltip(
            message: widget.pinned ? '' : widget.label,
            waitDuration: const Duration(milliseconds: 700),
            child: MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: Listener(
                onPointerDown: (e) {
                  if (e.buttons == kMiddleMouseButton) _close();
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onActivate,
                  onSecondaryTapUp: widget.onContextMenu == null
                      ? null
                      : (d) => widget.onContextMenu!(d.globalPosition),
                  child: Semantics(
                    button: true,
                    selected: selected,
                    label: widget.label,
                    child: Center(child: body),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Document icon with an unsaved-changes dot.
class _DirtyAwareIcon extends StatelessWidget {
  const _DirtyAwareIcon({
    required this.tab,
    required this.icon,
    required this.color,
  });

  final PdfViewerTab? tab;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, size: 15, color: color);
    final session = tab?.session;
    if (session == null) return iconWidget;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (!session.isDirty) return iconWidget;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            iconWidget,
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: DsColors.warning,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 1,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TabCloseButton extends StatefulWidget {
  const _TabCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_TabCloseButton> createState() => _TabCloseButtonState();
}

class _TabCloseButtonState extends State<_TabCloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Semantics(
          button: true,
          label: 'Close tab',
          child: AnimatedContainer(
            duration: DsMotion.hoverDuration,
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: _hovered
                  ? DsColors.textPrimary(brightness).withValues(alpha: 0.10)
                  : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.close_rounded,
              size: 13,
              color: DsColors.textSecondary(brightness),
            ),
          ),
        ),
      ),
    );
  }
}

class _DsNewTabButton extends StatefulWidget {
  const _DsNewTabButton({required this.width, required this.onPressed});

  final double width;
  final VoidCallback onPressed;

  @override
  State<_DsNewTabButton> createState() => _DsNewTabButtonState();
}

class _DsNewTabButtonState extends State<_DsNewTabButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Tooltip(
      message: 'Open PDF in new tab',
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          key: const Key('pdf_tab_open_another'),
          onTap: widget.onPressed,
          child: SizedBox(
            width: widget.width,
            child: Center(
              child: AnimatedContainer(
                duration: DsMotion.hoverDuration,
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _hovered
                      ? DsColors.textPrimary(brightness).withValues(alpha: 0.07)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
                ),
                child: Icon(
                  Icons.add_rounded,
                  size: 18,
                  color: DsColors.textSecondary(brightness),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
