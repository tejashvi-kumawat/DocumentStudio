import 'package:document_studio/core/update/app_updater.dart';
import 'package:document_studio/features/settings/update_dialog.dart';
import 'package:document_studio/design_system/brand/ds_built_by.dart';

import 'dart:async';
import 'dart:io' show Platform, exit;

import 'package:document_studio/app/shell/ds_shell_actions.dart';
import 'package:document_studio/app/shell/ds_shell_document_tab_bar.dart';
import 'package:document_studio/app/shell/ds_sidebar_state.dart';
import 'package:document_studio/app/shell/window/ds_window.dart';
import 'package:document_studio/core/pdf/pdf_document_cache.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/command_palette/ds_command_palette.dart';
import 'package:document_studio/features/document_lifecycle/document_close_guard.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

/// Label + icon for the pinned start tab, derived from the current location.
({String label, IconData icon}) dsStartTabFor(String path) {
  if (path == '/' || path.startsWith('/viewer')) {
    return (label: 'Home', icon: Icons.home_rounded);
  }
  if (path.startsWith('/workspace')) {
    return (label: 'Workspace', icon: Icons.dashboard_customize_rounded);
  }
  if (path == '/tools') return (label: 'Tools', icon: Icons.apps_rounded);
  if (path.startsWith('/office')) {
    final uri = Uri.tryParse(path);
    final file = uri?.queryParameters['path'];
    final kind = file == null
        ? uri?.queryParameters['kind']
        : file.split('.').last.toLowerCase();
    return (
      label: file != null
          ? file.split(RegExp(r'[\\/]')).last
          : (kind == 'pptx' ? 'New presentation' : 'New document'),
      icon: kind == 'pptx'
          ? Icons.slideshow_rounded
          : Icons.description_rounded,
    );
  }
  if (path.startsWith('/create-pdf')) {
    return (label: 'Create PDF', icon: Icons.note_add_rounded);
  }
  if (path.startsWith('/compose')) {
    final lang = Uri.tryParse(path)?.queryParameters['lang'];
    return (
      label: switch (lang) {
        'tex' => 'LaTeX editor',
        'html' => 'HTML editor',
        _ => 'Markdown editor',
      },
      icon: Icons.code_rounded,
    );
  }
  if (path == '/settings') {
    return (label: 'Settings', icon: Icons.settings_rounded);
  }
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  final raw = segments.isEmpty ? 'Tool' : segments.last;
  final words = raw.split(RegExp(r'[-_]')).where((w) => w.isNotEmpty);
  final label = words
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
  return (label: label.isEmpty ? 'Tool' : label, icon: Icons.handyman_rounded);
}

/// Desktop window frame: custom title bar with document tabs above [child].
///
/// Lives in [MaterialApp.builder] so full-screen tool routes keep the window
/// controls and drag area. On platforms without a custom frame it returns
/// [child] unchanged.
class DsWindowFrame extends ConsumerStatefulWidget {
  const DsWindowFrame({
    super.key,
    required this.router,
    required this.navigatorContext,
    required this.child,
  });

  final GoRouter router;
  final BuildContext? Function() navigatorContext;
  final Widget child;

  @override
  ConsumerState<DsWindowFrame> createState() => _DsWindowFrameState();
}

