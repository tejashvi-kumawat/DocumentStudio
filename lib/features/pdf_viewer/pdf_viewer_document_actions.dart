import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/compression/compress_route.dart';
import 'package:document_studio/features/conversion/conversion_route.dart';
import 'package:document_studio/features/ocr/ocr_route.dart';
import 'package:document_studio/features/page_management/organize_tool_catalog.dart'
    show OrganizeToolCatalog, OrganizeToolAvailability;
import 'package:document_studio/features/page_management/tools/page_box_qpdf_tool_shared.dart';
import 'package:document_studio/features/home/home_tool_route.dart';
import 'package:document_studio/features/pdf_viewer/pdf_document_route_args.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_tool_panel_scope.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio/features/pdf_markup/pdf_markup_route.dart';
import 'package:document_studio/features/document_workspace/workspace_launch_args.dart';
import 'package:document_studio/features/security/security_route.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Active document context for viewer menus and shortcuts.
class PdfViewerDocumentHandoff {
  const PdfViewerDocumentHandoff({
    required this.file,
    this.password,
    this.currentPage1 = 1,
  });

  final LocalFileRef file;
  final String? password;
  final int currentPage1;

  PdfDocumentRouteArgs get documentArgs =>
      PdfDocumentRouteArgs(file: file, password: password);
}

/// Navigate from the viewer to another screen with the open PDF pre-selected.
class PdfViewerDocumentActions {
  PdfViewerDocumentActions._();

  static void openDocumentWorkspace(
    BuildContext context,
    PdfViewerDocumentHandoff doc,
  ) {
    final pw = doc.password;
    final passwords = (pw != null && pw.isNotEmpty)
        ? {doc.file.path: pw}
        : const <String, String>{};
    context.push(
      '/workspace',
      extra: WorkspaceLaunchArgs(
        files: [doc.file],
        passwordsByPath: passwords,
        returnToViewer: true,
      ),
    );
  }

  static void compress(BuildContext context, PdfViewerDocumentHandoff doc) {
    openViewerToolPanelOr(
      context,
      ViewerToolId.compress,
      () => pushCompressForPdf(
        context,
        file: doc.file,
        password: doc.password,
      ),
    );
  }

  static void protect(BuildContext context, PdfViewerDocumentHandoff doc) {
    openViewerToolPanelOr(
      context,
      ViewerToolId.protect,
      () {
        rememberViewerToolReturnFromContext(context, doc.documentArgs);
        context.push(protectRoutePath, extra: doc.documentArgs);
      },
    );
  }

  static void unlock(BuildContext context, PdfViewerDocumentHandoff doc) {
    openViewerToolPanelOr(
      context,
      ViewerToolId.unlock,
      () {
        rememberViewerToolReturnFromContext(context, doc.documentArgs);
        context.push(unlockRoutePath, extra: doc.documentArgs);
      },
    );
  }

  static void editMetadata(BuildContext context, PdfViewerDocumentHandoff doc) {
    final args = MetadataEditorRouteArgs(
      file: doc.file,
      password: doc.password,
    );
    openViewerToolPanelOr(
      context,
      ViewerToolId.metadata,
      () {
        rememberViewerToolReturnFromContext(context, args);
        context.push(metadataRoutePath, extra: args);
      },
    );
  }

  static void removeMetadata(
    BuildContext context,
    PdfViewerDocumentHandoff doc,
  ) {
    openViewerToolPanelOr(
      context,
      ViewerToolId.removeMetadata,
      () {
        rememberViewerToolReturnFromContext(context, doc.documentArgs);
        context.push(removeMetadataRoutePath, extra: doc.documentArgs);
      },
    );
  }

  static void exportToImages(
    BuildContext context,
    PdfViewerDocumentHandoff doc,
  ) {
    openViewerToolPanelOr(context, ViewerToolId.exportImages, () {
      final args = PdfToImagesRouteArgs(
        file: doc.file,
        page1: doc.currentPage1,
        password: doc.password,
      );
      rememberViewerToolReturnFromContext(context, doc.documentArgs);
      context.push(pdfToImagesRoutePath, extra: args);
    });
  }

  static void splitPdf(BuildContext context, PdfViewerDocumentHandoff doc) {
    openViewerToolPanelOr(
      context,
      ViewerToolId.split,
      () => context.push('/organize/split', extra: doc.documentArgs),
    );
  }

  static void exportToJpg(BuildContext context, PdfViewerDocumentHandoff doc) {
    openViewerToolPanelOr(context, ViewerToolId.exportJpg, () {
      context.push(
        Uri(
          path: pdfToImagesRoutePath,
          queryParameters: const {'format': 'jpeg'},
        ).toString(),
        extra: PdfToImagesRouteArgs(
          file: doc.file,
          page1: doc.currentPage1,
          password: doc.password,
        ),
      );
    });
  }

