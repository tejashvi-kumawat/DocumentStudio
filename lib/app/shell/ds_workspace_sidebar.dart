import 'package:document_studio/app/providers.dart';
import 'package:document_studio/app/shell/ds_sidebar_state.dart';
import 'package:document_studio/app/shell/window/ds_window.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/errors/document_studio_error_ui.dart';
import 'package:document_studio/design_system/brand/ds_brand_assets.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/document_lifecycle/document_close_guard.dart';
import 'package:document_studio/features/document_lifecycle/document_session.dart';
import 'package:document_studio/features/command_palette/ds_command_palette.dart';
import 'package:document_studio/features/conversion/conversion_route.dart';
import 'package:document_studio/features/home/home_pdf_open_flow.dart';
import 'package:document_studio/features/home/home_screen.dart';
import 'package:document_studio/features/home/home_tool.dart';
import 'package:document_studio/features/home/home_tool_catalog.dart';
import 'package:document_studio/features/home/home_tool_route.dart';
import 'package:document_studio/features/pdf_viewer/document_tabs_controller.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One primary shell destination shown in the sidebar "Library" group.
class DsSidebarDestination {
  const DsSidebarDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Floating, inset sidebar in the style of macOS Finder / Notes / Preview.
///
/// Full mode shows grouped sections (quick actions, library, open documents,
/// pinned, recent, tools by category, storage). Rail mode keeps icons only.
class DsWorkspaceSidebar extends ConsumerWidget {
  const DsWorkspaceSidebar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onNavigate,
    required this.rail,
    required this.documentsVisible,
    this.showCollapseToggle = false,
  });

  /// Home, Workspace, Tools, Settings — Settings is rendered in the footer.
  final List<DsSidebarDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onNavigate;
  final bool rail;
  final bool documentsVisible;

  /// Show an in-sidebar collapse button (when the title bar has none).
  final bool showCollapseToggle;

  static const _settingsIndex = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final tabs = ref.watch(documentTabsControllerProvider);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: DsColors.sidebar(brightness),
        borderRadius: BorderRadius.circular(DsSpacing.radiusSidebar),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 2,
            offset: const Offset(0, 0.5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DsSpacing.radiusSidebar),
        child: ListenableBuilder(
          listenable: tabs,
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) {
              // While the width animates, show the rail until there is room
              // for labels; the full layout never lays out narrower than
              // minWidth (it is clipped instead), so rows cannot overflow.
              final showRail = rail || constraints.maxWidth < _fullThreshold;
              return AnimatedSwitcher(
                duration: DsMotion.switchDuration,
                switchInCurve: DsMotion.switchCurve,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topLeft,
                  fit: StackFit.expand,
                  children: [...previous, ?current],
                ),
                child: showRail
                    ? _MinWidthClip(
                        key: const ValueKey('rail'),
                        minWidth: DsSidebarState.railWidth,
                        child: _RailContent(sidebar: this, tabs: tabs),
                      )
                    : _MinWidthClip(
                        key: const ValueKey('full'),
                        minWidth: DsSidebarState.minWidth,
                        child: _FullContent(sidebar: this, tabs: tabs),
                      ),
              );
            },
          ),
        ),
      ),
    );
  }
}

const double _fullThreshold = 150;

/// Lays [child] out at least [minWidth] wide and clips whatever overflows.
class _MinWidthClip extends StatelessWidget {
  const _MinWidthClip({super.key, required this.minWidth, required this.child});

  final double minWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < minWidth
            ? minWidth
            : constraints.maxWidth;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: width,
            maxWidth: width,
            child: child,
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Shared actions
// ---------------------------------------------------------------------------

Future<void> _openFile(
  BuildContext context,
  WidgetRef ref,
  LocalFileRef file,
) async {
  final storage = ref.read(fileStorageProvider);
  if (!await storage.fileExists(file)) {
    if (!context.mounted) return;
    showDocumentStudioErrorSnackBar(
      context,
      const DocumentStudioError(
        code: DocumentStudioErrorCode.fileNotFound,
        message: 'File missing',
        recoveryHint: 'The file may have moved or been deleted.',
      ),
    );
    return;
  }
  if (!context.mounted) return;
  final mode = await homeLastOpenModeFor(ref, file.path);
  if (!context.mounted) return;
  await homeOpenPdfWithMode(context, ref, file, mode);
}

void _activateTab(
  DsWorkspaceSidebar sidebar,
  DocumentTabsController tabs,
  int index,
) {
  // Navigating to the Home branch resets to the Home page, so select after.
  if (sidebar.selectedIndex != 0) sidebar.onNavigate(0);
  tabs.activateTab(index);
  tabs.showDocument();
}

String _shortcut(String key) => DsWindow.isMacOS ? '⌘$key' : 'Ctrl+$key';

// ---------------------------------------------------------------------------
// Full sidebar
// ---------------------------------------------------------------------------

class _FullContent extends ConsumerWidget {
  const _FullContent({required this.sidebar, required this.tabs});

