import 'dart:io';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/infrastructure/pdf/dart_pdf_compress.dart';
import 'package:document_studio/infrastructure/pdf/dart_pdf_page_box.dart';
import 'package:document_studio/infrastructure/pdf/page_source.dart';
import 'package:document_studio/infrastructure/pdf/pdf_compress_options.dart';
import 'package:document_studio/infrastructure/pdf/pdf_page_box_options.dart';
import 'package:document_studio/infrastructure/pdf/pdf_structure_port.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

/// Page-level structure using PDFium assemble/encode (pdfrx_engine).
///
/// Works offline on all pdfrx-supported platforms for typical unencrypted PDFs.
class PdfrxStructureAdapter implements PdfStructurePort {
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<StructureEngineInfo> engineInfo() async {
    return const StructureEngineInfo(
      id: 'pdfrx_structure',
      label: 'PDFium page assembly (pdfrx)',
      supportsEncryptedInput: false,
    );
  }

  @override
  Future<LocalFileRef> merge({
    required List<LocalFileRef> inputs,
    required String outputPath,
    String? password,
    Map<String, String>? passwordsByPath,
  }) async {
    return _buildFromPages(
      outputPath: outputPath,
      pageSources: [
        for (final doc in inputs)
          for (
            var i = 0;
            i < await _pageCount(doc, passwordsByPath?[doc.path] ?? password);
            i++
          )
            PageSource(doc, i + 1),
      ],
      password: password,
      passwordsByPath: passwordsByPath,
    );
  }

  @override
  Future<LocalFileRef> assemblePageSources({
    required List<PageSource> sources,
    required String outputPath,
    String? password,
  }) {
    return _buildFromPages(
      outputPath: outputPath,
      pageSources: sources,
      password: password,
    );
  }

  @override
  Future<LocalFileRef> extractPages({
    required LocalFileRef input,
    required List<int> pageNumbers1Based,
    required String outputPath,
    String? password,
  }) async {
    return _buildFromPages(
      outputPath: outputPath,
      pageSources: [for (final n in pageNumbers1Based) PageSource(input, n)],
      password: password,
    );
  }

  @override
  Future<List<LocalFileRef>> splitEveryNPages({
    required LocalFileRef input,
    required int pagesPerFile,
    required String outputDirectory,
    required String namePrefix,
    String? password,
  }) async {
    if (pagesPerFile < 1) {
      throw ArgumentError('pagesPerFile must be >= 1');
    }
    final total = await _pageCount(input, password);
    final outputs = <LocalFileRef>[];
    var part = 1;
    for (var start = 1; start <= total; start += pagesPerFile) {
      final end = (start + pagesPerFile - 1).clamp(1, total);
      final pages = [for (var p = start; p <= end; p++) p];
      final outPath = p.join(outputDirectory, '$namePrefix-part$part.pdf');
      outputs.add(
        await extractPages(
          input: input,
          pageNumbers1Based: pages,
          outputPath: outPath,
          password: password,
        ),
      );
      part++;
    }
    return outputs;
  }

  @override
  Future<LocalFileRef> deletePages({
    required LocalFileRef input,
    required Set<int> deletePages1Based,
    required String outputPath,
    String? password,
  }) async {
    final total = await _pageCount(input, password);
    final keep = [
      for (var i = 1; i <= total; i++)
        if (!deletePages1Based.contains(i)) i,
    ];
    return extractPages(
      input: input,
      pageNumbers1Based: keep,
      outputPath: outputPath,
      password: password,
    );
  }

  @override
  Future<LocalFileRef> reorderPages({
    required LocalFileRef input,
    required List<int> newOrder1Based,
    required String outputPath,
    String? password,
  }) async {
    return extractPages(
      input: input,
      pageNumbers1Based: newOrder1Based,
      outputPath: outputPath,
      password: password,
    );
  }

  @override
  Future<LocalFileRef> rotatePages({
    required LocalFileRef input,
    required Map<int, int> pageRotationsDegrees,
    required String outputPath,
    String? password,
  }) async {
    final doc = await _open(input, password);
    try {
      final pages = <PdfPage>[];
      for (var i = 0; i < doc.pages.length; i++) {
        final pageNum = i + 1;
        var page = doc.pages[i];
        final deg = pageRotationsDegrees[pageNum];
        if (deg != null && deg != 0) {
          page = _rotatePage(page, deg);
        }
        pages.add(page);
      }
      return await _encodePages(pages, outputPath);
    } finally {
      await doc.dispose();
    }
  }

  @override
  Future<LocalFileRef> reversePages({
    required LocalFileRef input,
    required String outputPath,
    String? password,
  }) async {
    final total = await _pageCount(input, password);
    final order = [for (var i = total; i >= 1; i--) i];
    return extractPages(
      input: input,
      pageNumbers1Based: order,
      outputPath: outputPath,
      password: password,
    );
  }

