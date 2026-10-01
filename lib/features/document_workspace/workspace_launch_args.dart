import 'package:document_studio/domain/models/local_file_ref.dart';

/// Route `extra` for `/workspace` (viewer/home handoff into the page workspace).
class WorkspaceLaunchArgs {
  const WorkspaceLaunchArgs({
    required this.files,
    this.passwordsByPath = const {},
    this.returnToViewer = false,
  });

  final List<LocalFileRef> files;
  final Map<String, String> passwordsByPath;

  /// When true, workspace shows **Back to viewer** for the primary handoff file.
  final bool returnToViewer;
}