  final DsWorkspaceSidebar sidebar;
  final DocumentTabsController tabs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentsProvider).asData?.value ??
        const <LocalFileRef>[];
    final favorites = ref.watch(favoritesProvider).asData?.value ??
        const <LocalFileRef>[];
    final collapsed = ref.watch(dsSidebarProvider).collapsedSections;
    final tools = buildHomeToolCatalog(context, ref);
    final openTabs = tabs.tabs;
    final dests = sidebar.destinations;

    Widget section(
      String id,
      String title,
      List<Widget> children, {
      Widget? action,
    }) {
      return _SidebarSection(
        title: title,
        collapsed: collapsed.contains(id),
        onToggle: () => ref.read(dsSidebarProvider.notifier).toggleSection(id),
        action: action,
        children: children,
      );
    }

    final byCategory = <HomeToolCategory, List<HomeTool>>{};
    for (final t in tools) {
      byCategory.putIfAbsent(t.category, () => []).add(t);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SidebarHeader(showCollapseToggle: sidebar.showCollapseToggle),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
          child: _QuickActions(
            onOpen: () => HomeScreen.openPdfFromPicker(context, ref),
            onCreate: () => pushHomeToolRoute(
              context,
              ref,
              createPdfRoutePath,
              documentEntry: HomeToolDocumentEntry.standalone,
            ),
            onSearch: () => showDocumentStudioCommandPalette(context),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            children: [
              section('library', 'Library', [
                for (var i = 0; i < dests.length; i++)
                  if (i != DsWorkspaceSidebar._settingsIndex)
                    _SidebarItem(
                      icon: sidebar.selectedIndex == i
                          ? dests[i].selectedIcon
                          : dests[i].icon,
                      label: dests[i].label,
                      selected: sidebar.selectedIndex == i &&
                          !(i == 0 && sidebar.documentsVisible),
                      onTap: () => sidebar.onNavigate(i),
                    ),
              ]),
              if (openTabs.isNotEmpty)
                section(
                  'open',
                  'Open documents',
                  [
                    for (var i = 0; i < openTabs.length; i++)
                      _SidebarItem(
                        key: ValueKey('sidebar_tab_${openTabs[i].id}'),
                        icon: Icons.picture_as_pdf_rounded,
                        iconColor: DsColors.primary,
                        label: openTabs[i].file.displayName,
                        tooltip: openTabs[i].session.sourcePath,
                        dirty: openTabs[i].session,
                        selected: sidebar.documentsVisible &&
                            !tabs.isHomeActive &&
                            tabs.activeIndex == i,
                        onTap: () => _activateTab(sidebar, tabs, i),
                        onClose: () async {
                          final ok = await confirmCloseDocumentTab(
                            context: context,
                            ref: ref,
                            tabs: tabs,
                            index: i,
                          );
                          if (ok) tabs.closeTab(i);
                        },
                      ),
                  ],
                  action: _CountBadge(count: openTabs.length),
                ),
              section(
                'pinned',
                'Pinned',
                favorites.isEmpty
                    ? [
                        const _SidebarHint(
                          icon: Icons.star_outline_rounded,
                          text: 'Star a document on Home to pin it here.',
                        ),
                      ]
                    : [
                        for (final f in favorites.take(6))
                          _SidebarItem(
                            icon: Icons.star_rounded,
                            iconColor: const Color(0xFFF5B400),
                            label: f.displayName,
                            tooltip: f.path,
                            onTap: () => _openFile(context, ref, f),
                          ),
                      ],
              ),
              section(
                'recent',
                'Recent',
                recents.isEmpty
                    ? [
                        const _SidebarHint(
                          icon: Icons.history_rounded,
                          text: 'Documents you open appear here.',
                        ),
                      ]
                    : [
                        for (final f in recents.take(6))
                          _SidebarItem(
                            icon: Icons.description_outlined,
                            label: f.displayName,
                            tooltip: f.path,
                            onTap: () => _openFile(context, ref, f),
                          ),
                      ],
              ),
              for (final category in HomeToolCategory.values)
                if (byCategory[category] case final list? when list.isNotEmpty)
                  section(
                    'tools_${category.name}',
                    category.title,
                    [
                      for (final t in list)
                        _SidebarItem(
                          icon: t.icon,
                          label: t.label,
                          tooltip: t.subtitle,
                          enabled: t.availability ==
                                  HomeToolAvailability.available &&
                              t.onTap != null,
                          trailingText: t.availability ==
                                  HomeToolAvailability.comingSoon
                              ? 'Soon'
                              : null,
                          onTap: t.onTap ?? () {},
                        ),
                    ],
                  ),
            ],
          ),
        ),
        _StorageFooter(
          recentCount: recents.length,
          pinnedCount: favorites.length,
          settings: sidebar.destinations[DsWorkspaceSidebar._settingsIndex],
          settingsSelected:
              sidebar.selectedIndex == DsWorkspaceSidebar._settingsIndex,
          onSettings: () =>
              sidebar.onNavigate(DsWorkspaceSidebar._settingsIndex),
        ),
      ],
    );
  }
}