  @override
  Future<List<LocalFileRef>> splitByRanges({
    required LocalFileRef input,
    required List<List<int>> rangesPages1Based,
    required String outputDirectory,
    required String namePrefix,
    String? password,
  }) async {
    final outputs = <LocalFileRef>[];
    var part = 1;
    for (final pages in rangesPages1Based) {
      if (pages.isEmpty) continue;
      final outPath = p.join(outputDirectory, '$namePrefix-part$part.pdf');
      outputs.add(
        await extractPages(
          input: input,
          pageNumbers1Based: pages,
          outputPath: outPath,
          password: password,
        ),
      );
      part++;
    }
    return outputs;
  }

  @override
  Future<LocalFileRef> compressPdf({
    required LocalFileRef input,
    required String outputPath,
    PdfCompressOptions options = const PdfCompressOptions(),
    String? password,
  }) {
    // On-device path used when CompositePdfStructureAdapter has no qpdf:
    // DartPdfCompress (image JPEG re-encode + Flate recompress + full rewrite).
    return DartPdfCompress.compressToFile(
      input: input,
      outputPath: outputPath,
      options: options,
      password: password,
    );
  }

  @override
  Future<bool> supportsPageBoxEditing() async => true;

  @override
  Future<LocalFileRef> cropPages({
    required LocalFileRef input,
    required Set<int> pageNumbers1Based,
    required PdfCropMarginPreset margin,
    required String outputPath,
    String? password,
  }) {
    return DartPdfPageBox.cropPages(
      input: input,
      pageNumbers1Based: pageNumbers1Based,
      margin: margin,
      outputPath: outputPath,
      password: password,
    );
  }

  @override
  Future<LocalFileRef> cropPagesToBox({
    required LocalFileRef input,
    required Set<int> pageNumbers1Based,
    required PdfCropRectPt box,
    required String outputPath,
    String? password,
  }) {
    return DartPdfPageBox.cropPagesToBox(
      input: input,
      pageNumbers1Based: pageNumbers1Based,
      box: box,
      outputPath: outputPath,
      password: password,
    );
  }

  @override
  Future<LocalFileRef> setPageSize({
    required LocalFileRef input,
    required Set<int> pageNumbers1Based,
    required PdfPaperSize paperSize,
    required String outputPath,
    String? password,
  }) {
    return DartPdfPageBox.setPageSize(
      input: input,
      pageNumbers1Based: pageNumbers1Based,
      paperSize: paperSize,
      outputPath: outputPath,
      password: password,
    );
  }

  Future<LocalFileRef> _buildFromPages({
    required String outputPath,
    required List<PageSource> pageSources,
    String? password,
    Map<String, String>? passwordsByPath,
  }) async {
    if (pageSources.isEmpty) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.invalidPdf,
        message: 'No pages selected',
      );
    }
    final openDocs = <String, PdfDocument>{};
    try {
      final pages = <PdfPage>[];
      for (final src in pageSources) {
        final key = src.file.path;
        final pw = passwordsByPath?[key] ?? password;
        openDocs[key] ??= await _open(src.file, pw);
        final doc = openDocs[key]!;
        if (src.pageNumber < 1 || src.pageNumber > doc.pages.length) {
          throw DocumentStudioError(
            code: DocumentStudioErrorCode.invalidPdf,
            message:
                'Page ${src.pageNumber} out of range in ${src.file.displayName}',
          );
        }
        var page = doc.pages[src.pageNumber - 1];
        if (src.rotationDegrees != 0) {
          page = _rotatePage(page, src.rotationDegrees);
        }
        pages.add(page);
      }
      return await _encodePages(pages, outputPath);
    } finally {
      for (final d in openDocs.values) {
        await d.dispose();
      }
    }
  }

  Future<LocalFileRef> _encodePages(
    List<PdfPage> pages,
    String outputPath,
  ) async {
    final outDoc = await PdfDocument.createNew(
      sourceName:
          'document_studio://organize/${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      outDoc.pages = pages;
      await outDoc.assemble();
      final bytes = await outDoc.encodePdf();
      await Directory(p.dirname(outputPath)).create(recursive: true);
      await File(outputPath).writeAsBytes(bytes, flush: true);
      final stat = await File(outputPath).stat();
      return LocalFileRef(
        path: outputPath,
        displayName: p.basename(outputPath),
        sizeBytes: stat.size,
        lastModified: stat.modified,
      );
    } finally {
      await outDoc.dispose();
    }
  }

  Future<int> _pageCount(LocalFileRef file, String? password) async {
    final doc = await _open(file, password);
    try {
      return doc.pages.length;
    } finally {
      await doc.dispose();
    }
  }

  Future<PdfDocument> _open(LocalFileRef file, String? password) async {
    try {
      return await PdfDocument.openFile(
        file.path,
        passwordProvider: password == null ? null : () async => password,
      );
    } on PdfPasswordException {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.passwordRequired,
        message: 'Password required',
      );
    } on PdfException catch (e) {
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.invalidPdf,
        message: e.toString(),
        cause: e,
      );
    }
  }

  PdfPage _rotatePage(PdfPage page, int degrees) {
    final steps = ((degrees % 360) + 360) % 360 ~/ 90;
    var result = page;
    for (var i = 0; i < steps; i++) {
      result = result.rotatedCW90();
    }
    return result;
  }
}
