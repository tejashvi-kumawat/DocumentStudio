import 'package:document_studio/features/home/home_shell_action_bar.dart';
import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/errors/document_studio_error_ui.dart';
import 'package:document_studio/design_system/brand/ds_document_studio_logo.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_shell_page.dart';
import 'package:document_studio/design_system/widgets/ds_hover_lift.dart';
import 'package:document_studio/design_system/widgets/ds_page_busy_bar.dart';
import 'package:document_studio/design_system/widgets/ds_reveal.dart';
import 'package:document_studio/design_system/widgets/ds_search_field.dart';
import 'package:document_studio/design_system/widgets/ds_section_header.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/conversion/conversion_route.dart';
import 'package:document_studio/features/home/home_document_card.dart';
import 'package:document_studio/features/home/home_documents_panel.dart';
import 'package:document_studio/features/home/home_drop_zone.dart';
import 'package:document_studio/features/home/home_left_nav.dart';
import 'package:document_studio/features/home/home_pdf_drop_target.dart';
import 'package:document_studio/features/home/home_pdf_open_flow.dart';
import 'package:document_studio/features/home/home_pdf_open_mode.dart';
import 'package:document_studio/features/home/home_recent_activity.dart';
import 'package:document_studio/features/home/home_recents_filter.dart';
import 'package:document_studio/features/home/home_suggested_tools.dart';
import 'package:document_studio/features/home/home_tool.dart';
import 'package:document_studio/features/home/home_tool_route.dart';
import 'package:document_studio/features/compose/template_gallery_screen.dart';
import 'package:document_studio/features/office/office_route.dart';
import 'package:document_studio/features/page_management/shared/organize_accessible_files.dart';
import 'package:document_studio/features/pdf_viewer/shell_pdf_open.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();

  /// Opens the system file picker and navigates to the viewer when successful.
  static Future<void> openPdfFromPicker(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await _openPdf(context, ref);
  }

  static Future<void> _openDroppedPdf(
    BuildContext context,
    WidgetRef ref,
    LocalFileRef file,
  ) async {
    if (!context.mounted) return;
    if (isOfficePath(file.path)) {
      context.push(officeLocation(path: file.path));
      return;
    }
    await homeShowPdfOpenChooserAndNavigate(context, ref, file);
  }

  static Future<void> _openPdf(BuildContext context, WidgetRef ref) async {
    final storage = ref.read(fileStorageProvider);
    try {
      final picked = await storage.pickOpenFile(
        allowedExtensions: const ['pdf', ...officeExtensions],
      );
      if (picked == null || !context.mounted) return;
      if (isOfficePath(picked.path)) {
        context.push(officeLocation(path: picked.path));
        return;
      }
      await homeOpenPdfWithMode(context, ref, picked, HomePdfOpenMode.read);
    } on DocumentStudioError catch (e) {
      if (!context.mounted) return;
      _showError(context, e);
    }
  }

  static Future<void> _openRecent(
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
          message: 'Recent file missing',
          recoveryHint: 'The file may have moved or been deleted.',
        ),
      );
      return;
    }
    if (!context.mounted) return;
    if (isOfficePath(file.path)) {
      context.push(officeLocation(path: file.path));
      return;
    }
    if (file.isPdf) {
      final mode = await homeLastOpenModeFor(ref, file.path);
      if (!context.mounted) return;
      await homeOpenPdfWithMode(context, ref, file, mode);
      return;
    }
    await _openRef(context, ref, file);
  }

  static Future<void> _openRef(
    BuildContext context,
    WidgetRef ref,
    LocalFileRef file,
  ) async {
    // Single open via shell resolve + viewer warm lease (no pre-validate).
    await ref.read(recentsProvider.notifier).addRecent(file);
    if (!context.mounted) return;
    await openPdfInShellViewer(context, ref, file);
  }

  static void _showError(BuildContext context, DocumentStudioError e) {
    showDocumentStudioErrorSnackBar(context, e);
  }
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const _viewPrefKey = 'home.documents_view';

  String _recentsSearchQuery = '';
  HomeRecentsSort _recentsSort = HomeRecentsSort.recentFirst;
  HomeSidebarSection _sidebarSection = HomeSidebarSection.recent;
  HomeDocumentsView _view = HomeDocumentsView.list;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _restoreView();
  }

  Future<void> _restoreView() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_viewPrefKey);
      if (!mounted || stored == null) return;
      final view = HomeDocumentsView.values.firstWhere(
        (v) => v.name == stored,
        orElse: () => _view,
      );
      if (view != _view) setState(() => _view = view);
    } catch (_) {}
  }

  Future<void> _setView(HomeDocumentsView view) async {
    setState(() => _view = view);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_viewPrefKey, view.name);
    } catch (_) {}
  }

  void _toggleFavorite(LocalFileRef file) {
    ref.read(favoritesProvider.notifier).toggleFavorite(file);
  }

  @override
  Widget build(BuildContext context) {
    final recentsAsync = ref.watch(recentsProvider);
    final favoritesAsync = ref.watch(favoritesProvider);
    final favoritePaths = {
      for (final f in favoritesAsync.asData?.value ?? const <LocalFileRef>[])
        f.path,
    };
    final suggestedTools = buildHomeSuggestedTools(context, ref);
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final denseDocuments = width >= DsSpacing.breakpointCompact;
    final compact = width < DsSpacing.breakpointCompact;
    final contentInset = dsShellContentHorizontalPadding(width);
    final recents = recentsAsync.asData?.value ?? const <LocalFileRef>[];
    final favorites = favoritesAsync.asData?.value ?? const <LocalFileRef>[];

    void openFile(LocalFileRef file) =>
        HomeScreen._openRecent(context, ref, file);

    Widget? buildDropZone({required bool tall}) {
      if (!denseDocuments) return null;
      return HomeDropZone(
        tall: tall,
        active: _dragging,
        onBrowse: () => HomeScreen._openPdf(context, ref),
      );
    }

    final viewAllTools = TextButton(
      onPressed: () => context.go('/tools'),
      style: TextButton.styleFrom(
        foregroundColor: DsColors.primary,
        textStyle: theme.textTheme.labelLarge?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: const Text('View all tools'),
    );

    final toolsSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DsSectionHeader(
          title: 'Suggested tools',
          icon: Icons.auto_awesome_outlined,
          action: viewAllTools,
        ),
        HomeSuggestedToolsRow(tiles: suggestedTools),
      ],
    );

    final activitySection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DsSectionHeader(
          title: 'Recent activity',
          icon: Icons.history_rounded,
        ),
        HomeRecentActivity(recents: recents, onOpen: openFile),
      ],
    );

    final sections = <Widget>[
      _HomeHero(
        onOpenPdf: () => HomeScreen._openPdf(context, ref),
        onCreatePdf: () => pushHomeToolRoute(
          context,
          ref,
          createPdfRoutePath,
          documentEntry: HomeToolDocumentEntry.standalone,
        ),
        onImagesToPdf: () => pushHomeToolRoute(
          context,
          ref,
          imagesToPdfRoutePath,
          documentEntry: HomeToolDocumentEntry.standalone,
        ),
        onAllTools: () => context.go('/tools'),
        onNewWord: () => context.push(officeLocation(kind: 'docx')),
        onNewSlides: () => context.push(officeLocation(kind: 'pptx')),
        onTemplates: () => context.push(templateGalleryRoutePath),
        onOpenOffice: () async {
          final f = await ref
              .read(fileStorageProvider)
              .pickOpenFile(allowedExtensions: officeExtensions);
          if (f != null && context.mounted) {
            context.push(officeLocation(path: f.path));
          }
        },
        dropZoneBuilder: buildDropZone,
      ),
      if (favorites.isNotEmpty)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DsSectionHeader(
              title: 'Pinned',
              icon: Icons.star_rounded,
              count: favorites.length,
            ),
            HomePinnedStrip(
              files: favorites,
              onOpen: openFile,
              onToggleStar: _toggleFavorite,
            ),
          ],
        ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DsSectionHeader(
            title: 'Documents',
            icon: Icons.folder_open_rounded,
          ),
          Wrap(
            spacing: DsSpacing.sm,
            runSpacing: DsSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: width >= 480 ? 280 : double.infinity,
                child: DsSearchField(
                  fieldKey: const Key('home_recents_search'),
                  hintText: 'Search documents',
                  onChanged: (value) =>
                      setState(() => _recentsSearchQuery = value),
                ),
              ),
              for (final section in HomeSidebarSection.values)
                _HomeFilterChip(
                  label: section.label,
                  selected: _sidebarSection == section,
                  onSelected: () => setState(() => _sidebarSection = section),
                ),
            ],
          ),
          const SizedBox(height: DsSpacing.sm),
          OrganizeAccessibleFilesList(onOpen: openFile, maxRecents: 0),
          AnimatedSize(
            duration: DsMotion.switchDuration,
            curve: DsMotion.switchCurve,
            alignment: Alignment.topCenter,
            child: HomeDocumentsPanel(
              section: _sidebarSection,
              recents: recents,
              favorites: favorites,
              favoritePaths: favoritePaths,
              query: _recentsSearchQuery,
              sort: _recentsSort,
              onSortChanged: (value) => setState(() => _recentsSort = value),
              onOpenDocument: HomeScreen._openRecent,
              onOpenPdf: () => HomeScreen._openPdf(context, ref),
              onToggleFavorite: _toggleFavorite,
              showPath: !denseDocuments,
              view: _view,
              onViewChanged: _setView,
            ),
          ),
        ],
      ),
      LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 860 && recents.isNotEmpty) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: toolsSection),
                const SizedBox(width: DsSpacing.lg),
                Expanded(flex: 2, child: activitySection),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              toolsSection,
              if (recents.isNotEmpty) ...[
                const SizedBox(height: DsSpacing.shellSectionGap),
                activitySection,
              ],
            ],
          );
        },
      ),
    ];

    final scroll = CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            contentInset,
            compact ? DsSpacing.md : DsSpacing.lg,
            contentInset,
            DsSpacing.shellPageBottom,
          ),
          sliver: SliverToBoxAdapter(
            child: DsShellPageFrame(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < sections.length; i++) ...[
                    if (i > 0)
                      SizedBox(
                        height: compact
                            ? DsSpacing.lg
                            : DsSpacing.shellSectionGap,
                      ),
                    DsStaggeredReveal(index: i * 2, child: sections[i]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );

    return ColoredBox(
      color: DsColors.groupedBackground(theme.brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HomeShellActionBar(),
          Expanded(
            child: Stack(
              children: [
                HomePdfDropTarget(
                  enabled: denseDocuments,
                  onDragActiveChanged: (active) {
                    if (mounted && active != _dragging) {
                      setState(() => _dragging = active);
                    }
                  },
                  onPdfDropped: (file) =>
                      HomeScreen._openDroppedPdf(context, ref, file),
                  child: scroll,
                ),
                DsPageBusyBar(
                  visible: recentsAsync.isLoading,
                  message: recentsAsync.isLoading ? 'Loading documents…' : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Selected filter uses brand red — never Material secondary/teal defaults.
class _HomeFilterChip extends StatelessWidget {
  const _HomeFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = DsColors.primary;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;

    return AnimatedContainer(
      duration: DsMotion.hoverDuration,
      curve: DsMotion.switchCurve,
      height: 32,
      decoration: BoxDecoration(
        color: selected
            ? primary.withValues(alpha: isDark ? 0.18 : 0.10)
            : DsColors.groupedCell(theme.brightness),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? primary.withValues(alpha: 0.6) : border,
          width: selected ? 1 : 0.5,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onSelected,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: DsSpacing.md),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected
                      ? primary
                      : DsColors.textSecondary(theme.brightness),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _greeting(DateTime now) {
  final h = now.hour;
  if (h < 5) return 'Working late';
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}

/// Hero: brand greeting, quick actions, and the drop zone.
class _HomeHero extends StatelessWidget {
  const _HomeHero({
    required this.onOpenPdf,
    required this.onCreatePdf,
    required this.onImagesToPdf,
    required this.onAllTools,
    required this.onNewWord,
    required this.onNewSlides,
    required this.onTemplates,
    required this.onOpenOffice,
    required this.dropZoneBuilder,
  });

  final VoidCallback onOpenPdf;
  final VoidCallback onCreatePdf;
  final VoidCallback onImagesToPdf;
  final VoidCallback onAllTools;
  final VoidCallback onNewWord, onNewSlides, onTemplates, onOpenOffice;
  final Widget? Function({required bool tall}) dropZoneBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = DsColors.textSecondary(theme.brightness);
    final viewportW = MediaQuery.sizeOf(context).width;
    final compact = viewportW < DsSpacing.breakpointCompact;

    final heading = Row(
      children: [
        DsDocumentStudioLogo(height: compact ? 28 : 44),
        SizedBox(width: compact ? DsSpacing.sm : DsSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(DateTime.now()),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: compact ? 17 : 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  height: 1.15,
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 2),
                Text(
                  'Open and edit PDFs, Word documents and presentations — everything stays on this device.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    color: secondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    final actions = _HomeQuickActions(
      onOpenPdf: onOpenPdf,
      onCreatePdf: onCreatePdf,
      onImagesToPdf: onImagesToPdf,
      onAllTools: onAllTools,
      onNewWord: onNewWord,
      onNewSlides: onNewSlides,
      onTemplates: onTemplates,
      onOpenOffice: onOpenOffice,
    );

    // Phone: no giant gradient hero card — flat dense section like Acrobat home.
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading,
          const SizedBox(height: DsSpacing.md),
          actions,
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DsSpacing.radiusCard + 4),
        border: Border.all(
          color: DsColors.border(theme.brightness),
          width: isDark ? 1 : 0.5,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Color.alphaBlend(
                    DsColors.primary.withValues(alpha: 0.10),
                    DsColors.groupedCellDark,
                  ),
                  DsColors.groupedCellDark,
                ]
              : [
                  Color.alphaBlend(
                    DsColors.primary.withValues(alpha: 0.05),
                    Colors.white,
                  ),
                  Colors.white,
                ],
        ),
        boxShadow: isDark ? null : DsSpacing.cardShadowLight(opacity: 0.05),
      ),
      padding: const EdgeInsets.all(DsSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 820;
          if (wide) {
            final drop = dropZoneBuilder(tall: true);
            // The quick-action tiles use LayoutBuilder. IntrinsicHeight asks
            // every child for an intrinsic height, which LayoutBuilder refuses,
            // so the hero never gets a size and the frame cascades into
            // "was not laid out", null checks, and parentDataDirty.
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      heading,
                      const SizedBox(height: DsSpacing.lg),
                      actions,
                    ],
                  ),
                ),
                if (drop != null) ...[
                  const SizedBox(width: DsSpacing.lg),
                  SizedBox(width: 260, child: drop),
                ],
              ],
            );
          }
          final drop = dropZoneBuilder(tall: false);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              const SizedBox(height: DsSpacing.lg),
              actions,
              if (drop != null) ...[const SizedBox(height: DsSpacing.md), drop],
            ],
          );
        },
      ),
    );
  }
}