class _SidebarHeader extends ConsumerWidget {
  const _SidebarHeader({required this.showCollapseToggle});

  final bool showCollapseToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
      child: Row(
        children: [
          const _BrandMark(size: 26),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Document Studio',
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: theme.textTheme.titleSmall?.copyWith(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (showCollapseToggle)
            _SmallIconButton(
              icon: Icons.view_sidebar_outlined,
              tooltip: 'Collapse sidebar',
              onPressed: () =>
                  ref.read(dsSidebarProvider.notifier).toggleCollapsed(),
            ),
        ],
      ),
    );
  }
}

/// Icon portion of the brand lockup (the wordmark is cropped away).
class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipRect(
        child: OverflowBox(
          maxWidth: size * 1.6,
          maxHeight: size * 1.6,
          alignment: const Alignment(0, -0.62),
          child: Image.asset(
            DsBrandAssets.documentStudioLogoTransparent,
            width: size * 1.6,
            height: size * 1.6,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => Icon(
              Icons.description_rounded,
              size: size * 0.8,
              color: DsColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onOpen,
    required this.onCreate,
    required this.onSearch,
  });

  final VoidCallback onOpen;
  final VoidCallback onCreate;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionTile(
            icon: Icons.folder_open_rounded,
            label: 'Open',
            tooltip: 'Open PDF (${_shortcut('O')})',
            primary: true,
            onTap: onOpen,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _QuickActionTile(
            icon: Icons.note_add_outlined,
            label: 'New',
            tooltip: 'Create PDF',
            onTap: onCreate,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _QuickActionTile(
            icon: Icons.search_rounded,
            label: 'Search',
            tooltip: 'Command palette (${_shortcut('K')})',
            onTap: onSearch,
          ),
        ),
      ],
    );
  }
}

class _QuickActionTile extends StatefulWidget {
  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;
  final bool primary;

  @override
  State<_QuickActionTile> createState() => _QuickActionTileState();
}

class _QuickActionTileState extends State<_QuickActionTile> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final isDark = brightness == Brightness.dark;
    final fg = widget.primary ? DsColors.primary : DsColors.textPrimary(brightness);
    final bg = widget.primary
        ? DsColors.primary.withValues(alpha: _hovered ? 0.16 : 0.10)
        : (isDark ? Colors.white : Colors.black)
            .withValues(alpha: _hovered ? 0.08 : 0.04);

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _pressed ? 0.96 : 1,
            duration: DsMotion.hoverDuration,
            curve: DsMotion.switchCurve,
            child: AnimatedContainer(
              duration: DsMotion.hoverDuration,
              curve: DsMotion.switchCurve,
              height: 52,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(DsSpacing.radiusGrouped),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, size: 18, color: fg),
                  const SizedBox(height: 3),
                  Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Finder-style group: small header, disclosure chevron, animated body.
class _SidebarSection extends StatefulWidget {
  const _SidebarSection({
    required this.title,
    required this.collapsed,
    required this.onToggle,
    required this.children,
    this.action,
  });

  final String title;
  final bool collapsed;
  final VoidCallback onToggle;
  final List<Widget> children;
  final Widget? action;

  @override
  State<_SidebarSection> createState() => _SidebarSectionState();
}