  static void openImageOcr(BuildContext context, PdfViewerDocumentHandoff doc) {
    openViewerToolPanelOr(context, ViewerToolId.ocrImage, () {
      rememberViewerToolReturnFromContext(context, doc.documentArgs);
      context.push(imageOcrRoutePath, extra: doc.documentArgs);
    });
  }

  static void exportToPng(BuildContext context, PdfViewerDocumentHandoff doc) {
    openViewerToolPanelOr(context, ViewerToolId.exportPng, () {
      context.push(
        Uri(
          path: pdfToImagesRoutePath,
          queryParameters: const {'format': 'png'},
        ).toString(),
        extra: PdfToImagesRouteArgs(
          file: doc.file,
          page1: doc.currentPage1,
          password: doc.password,
        ),
      );
    });
  }

  static void organizeTool(
    BuildContext context,
    PdfViewerDocumentHandoff doc,
    String routePath, {
    Object? extra,
  }) {
    if (routePath.endsWith('/reorder')) {
      openViewerToolPanelOr(
        context,
        ViewerToolId.workspaceReorder,
        () => context.push(routePath, extra: extra ?? doc.documentArgs),
      );
      return;
    }
    if (routePath.endsWith('/reverse')) {
      openViewerToolPanelOr(
        context,
        ViewerToolId.reverse,
        () => context.push(routePath, extra: extra ?? doc.documentArgs),
      );
      return;
    }
    if (routePath.endsWith('/split')) {
      splitPdf(context, doc);
      return;
    }
    if (routePath.endsWith('/merge')) {
      openViewerToolPanelOr(
        context,
        ViewerToolId.workspaceMerge,
        () => context.push(routePath, extra: extra ?? doc.documentArgs),
      );
      return;
    }
    context.push(routePath, extra: extra ?? doc.documentArgs);
  }

  static void cropPages(BuildContext context, PdfViewerDocumentHandoff doc) {
    context.push(
      '/organize/crop',
      extra: PageBoxQpdfToolLaunch(file: doc.file),
    );
  }

  static void resizePages(BuildContext context, PdfViewerDocumentHandoff doc) {
    context.push(
      '/organize/resize',
      extra: PageBoxQpdfToolLaunch(file: doc.file),
    );
  }

  static void headersFooters(BuildContext context, PdfViewerDocumentHandoff doc) {
    openViewerToolPanelOr(
      context,
      ViewerToolId.headersFooters,
      () => context.push(headersFootersRoutePath, extra: doc.documentArgs),
    );
  }

  static void watermark(BuildContext context, PdfViewerDocumentHandoff doc) {
    openViewerToolPanelOr(
      context,
      ViewerToolId.watermark,
      () => context.push(watermarkRoutePath, extra: doc.documentArgs),
    );
  }

  static void pageNumbers(BuildContext context, PdfViewerDocumentHandoff doc) {
    openViewerToolPanelOr(
      context,
      ViewerToolId.pageNumbers,
      () => context.push(pageNumbersRoutePath, extra: doc.documentArgs),
    );
  }
}

/// Acrobat-style **File** menu for the PDF viewer toolbar.
class PdfViewerFileMenuButton extends StatelessWidget {
  const PdfViewerFileMenuButton({
    super.key,
    required this.handoff,
    required this.enabled,
    this.showCaption = true,
    this.onDocumentInfo,
    this.onPrint,
    this.onOpenAnotherPdf,
    this.onExportText,
  });

  final PdfViewerDocumentHandoff handoff;
  final bool enabled;
  final bool showCaption;
  final VoidCallback? onDocumentInfo;
  final VoidCallback? onPrint;
  final VoidCallback? onOpenAnotherPdf;
  final VoidCallback? onExportText;

