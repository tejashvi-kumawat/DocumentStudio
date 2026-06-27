import 'package:equatable/equatable.dart';

/// Reference to a user document on local storage.
class LocalFileRef extends Equatable {
  const LocalFileRef({
    required this.path,
    required this.displayName,
    this.contentUri,
    this.lastModified,
    this.sizeBytes,
  });

  final String path;
  final String displayName;
  final String? contentUri;
  final DateTime? lastModified;
  final int? sizeBytes;

  String get extension {
    final i = displayName.lastIndexOf('.');
    if (i <= 0) return '';
    return displayName.substring(i + 1).toLowerCase();
  }

  bool get isPdf => extension == 'pdf';

  LocalFileRef copyWithPath(String newPath) => LocalFileRef(
    path: newPath,
    displayName: displayName,
    contentUri: contentUri,
    lastModified: lastModified,
    sizeBytes: sizeBytes,
  );

  @override
  List<Object?> get props => [path, displayName, contentUri];
}
