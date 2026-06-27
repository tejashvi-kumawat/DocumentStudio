import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/document_workspace/document_workspace_screen.dart';
import 'package:document_studio/features/document_workspace/workspace_launch_args.dart';
import 'package:document_studio/features/pdf_viewer/pdf_document_route_args.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Parses `/workspace` route `extra` from viewer/home handoffs.
({List<LocalFileRef> files, Map<String, String> passwords, bool returnToViewer})
    parseWorkspaceRouteExtra(
  Object? extra,
) {
  final files = <LocalFileRef>[];
  var passwords = <String, String>{};
  var returnToViewer = false;
  if (extra is WorkspaceLaunchArgs) {
    files.addAll(extra.files);
    passwords = Map<String, String>.from(extra.passwordsByPath);
    returnToViewer = extra.returnToViewer;
  } else {
    final doc = PdfDocumentRouteArgs.tryParse(extra);
    if (doc != null) {
      files.add(doc.file);
      final pw = doc.password;
      if (pw != null && pw.isNotEmpty) {
        passwords[doc.file.path] = pw;
      }
    } else if (extra is LocalFileRef) {
      files.add(extra);
    } else if (extra is List<LocalFileRef>) {
      files.addAll(extra);
    }
  }
  return (files: files, passwords: passwords, returnToViewer: returnToViewer);
}

List<RouteBase> buildDocumentWorkspaceRoutes({
  GlobalKey<NavigatorState>? parentNavigatorKey,
}) {
  return [
    GoRoute(
      parentNavigatorKey: parentNavigatorKey,
      path: '/workspace',
      builder: (context, state) {
        final parsed = parseWorkspaceRouteExtra(state.extra);
        return DocumentWorkspaceScreen(
          initialFiles: parsed.files,
          initialPasswordsByPath: parsed.passwords,
          returnToViewer: parsed.returnToViewer,
        );
      },
    ),
  ];
}
