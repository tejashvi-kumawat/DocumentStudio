import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/pdf_document_route_args.dart';
import 'package:document_studio/features/pdf_viewer/viewer_route_args.dart';

/// Pre-opened PDF from viewer, home chooser, or related-tool cross-links.
///
/// Used by compress (`DS-OPT-001`) and security tools (`DS-SEC-*`, `DS-META-001`).
class PdfToolRouteArgs {
  const PdfToolRouteArgs({required this.file, this.password});

  final LocalFileRef file;
  final String? password;
}

/// Parses [GoRouterState.extra] for routes that accept a handoff PDF.
PdfToolRouteArgs? pdfToolRouteArgsFromExtra(Object? extra) {
  if (extra is PdfToolRouteArgs) return extra;
  final doc = PdfDocumentRouteArgs.tryParse(extra);
  if (doc != null) {
    return PdfToolRouteArgs(file: doc.file, password: doc.password);
  }
  if (extra is ViewerRouteArgs) {
    return PdfToolRouteArgs(file: extra.file, password: extra.password);
  }
  if (extra is LocalFileRef) return PdfToolRouteArgs(file: extra);
  return null;
}