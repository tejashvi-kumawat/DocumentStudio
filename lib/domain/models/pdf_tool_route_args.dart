import 'package:document_studio/domain/models/local_file_ref.dart';

/// Preloads a PDF tool screen from the viewer or workspace ([DS-READ-001], tools handoff).
class PdfToolRouteArgs {
  const PdfToolRouteArgs({required this.file, this.password});

  final LocalFileRef file;
  final String? password;
}

PdfToolRouteArgs? pdfToolRouteArgsFromExtra(Object? extra) {
  if (extra is PdfToolRouteArgs) return extra;
  if (extra is LocalFileRef) return PdfToolRouteArgs(file: extra);
  return null;
}