class _DsWindowFrameState extends ConsumerState<DsWindowFrame>
    with WindowListener {
  late final OverlayEntry _barEntry = OverlayEntry(builder: _buildBar);
  String _location = '/';

  @override
  void initState() {
    super.initState();
    _location = dsRouterLocation(widget.router);
    widget.router.routerDelegate.addListener(_onRouteChanged);
    if (DsWindow.isDesktop) {
      windowManager.addListener(this);
      unawaited(windowManager.setPreventClose(true));
    }
  }

  @override
  void didUpdateWidget(covariant DsWindowFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.router != widget.router) {
      oldWidget.router.routerDelegate.removeListener(_onRouteChanged);
      widget.router.routerDelegate.addListener(_onRouteChanged);
    }
    _barEntry.markNeedsBuild();
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_onRouteChanged);
    if (DsWindow.isDesktop) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowClose() {
    unawaited(_handleWindowClose());
  }

  Future<void> _handleWindowClose() async {
    final ok = await requestQuitWithDirtyPrompt(ref);
    if (!ok) return;
    // Hide first so close feels instant; Windows otherwise waits on PDFium /
    // Flutter teardown while the window is still on screen.
    try {
      await windowManager.hide();
    } catch (_) {}
    try {
      ref.read(documentTabsControllerProvider).clearAll();
    } catch (_) {}
    PdfDocumentCache.instance.disposeAllNow();
    try {
      await windowManager.setPreventClose(false);
    } catch (_) {}
    if (Platform.isWindows) {
      // windowManager.destroy() can hang for seconds on Windows with open PDFs.
      exit(0);
    }
    try {
      await windowManager.destroy();
    } catch (_) {
      exit(0);
    }
  }

  Future<void> _requestCloseTab(int index) async {
    final tabs = ref.read(documentTabsControllerProvider);
    final ctx = widget.navigatorContext() ?? context;
    if (!ctx.mounted) return;
    final ok = await confirmCloseDocumentTab(
      context: ctx,
      ref: ref,
      tabs: tabs,
      index: index,
    );
    if (ok) tabs.closeTab(index);
  }

  String? _fullLocation;

  void _onRouteChanged() {
    final next = dsRouterLocation(widget.router);
    var full = next;
    try {
      full = widget.router.state.uri.toString();
    } catch (_) {}
    // The query matters too: /office?path=a.docx → /office?path=b.docx is
    // another document (another tab).
    final locationChanged = next != _location;
    if ((!locationChanged && full == _fullLocation) || !mounted) return;
    _fullLocation = full;
    final tabs = ref.read(documentTabsControllerProvider);
    final docInFront = next == '/' && tabs.hasTabs && !tabs.isHomeActive;
    if (!docInFront) {
      // Never notify tab listeners in the middle of a route build.
      scheduleMicrotask(() => tabs.notePageLocation(full));
    }
    // Only the query changed (another document in the same editor): the
    // tabs update via notePageLocation; the frame itself stays as it is.
    if (!locationChanged) return;
    setState(() => _location = next);
    _barEntry.markNeedsBuild();
  }

  Widget _buildBar(BuildContext overlayContext) {
    return _DsTitleBar(
      location: _location,
      router: widget.router,
      navigatorContext: widget.navigatorContext,
      onRequestCloseTab: _requestCloseTab,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!DsWindow.usesCustomFrame) return widget.child;
    final window = ref.watch(dsWindowStateProvider);
    final brightness = Theme.of(context).brightness;
    final barHeight = window.fullScreen && DsWindow.isMacOS
        ? DsSpacing.titleBarHeight - 4
        : DsSpacing.titleBarHeight;

    Widget frame = ColoredBox(
      color: DsColors.windowChrome(brightness),
      child: Stack(
        children: [
          Positioned.fill(
            top: barHeight,
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: widget.child,
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: barHeight,
            // Own overlay so tooltips work above the router's navigator.
            child: Overlay(
              clipBehavior: Clip.none,
              initialEntries: [_barEntry],
            ),
          ),
        ],
      ),
    );

    if (DsWindow.clipsWindowCorners) {
      frame = AnimatedContainer(
        duration: DsMotion.switchDuration,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: DsColors.windowChrome(brightness),
          borderRadius: BorderRadius.circular(
            window.edgeToEdge ? 0 : DsSpacing.radiusWindow,
          ),
        ),
        child: frame,
      );
    }
    return frame;
  }
}

class _DsTitleBar extends ConsumerWidget {
  const _DsTitleBar({
    required this.location,
    required this.router,
    required this.navigatorContext,
    required this.onRequestCloseTab,
  });

  final String location;
  final GoRouter router;
  final BuildContext? Function() navigatorContext;
  final Future<void> Function(int index) onRequestCloseTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.watch(documentTabsControllerProvider);
    final window = ref.watch(dsWindowStateProvider);
    final width = MediaQuery.sizeOf(context).width;
    final brightness = Theme.of(context).brightness;
    final inShell = dsIsShellLocation(location);
    final showSidebarToggle = inShell && width >= 900;
    final leadingInset = DsWindow.isMacOS && !window.fullScreen
        ? DsWindow.macTrafficLightInset
        : DsSpacing.sm;

