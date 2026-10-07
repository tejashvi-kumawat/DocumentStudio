import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// One page slot in the organize workspace (order = export order).
class OrganizePageRef extends Equatable {
  const OrganizePageRef({
    required this.id,
    required this.file,
    required this.pageNumber1Based,
    this.rotationDegrees = 0,
  });

  factory OrganizePageRef.fromFilePage(
    LocalFileRef file,
    int pageNumber1Based,
  ) {
    return OrganizePageRef(
      id: const Uuid().v4(),
      file: file,
      pageNumber1Based: pageNumber1Based,
    );
  }

  final String id;
  final LocalFileRef file;
  final int pageNumber1Based;
  final int rotationDegrees;

  OrganizePageRef copyWith({
    String? id,
    LocalFileRef? file,
    int? pageNumber1Based,
    int? rotationDegrees,
  }) {
    return OrganizePageRef(
      id: id ?? this.id,
      file: file ?? this.file,
      pageNumber1Based: pageNumber1Based ?? this.pageNumber1Based,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
    );
  }

  @override
  List<Object?> get props => [id, file.path, pageNumber1Based, rotationDegrees];
}
