import 'package:document_studio/core/pdf/large_doc_policy.dart';
import 'package:document_studio/domain/pdf_markup/pdf_markup_models.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_service.dart';
import 'package:document_studio_ocr/document_studio_ocr.dart';

import 'dart:io';

import 'package:document_studio/core/batch/batch_runner.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/jobs/job_models.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/compression/compress_service.dart';
import 'package:document_studio/infrastructure/conversion/images_to_pdf_service.dart';
import 'package:document_studio/infrastructure/pdf/pdf_compress_options.dart';
import 'package:document_studio/infrastructure/pdf/qpdf_encrypt_adapter.dart';
import 'package:document_studio/infrastructure/pdf/qpdf_metadata_adapter.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

enum BatchToolKind {
  compressBalanced,
  compressSmallest,
  compressLossless,
  removeMetadata,
  protect,
  ocr,
  watermark,
  verify,
}

extension BatchToolKindX on BatchToolKind {
  String get label => batchToolLabel(this);

  String get description => switch (this) {
    BatchToolKind.compressBalanced =>
      'Much smaller files with sharp text and good image quality.',
    BatchToolKind.compressSmallest =>
      'Smallest files; photos and scans lose some quality.',
    BatchToolKind.compressLossless =>
      'Rewrites each PDF more compactly without touching images.',
    BatchToolKind.removeMetadata =>
      'Strips title, author, dates and XMP metadata from every file.',
    BatchToolKind.protect => 'Encrypts every file with the same open password.',
    BatchToolKind.ocr =>
      'Recognizes text in scanned pages so every file becomes searchable.',
    BatchToolKind.watermark =>
      'Stamps the same text across every page of every file.',
    BatchToolKind.verify =>
      'Checks that every file exists and can be read — writes nothing.',
  };

  IconData get icon => switch (this) {
    BatchToolKind.compressBalanced => Icons.tune_rounded,
    BatchToolKind.compressSmallest => Icons.compress_rounded,
    BatchToolKind.compressLossless => Icons.high_quality_outlined,
    BatchToolKind.removeMetadata => Icons.cleaning_services_outlined,
    BatchToolKind.protect => Icons.lock_outline_rounded,
    BatchToolKind.ocr => Icons.document_scanner_outlined,
    BatchToolKind.watermark => Icons.branding_watermark_outlined,
    BatchToolKind.verify => Icons.fact_check_outlined,
  };

  String get defaultSuffix => switch (this) {
    BatchToolKind.compressBalanced ||
    BatchToolKind.compressSmallest ||
    BatchToolKind.compressLossless => '_compressed',
    BatchToolKind.removeMetadata => '_clean',
    BatchToolKind.protect => '_protected',
    BatchToolKind.ocr => '_searchable',
    BatchToolKind.watermark => '_marked',
    BatchToolKind.verify => '',
  };

  bool get writesFiles => this != BatchToolKind.verify;

  /// Historically qpdf-only; protect / strip-metadata now have Dart fallbacks.
  bool get needsQpdf => false;
}

class BatchOutputNaming {
  BatchOutputNaming({this.outputDirectory, this.suffix = '_compressed'});

  /// When null, outputs sit beside each input file.
  final String? outputDirectory;
  final String suffix;
  final Set<String> _claimed = {};

  /// Inputs that are temporary conversions (image → PDF): where their result
  /// should land when no output folder was chosen.
  final Map<String, String> _originDirs = {};

  void rememberOrigin(String tempPath, String originalDir) =>
      _originDirs[tempPath] = originalDir;

  /// Next free output path: never overwrites an existing file or another
  /// output from the same run (inputs with equal names from different
  /// folders), and never the input itself.
  String outputPathFor(LocalFileRef input) {
    final dir =
        outputDirectory ?? _originDirs[input.path] ?? p.dirname(input.path);
    final base = p.basenameWithoutExtension(input.path);
    final safeSuffix = suffix.isEmpty ? '_out' : suffix;
    var candidate = p.join(dir, '$base$safeSuffix.pdf');
    var n = 2;
    while (_claimed.contains(candidate) ||
        File(candidate).existsSync() ||
        p.equals(candidate, input.path)) {
      candidate = p.join(dir, '$base$safeSuffix ($n).pdf');
      n++;
    }
    _claimed.add(candidate);
    return candidate;
  }
}

