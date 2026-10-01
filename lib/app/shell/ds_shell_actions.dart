import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/errors/document_studio_error_ui.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/shell_pdf_open.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Current top-most location of [router] (pushed routes included).
String dsRouterLocation(GoRouter router) {
  try {
    return router.state.matchedLocation;
  } catch (_) {
    return '/';
  }
}

bool dsIsShellLocation(String path) =>
    path == '/' ||
    path.startsWith('/workspace') ||
    path == '/tools' ||
    path == '/settings';

/// Picks a PDF and opens it as a document tab, for chrome that sits above the
/// router's pages (title bar, global shortcuts) where [GoRouterState] is not
/// available. [navigatorContext] must be a context of (or under) a Navigator.
Future<void> dsOpenPdfFromChrome({
  required WidgetRef ref,
  required GoRouter router,
  required BuildContext? Function() navigatorContext,
}) async {
  final storage = ref.read(fileStorageProvider);
  try {
    final picked = await storage.pickOpenFile(allowedExtensions: ['pdf']);
    if (picked == null) return;
    await dsOpenPdfTab(
      ref: ref,
      router: router,
      navigatorContext: navigatorContext,
      file: picked,
    );
  } on DocumentStudioError catch (e) {
    final ctx = navigatorContext();
    if (ctx != null && ctx.mounted) showDocumentStudioErrorSnackBar(ctx, e);
  }
}

/// Validates [file] (prompting for a password if needed), records it as
/// recent, opens it as a tab and shows the viewer.
Future<void> dsOpenPdfTab({
  required WidgetRef ref,
  required GoRouter router,
  required BuildContext? Function() navigatorContext,
  required LocalFileRef file,
  String? password,
}) async {
  // Resolve + one viewer open. Do not validateOpenable first (that opened the
  // portal FUSE path and raced a second host open).
  await ref.read(recentsProvider.notifier).addRecent(file);
  await openPdfInDocumentTabs(ref, file, password: password);
  if (dsRouterLocation(router) != '/') router.go('/');
}
