import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/routing/pdf_tool_route_args.dart';
import 'package:document_studio/features/pdf_viewer/viewer_route_args.dart';

/// Handoff when opening a tool with the PDF already loaded (viewer, workspace, recents).
class PdfDocumentRouteArgs {
  const PdfDocumentRouteArgs({
    required this.file,
    this.password,
  });

  final LocalFileRef file;
  final String? password;

  /// Accepts handoff types used across viewer → tool navigation.
  static PdfDocumentRouteArgs? tryParse(Object? extra) {
    if (extra is PdfDocumentRouteArgs) return extra;
    if (extra is PdfToolRouteArgs) {
      return PdfDocumentRouteArgs(file: extra.file, password: extra.password);
    }
    if (extra is ViewerRouteArgs) {
      return PdfDocumentRouteArgs(file: extra.file, password: extra.password);
    }
    if (extra is LocalFileRef) {
      return PdfDocumentRouteArgs(file: extra);
    }
    return null;
  }
}
