import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/annotations/annotation_port.dart';
import 'package:pdfrx/pdfrx.dart';

/// Read-only annotation listing via pdfrx [PdfPage.loadLinks].
///
/// pdfrx 2.6.x exposes annotation *metadata* only through link loading; there is
/// no public add/update/remove or save API (see pdfrx_engine `FPDFAnnot_*` usage
/// limited to link extraction). Authoring remains `[R]` in BLOCKED-FEATURES.
class PdfrxAnnotationAdapter implements PdfAnnotationPort {
  @override
  PdfAnnotationCapabilities get capabilities => const PdfAnnotationCapabilities(
        canList: true,
        canAuthor: false,
        canPersist: false,
        listLimitation:
            'Lists link annotations and markup entries pdfrx surfaces via loadLinks; '
            'silent highlights/ink without popup metadata may be omitted until PDFium FFI.',
      );

  @override
  Future<List<PdfMarkupAnnotation>> listAnnotations(
    LocalFileRef file, {
    String? password,
  }) async {
    final doc = await _open(file, password: password);
    try {
      return listFromOpenDocument(doc);
    } finally {
      await doc.dispose();
    }
  }

  /// Lists annotations while a viewer session already holds an open [PdfDocument].
  Future<List<PdfMarkupAnnotation>> listFromOpenDocument(PdfDocument document) async {
    final results = <PdfMarkupAnnotation>[];
    for (final page in document.pages) {
      final loaded = await page.ensureLoaded();
      final links = await loaded.loadLinks(enableAutoLinkDetection: false);
      for (var i = 0; i < links.length; i++) {
        final link = links[i];
        results.add(_mapLink(link, pageNumber: loaded.pageNumber, index: i));
      }
    }
    return results;
  }

  @override
  Future<PdfMarkupAnnotation> addAnnotation({
    required LocalFileRef file,
    required PdfMarkupAnnotation draft,
    String? password,
  }) =>
      _authoringBlocked();

  @override
  Future<PdfMarkupAnnotation> updateAnnotation({
    required LocalFileRef file,
    required PdfMarkupAnnotation annotation,
    String? password,
  }) =>
      _authoringBlocked();

  @override
  Future<void> removeAnnotation({
    required LocalFileRef file,
    required String annotationId,
    String? password,
  }) =>
      _authoringBlocked();

  @override
  Future<LocalFileRef> saveAnnotatedCopy({
    required LocalFileRef file,
    required String outputPath,
    String? password,
  }) async {
    await _authoringBlocked();
    // _authoringBlocked always throws; keep signature for port compliance.
    throw const DocumentStudioError(
      code: DocumentStudioErrorCode.featureUnavailable,
      message: 'Annotation authoring is not available.',
    );
  }

  Future<PdfDocument> _open(
    LocalFileRef file, {
    String? password,
  }) async {
    try {
      return await PdfDocument.openFile(
        file.path,
        passwordProvider: password == null ? null : () async => password,
      );
    } on PdfPasswordException catch (e) {
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.passwordRequired,
        message: e.toString(),
        cause: e,
      );
    } on PdfException catch (e) {
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.invalidPdf,
        message: e.toString(),
        cause: e,
      );
    } catch (e) {
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.renderFailed,
        message: e.toString(),
        cause: e,
      );
    }
  }

  Future<PdfMarkupAnnotation> _authoringBlocked() {
    return Future.error(
      const DocumentStudioError(
        code: DocumentStudioErrorCode.featureUnavailable,
        message: 'PDF annotation authoring is not available via pdfrx yet.',
        recoveryHint:
            'See docs/BLOCKED-FEATURES-IMPLEMENTATION.md ([R] annotations authoring).',
      ),
    );
  }

  PdfMarkupAnnotation _mapLink(
    PdfLink link, {
    required int pageNumber,
    required int index,
  }) {
    final meta = link.annotation;
    return PdfMarkupAnnotation(
      id: 'p$pageNumber-a$index',
      pageNumber: pageNumber,
      kind: _kindFromLink(link),
      author: meta?.title,
      contents: meta?.content,
      subject: meta?.subject,
      modifiedAt: meta?.modificationDate?.toDateTime(),
      createdAt: meta?.creationDate?.toDateTime(),
      rects: link.rects
          .map(
            (r) => PdfAnnotationBounds(
              left: r.left,
              top: r.top,
              right: r.right,
              bottom: r.bottom,
            ),
          )
          .toList(growable: false),
    );
  }

  PdfAnnotationKind _kindFromLink(PdfLink link) {
    if (link.url != null) return PdfAnnotationKind.uriLink;
    if (link.dest != null) return PdfAnnotationKind.destinationLink;

    final subject = link.annotation?.subject?.toLowerCase();
    if (subject != null) {
      if (subject.contains('highlight')) return PdfAnnotationKind.highlight;
      if (subject.contains('underline')) return PdfAnnotationKind.underline;
      if (subject.contains('strike')) return PdfAnnotationKind.strikeOut;
      if (subject.contains('squigg')) return PdfAnnotationKind.squiggly;
      if (subject.contains('ink') || subject.contains('pencil')) {
        return PdfAnnotationKind.ink;
      }
      if (subject.contains('stamp')) return PdfAnnotationKind.stamp;
      if (subject.contains('freetext') || subject.contains('free text')) {
        return PdfAnnotationKind.freeText;
      }
      if (subject.contains('text')) return PdfAnnotationKind.text;
    }

    if (link.annotation?.isNotEmpty == true) {
      return PdfAnnotationKind.comment;
    }
    return PdfAnnotationKind.unknown;
  }
}