class _SidebarSectionState extends State<_SidebarSection> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = DsColors.textSecondary(theme.brightness);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onToggle,
              child: Semantics(
                button: true,
                expanded: !widget.collapsed,
                label: widget.title,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 6, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                            color: muted,
                          ),
                        ),
                      ),
                      ?widget.action,
                      AnimatedOpacity(
                        duration: DsMotion.hoverDuration,
                        opacity: _hovered || widget.collapsed ? 1 : 0,
                        child: AnimatedRotation(
                          turns: widget.collapsed ? -0.25 : 0,
                          duration: DsMotion.sidebarDuration,
                          curve: DsMotion.emphasizedCurve,
                          child: Icon(
                            Icons.expand_more_rounded,
                            size: 16,
                            color: muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ClipRect(
            child: AnimatedSize(
              duration: DsMotion.sidebarDuration,
              curve: DsMotion.emphasizedCurve,
              alignment: Alignment.topCenter,
              child: widget.collapsed
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: widget.children,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.enabled = true,
    this.iconColor,
    this.tooltip,
    this.trailingText,
    this.onClose,
    this.dirty,
    this.iconOnly = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool enabled;
  final Color? iconColor;
  final String? tooltip;
  final String? trailingText;
  final VoidCallback? onClose;

  /// Shows an unsaved-changes dot while the session is dirty.
  final DocumentSession? dirty;
  final bool iconOnly;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final isDark = brightness == Brightness.dark;
    final selected = widget.selected;
    final enabled = widget.enabled;
    final primaryInk = DsColors.textPrimary(brightness);
    final muted = DsColors.textSecondary(brightness);

    final bg = selected
        ? DsColors.primary.withValues(alpha: isDark ? 0.22 : 0.12)
        : (_hovered && enabled
            ? (isDark ? Colors.white : Colors.black)
                .withValues(alpha: isDark ? 0.07 : 0.05)
            : Colors.transparent);
    final iconColor = !enabled
        ? muted.withValues(alpha: 0.5)
        : selected
            ? DsColors.primary
            : (widget.iconColor ?? muted);
    final textColor = !enabled
        ? muted.withValues(alpha: 0.6)
        : selected
            ? (isDark ? const Color(0xFFFFB3C0) : DsColors.primaryDark)
            : primaryInk;

    Widget icon = Icon(widget.icon, size: 17, color: iconColor);
    final session = widget.dirty;
    if (session != null) {
      icon = ListenableBuilder(
        listenable: session,
        builder: (context, child) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              child!,
              if (session.isDirty)
                const Positioned(
                  right: -2,
                  top: -1,
                  child: _Dot(color: DsColors.warning),
                ),
            ],
          );
        },
        child: icon,
      );
    }

    final showClose = widget.onClose != null && _hovered && !widget.iconOnly;

    final content = AnimatedContainer(
      duration: DsMotion.hoverDuration,
      curve: DsMotion.switchCurve,
      height: 30,
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: EdgeInsets.symmetric(horizontal: widget.iconOnly ? 0 : 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: widget.iconOnly
          ? Center(child: icon)
          : Row(
              children: [
                icon,
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      height: 1.2,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                ),
                if (widget.trailingText != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: muted.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.trailingText!,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(fontSize: 10, color: muted),
                    ),
                  ),
                if (widget.onClose != null)
                  AnimatedOpacity(
                    duration: DsMotion.hoverDuration,
                    opacity: showClose ? 1 : 0,
                    child: IgnorePointer(
                      ignoring: !showClose,
                      child: _SmallIconButton(
                        icon: Icons.close_rounded,
                        tooltip: 'Close',
                        size: 20,
                        iconSize: 13,
                        onPressed: widget.onClose!,
                      ),
                    ),
                  ),
              ],
            ),
    );

    Widget result = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: enabled ? widget.onTap : null,
        child: Semantics(
          button: true,
          enabled: enabled,
          selected: selected,
          label: widget.label,
          child: AnimatedScale(
            scale: _pressed ? 0.98 : 1,
            duration: DsMotion.hoverDuration,
            child: content,
          ),
        ),
      ),
    );

    final tip = widget.iconOnly ? widget.label : widget.tooltip;
    if (tip != null && tip.isNotEmpty) {
      result = Tooltip(
        message: tip,
        waitDuration: Duration(milliseconds: widget.iconOnly ? 300 : 900),
        preferBelow: false,
        child: result,
      );
    }
    return result;
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _SidebarHint extends StatelessWidget {
  const _SidebarHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = DsColors.textSecondary(theme.brightness);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: muted.withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11.5,
                height: 1.35,
                color: muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedSwitcher(
      duration: DsMotion.switchDuration,
      transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
      child: Container(
        key: ValueKey(count),
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: DsColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$count',
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: DsColors.primary,
          ),
        ),
      ),
    );
  }
}

