import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_grouped_menu_bar.dart';
import 'package:document_studio/features/home/home_tool.dart';
import 'package:document_studio/features/home/home_tool_catalog.dart';
import 'package:document_studio/features/home/home_tool_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Top action strip for Home / Tools / Settings: Edit · Pages · Protect · Tools.
///
/// Opens existing catalog tools — does not invent features. Prefer this over a
/// long row of individual icons on phone width.
class HomeShellActionBar extends ConsumerWidget {
  const HomeShellActionBar({super.key});

  static const _editIds = [
    'edit_text',
    'place_image',
    'draw',
    'watermark',
    'fill_form',
  ];
  static const _pagesIds = [
    'edit_pages',
    'organize',
    'pdf_to_images',
    'create_pdf',
    'images_to_pdf',
  ];
  static const _protectIds = [
    'protect',
    'unlock',
    'visual_sign',
    'metadata',
    'compress',
  ];
  static const _toolsIds = [
    'convert',
    'ocr_image',
    'ocr_searchable_pdf',
    'scan',
    'batch',
  ];

  List<DsGroupedMenuItem> _items(
    List<HomeTool> catalog,
    List<String> ids, {
    int max = 5,
  }) {
    final byId = {for (final t in catalog) t.id: t};
    final out = <DsGroupedMenuItem>[];
    for (final id in ids) {
      if (out.length >= max) break;
      final t = byId[id];
      if (t == null || t.onTap == null) continue;
      if (t.availability == HomeToolAvailability.comingSoon) continue;
      out.add(
        DsGroupedMenuItem(
          label: t.label,
          icon: t.icon,
          onSelected: t.onTap!,
          enabled: t.availability != HomeToolAvailability.blocked,
        ),
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final catalog = buildHomeToolCatalog(context, ref);
    final width = MediaQuery.sizeOf(context).width;
    final iconOnly = width < 400;

    final edit = _items(catalog, _editIds);
    final pages = _items(catalog, _pagesIds);
    final protect = _items(catalog, _protectIds);
    final tools = <DsGroupedMenuItem>[
      DsGroupedMenuItem(
        label: 'All tools',
        icon: Icons.apps_outlined,
        onSelected: () => context.go('/tools'),
      ),
      ..._items(catalog, _toolsIds),
    ];

    return Material(
      color: isDark
          ? DsColors.surfaceContainerDark.withValues(alpha: 0.92)
          : DsColors.surfaceContainerLight.withValues(alpha: 0.96),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isDark ? DsColors.borderDark : DsColors.borderLight,
            ),
          ),
        ),
        child: SizedBox(
          height: DsSpacing.appBarHeightCompact,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: DsSpacing.sm),
            child: Align(
              alignment: Alignment.centerRight,
              child: DsGroupedMenuBar(
                children: [
                  if (edit.isNotEmpty)
                    DsGroupedMenuButton(
                      label: 'Edit',
                      icon: Icons.edit_note_rounded,
                      iconOnly: iconOnly,
                      items: edit,
                    ),
                  if (pages.isNotEmpty)
                    DsGroupedMenuButton(
                      label: 'Pages',
                      icon: Icons.auto_stories_outlined,
                      iconOnly: iconOnly,
                      items: pages,
                    ),
                  if (protect.isNotEmpty)
                    DsGroupedMenuButton(
                      label: 'Security',
                      icon: Icons.verified_user_outlined,
                      iconOnly: iconOnly,
                      items: protect,
                    ),
                  DsGroupedMenuButton(
                    label: 'Tools',
                    icon: Icons.apps_outlined,
                    iconOnly: iconOnly,
                    emphasize: true,
                    items: tools,
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

/// Convenience launcher used when a shell menu needs a one-off tool path.
Future<void> launchShellTool(
  BuildContext context,
  WidgetRef ref,
  String path,
  HomeToolDocumentEntry entry,
) {
  return pushHomeToolRoute(context, ref, path, documentEntry: entry);
}
