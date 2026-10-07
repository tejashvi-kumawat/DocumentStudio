import 'package:document_studio/app/keyboard/text_input_guard.dart';
import 'package:document_studio/app/keyboard/ds_shell_keyboard_scope.dart';
import 'package:document_studio/app/shell/ds_shell_document_tab_bar.dart';
import 'package:document_studio/app/shell/ds_sidebar_state.dart';
import 'package:document_studio/app/shell/ds_workspace_sidebar.dart';
import 'package:document_studio/app/shell/window/ds_window.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_shell_page.dart';
import 'package:document_studio/features/document_lifecycle/document_close_guard.dart';
import 'package:document_studio/features/home/home_screen.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DsNavDestination {
  const DsNavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.path,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;
}

const kDsNavDestinations = [
  DsNavDestination(
    label: 'Home',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    path: '/',
  ),
  DsNavDestination(
    label: 'Workspace',
    icon: Icons.dashboard_customize_outlined,
    selectedIcon: Icons.dashboard_customize,
    path: '/workspace',
  ),
  DsNavDestination(
    label: 'Tools',
    icon: Icons.apps_outlined,
    selectedIcon: Icons.apps_rounded,
    path: '/tools',
  ),
  DsNavDestination(
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
    path: '/settings',
  ),
];

/// App chrome: floating inset sidebar + rounded content panel.
///
/// Document tabs live in the window title bar on desktop ([DsWindowFrame]).
/// On Android ([TargetPlatform.android], including tablets) and phone-width
/// they are omitted — open PDF replaces the screen and system/app back
/// returns to Home. Non-Android medium/tablet without a custom frame still
/// show tabs at the top of this shell inside the safe area.
/// Tab bodies (Home, Tools, Settings) use [DsShellPageFrame],
/// [DsShellPageHeader], and [DsSectionHeader] — see docs/DESIGN-SYSTEM.md.
class DsAppShell extends ConsumerWidget {
  const DsAppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// Below: bottom navigation bar instead of the sidebar.
  static const compactBreakpoint = DsSpacing.breakpointCompact;

  /// Below: sidebar is forced into icon-only rail mode (medium window class).
  static const expandedRailBreakpoint = DsSpacing.breakpointExpanded;

  static const railWidth = DsSidebarState.railWidth;
  static const railIconSize = 20.0;
  static const railLabelSize = 13.0;
  static const railItemGap = 8.0;

  /// Gap around the floating sidebar and content panel.
  static const _inset = DsSpacing.sm;

  /// Sidebar destinations: Home(0), Workspace(1), Tools(2), Settings(3).
  /// Shell branches: Home(0), Tools(1), Settings(2). Workspace is a root route.
  int _selectedIndex(String location) {
    if (location.startsWith('/settings')) return 3;
    if (location.startsWith('/tools')) return 2;
    if (location.startsWith('/workspace')) return 1;
    return 0;
  }