  @override
  Widget build(BuildContext context) {
    return _PdfViewerToolbarMenuButton(
      label: 'File',
      icon: Icons.folder_open_outlined,
      enabled: enabled,
      showCaption: showCaption,
      items: [
        if (onOpenAnotherPdf != null)
          _ViewerMenuItem(
            label: 'Open…',
            icon: Icons.folder_open_outlined,
            onSelected: onOpenAnotherPdf,
          ),
        _ViewerMenuItem(
          label: 'Open in Document workspace',
          icon: Icons.dashboard_customize_outlined,
          onSelected: () =>
              PdfViewerDocumentActions.openDocumentWorkspace(context, handoff),
        ),
        const PopupMenuDivider(),
        _ViewerMenuItem(
          label: 'Print…',
          icon: Icons.print_outlined,
          onSelected: onPrint,
        ),
        _ViewerMenuItem(
          label: 'Export to images…',
          icon: Icons.image_outlined,
          onSelected: () =>
              PdfViewerDocumentActions.exportToImages(context, handoff),
        ),
        _ViewerMenuItem(
          label: 'Export to JPG…',
          icon: Icons.photo_outlined,
          onSelected: () =>
              PdfViewerDocumentActions.exportToJpg(context, handoff),
        ),
        _ViewerMenuItem(
          label: 'Export to PNG…',
          icon: Icons.image_outlined,
          onSelected: () =>
              PdfViewerDocumentActions.exportToPng(context, handoff),
        ),
        _ViewerMenuItem(
          label: 'Export to text (.txt)…',
          icon: Icons.text_snippet_outlined,
          onSelected: onExportText,
        ),
        _ViewerMenuItem(
          label: 'Compress PDF…',
          icon: Icons.compress,
          onSelected: () => PdfViewerDocumentActions.compress(context, handoff),
        ),
        _ViewerMenuItem(
          label: 'Headers & footers…',
          icon: Icons.vertical_align_center_outlined,
          onSelected: () =>
              PdfViewerDocumentActions.headersFooters(context, handoff),
        ),
        _ViewerMenuItem(
          label: 'Watermark…',
          icon: Icons.branding_watermark_outlined,
          onSelected: () => PdfViewerDocumentActions.watermark(context, handoff),
        ),
        _ViewerMenuItem(
          label: 'Page numbers…',
          icon: Icons.format_list_numbered,
          onSelected: () => PdfViewerDocumentActions.pageNumbers(context, handoff),
        ),
        const PopupMenuDivider(),
        _ViewerMenuItem(
          label: 'Encrypt…',
          icon: Icons.lock_outline,
          onSelected: () => PdfViewerDocumentActions.protect(context, handoff),
        ),
        _ViewerMenuItem(
          label: 'Decrypt…',
          icon: Icons.lock_open_outlined,
          onSelected: () => PdfViewerDocumentActions.unlock(context, handoff),
        ),
        _ViewerMenuItem(
          label: 'Document properties…',
          icon: Icons.info_outline,
          onSelected: onDocumentInfo,
        ),
        _ViewerMenuItem(
          label: 'Edit metadata…',
          icon: Icons.edit_note_outlined,
          onSelected: () =>
              PdfViewerDocumentActions.editMetadata(context, handoff),
        ),
        _ViewerMenuItem(
          label: 'Remove metadata…',
          icon: Icons.cleaning_services_outlined,
          onSelected: () =>
              PdfViewerDocumentActions.removeMetadata(context, handoff),
        ),
      ],
    );
  }
}

/// **Tools** menu for organize + in-document actions.
class PdfViewerToolsMenuButton extends StatelessWidget {
  const PdfViewerToolsMenuButton({
    super.key,
    required this.handoff,
    required this.enabled,
    this.showCaption = true,
    this.onSearch,
    this.onShowBookmarks,
    this.onCopySelection,
    this.onSelectAllText,
    this.ocrBlocked = false,
    this.ocrBlockedReason,
  });

  final PdfViewerDocumentHandoff handoff;
  final bool enabled;
  final bool showCaption;
  final VoidCallback? onSearch;
  final VoidCallback? onShowBookmarks;
  final VoidCallback? onCopySelection;
  final VoidCallback? onSelectAllText;
  final bool ocrBlocked;
  final String? ocrBlockedReason;

  @override
  Widget build(BuildContext context) {
    final organizeTools = OrganizeToolCatalog.tools
        .where((t) => t.availability == OrganizeToolAvailability.available)
        .toList();

    return _PdfViewerToolbarMenuButton(
      label: 'Tools',
      icon: Icons.handyman_outlined,
      enabled: enabled,
      showCaption: showCaption,
      items: [
        _ViewerMenuItem(
          label: 'Find in document',
          icon: Icons.search,
          onSelected: onSearch,
        ),
        _ViewerMenuItem(
          label: 'Bookmarks',
          icon: Icons.bookmarks_outlined,
          onSelected: onShowBookmarks,
        ),
        _ViewerMenuItem(
          label: 'Copy selection',
          icon: Icons.copy_outlined,
          onSelected: onCopySelection,
        ),
        _ViewerMenuItem(
          label: 'Select all text',
          icon: Icons.select_all,
          onSelected: onSelectAllText,
        ),
        _ViewerMenuItem(
          label: ocrBlocked
              ? 'Recognize text (OCR)… — unavailable'
              : 'Recognize text (OCR)…',
          icon: Icons.document_scanner_outlined,
          onSelected: ocrBlocked
              ? () {
                  final reason = ocrBlockedReason;
                  if (reason == null) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(reason)),
                  );
                }
              : () => PdfViewerDocumentActions.openImageOcr(context, handoff),
        ),
        const PopupMenuDivider(),
        _ViewerMenuItem(
          label: 'Organize pages',
          icon: Icons.view_module_outlined,
          onSelected: () => openViewerToolPanelOr(
            context,
            ViewerToolId.workspaceReorder,
            () => PdfViewerDocumentActions.organizeTool(
              context,
              handoff,
              '/organize/reorder',
            ),
          ),
        ),
        _ViewerMenuItem(
          label: 'Organize pages (workspace)',
          icon: Icons.dashboard_customize_outlined,
          onSelected: () =>
              PdfViewerDocumentActions.openDocumentWorkspace(context, handoff),
        ),
        ...organizeTools.map((tool) {
          return _ViewerMenuItem(
            label: tool.label,
            icon: tool.icon,
            onSelected: () {
              if (tool.id == 'crop') {
                PdfViewerDocumentActions.cropPages(context, handoff);
              } else if (tool.id == 'resize') {
                PdfViewerDocumentActions.resizePages(context, handoff);
              } else if (tool.id == 'reorder') {
                openViewerToolPanelOr(
                  context,
                  ViewerToolId.workspaceReorder,
                  () => PdfViewerDocumentActions.organizeTool(
                    context,
                    handoff,
                    tool.routePath,
                  ),
                );
              } else if (tool.id == 'move_between') {
                context.push(
                  '/organize/move-between',
                  extra: [handoff.file],
                );
              } else {
                PdfViewerDocumentActions.organizeTool(
                  context,
                  handoff,
                  tool.routePath,
                );
              }
            },
          );
        }),
      ],
    );
  }
}

