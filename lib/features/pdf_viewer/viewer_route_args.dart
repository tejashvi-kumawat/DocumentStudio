import 'package:document_studio/domain/models/local_file_ref.dart';

class ViewerRouteArgs {
  const ViewerRouteArgs({required this.file, this.password});

  final LocalFileRef file;
  final String? password;
}