    return Material(
      type: MaterialType.transparency,
      child: AnimatedOpacity(
        duration: DsMotion.switchDuration,
        opacity: window.focused ? 1 : 0.72,
        child: Row(
          children: [
            SizedBox(width: leadingInset, child: const DsWindowDragArea()),
            if (showSidebarToggle) ...[
              _TitleBarIconButton(
                icon: Icons.view_sidebar_outlined,
                tooltip: 'Toggle sidebar',
                onPressed: () =>
                    ref.read(dsSidebarProvider.notifier).toggleCollapsed(),
              ),
              const SizedBox(width: DsSpacing.xs),
            ],
            Expanded(
              child: DsShellDocumentTabBar(
                controller: tabs,
                documentsVisible:
                    location == '/' && tabs.hasTabs && !tabs.isHomeActive,
                startLabel: 'Home',
                startIcon: Icons.home_rounded,
                pageLabel: dsStartTabFor,
                onNavigate: (loc) {
                  tabs.showHome();
                  router.go(loc);
                },
                menuContext: navigatorContext,
                onRequestCloseTab: onRequestCloseTab,
                onActivateStart: () {
                  tabs.activateStartTab();
                  if (location != '/') router.go('/');
                },
                onActivateDocument: (index) {
                  tabs.activateTab(index);
                  tabs.showDocument();
                  if (location != '/') router.go('/');
                },
                // + opens a new Home tab (open a PDF from there).
                onOpenAnother: () => router.go(tabs.openNewHomeTab()),
                trailingFill: const _CreditDragArea(),
              ),
            ),
            ValueListenableBuilder<AppUpdate?>(
              valueListenable: AppUpdater.instance.available,
              builder: (context, u, _) => u == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(right: DsSpacing.xs),
                      child: FilledButton.tonalIcon(
                        key: const Key('title_bar_update'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        onPressed: () {
                          final ctx = navigatorContext();
                          if (ctx != null && ctx.mounted) {
                            showUpdateDialog(ctx, u);
                          }
                        },
                        icon: const Icon(Icons.system_update_alt, size: 16),
                        label: Text('Update ${u.version}'),
                      ),
                    ),
            ),
            _CommandSearchButton(
              compact: width < 900,
              onPressed: () {
                final ctx = navigatorContext();
                if (ctx != null && ctx.mounted) {
                  showDocumentStudioCommandPalette(ctx);
                }
              },
            ),
            if (DsWindow.drawsCaptionButtons) ...[
              const SizedBox(width: DsSpacing.xs),
              DsWindowCaptionButtons(maximized: window.maximized),
            ] else
              const SizedBox(width: DsSpacing.sm),
          ],
        ),
      ),
    ).withBottomHairline(DsColors.border(brightness).withValues(alpha: 0.0));
  }
}

extension on Widget {
  Widget withBottomHairline(Color color) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: color, width: 0.5)),
    ),
    child: this,
  );
}

/// Empty title-bar space: drag to move, double-click to maximize/restore,
/// right-click for the system window menu (Linux / Windows).
class DsWindowDragArea extends StatelessWidget {
  const DsWindowDragArea({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (!DsWindow.usesCustomFrame) return child ?? const SizedBox.expand();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: DsWindow.toggleMaximize,
      onSecondaryTap: Platform.isMacOS ? null : windowManager.popUpWindowMenu,
      child: child ?? const SizedBox.expand(),
    );
  }
}

class _TitleBarIconButton extends StatefulWidget {
  const _TitleBarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<_TitleBarIconButton> createState() => _TitleBarIconButtonState();
}

class _TitleBarIconButtonState extends State<_TitleBarIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: DsMotion.hoverDuration,
            width: 30,
            height: 28,
            decoration: BoxDecoration(
              color: _hovered
                  ? DsColors.textPrimary(brightness).withValues(alpha: 0.07)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
            ),
            child: Icon(
              widget.icon,
              size: 18,
              color: DsColors.textSecondary(brightness),
            ),
          ),
        ),
      ),
    );
  }
}

class _CommandSearchButton extends StatefulWidget {
  const _CommandSearchButton({required this.compact, required this.onPressed});

  final bool compact;
  final VoidCallback onPressed;

  @override
  State<_CommandSearchButton> createState() => _CommandSearchButtonState();
}

