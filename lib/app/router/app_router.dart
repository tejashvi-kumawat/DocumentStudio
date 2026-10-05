import 'package:document_studio/features/compose/compose_model.dart';
import 'package:document_studio/features/compose/compose_screen.dart';
import 'package:document_studio/app/shell/ds_document_tab_shell.dart';
import 'package:document_studio/design_system/shell/ds_app_shell.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/features/batch/batch_route.dart';
import 'package:document_studio/features/compression/compress_route.dart';
import 'package:document_studio/features/conversion/conversion_route.dart';
import 'package:document_studio/features/document_workspace/document_workspace_routes.dart';
import 'package:document_studio/features/form_sign/form_sign_route.dart';
import 'package:document_studio/features/image_tools/image_tools_route.dart';
import 'package:document_studio/features/image_viewer/image_viewer_route.dart';
import 'package:document_studio/features/ocr/ocr_route.dart';
import 'package:document_studio/features/page_management/organize_routes.dart';
import 'package:document_studio/features/pdf_markup/pdf_markup_route.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_screen.dart';
import 'package:document_studio/features/security/security_route.dart';
import 'package:document_studio/features/pdf_viewer/viewer_route_args.dart';
import 'package:document_studio/features/settings/settings_screen.dart';
import 'package:document_studio/features/tools/tools_hub_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Root navigator for full-screen routes and global shortcuts.
final rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorHomeKey = GlobalKey<NavigatorState>(debugLabel: 'shellHome');
final _shellNavigatorToolsKey =
    GlobalKey<NavigatorState>(debugLabel: 'shellTools');
final _shellNavigatorSettingsKey =
    GlobalKey<NavigatorState>(debugLabel: 'shellSettings');

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return DsAppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: _shellNavigatorHomeKey,
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const DsDocumentTabShell(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _shellNavigatorToolsKey,
            routes: [
              GoRoute(
                path: '/tools',
                builder: (context, state) => const ToolsHubScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _shellNavigatorSettingsKey,
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/viewer',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is ViewerRouteArgs) {
            return PdfViewerScreen(
              file: extra.file,
              password: extra.password,
            );
          }
          if (extra is LocalFileRef) {
            return PdfViewerScreen(file: extra);
          }
          return const Scaffold(
            body: Center(child: Text('No document specified')),
          );
        },
      ),
      buildCompressRoute(parentNavigatorKey: rootNavigatorKey),
      buildImageToolsRoute(parentNavigatorKey: rootNavigatorKey),
      buildImageConverterRoute(parentNavigatorKey: rootNavigatorKey),
      buildImageViewerRoute(parentNavigatorKey: rootNavigatorKey),
      ...buildOrganizeRoutes(parentNavigatorKey: rootNavigatorKey),
      ...buildDocumentWorkspaceRoutes(parentNavigatorKey: rootNavigatorKey),
      buildCreatePdfRoute(parentNavigatorKey: rootNavigatorKey),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: composeRoutePath,
        builder: (context, state) => ComposeScreen(
          language: ComposeLanguage.values.firstWhere(
            (l) => l.extension == state.uri.queryParameters['lang'],
            orElse: () => ComposeLanguage.markdown,
          ),
        ),
      ),
      buildImagesToPdfRoute(parentNavigatorKey: rootNavigatorKey),
      buildPdfToImagesRoute(parentNavigatorKey: rootNavigatorKey),
      buildOfficeConvertRoute(parentNavigatorKey: rootNavigatorKey),
      buildScanRoute(parentNavigatorKey: rootNavigatorKey),
      ...buildConversionFormatAliasRoutes(
        parentNavigatorKey: rootNavigatorKey,
      ),
      ...buildSecurityRoutes(parentNavigatorKey: rootNavigatorKey),
      buildSearchablePdfRoute(parentNavigatorKey: rootNavigatorKey),
      buildImageOcrRoute(parentNavigatorKey: rootNavigatorKey),
      buildBatchRoute(parentNavigatorKey: rootNavigatorKey),
      ...buildPdfMarkupRoutes(parentNavigatorKey: rootNavigatorKey),
      ...buildFormSignRoutes(parentNavigatorKey: rootNavigatorKey),
    ],
    errorBuilder: (context, state) => _RouteNotFound(location: state.uri.path),
  );
});

class _RouteNotFound extends StatelessWidget {
  const _RouteNotFound({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: DsEmptyState(
          icon: Icons.explore_off_outlined,
          title: 'This page is not available',
          subtitle: 'Nothing is registered at $location.',
          action: DsPrimaryButton(
            label: 'Back to Home',
            icon: Icons.home_outlined,
            onPressed: () => context.go('/'),
          ),
        ),
      ),
    );
  }
}