  /// Maps a Library destination index to a [StatefulNavigationShell] branch.
  /// Returns null for Workspace (handled via [GoRouter.go]).
  static int? shellBranchForDestination(int destinationIndex) {
    return switch (destinationIndex) {
      0 => 0, // Home
      2 => 1, // Tools
      3 => 2, // Settings
      _ => null, // Workspace or unknown
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final location = GoRouterState.of(context).uri.path;
    final selected = _selectedIndex(location);
    final brightness = Theme.of(context).brightness;
    final tabs = ref.watch(documentTabsControllerProvider);
    final customFrame = DsWindow.usesCustomFrame;

    void goTo(int index) {
      // Workspace lives outside the indexed shell (full-screen /workspace).
      if (index == 1) {
        context.go('/workspace');
        return;
      }
      final branch = shellBranchForDestination(index);
      if (branch == null) return;
      if (index == 0) tabs.showHome();
      navigationShell.goBranch(
        branch,
        initialLocation: branch == navigationShell.currentIndex,
      );
    }

    final content = _DsShellContentFade(
      index: selected,
      child: navigationShell,
    );

    final hideDocumentTabs = dsHideDocumentTabStrip(context);
    final documentOpen = selected == 0 && tabs.hasTabs && !tabs.isHomeActive;

    // Non-Android tablet/phone without a custom title bar: tabs at the top.
    // Android never shows the Home/document tab strip (full-screen viewer + back).
    Widget withTopTabs(Widget body) {
      if (customFrame || hideDocumentTabs) return body;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: DsColors.windowChrome(brightness),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: DsSpacing.xs),
                child: DsShellDocumentTabBar(
                  controller: tabs,
                  height: 44,
                  documentsVisible:
                      selected == 0 && tabs.hasTabs && !tabs.isHomeActive,
                  startLabel: kDsNavDestinations[selected].label,
                  startIcon: kDsNavDestinations[selected].selectedIcon,
                  onActivateStart: () {
                    if (selected == 0) tabs.showHome();
                  },
                  onActivateDocument: (index) {
                    if (selected != 0) goTo(0);
                    tabs.activateTab(index);
                    tabs.showDocument();
                  },
                  onRequestCloseTab: (index) async {
                    final ok = await confirmCloseDocumentTab(
                      context: context,
                      ref: ref,
                      tabs: tabs,
                      index: index,
                    );
                    if (ok) tabs.closeTab(index);
                  },
                  onOpenAnother: () =>
                      HomeScreen.openPdfFromPicker(context, ref),
                ),
              ),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: body,
            ),
          ),
        ],
      );
    }

    if (width < compactBreakpoint) {
      // Phone: no Home/document tab strip — open PDF replaces the screen;
      // system/app back returns via [DocumentTabsController.showHome].
      // Bottom nav only on shell pages, never over an open viewer.
      return DsShellKeyboardScope(
        child: PopScope(
          canPop: !documentOpen,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop || !documentOpen) return;
            tabs.showHome();
          },
          child: Scaffold(
            backgroundColor: DsColors.windowChrome(brightness),
            // System insets come from MediaQuery.padding (merged from
            // viewPadding in DocumentStudioApp). SafeArea top for shell tabs.
            // When a PDF is open skip body SafeArea so the page canvas fills
            // between chrome — viewer top chrome SafeArea's the status bar;
            // bottom status strip SafeAreas the nav/gesture bar.
            // NavigationBar sits in Scaffold.bottomNavigationBar which already
            // consumes the bottom system inset — do not SafeArea bottom here.
            body: documentOpen
                ? content
                : SafeArea(bottom: false, child: content),
            bottomNavigationBar: documentOpen
                ? null
                : NavigationBar(
                    // Compact Acrobat-style phone chrome (40–48dp targets, 56dp bar).
                    height: DsSpacing.bottomNavHeight,
                    labelBehavior:
                        NavigationDestinationLabelBehavior.alwaysShow,
                    selectedIndex: selected,
                    onDestinationSelected: goTo,
                    destinations: [
                      for (final d in kDsNavDestinations)
                        NavigationDestination(
                          icon: Icon(d.icon, size: 22),
                          selectedIcon: Icon(d.selectedIcon, size: 22),
                          label: d.label,
                        ),
                    ],
                  ),
          ),
        ),
      );
    }

    final sidebarState = ref.watch(dsSidebarProvider);
    final forcedRail = width < expandedRailBreakpoint;
    final rail = forcedRail || sidebarState.collapsed;

    // Android + open PDF: full-screen viewer (no sidebar / tab strip); back
    // returns home. Desktop Linux keeps sidebar + tabs.
    final Widget wideBody;
    if (hideDocumentTabs && documentOpen) {
      wideBody = content;
    } else {
      wideBody = withTopTabs(
        // Bottom/side viewPadding clears Android gesture/nav bars.
        // Top is handled by withTopTabs' SafeArea (or is 0 under a custom
        // window frame on Linux). When Android hides the tab strip, apply
        // top SafeArea for shell pages.
        SafeArea(
          top: hideDocumentTabs,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              _inset,
              customFrame || hideDocumentTabs ? 0 : _inset,
              0,
              _inset,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AnimatedSidebarWidth(
                  width: rail ? railWidth : sidebarState.width,
                  child: DsWorkspaceSidebar(
                    destinations: [
                      for (final d in kDsNavDestinations)
                        DsSidebarDestination(
                          label: d.label,
                          icon: d.icon,
                          selectedIcon: d.selectedIcon,
                        ),
                    ],
                    selectedIndex: selected,
                    onNavigate: goTo,
                    rail: rail,
                    documentsVisible: documentOpen,
                    showCollapseToggle: !customFrame && !forcedRail,
                  ),
                ),
                _SidebarResizeHandle(enabled: !rail),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: _inset),
                    child: _ContentPanel(child: content),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return DsShellKeyboardScope(
      child: PopScope(
        canPop: !hideDocumentTabs || !documentOpen,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop || !hideDocumentTabs || !documentOpen) return;
          tabs.showHome();
        },
        child: _SidebarShortcut(
          child: Scaffold(
            backgroundColor: DsColors.windowChrome(brightness),
            body: wideBody,
          ),
        ),
      ),
    );
  }
}

