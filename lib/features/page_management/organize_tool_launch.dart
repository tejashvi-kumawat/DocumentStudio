import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/pdf_document_route_args.dart';

/// Route extra when opening an organize tool with a document already loaded.
class OrganizeToolLaunch {
  const OrganizeToolLaunch({required this.file, this.password});

  final LocalFileRef file;
  final String? password;

  static OrganizeToolLaunch? fromExtra(Object? extra) {
    final doc = PdfDocumentRouteArgs.tryParse(extra);
    if (doc != null) {
      return OrganizeToolLaunch(file: doc.file, password: doc.password);
    }
    return null;
  }
}
