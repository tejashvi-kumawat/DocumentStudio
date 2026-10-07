import 'dart:io';

import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/infrastructure/pdf/dart_pdf_compress.dart';
import 'package:document_studio/infrastructure/pdf/page_source.dart';
import 'package:document_studio/infrastructure/pdf/pdf_image_downsampler.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/infrastructure/pdf/pdf_compress_options.dart';
import 'package:document_studio/infrastructure/pdf/pdf_page_box_options.dart';
import 'package:document_studio/infrastructure/pdf/pdf_structure_port.dart';
import 'package:document_studio/infrastructure/pdf/pdfrx_structure_adapter.dart'
    show PdfrxStructureAdapter;
import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:path/path.dart' as p;

/// Prefers pdfrx assembly; uses qpdf CLI when installed for encrypted merges (future).
class CompositePdfStructureAdapter implements PdfStructurePort {
  CompositePdfStructureAdapter({
    PdfrxStructureAdapter? pdfrx,
    QpdfCliRunner? cli,
  }) : _pdfrx = pdfrx ?? PdfrxStructureAdapter(),
       _cli = cli ?? QpdfCliRunner();

  final PdfrxStructureAdapter _pdfrx;
  final QpdfCliRunner _cli;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<StructureEngineInfo> engineInfo() async {
    final cli = await isQpdfCliAvailable();
    return StructureEngineInfo(
      id: cli ? 'pdfrx+qpdf_cli' : 'pdfrx_structure',
      label: cli
          ? 'PDFium assembly + qpdf CLI'
          : 'PDFium page assembly (pdfrx)',
      supportsEncryptedInput: cli,
    );
  }

  @override
  Future<LocalFileRef> merge({
    required List<LocalFileRef> inputs,
    required String outputPath,
    String? password,
    Map<String, String>? passwordsByPath,
  }) async {
    final hasPassword =
        (password != null && password.isNotEmpty) ||
        (passwordsByPath?.values.any((p) => p.isNotEmpty) ?? false);
    if (inputs.isNotEmpty && await isQpdfCliAvailable()) {
      try {
        await Directory(p.dirname(outputPath)).create(recursive: true);
        await _cli.mergeFiles(
          inputPaths: inputs.map((e) => e.path).toList(),
          outputPath: outputPath,
          password: password,
          passwordsByPath: passwordsByPath,
        );
        return LocalFileRef(
          path: outputPath,
          displayName: p.basename(outputPath),
          sizeBytes: (await File(outputPath).stat()).size,
        );
      } on QpdfCliException {
        if (hasPassword) rethrow;
      }
    }
    return _pdfrx.merge(
      inputs: inputs,
      outputPath: outputPath,
      password: password,
      passwordsByPath: passwordsByPath,
    );
  }

  @override
  Future<LocalFileRef> assemblePageSources({
    required List<PageSource> sources,
    required String outputPath,
    String? password,
  }) async =>
      await _qpdfAssemble(sources, outputPath, password) ??
      await _pdfrx.assemblePageSources(
        sources: sources,
        outputPath: outputPath,
        password: password,
      );

  @override
  Future<LocalFileRef> extractPages({
    required LocalFileRef input,
    required List<int> pageNumbers1Based,
    required String outputPath,
    String? password,
  }) async =>
      await _qpdfAssemble(
        [for (final n in pageNumbers1Based) PageSource(input, n)],
        outputPath,
        password,
      ) ??
      await _pdfrx.extractPages(
        input: input,
        pageNumbers1Based: pageNumbers1Based,
        outputPath: outputPath,
        password: password,
      );

  Future<int?> _qpdfPageCount(LocalFileRef input, String? password) async {
    if (!await isQpdfCliAvailable()) return null;
    try {
      return await _cli.pageCount(input.path, password: password);
    } catch (_) {
      return null;
    }
  }