class _CommandSearchButtonState extends State<_CommandSearchButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final isDark = brightness == Brightness.dark;
    final muted = DsColors.textSecondary(brightness);
    final shortcut = DsWindow.isMacOS ? '⌘K' : 'Ctrl K';

    return Tooltip(
      message: 'Search commands ($shortcut)',
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: DsMotion.hoverDuration,
            curve: DsMotion.switchCurve,
            height: 28,
            width: widget.compact ? 30 : 176,
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 0 : DsSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: widget.compact
                  ? (_hovered
                        ? DsColors.textPrimary(brightness)
                              .withValues(alpha: 0.07)
                        : Colors.transparent)
                  : (isDark
                        ? Colors.white.withValues(alpha: _hovered ? 0.10 : 0.06)
                        : Colors.white.withValues(alpha: _hovered ? 1 : 0.7)),
              borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
              border: widget.compact
                  ? null
                  : Border.all(color: DsColors.border(brightness), width: 0.5),
            ),
            child: widget.compact
                ? Icon(Icons.search_rounded, size: 18, color: muted)
                : Row(
                    children: [
                      Icon(Icons.search_rounded, size: 16, color: muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Search',
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12.5,
                            color: muted,
                          ),
                        ),
                      ),
                      Text(
                        shortcut,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 11,
                          color: muted.withValues(alpha: 0.8),
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

/// Minimize / maximize / close for Linux (GNOME-style round buttons) and
/// Windows (Fluent-style caption buttons).
class DsWindowCaptionButtons extends StatelessWidget {
  const DsWindowCaptionButtons({super.key, required this.maximized});

  final bool maximized;

  @override
  Widget build(BuildContext context) {
    final windows = Platform.isWindows;
    final buttons = [
      _CaptionButton(
        kind: _CaptionKind.minimize,
        windowsStyle: windows,
        onPressed: windowManager.minimize,
      ),
      _CaptionButton(
        kind: maximized ? _CaptionKind.restore : _CaptionKind.maximize,
        windowsStyle: windows,
        onPressed: DsWindow.toggleMaximize,
      ),
      _CaptionButton(
        kind: _CaptionKind.close,
        windowsStyle: windows,
        onPressed: windowManager.close,
      ),
    ];
    if (windows) {
      return Row(mainAxisSize: MainAxisSize.min, children: buttons);
    }
    return Padding(
      padding: const EdgeInsets.only(right: DsSpacing.sm + 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final b in buttons) ...[b, const SizedBox(width: 10)],
        ]..removeLast(),
      ),
    );
  }
}

enum _CaptionKind { minimize, maximize, restore, close }

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.kind,
    required this.windowsStyle,
    required this.onPressed,
  });

  final _CaptionKind kind;
  final bool windowsStyle;
  final VoidCallback onPressed;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovered = false;
  bool _pressed = false;

  String get _label => switch (widget.kind) {
    _CaptionKind.minimize => 'Minimize',
    _CaptionKind.maximize => 'Maximize',
    _CaptionKind.restore => 'Restore',
    _CaptionKind.close => 'Close',
  };

  IconData get _icon => switch (widget.kind) {
    _CaptionKind.minimize => Icons.remove_rounded,
    _CaptionKind.maximize =>
      widget.windowsStyle
          ? Icons.crop_square_rounded
          : Icons.keyboard_arrow_up_rounded,
    _CaptionKind.restore =>
      widget.windowsStyle
          ? Icons.filter_none_rounded
          : Icons.keyboard_arrow_down_rounded,
    _CaptionKind.close => Icons.close_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final isClose = widget.kind == _CaptionKind.close;
    final ink = DsColors.textPrimary(brightness);

    final Widget visual;
    if (widget.windowsStyle) {
      final hoverBg = isClose
          ? const Color(0xFFC42B1C)
          : ink.withValues(alpha: _pressed ? 0.10 : 0.06);
      visual = AnimatedContainer(
        duration: DsMotion.hoverDuration,
        width: 46,
        height: DsSpacing.titleBarHeight,
        color: _hovered ? hoverBg : Colors.transparent,
        child: Icon(
          _icon,
          size: widget.kind == _CaptionKind.restore ? 13 : 16,
          color: _hovered && isClose
              ? Colors.white
              : ink.withValues(alpha: 0.85),
        ),
      );
    } else {
      final base = isDark
          ? Colors.white.withValues(alpha: 0.10)
          : Colors.black.withValues(alpha: 0.06);
      final hover = isDark
          ? Colors.white.withValues(alpha: _pressed ? 0.24 : 0.17)
          : Colors.black.withValues(alpha: _pressed ? 0.16 : 0.11);
      visual = AnimatedContainer(
        duration: DsMotion.hoverDuration,
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _hovered ? hover : base,
        ),
        child: Icon(_icon, size: 15, color: ink.withValues(alpha: 0.85)),
      );
    }

    return Semantics(
      button: true,
      label: _label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: widget.onPressed,
          child: Center(child: visual),
        ),
      ),
    );
  }
}

/// Free space after the tabs: still drags the window, and shows the credit
/// while there is room for it (it gives way as tabs fill the bar).
class _CreditDragArea extends StatelessWidget {
  const _CreditDragArea();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final room = c.maxWidth >= 250;
        return Stack(
          fit: StackFit.expand,
          children: [
            const DsWindowDragArea(),
            if (room)
              const IgnorePointer(
                child: Align(
                  alignment: Alignment.center,
                  child: Opacity(
                    opacity: 0.8,
                    child: DsBuiltBy(fontSize: 11.5, link: false),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