typedef BatchProcessor = BatchFileProcessor;

Never _cancelled() => throw const DocumentStudioError(
  code: DocumentStudioErrorCode.processCancelled,
  message: 'Cancelled',
);

BatchProcessor batchProcessorFor({
  required BatchToolKind tool,
  required FileStoragePort storage,
  CompressService? compress,
  PdfMetadataPort? metadata,
  PdfEncryptPort? encrypt,
  String? password,
  BatchOutputNaming? naming,
  SearchablePdfPort? searchable,
  PdfOverlayService? overlay,
  String watermarkText = 'CONFIDENTIAL',
}) {
  final outNaming = naming ?? BatchOutputNaming(suffix: tool.defaultSuffix);
  switch (tool) {
    case BatchToolKind.verify:
      return (input, report, cancelToken) async {
        if (cancelToken.isCancelled) _cancelled();
        report(const JobProgress(fraction: 0.3, message: 'Checking file'));
        if (!await storage.fileExists(input)) {
          throw StateError('File not found');
        }
        final header = await File(input.path).openRead(0, 5).first;
        if (String.fromCharCodes(header) != '%PDF-') {
          throw StateError('Not a PDF file');
        }
        report(const JobProgress(fraction: 1, message: 'Looks good'));
        return null;
      };
    case BatchToolKind.compressBalanced:
    case BatchToolKind.compressSmallest:
    case BatchToolKind.compressLossless:
      final compressService = compress;
      if (compressService == null) {
        throw StateError('Compress service not configured');
      }
      final profile = switch (tool) {
        BatchToolKind.compressSmallest => CompressProfile.smallest,
        BatchToolKind.compressLossless => CompressProfile.highQuality,
        _ => CompressProfile.balanced,
      };
      return (input, report, cancelToken) async {
        if (cancelToken.isCancelled) _cancelled();
        report(const JobProgress(fraction: 0.05, message: 'Compressing'));
        final outPath = outNaming.outputPathFor(input);
        await compressService.compressToPath(
          input: input,
          outputPath: outPath,
          options: PdfCompressOptions.fromProfile(profile),
          onProgress: report,
        );
        return outPath;
      };
    case BatchToolKind.removeMetadata:
      final port = metadata;
      if (port == null) throw StateError('Metadata engine not configured');
      return (input, report, cancelToken) async {
        if (cancelToken.isCancelled) _cancelled();
        report(const JobProgress(fraction: 0.2, message: 'Removing metadata'));
        final outPath = outNaming.outputPathFor(input);
        await port.stripAllMetadata(input: input, outputPath: outPath);
        return outPath;
      };
    case BatchToolKind.ocr:
      final ocr = searchable;
      if (ocr == null || ocr is BlockedSearchablePdfPort) {
        throw StateError(BlockedSearchablePdfPort.blockedReason);
      }
      return (input, report, cancelToken) async {
        if (cancelToken.isCancelled) _cancelled();
        report(const JobProgress(fraction: 0.1, message: 'Recognizing text'));
        if (await File(input.path).length() >
            LargeDocPolicy.analysisByteLimit) {
          throw StateError('This file is too large to OCR in one go.');
        }
        final bytes = await File(input.path).readAsBytes();
        final out = await ocr.createSearchablePdf(bytes);
        final outPath = outNaming.outputPathFor(input);
        await File(outPath).writeAsBytes(out, flush: true);
        return outPath;
      };
    case BatchToolKind.watermark:
      final svc = overlay;
      if (svc == null) throw StateError('Watermark engine not configured');
      return (input, report, cancelToken) async {
        if (cancelToken.isCancelled) _cancelled();
        report(const JobProgress(fraction: 0.2, message: 'Adding watermark'));
        final outPath = outNaming.outputPathFor(input);
        await svc.applyTextWatermark(
          input: input,
          outputPath: outPath,
          options: WatermarkOptions(textTemplate: watermarkText),
        );
        return outPath;
      };
    case BatchToolKind.protect:
      final port = encrypt;
      final pw = password;
      if (port == null) throw StateError('Encryption engine not configured');
      if (pw == null || pw.isEmpty) throw StateError('Enter a password first');
      return (input, report, cancelToken) async {
        if (cancelToken.isCancelled) _cancelled();
        report(const JobProgress(fraction: 0.2, message: 'Encrypting'));
        final outPath = outNaming.outputPathFor(input);
        await port.encryptWithPassword(
          input: input,
          outputPath: outPath,
          userPassword: pw,
          permissions: const PdfEncryptPermissions(
            allowPrinting: true,
            allowModify: true,
            allowExtract: true,
            allowAnnotate: true,
          ),
        );
        return outPath;
      };
  }
}