class _HomeQuickActions extends StatelessWidget {
  const _HomeQuickActions({
    required this.onOpenPdf,
    required this.onCreatePdf,
    required this.onImagesToPdf,
    required this.onAllTools,
    required this.onNewWord,
    required this.onNewSlides,
    required this.onTemplates,
    required this.onOpenOffice,
  });

  final VoidCallback onOpenPdf;
  final VoidCallback onCreatePdf;
  final VoidCallback onImagesToPdf;
  final VoidCallback onAllTools;
  final VoidCallback onNewWord, onNewSlides, onTemplates, onOpenOffice;

  static const _openPdfKey = Key('home_hero_open_pdf');

  @override
  Widget build(BuildContext context) {
    final actions = [
      (
        key: _openPdfKey as Key?,
        primary: true,
        icon: Icons.folder_open_rounded,
        title: 'Open file',
        subtitle: 'PDF, Word or PowerPoint',
        onTap: onOpenPdf,
      ),
      (
        key: const Key('home_new_word') as Key?,
        primary: false,
        icon: Icons.description_outlined,
        title: 'New document',
        subtitle: 'Word (.docx)',
        onTap: onNewWord,
      ),
      (
        key: const Key('home_new_slides') as Key?,
        primary: false,
        icon: Icons.slideshow_outlined,
        title: 'New presentation',
        subtitle: 'PowerPoint (.pptx)',
        onTap: onNewSlides,
      ),
      (
        key: null as Key?,
        primary: false,
        icon: Icons.file_open_outlined,
        title: 'Open Word / PowerPoint',
        subtitle: 'Edit .docx and .pptx',
        onTap: onOpenOffice,
      ),
      (
        key: null as Key?,
        primary: false,
        icon: Icons.note_add_outlined,
        title: 'Create PDF',
        subtitle: 'Blank or from text',
        onTap: onCreatePdf,
      ),
      (
        key: null as Key?,
        primary: false,
        icon: Icons.photo_library_outlined,
        title: 'Images to PDF',
        subtitle: 'Photos, scans, screenshots',
        onTap: onImagesToPdf,
      ),
      (
        key: null as Key?,
        primary: false,
        icon: Icons.auto_awesome_mosaic_outlined,
        title: 'Templates',
        subtitle: 'Résumés, letters, invoices…',
        onTap: onTemplates,
      ),
      (
        key: null as Key?,
        primary: false,
        icon: Icons.apps_rounded,
        title: 'All tools',
        subtitle: 'Merge, split, compress…',
        onTap: onAllTools,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        // Prefer 2+ columns on phone; only collapse to 1 under ~280px.
        final columns = w >= DsSpacing.breakpointExpanded
            ? 4
            : (w >= DsSpacing.breakpointCompact ? 4 : (w >= 280 ? 2 : 1));
        const gap = DsSpacing.sm;
        final tileW = (w - gap * (columns - 1)) / columns;
        final compact = w < DsSpacing.breakpointCompact;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < actions.length; i++)
              SizedBox(
                width: tileW,
                child: DsStaggeredReveal(
                  index: i + 1,
                  child: _QuickActionTile(
                    key: actions[i].key,
                    primary: actions[i].primary,
                    icon: actions[i].icon,
                    title: actions[i].title,
                    subtitle: actions[i].subtitle,
                    onTap: actions[i].onTap,
                    compact: compact,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _QuickActionTile extends StatefulWidget {
  const _QuickActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool primary;
  final bool compact;

  @override
  State<_QuickActionTile> createState() => _QuickActionTileState();
}

class _QuickActionTileState extends State<_QuickActionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = DsColors.textSecondary(theme.brightness);
    final radius = BorderRadius.circular(DsSpacing.radiusCard);
    final primary = widget.primary;

    final bg = primary
        ? (_hovered ? DsColors.primaryDark : DsColors.primary)
        : DsColors.groupedCell(theme.brightness);
    final fg = primary ? DsColors.onPrimary : null;

    return Semantics(
      button: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: DsHoverLift(
          borderRadius: radius,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: DsMotion.hoverDuration,
            curve: DsMotion.switchCurve,
            height: widget.compact
                ? DsSpacing.controlHeightComfortable + 8
                : 76,
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? DsSpacing.sm + 2 : DsSpacing.md,
              vertical: widget.compact ? DsSpacing.sm : DsSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: radius,
              border: primary
                  ? null
                  : Border.all(
                      color: _hovered
                          ? DsColors.primary.withValues(alpha: 0.35)
                          : DsColors.border(theme.brightness),
                      width: isDark ? 1 : 0.5,
                    ),
              boxShadow: primary
                  ? [
                      BoxShadow(
                        color: DsColors.primary.withValues(
                          alpha: _hovered ? 0.35 : 0.22,
                        ),
                        blurRadius: _hovered ? 16 : 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: DsMotion.hoverDuration,
                  width: widget.compact ? 32 : 36,
                  height: widget.compact ? 32 : 36,
                  decoration: BoxDecoration(
                    color: primary
                        ? Colors.white.withValues(alpha: 0.18)
                        : DsColors.primary.withValues(
                            alpha: _hovered ? 0.14 : (isDark ? 0.18 : 0.08),
                          ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    widget.icon,
                    size: widget.compact ? 18 : 20,
                    color: primary ? DsColors.onPrimary : DsColors.primary,
                  ),
                ),
                SizedBox(
                  width: widget.compact ? DsSpacing.sm : DsSpacing.sm + 2,
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontSize: widget.compact ? 12.5 : 13.5,
                          fontWeight: FontWeight.w600,
                          color: fg,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: widget.compact ? 11 : 11.5,
                          color: primary
                              ? DsColors.onPrimary.withValues(alpha: 0.85)
                              : secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!widget.compact)
                  AnimatedSlide(
                    offset: Offset(_hovered ? 0 : -0.3, 0),
                    duration: DsMotion.hoverDuration,
                    child: AnimatedOpacity(
                      opacity: _hovered ? 1 : 0,
                      duration: DsMotion.hoverDuration,
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: primary ? DsColors.onPrimary : DsColors.primary,
                      ),
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
