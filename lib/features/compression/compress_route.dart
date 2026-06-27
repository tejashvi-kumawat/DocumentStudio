import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/routing/pdf_tool_route_args.dart';
import 'package:document_studio/features/compression/compress_screen.dart';
import 'package:document_studio/features/pdf_viewer/pdf_document_route_args.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const compressRoutePath = '/compress';

PdfToolRouteArgs? _compressHandoffFromExtra(Object? extra) {
  final fromTool = pdfToolRouteArgsFromExtra(extra);
  if (fromTool != null) return fromTool;
  final doc = PdfDocumentRouteArgs.tryParse(extra);
  if (doc != null) {
    return PdfToolRouteArgs(file: doc.file, password: doc.password);
  }
  return null;
}

GoRoute buildCompressRoute({GlobalKey<NavigatorState>? parentNavigatorKey}) {
  return GoRoute(
    parentNavigatorKey: parentNavigatorKey,
    path: compressRoutePath,
    builder: (context, state) {
      final handoff = _compressHandoffFromExtra(state.extra);
      return CompressScreen(
        initialFile: handoff?.file,
        initialPassword: handoff?.password,
      );
    },
  );
}

/// Navigate from viewer with the active document pre-selected ([DS-OPT-001]).
void pushCompressForPdf(
  BuildContext context, {
  required LocalFileRef file,
  String? password,
}) {
  context.push(
    compressRoutePath,
    extra: PdfToolRouteArgs(file: file, password: password),
  );
}