String batchToolLabel(BatchToolKind kind) => switch (kind) {
  BatchToolKind.compressBalanced => 'Compress — recommended',
  BatchToolKind.compressSmallest => 'Compress — smallest',
  BatchToolKind.compressLossless => 'Compress — lossless',
  BatchToolKind.removeMetadata => 'Remove metadata',
  BatchToolKind.protect => 'Password-protect',
  BatchToolKind.ocr => 'Make searchable (OCR)',
  BatchToolKind.watermark => 'Add watermark',
  BatchToolKind.verify => 'Check files only',
};

/// Runs several tools on each file in order (Acrobat "Action Wizard"):
/// each step reads the previous step's output; only the last one is written
/// to the user's folder, the rest go to a scratch folder that is removed.
BatchProcessor batchPipelineProcessor({
  required List<BatchToolKind> steps,
  required FileStoragePort storage,
  required BatchOutputNaming finalNaming,
  CompressService? compress,
  PdfMetadataPort? metadata,
  PdfEncryptPort? encrypt,
  String? password,
  SearchablePdfPort? searchable,
  PdfOverlayService? overlay,
  String watermarkText = 'CONFIDENTIAL',
}) {
  if (steps.length == 1) {
    return batchProcessorFor(
      tool: steps.single,
      storage: storage,
      compress: compress,
      metadata: metadata,
      encrypt: encrypt,
      password: password,
      naming: finalNaming,
      searchable: searchable,
      overlay: overlay,
      watermarkText: watermarkText,
    );
  }
  return (input, report, cancelToken) async {
    final scratch = await Directory.systemTemp.createTemp('ds_batch_');
    try {
      var current = input;
      String? last;
      // Pictures are turned into a one-page PDF first, then run through the
      // same steps.
      if (batchIsImage(input.path)) {
        report(
          const JobProgress(fraction: 0.02, message: 'Converting image to PDF'),
        );
        final pdfPath = p.join(
          scratch.path,
          '${p.basenameWithoutExtension(input.path)}.pdf',
        );
        await ImagesToPdfService().fromImageFiles(
          images: [input],
          outputPath: pdfPath,
        );
        finalNaming.rememberOrigin(pdfPath, p.dirname(input.path));
        current = LocalFileRef(path: pdfPath, displayName: p.basename(pdfPath));
      }
      for (var i = 0; i < steps.length; i++) {
        if (cancelToken.isCancelled) _cancelled();
        final isLast = i == steps.length - 1;
        final step = batchProcessorFor(
          tool: steps[i],
          storage: storage,
          compress: compress,
          metadata: metadata,
          encrypt: encrypt,
          password: password,
          searchable: searchable,
          overlay: overlay,
          watermarkText: watermarkText,
          naming: isLast
              ? finalNaming
              : BatchOutputNaming(
                  outputDirectory: scratch.path,
                  suffix: '_step$i',
                ),
        );
        last = await step(
          current,
          (prog) => report(
            JobProgress(
              fraction: ((i + prog.fraction) / steps.length).clamp(0.0, 1.0),
              message: '${steps[i].label}: ${prog.message ?? ''}'.trim(),
            ),
          ),
          cancelToken,
        );
        if (last == null) return null;
        current = LocalFileRef(path: last, displayName: p.basename(last));
      }
      return last;
    } finally {
      try {
        await scratch.delete(recursive: true);
      } catch (_) {}
    }
  };
}

const kBatchImageExtensions = [
  'jpg',
  'jpeg',
  'png',
  'tif',
  'tiff',
  'bmp',
  'webp',
];

bool batchIsImage(String path) => kBatchImageExtensions.contains(
  p.extension(path).toLowerCase().replaceFirst('.', ''),
);
