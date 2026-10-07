import 'package:document_studio/design_system/shell/ds_toolbar.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/conversion/conversion_route.dart';
import 'package:document_studio/features/page_management/organize_tool_catalog.dart';
import 'package:document_studio/features/pdf_markup/pdf_markup_route.dart';
import 'package:document_studio/features/document_workspace/workspace_launch_args.dart';
import 'package:document_studio/features/pdf_viewer/pdf_document_route_args.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_acrobat_tool_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_tool_panel_scope.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio/features/print/pdf_print_button.dart';
import 'package:document_studio/features/print/print_exception.dart';
import 'package:document_studio/features/security/security_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const _menuStyle = MenuStyle(
  visualDensity: VisualDensity.compact,
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
);

PdfDocumentRouteArgs pdfViewerToolHandoff({
  required LocalFileRef file,
  String? password,
}) => PdfDocumentRouteArgs(file: file, password: password);

Future<void> showPdfViewerDocumentContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required LocalFileRef file,
  String? password,
  int? currentPage1,
  VoidCallback? onDocumentInfo,
}) {
  final handoff = pdfViewerToolHandoff(file: file, password: password);
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
        onTap: () => context.push('/workspace', extra: handoff),
        child: const ListTile(
          leading: Icon(Icons.dashboard_customize_outlined),
          title: Text('Open in Document workspace'),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
      PopupMenuItem(
        onTap: () => PdfViewerDocumentActions.compress(
          context,
          PdfViewerDocumentHandoff(file: file, password: password),
        ),
        child: const ListTile(
          leading: Icon(Icons.compress),
          title: Text('Compress PDF…'),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
      PopupMenuItem(
        onTap: () => context.push(
          pdfToImagesRoutePath,
          extra: PdfToImagesRouteArgs(
            file: file,
            page1: currentPage1,
            password: password,
          ),
        ),
        child: const ListTile(
          leading: Icon(Icons.image_outlined),
          title: Text('Export to images…'),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
      if (onDocumentInfo != null)
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

Future<void> pdfViewerToolsPrintDocument({
  required BuildContext context,
  required WidgetRef ref,
  required LocalFileRef file,
}) async {
  final service = ref.read(printServiceProvider);
  try {
    await service.printPdf(file);
  } on PrintException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.message)));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Print failed: $e')));
  }
}

/// Dense Acrobat-style **Tools** menu on the viewer toolbar ([DS-READ-009-C]).
class PdfViewerDocumentToolsMenu extends ConsumerWidget {
  const PdfViewerDocumentToolsMenu({
    super.key,
    required this.file,
    this.password,
    this.currentPage1,
    this.enabled = true,
  });

  final LocalFileRef file;
  final String? password;
  final int? currentPage1;
  final bool enabled;

  PdfDocumentRouteArgs get _handoff =>
      pdfViewerToolHandoff(file: file, password: password);

  PdfViewerDocumentHandoff get _docHandoff => PdfViewerDocumentHandoff(
    file: file,
    password: password,
    currentPage1: currentPage1 ?? 1,
  );

  /// Prefer the in-viewer panel (open document + session Apply). Fall back to
  /// the organize route with [PdfDocumentRouteArgs] so the file is not lost.
  void _openOrganizeTool(BuildContext context, String organizeId) {
    runPdfViewerAcrobatTool(
      context: context,
      handoff: _docHandoff,
      toolId: 'organize_$organizeId',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    MenuItemButton denseItem({
      required String label,
      required IconData icon,
      required VoidCallback? onPressed,
    }) {
      return MenuItemButton(
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        leadingIcon: Icon(icon, size: 20),
        onPressed: onPressed,
        child: Text(label),
      );
    }

    SubmenuButton denseSubmenu({
      required String label,
      required IconData icon,
      required List<Widget> menuChildren,
    }) {
      return SubmenuButton(
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        menuStyle: _menuStyle,
        menuChildren: menuChildren,
        leadingIcon: Icon(icon, size: 20),
        child: Text(label),
      );
    }

    final handoffEnabled = enabled && file.isPdf;

    return MenuAnchor(
      key: const Key('pdf_viewer_tools_menu'),
      style: _menuStyle,
      menuChildren: [
        denseSubmenu(
          label: 'Organize pages',
          icon: Icons.view_day_outlined,
          menuChildren: [
            denseItem(
              label: 'Document workspace',
              icon: Icons.dashboard_customize_outlined,
              onPressed: handoffEnabled
                  ? () => context.push(
                      '/workspace',
                      extra: WorkspaceLaunchArgs(
                        files: [file],
                        passwordsByPath:
                            password != null && password!.isNotEmpty
                            ? {file.path: password!}
                            : const {},
                      ),
                    )
                  : null,
            ),
            denseItem(
              label: 'All organize tools',
              icon: Icons.apps_outlined,
              onPressed: handoffEnabled
                  ? () => context.push(
                      OrganizeToolCatalog.hubPath,
                      extra: _handoff,
                    )
                  : null,
            ),
            denseItem(
              label: 'Reorder pages',
              icon: Icons.view_module_outlined,
              onPressed: handoffEnabled
                  ? () => _openOrganizeTool(context, 'reorder')
                  : null,
            ),
            denseItem(
              label: 'Split PDF',
              icon: Icons.call_split,
              onPressed: handoffEnabled
                  ? () => _openOrganizeTool(context, 'split')
                  : null,
            ),
            denseItem(
              label: 'Merge PDFs',
              icon: Icons.merge_type,
              onPressed: handoffEnabled
                  ? () => _openOrganizeTool(context, 'merge')
                  : null,
            ),
            denseItem(
              label: 'Extract pages',
              icon: Icons.content_cut,
              onPressed: handoffEnabled
                  ? () => _openOrganizeTool(context, 'extract')
                  : null,
            ),
            denseItem(
              label: 'Rotate pages',
              icon: Icons.rotate_right,
              onPressed: handoffEnabled
                  ? () => _openOrganizeTool(context, 'rotate')
                  : null,
            ),
            denseItem(
              label: 'Delete pages',
              icon: Icons.delete_outline,
              onPressed: handoffEnabled
                  ? () => _openOrganizeTool(context, 'delete')
                  : null,
            ),
            denseItem(
              label: 'Insert pages',
              icon: Icons.playlist_add,
              onPressed: handoffEnabled
                  ? () => _openOrganizeTool(context, 'insert')
                  : null,
            ),
            denseItem(
              label: 'Crop pages',
              icon: Icons.crop,
              onPressed: handoffEnabled
                  ? () => _openOrganizeTool(context, 'crop')
                  : null,
            ),
            denseItem(
              label: 'Resize pages',
              icon: Icons.aspect_ratio,
              onPressed: handoffEnabled
                  ? () => _openOrganizeTool(context, 'resize')
                  : null,
            ),
            denseItem(
              label: 'Reverse order',
              icon: Icons.swap_vert,
              onPressed: handoffEnabled
                  ? () => _openOrganizeTool(context, 'reverse')
                  : null,
            ),
          ],
        ),
        denseSubmenu(
          label: 'Convert',
          icon: Icons.swap_horiz,
          menuChildren: [
            denseItem(
              label: 'Compress PDF',
              icon: Icons.compress,
              onPressed: handoffEnabled
                  ? () => PdfViewerDocumentActions.compress(
                      context,
                      PdfViewerDocumentHandoff(file: file, password: password),
                    )
                  : null,
            ),
            denseItem(
              label: 'PDF to images',
              icon: Icons.image_outlined,
              onPressed: handoffEnabled
                  ? () => context.push(
                      pdfToImagesRoutePath,
                      extra: PdfToImagesRouteArgs(
                        file: file,
                        page1: currentPage1,
                        password: password,
                      ),
                    )
                  : null,
            ),
            denseItem(
              label: 'Export to JPG',
              icon: Icons.photo_outlined,
              onPressed: handoffEnabled
                  ? () => context.push(
                      Uri(
                        path: pdfToImagesRoutePath,
                        queryParameters: const {'format': 'jpeg'},
                      ).toString(),
                      extra: PdfToImagesRouteArgs(
                        file: file,
                        page1: currentPage1,
                        password: password,
                      ),
                    )
                  : null,
            ),
            denseItem(
              label: 'Export to PNG',
              icon: Icons.image_outlined,
              onPressed: handoffEnabled
                  ? () => context.push(
                      Uri(
                        path: pdfToImagesRoutePath,
                        queryParameters: const {'format': 'png'},
                      ).toString(),
                      extra: PdfToImagesRouteArgs(
                        file: file,
                        page1: currentPage1,
                        password: password,
                      ),
                    )
                  : null,
            ),
          ],
        ),
        denseSubmenu(
          label: 'Security',
          icon: Icons.lock_outline,
          menuChildren: [
            denseItem(
              label: 'Encrypt',
              icon: Icons.lock_outline,
              onPressed: handoffEnabled
                  ? () => context.push(protectRoutePath, extra: _handoff)
                  : null,
            ),
            denseItem(
              label: 'Decrypt',
              icon: Icons.lock_open_outlined,
              onPressed: handoffEnabled
                  ? () => context.push(unlockRoutePath, extra: _handoff)
                  : null,
            ),
            denseItem(
              label: 'Edit metadata',
              icon: Icons.description_outlined,
              onPressed: handoffEnabled
                  ? () => context.push(
                      metadataRoutePath,
                      extra: MetadataEditorRouteArgs(
                        file: file,
                        password: password,
                      ),
                    )
                  : null,
            ),
            denseItem(
              label: 'Remove metadata',
              icon: Icons.cleaning_services_outlined,
              onPressed: handoffEnabled
                  ? () => context.push(removeMetadataRoutePath, extra: _handoff)
                  : null,
            ),
          ],
        ),
        denseSubmenu(
          label: 'Markup',
          icon: Icons.draw_outlined,
          menuChildren: [
            denseItem(
              label: 'Headers & footers',
              icon: Icons.vertical_align_center_outlined,
              onPressed: handoffEnabled
                  ? () => openViewerToolPanelOr(
                      context,
                      ViewerToolId.headersFooters,
                      () => context.push(
                        headersFootersRoutePath,
                        extra: _handoff,
                      ),
                    )
                  : null,
            ),
            denseItem(
              label: 'Watermark',
              icon: Icons.branding_watermark_outlined,
              onPressed: handoffEnabled
                  ? () => openViewerToolPanelOr(
                      context,
                      ViewerToolId.watermark,
                      () => context.push(watermarkRoutePath, extra: _handoff),
                    )
                  : null,
            ),
            denseItem(
              label: 'Page numbers',
              icon: Icons.format_list_numbered,
              onPressed: handoffEnabled
                  ? () => openViewerToolPanelOr(
                      context,
                      ViewerToolId.pageNumbers,
                      () => context.push(pageNumbersRoutePath, extra: _handoff),
                    )
                  : null,
            ),
          ],
        ),
        denseSubmenu(
          label: 'Print',
          icon: Icons.print_outlined,
          menuChildren: [
            denseItem(
              label: 'Print…',
              icon: Icons.print,
              onPressed: handoffEnabled
                  ? () => pdfViewerToolsPrintDocument(
                      context: context,
                      ref: ref,
                      file: file,
                    )
                  : null,
            ),
          ],
        ),
      ],
      builder: (context, controller, child) {
        return Semantics(
          button: true,
          enabled: handoffEnabled,
          label: 'Document tools menu',
          child: DsToolbarIconButton(
            dense: true,
            key: const Key('pdf_viewer_tools_menu_button'),
            icon: Icons.apps_outlined,
            tooltip: 'Document tools',
            onPressed: handoffEnabled
                ? () {
                    if (controller.isOpen) {
                      controller.close();
                    } else {
                      controller.open();
                    }
                  }
                : null,
          ),
        );
      },
    );
  }
}
