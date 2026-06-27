import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/pdf/pdf_document_cache.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/infrastructure/pdf/pdf_compress_options.dart';
import 'package:document_studio/infrastructure/pdf/pdf_page_box_options.dart';
import 'package:document_studio/infrastructure/pdf/pdf_structure_port.dart';
import 'package:document_studio/infrastructure/pdf/pdfrx_error_mapping.dart';
import 'package:document_studio/infrastructure/pdf/pdfrx_structure_adapter.dart';
import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:path/path.dart' as p;

/// qpdf CLI compress with pdfrx fallback when qpdf is missing.
class QpdfCompressRoutingAdapter implements PdfStructurePort {
  QpdfCompressRoutingAdapter({
    QpdfCliRunner? cli,
    PdfrxStructureAdapter? pdfrxFallback,
  })  : _cli = cli ?? QpdfCliRunner(),
        _pdfrx = pdfrxFallback ?? PdfrxStructureAdapter();

  final QpdfCliRunner _cli;
  final PdfrxStructureAdapter _pdfrx;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<StructureEngineInfo> engineInfo() async {
    final qpdf = await isQpdfCliAvailable();
    return StructureEngineInfo(
      id: qpdf ? 'qpdf_compress' : 'pdfrx_rewrite',
      label: qpdf ? 'qpdf optimize' : 'PDFium rewrite (fallback)',
      supportsEncryptedInput: qpdf,
    );
  }

  @override
  Future<LocalFileRef> compressPdf({
    required LocalFileRef input,
    required String outputPath,
    PdfCompressOptions options = const PdfCompressOptions(),
    String? password,
  }) async {
    if (await isQpdfCliAvailable()) {
      try {
        await _cli.compressPdf(
          inputPath: input.path,
          outputPath: outputPath,
          password: password,
          linearize: options.linearize,
          recompressFlate: options.recompressFlate,
        );
      } on QpdfCliException catch (e) {
        throw DocumentStudioError(
          code: DocumentStudioErrorCode.nativeEngineError,
          message: 'qpdf could not compress this PDF.',
          cause: e,
        );
      }
      return LocalFileRef(
        path: outputPath,
        displayName: p.basename(outputPath),
      );
    }
    // Fallback: full page rewrite (weaker optimization, always local).
    final total = await _pageCount(input, password);
    final pages = [for (var i = 1; i <= total; i++) i];
    return _pdfrx.extractPages(
      input: input,
      pageNumbers1Based: pages,
      outputPath: outputPath,
      password: password,
    );
  }

  Future<int> _pageCount(LocalFileRef file, String? password) async {
    final PdfDocumentLease lease;
    try {
      lease = await PdfDocumentCache.instance.acquire(
        file.path,
        password: password,
      );
    } catch (e) {
      throw documentStudioErrorFromPdfrxOpen(e, password: password);
    }
    try {
      return lease.document.pages.length;
    } finally {
      lease.release();
    }
  }

  // --- delegate unimplemented compress-only port methods to pdfrx ---

  @override
  Future<LocalFileRef> assemblePageSources({
    required List sources,
    required String outputPath,
    String? password,
  }) =>
      _pdfrx.assemblePageSources(
        sources: sources.cast(),
        outputPath: outputPath,
        password: password,
      );

  @override
  Future<LocalFileRef> merge({
    required List<LocalFileRef> inputs,
    required String outputPath,
    String? password,
    Map<String, String>? passwordsByPath,
  }) =>
      _pdfrx.merge(
        inputs: inputs,
        outputPath: outputPath,
        password: password,
        passwordsByPath: passwordsByPath,
      );

  @override
  Future<List<LocalFileRef>> splitByRanges({
    required LocalFileRef input,
    required List<List<int>> rangesPages1Based,
    required String outputDirectory,
    required String namePrefix,
    String? password,
  }) =>
      _pdfrx.splitByRanges(
        input: input,
        rangesPages1Based: rangesPages1Based,
        outputDirectory: outputDirectory,
        namePrefix: namePrefix,
        password: password,
      );

  @override
  Future<bool> supportsPageBoxEditing() => _pdfrx.supportsPageBoxEditing();

  @override
  Future<LocalFileRef> cropPages({
    required LocalFileRef input,
    required Set<int> pageNumbers1Based,
    required PdfCropMarginPreset margin,
    required String outputPath,
    String? password,
  }) =>
      _pdfrx.cropPages(
        input: input,
        pageNumbers1Based: pageNumbers1Based,
        margin: margin,
        outputPath: outputPath,
        password: password,
      );

  @override
  Future<LocalFileRef> cropPagesToBox({
    required LocalFileRef input,
    required Set<int> pageNumbers1Based,
    required PdfCropRectPt box,
    required String outputPath,
    String? password,
  }) =>
      _pdfrx.cropPagesToBox(
        input: input,
        pageNumbers1Based: pageNumbers1Based,
        box: box,
        outputPath: outputPath,
        password: password,
      );

  @override
  Future<LocalFileRef> setPageSize({
    required LocalFileRef input,
    required Set<int> pageNumbers1Based,
    required PdfPaperSize paperSize,
    required String outputPath,
    String? password,
  }) =>
      _pdfrx.setPageSize(
        input: input,
        pageNumbers1Based: pageNumbers1Based,
        paperSize: paperSize,
        outputPath: outputPath,
        password: password,
      );

  @override
  Future<LocalFileRef> extractPages({
    required LocalFileRef input,
    required List<int> pageNumbers1Based,
    required String outputPath,
    String? password,
  }) =>
      _pdfrx.extractPages(
        input: input,
        pageNumbers1Based: pageNumbers1Based,
        outputPath: outputPath,
        password: password,
      );

  @override
  Future<List<LocalFileRef>> splitEveryNPages({
    required LocalFileRef input,
    required int pagesPerFile,
    required String outputDirectory,
    required String namePrefix,
    String? password,
  }) =>
      _pdfrx.splitEveryNPages(
        input: input,
        pagesPerFile: pagesPerFile,
        outputDirectory: outputDirectory,
        namePrefix: namePrefix,
        password: password,
      );

  @override
  Future<LocalFileRef> deletePages({
    required LocalFileRef input,
    required Set<int> deletePages1Based,
    required String outputPath,
    String? password,
  }) =>
      _pdfrx.deletePages(
        input: input,
        deletePages1Based: deletePages1Based,
        outputPath: outputPath,
        password: password,
      );

  @override
  Future<LocalFileRef> reorderPages({
    required LocalFileRef input,
    required List<int> newOrder1Based,
    required String outputPath,
    String? password,
  }) =>
      _pdfrx.reorderPages(
        input: input,
        newOrder1Based: newOrder1Based,
        outputPath: outputPath,
        password: password,
      );

  @override
  Future<LocalFileRef> rotatePages({
    required LocalFileRef input,
    required Map<int, int> pageRotationsDegrees,
    required String outputPath,
    String? password,
  }) =>
      _pdfrx.rotatePages(
        input: input,
        pageRotationsDegrees: pageRotationsDegrees,
        outputPath: outputPath,
        password: password,
      );

  @override
  Future<LocalFileRef> reversePages({
    required LocalFileRef input,
    required String outputPath,
    String? password,
  }) =>
      _pdfrx.reversePages(
        input: input,
        outputPath: outputPath,
        password: password,
      );
}
