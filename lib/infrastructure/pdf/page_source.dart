import 'package:document_studio/domain/models/local_file_ref.dart';

/// Reference to one page in a source file for structure assembly.
class PageSource {
  const PageSource(this.file, this.pageNumber, {this.rotationDegrees = 0});

  final LocalFileRef file;
  final int pageNumber;

  /// Clockwise rotation applied when assembling (0, 90, 180, 270).
  final int rotationDegrees;
}