/// Animates collapse / expand, but tracks the pointer 1:1 while resizing.
class _AnimatedSidebarWidth extends StatefulWidget {
  const _AnimatedSidebarWidth({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  State<_AnimatedSidebarWidth> createState() => _AnimatedSidebarWidthState();
}

class _AnimatedSidebarWidthState extends State<_AnimatedSidebarWidth> {
  bool _jump = false;

  @override
  void didUpdateWidget(covariant _AnimatedSidebarWidth oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Small deltas come from drag-resizing; big ones from collapse/expand.
    _jump = (widget.width - oldWidget.width).abs() < 24;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: _jump ? Duration.zero : DsMotion.sidebarDuration,
      curve: DsMotion.emphasizedCurve,
      width: widget.width,
      child: widget.child,
    );
  }
}

class _SidebarResizeHandle extends ConsumerStatefulWidget {
  const _SidebarResizeHandle({required this.enabled});

  final bool enabled;

  @override
  ConsumerState<_SidebarResizeHandle> createState() =>
      _SidebarResizeHandleState();
}

class _SidebarResizeHandleState extends ConsumerState<_SidebarResizeHandle> {
  bool _active = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    const width = DsAppShell._inset;
    if (!widget.enabled) return const SizedBox(width: width);
    final notifier = ref.read(dsSidebarProvider.notifier);
    final show = _active || _hovered;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _active = true),
        onHorizontalDragUpdate: (d) =>
            notifier.setWidth(ref.read(dsSidebarProvider).width + d.delta.dx),
        onHorizontalDragEnd: (_) {
          setState(() => _active = false);
          notifier.commitWidth();
        },
        onDoubleTap: notifier.toggleCollapsed,
        child: SizedBox(
          width: width,
          child: Center(
            child: AnimatedContainer(
              duration: DsMotion.hoverDuration,
              width: 3,
              height: show ? 44 : 24,
              decoration: BoxDecoration(
                color: show
                    ? DsColors.primary.withValues(alpha: _active ? 0.7 : 0.35)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded, softly bordered surface for the routed page.
class _ContentPanel extends StatelessWidget {
  const _ContentPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final radius = BorderRadius.circular(DsSpacing.radiusSidebar);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DsColors.groupedBackground(brightness),
        borderRadius: radius,
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.07),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: radius, child: child),
    );
  }
}

class _ToggleSidebarIntent extends Intent {
  const _ToggleSidebarIntent();
}

/// ⌘/Ctrl+Shift+S … no: ⌘/Ctrl+\ toggles the sidebar (Finder-like).
class _SidebarShortcut extends ConsumerWidget {
  const _SidebarShortcut({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.backslash, control: true):
            _ToggleSidebarIntent(),
        SingleActivator(LogicalKeyboardKey.backslash, meta: true):
            _ToggleSidebarIntent(),
      },
      child: Actions(
        actions: {
          _ToggleSidebarIntent: GuardedCallbackAction<_ToggleSidebarIntent>(
            allowWhileTyping: true,

            onInvoke: (_) {
              ref.read(dsSidebarProvider.notifier).toggleCollapsed();
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}

/// Subtle fade when switching primary shell destinations (no branch remount).
class _DsShellContentFade extends StatefulWidget {
  const _DsShellContentFade({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_DsShellContentFade> createState() => _DsShellContentFadeState();
}

class _DsShellContentFadeState extends State<_DsShellContentFade>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  int _lastIndex = 0;

  @override
  void initState() {
    super.initState();
    _lastIndex = widget.index;
    _controller = AnimationController(
      vsync: this,
      duration: DsMotion.shellDuration,
      value: 1,
    );
    _opacity = CurvedAnimation(parent: _controller, curve: DsMotion.shellCurve);
  }

  @override
  void didUpdateWidget(covariant _DsShellContentFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != _lastIndex) {
      _lastIndex = widget.index;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _controller.forward(from: 0);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: RepaintBoundary(child: widget.child),
    );
  }
}
