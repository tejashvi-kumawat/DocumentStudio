import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:equatable/equatable.dart';

/// Standard PDF markup categories for UI and export (DS-ANN-001 … DS-ANN-005).
enum PdfAnnotationKind {
  highlight,
  underline,
  strikeOut,
  squiggly,
  text,
  freeText,
  ink,
  stamp,
  comment,
  uriLink,
  destinationLink,
  unknown,
}

/// Axis-aligned bounds in PDF user space (points, origin bottom-left).
class PdfAnnotationBounds extends Equatable {
  const PdfAnnotationBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  @override
  List<Object?> get props => [left, top, right, bottom];
}

/// Feature-facing annotation record (engine-agnostic).
class PdfMarkupAnnotation extends Equatable {
  const PdfMarkupAnnotation({
    required this.id,
    required this.pageNumber,
    required this.kind,
    this.author,
    this.contents,
    this.subject,
    this.modifiedAt,
    this.createdAt,
    this.rects = const [],
  });

  final String id;
  final int pageNumber;
  final PdfAnnotationKind kind;
  final String? author;
  final String? contents;
  final String? subject;
  final DateTime? modifiedAt;
  final DateTime? createdAt;
  final List<PdfAnnotationBounds> rects;

  String get displayLabel {
    final text = contents?.trim();
    if (text != null && text.isNotEmpty) return text;
    final subj = subject?.trim();
    if (subj != null && subj.isNotEmpty) return subj;
    final name = author?.trim();
    if (name != null && name.isNotEmpty) return name;
    return kind.name;
  }

  @override
  List<Object?> get props => [
        id,
        pageNumber,
        kind,
        author,
        contents,
        subject,
        modifiedAt,
        createdAt,
        rects,
      ];
}

/// What the active [PdfAnnotationPort] implementation can do.
class PdfAnnotationCapabilities extends Equatable {
  const PdfAnnotationCapabilities({
    required this.canList,
    required this.canAuthor,
    required this.canPersist,
    this.listLimitation,
  });

  final bool canList;
  final bool canAuthor;
  final bool canPersist;
  final String? listLimitation;

  @override
  List<Object?> get props => [canList, canAuthor, canPersist, listLimitation];
}

/// Read/write standard PDF annotations (see MASTER-SPEC §10.2).
abstract class PdfAnnotationPort {
  PdfAnnotationCapabilities get capabilities;

  Future<List<PdfMarkupAnnotation>> listAnnotations(
    LocalFileRef file, {
    String? password,
  });

  Future<PdfMarkupAnnotation> addAnnotation({
    required LocalFileRef file,
    required PdfMarkupAnnotation draft,
    String? password,
  });

  Future<PdfMarkupAnnotation> updateAnnotation({
    required LocalFileRef file,
    required PdfMarkupAnnotation annotation,
    String? password,
  });

  Future<void> removeAnnotation({
    required LocalFileRef file,
    required String annotationId,
    String? password,
  });

  Future<LocalFileRef> saveAnnotatedCopy({
    required LocalFileRef file,
    required String outputPath,
    String? password,
  });
}
