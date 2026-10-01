import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/infrastructure/pdf/page_source.dart';
import 'package:document_studio/infrastructure/pdf/pdf_compress_options.dart';
import 'package:document_studio/infrastructure/pdf/pdf_page_box_options.dart';

class StructureEngineInfo {
  const StructureEngineInfo({
    required this.id,
    required this.label,
    required this.supportsEncryptedInput,
  });

  final String id;
  final String label;
  final bool supportsEncryptedInput;
}

/// Structure operations: merge, split, page edits. See PDF-ENGINE.md routing.
abstract class PdfStructurePort {
  Future<bool> isAvailable();

  Future<StructureEngineInfo> engineInfo();

  Future<LocalFileRef> merge({
    required List<LocalFileRef> inputs,
    required String outputPath,
    String? password,
    Map<String, String>? passwordsByPath,
  });

  /// Build a PDF from an ordered list of page references (merge / reorder / extract).
  Future<LocalFileRef> assemblePageSources({
    required List<PageSource> sources,
    required String outputPath,
    String? password,
  });

  Future<LocalFileRef> extractPages({
    required LocalFileRef input,
    required List<int> pageNumbers1Based,
    required String outputPath,
    String? password,
  });

  Future<List<LocalFileRef>> splitEveryNPages({
    required LocalFileRef input,
    required int pagesPerFile,
    required String outputDirectory,
    required String namePrefix,
    String? password,
  });

  /// One output PDF per [ranges] entry (inclusive 1-based page numbers).
  Future<List<LocalFileRef>> splitByRanges({
    required LocalFileRef input,
    required List<List<int>> rangesPages1Based,
    required String outputDirectory,
    required String namePrefix,
    String? password,
  });

  Future<LocalFileRef> deletePages({
    required LocalFileRef input,
    required Set<int> deletePages1Based,
    required String outputPath,
    String? password,
  });

  Future<LocalFileRef> reorderPages({
    required LocalFileRef input,
    required List<int> newOrder1Based,
    required String outputPath,
    String? password,
  });

  Future<LocalFileRef> rotatePages({
    required LocalFileRef input,
    required Map<int, int> pageRotationsDegrees,
    required String outputPath,
    String? password,
  });

  Future<LocalFileRef> reversePages({
    required LocalFileRef input,
    required String outputPath,
    String? password,
  });

  /// qpdf stream recompression / object cleanup (see [PdfCompressOptions]).
  Future<LocalFileRef> compressPdf({
    required LocalFileRef input,
    required String outputPath,
    PdfCompressOptions options = const PdfCompressOptions(),
    String? password,
  });

  /// Whether CropBox / MediaBox edits are available.
  ///
  /// True when qpdf is present or the on-device page-box editor can run.
  Future<bool> supportsPageBoxEditing();

  Future<LocalFileRef> cropPages({
    required LocalFileRef input,
    required Set<int> pageNumbers1Based,
    required PdfCropMarginPreset margin,
    required String outputPath,
    String? password,
  });

  Future<LocalFileRef> cropPagesToBox({
    required LocalFileRef input,
    required Set<int> pageNumbers1Based,
    required PdfCropRectPt box,
    required String outputPath,
    String? password,
  });

  Future<LocalFileRef> setPageSize({
    required LocalFileRef input,
    required Set<int> pageNumbers1Based,
    required PdfPaperSize paperSize,
    required String outputPath,
    String? password,
  });
}