class _ViewerMenuItem {
  const _ViewerMenuItem({
    required this.label,
    required this.icon,
    this.onSelected,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onSelected;
}

class _PdfViewerToolbarMenuButton extends StatelessWidget {
  const _PdfViewerToolbarMenuButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.items,
    this.showCaption = true,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final List<Object> items;
  final bool showCaption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<Object>(
            enabled: enabled,
            tooltip: label,
            offset: const Offset(0, 36),
            padding: EdgeInsets.zero,
            icon: Icon(icon, size: 18),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            itemBuilder: (context) {
              final entries = <PopupMenuEntry<Object>>[];
              for (final entry in items) {
                if (entry is PopupMenuDivider) {
                  entries.add(const PopupMenuDivider());
                  continue;
                }
                final item = entry as _ViewerMenuItem;
                entries.add(
                  PopupMenuItem<Object>(
                    value: item.label,
                    onTap: item.onSelected,
                    child: ListTile(
                      leading: Icon(item.icon, size: 22),
                      title: Text(item.label),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                );
              }
              return entries;
            },
          ),
          if (showCaption) ...[
            const SizedBox(height: 1),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9,
                height: 1,
                letterSpacing: 0.3,
                color: isDark
                    ? theme.colorScheme.onSurface.withValues(alpha: 0.65)
                    : theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Context menu for viewer canvas (right-click / long-press).
Future<void> showPdfViewerCanvasContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required PdfViewerDocumentHandoff handoff,
  VoidCallback? onDocumentInfo,
  VoidCallback? onPrint,
  VoidCallback? onCompress,
}) {
  return showMenu<void>(
    context: context,
    position: RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      globalPosition.dx,
      globalPosition.dy,
    ),
    items: [
      PopupMenuItem(
        onTap: () =>
            PdfViewerDocumentActions.openDocumentWorkspace(context, handoff),
        child: const ListTile(
          leading: Icon(Icons.dashboard_customize_outlined),
          title: Text('Open in Document workspace'),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
      PopupMenuItem(
        onTap: () => PdfViewerDocumentActions.organizeTool(
          context,
          handoff,
          '/organize/split',
        ),
        child: const ListTile(
          leading: Icon(Icons.call_split),
          title: Text('Split PDF…'),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
      PopupMenuItem(
        onTap: () => PdfViewerDocumentActions.organizeTool(
          context,
          handoff,
          '/organize/extract',
        ),
        child: const ListTile(
          leading: Icon(Icons.content_cut),
          title: Text('Extract pages…'),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
      PopupMenuItem(
        onTap: () => onCompress != null
            ? onCompress()
            : PdfViewerDocumentActions.compress(context, handoff),
        child: const ListTile(
          leading: Icon(Icons.compress),
          title: Text('Compress PDF…'),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
      PopupMenuItem(
        onTap: () => PdfViewerDocumentActions.exportToImages(context, handoff),
        child: const ListTile(
          leading: Icon(Icons.image_outlined),
          title: Text('Export to images…'),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
      if (onPrint != null)
        PopupMenuItem(
          onTap: onPrint,
          child: const ListTile(
            leading: Icon(Icons.print_outlined),
            title: Text('Print…'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      PopupMenuItem(
        onTap: onDocumentInfo,
        child: const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Document properties…'),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ],
  );
}