  /// Assembles [sources] with `qpdf --empty --pages …`, which keeps form
  /// fields, links, and annotations intact (PDFium page import drops the
  /// AcroForm). Returns null when qpdf is unavailable or fails for a reason
  /// other than a password, so callers fall back to PDFium.
  Future<LocalFileRef?> _qpdfAssemble(
    List<PageSource> sources,
    String outputPath,
    String? password,
  ) async {
    if (sources.isEmpty || !await isQpdfCliAvailable()) return null;
    final args = <String>['--empty', '--pages'];
    var i = 0;
    while (i < sources.length) {
      final file = sources[i].file.path;
      final pages = <int>[];
      while (i < sources.length && sources[i].file.path == file) {
        pages.add(sources[i].pageNumber);
        i++;
      }
      args.add(file);
      if (password != null && password.isNotEmpty) {
        args.add('--password=$password');
      }
      args.add(pages.join(','));
    }
    args.add('--');
    final byDegrees = <int, List<int>>{};
    for (var k = 0; k < sources.length; k++) {
      final deg = ((sources[k].rotationDegrees % 360) + 360) % 360;
      if (deg != 0 && deg % 90 == 0) {
        (byDegrees[deg] ??= []).add(k + 1);
      }
    }
    for (final e in byDegrees.entries) {
      args.add('--rotate=+${e.key}:${e.value.join(',')}');
    }
    args.add(outputPath);
    try {
      await Directory(p.dirname(outputPath)).create(recursive: true);
      await _cli.runRaw(args);
    } on QpdfCliException catch (e) {
      final text = '${e.stderr}${e.stdout}'.toLowerCase();
      if (text.contains('password')) {
        throw DocumentStudioError(
          code: (password == null || password.isEmpty)
              ? DocumentStudioErrorCode.passwordRequired
              : DocumentStudioErrorCode.wrongPassword,
          message: 'Password required',
          cause: e,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
    final stat = await File(outputPath).stat();
    return LocalFileRef(
      path: outputPath,
      displayName: p.basename(outputPath),
      sizeBytes: stat.size,
      lastModified: stat.modified,
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
    final total = await _qpdfPageCount(input, password);
    if (total == null || pagesPerFile < 1) {
      return _pdfrx.splitEveryNPages(
        input: input,
        pagesPerFile: pagesPerFile,
        outputDirectory: outputDirectory,
        namePrefix: namePrefix,
        password: password,
      );
    }
    return splitByRanges(
      input: input,
      rangesPages1Based: [
        for (var start = 1; start <= total; start += pagesPerFile)
          [
            for (
              var n = start;
              n <= (start + pagesPerFile - 1).clamp(1, total);
              n++
            )
              n,
          ],
      ],
      outputDirectory: outputDirectory,
      namePrefix: namePrefix,
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
    if (rangesPages1Based.isEmpty) {
      throw ArgumentError('rangesPages1Based must not be empty');
    }
    final outputs = <LocalFileRef>[];
    for (var i = 0; i < rangesPages1Based.length; i++) {
      final pages = rangesPages1Based[i];
      if (pages.isEmpty) continue;
      outputs.add(
        await extractPages(
          input: input,
          pageNumbers1Based: pages,
          outputPath: p.join(outputDirectory, '$namePrefix-part${i + 1}.pdf'),
          password: password,
        ),
      );
    }
    if (outputs.isEmpty) {
      throw ArgumentError('No non-empty ranges to split');
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
    final total = await _qpdfPageCount(input, password);
    if (total != null) {
      final assembled = await _qpdfAssemble(
        [
          for (var n = 1; n <= total; n++)
            if (!deletePages1Based.contains(n)) PageSource(input, n),
        ],
        outputPath,
        password,
      );
      if (assembled != null) return assembled;
    }
    return _pdfrx.deletePages(
      input: input,
      deletePages1Based: deletePages1Based,
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
  }) async =>
      await _qpdfAssemble(
        [for (final n in newOrder1Based) PageSource(input, n)],
        outputPath,
        password,
      ) ??
      await _pdfrx.reorderPages(
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
  }) async {
    final total = await _qpdfPageCount(input, password);
    if (total != null) {
      final assembled = await _qpdfAssemble(
        [
          for (var n = 1; n <= total; n++)
            PageSource(input, n, rotationDegrees: pageRotationsDegrees[n] ?? 0),
        ],
        outputPath,
        password,
      );
      if (assembled != null) return assembled;
    }
    return _pdfrx.rotatePages(
      input: input,
      pageRotationsDegrees: pageRotationsDegrees,
      outputPath: outputPath,
      password: password,
    );
  }

  @override
  Future<LocalFileRef> reversePages({
    required LocalFileRef input,
    required String outputPath,
    String? password,
  }) async {
    final total = await _qpdfPageCount(input, password);
    if (total != null) {
      final assembled = await _qpdfAssemble(
        [for (var n = total; n >= 1; n--) PageSource(input, n)],
        outputPath,
        password,
      );
      if (assembled != null) return assembled;
    }
    return _pdfrx.reversePages(
      input: input,
      outputPath: outputPath,
      password: password,
    );
  }

  /// Crop and resize always have an on-device editor. qpdf is optional.
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
    return _pageBoxWithQpdfOrDart(
      outputPath: outputPath,
      qpdf: () => _cli.cropPages(
        inputPath: input.path,
        outputPath: outputPath,
        marginMm: margin.marginMm,
        pages1Based: pageNumbers1Based,
        password: password,
      ),
      dart: () => _pdfrx.cropPages(
        input: input,
        pageNumbers1Based: pageNumbers1Based,
        margin: margin,
        outputPath: outputPath,
        password: password,
      ),
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
    return _pageBoxWithQpdfOrDart(
      outputPath: outputPath,
      qpdf: () => _cli.cropPagesToBox(
        inputPath: input.path,
        outputPath: outputPath,
        box: box,
        pages1Based: pageNumbers1Based,
        password: password,
      ),
      dart: () => _pdfrx.cropPagesToBox(
        input: input,
        pageNumbers1Based: pageNumbers1Based,
        box: box,
        outputPath: outputPath,
        password: password,
      ),
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
    return _pageBoxWithQpdfOrDart(
      outputPath: outputPath,
      qpdf: () => _cli.setPageSize(
        inputPath: input.path,
        outputPath: outputPath,
        paperSizeName: paperSize.qpdfName,
        pages1Based: pageNumbers1Based,
        password: password,
      ),
      dart: () => _pdfrx.setPageSize(
        input: input,
        pageNumbers1Based: pageNumbers1Based,
        paperSize: paperSize,
        outputPath: outputPath,
        password: password,
      ),
    );
  }

  /// Uses qpdf when the CLI exists. Any CLI failure (missing binary, old
  /// build without page-box flags) falls through to the pure-Dart editor.
  Future<LocalFileRef> _pageBoxWithQpdfOrDart({
    required String outputPath,
    required Future<void> Function() qpdf,
    required Future<LocalFileRef> Function() dart,
  }) async {
    if (await isQpdfCliPageBoxEditAvailable()) {
      try {
        await qpdf();
        return _localRef(outputPath);
      } on QpdfCliException {
        // On-device CropBox / MediaBox edit below.
      }
    }
    return dart();
  }

  LocalFileRef _localRef(String outputPath) =>
      LocalFileRef(path: outputPath, displayName: outputPath.split('/').last);

  @override
  Future<LocalFileRef> compressPdf({
    required LocalFileRef input,
    required String outputPath,
    PdfCompressOptions options = const PdfCompressOptions(),
    String? password,
  }) async {
    // Prefer qpdf on desktop when the CLI is present (stronger object /
    // stream optimizer). Android always uses DartPdfCompress — never a
    // "qpdf not available" error. That path is PdfEditDocument image
    // downsample + JPEG re-encode, Flate recompress, and a full classic-xref
    // rewrite (see lib/infrastructure/pdf/dart_pdf_compress.dart).
    if (!Platform.isAndroid && await isQpdfCliAvailable()) {
      String? downsampled;
      try {
        var source = input.path;
        final maxPx = options.downsampleMaxPx;
        if (maxPx != null) {
          downsampled = '$outputPath.images.pdf';
          await downsamplePdfJpegImages(
            inputPath: source,
            outputPath: downsampled,
            maxSidePx: maxPx,
            jpegQuality: options.jpegQuality ?? 75,
            password: password,
          );
          source = downsampled;
        }
        await _cli.compressPdf(
          inputPath: source,
          outputPath: outputPath,
          password: password,
          linearize: options.linearize,
          recompressFlate: options.recompressFlate,
          optimizeImages: options.optimizeImages,
          jpegQuality: options.jpegQuality,
        );
        // Prefer the smaller of source vs output; never claim growth as a win.
        final inLen = await File(input.path).length();
        if (await File(outputPath).length() >= inLen) {
          await File(input.path).copy(outputPath);
        }
      } on QpdfCliException catch (e) {
        final detail = e.stderr.trim().isEmpty
            ? e.stdout.trim()
            : e.stderr.trim();
        final text = detail.toLowerCase();
        if (text.contains('password') &&
            (text.contains('incorrect') || text.contains('invalid'))) {
          throw DocumentStudioError(
            code: DocumentStudioErrorCode.wrongPassword,
            message: 'Incorrect password for this PDF.',
            cause: e,
            recoveryHint: detail.isEmpty ? null : detail,
          );
        }
        // qpdf failed — fall through to on-device Dart compress.
        return DartPdfCompress.compressToFile(
          input: input,
          outputPath: outputPath,
          options: options,
          password: password,
        );
      } catch (e) {
        if (e is DocumentStudioError) rethrow;
        return DartPdfCompress.compressToFile(
          input: input,
          outputPath: outputPath,
          options: options,
          password: password,
        );
      } finally {
        if (downsampled != null) {
          try {
            await File(downsampled).delete();
          } catch (_) {}
        }
      }
      return LocalFileRef(
        path: outputPath,
        displayName: outputPath.split('/').last,
      );
    }
    return DartPdfCompress.compressToFile(
      input: input,
      outputPath: outputPath,
      options: options,
      password: password,
    );
  }
}