class _StorageFooter extends StatelessWidget {
  const _StorageFooter({
    required this.recentCount,
    required this.pinnedCount,
    required this.settings,
    required this.settingsSelected,
    required this.onSettings,
  });

  final int recentCount;
  final int pinnedCount;
  final DsSidebarDestination settings;
  final bool settingsSelected;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final isDark = brightness == Brightness.dark;
    final muted = DsColors.textSecondary(brightness);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            decoration: BoxDecoration(
              color: (isDark ? Colors.white : Colors.black)
                  .withValues(alpha: isDark ? 0.05 : 0.035),
              borderRadius: BorderRadius.circular(DsSpacing.radiusGrouped),
            ),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: DsColors.success.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    size: 14,
                    color: DsColors.success,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'On this device',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Private · offline · $recentCount recent · '
                        '$pinnedCount pinned',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontSize: 10.5, color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _SidebarItem(
            icon: settingsSelected ? settings.selectedIcon : settings.icon,
            label: settings.label,
            selected: settingsSelected,
            onTap: onSettings,
          ),
        ],
      ),
    );
  }
}

class _SmallIconButton extends StatefulWidget {
  const _SmallIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 26,
    this.iconSize = 17,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;

  @override
  State<_SmallIconButton> createState() => _SmallIconButtonState();
}

class _SmallIconButtonState extends State<_SmallIconButton> {
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
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: _hovered
                  ? DsColors.textPrimary(brightness).withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: DsColors.textSecondary(brightness),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rail (icon-only) sidebar
// ---------------------------------------------------------------------------

class _RailContent extends ConsumerWidget {
  const _RailContent({required this.sidebar, required this.tabs});

  final DsWorkspaceSidebar sidebar;
  final DocumentTabsController tabs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dests = sidebar.destinations;
    final openTabs = tabs.tabs;
    final settings = dests[DsWorkspaceSidebar._settingsIndex];
    final brightness = Theme.of(context).brightness;

    Widget divider() => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          child: Divider(
            height: 1,
            thickness: 0.5,
            color: DsColors.border(brightness),
          ),
        );

    return Column(
      children: [
        const SizedBox(height: 12),
        const _BrandMark(size: 28),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              _SidebarItem(
                iconOnly: true,
                icon: Icons.folder_open_rounded,
                iconColor: DsColors.primary,
                label: 'Open PDF (${_shortcut('O')})',
                onTap: () => HomeScreen.openPdfFromPicker(context, ref),
              ),
              _SidebarItem(
                iconOnly: true,
                icon: Icons.search_rounded,
                label: 'Command palette (${_shortcut('K')})',
                onTap: () => showDocumentStudioCommandPalette(context),
              ),
              divider(),
              for (var i = 0; i < dests.length; i++)
                if (i != DsWorkspaceSidebar._settingsIndex)
                  _SidebarItem(
                    iconOnly: true,
                    icon: sidebar.selectedIndex == i
                        ? dests[i].selectedIcon
                        : dests[i].icon,
                    label: dests[i].label,
                    selected: sidebar.selectedIndex == i &&
                        !(i == 0 && sidebar.documentsVisible),
                    onTap: () => sidebar.onNavigate(i),
                  ),
              if (openTabs.isNotEmpty) divider(),
              for (var i = 0; i < openTabs.length; i++)
                _SidebarItem(
                  key: ValueKey('rail_tab_${openTabs[i].id}'),
                  iconOnly: true,
                  icon: Icons.picture_as_pdf_rounded,
                  iconColor: DsColors.primary,
                  label: openTabs[i].file.displayName,
                  dirty: openTabs[i].session,
                  selected: sidebar.documentsVisible &&
                      !tabs.isHomeActive &&
                      tabs.activeIndex == i,
                  onTap: () => _activateTab(sidebar, tabs, i),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            children: [
              if (sidebar.showCollapseToggle)
                _SidebarItem(
                  iconOnly: true,
                  icon: Icons.view_sidebar_outlined,
                  label: 'Expand sidebar',
                  onTap: () =>
                      ref.read(dsSidebarProvider.notifier).toggleCollapsed(),
                ),
              _SidebarItem(
                iconOnly: true,
                icon: sidebar.selectedIndex == DsWorkspaceSidebar._settingsIndex
                    ? settings.selectedIcon
                    : settings.icon,
                label: settings.label,
                selected:
                    sidebar.selectedIndex == DsWorkspaceSidebar._settingsIndex,
                onTap: () =>
                    sidebar.onNavigate(DsWorkspaceSidebar._settingsIndex),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
