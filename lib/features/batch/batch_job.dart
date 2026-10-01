import 'dart:io';

import 'package:document_studio/core/batch/batch_runner.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/jobs/job_models.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/compression/compress_service.dart';
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
        BatchToolKind.protect =>
          'Encrypts every file with the same open password.',
        BatchToolKind.verify =>
          'Checks that every file exists and can be read — writes nothing.',
      };

  IconData get icon => switch (this) {
        BatchToolKind.compressBalanced => Icons.tune_rounded,
        BatchToolKind.compressSmallest => Icons.compress_rounded,
        BatchToolKind.compressLossless => Icons.high_quality_outlined,
        BatchToolKind.removeMetadata => Icons.cleaning_services_outlined,
        BatchToolKind.protect => Icons.lock_outline_rounded,
        BatchToolKind.verify => Icons.fact_check_outlined,
      };

  String get defaultSuffix => switch (this) {
        BatchToolKind.compressBalanced ||
        BatchToolKind.compressSmallest ||
        BatchToolKind.compressLossless =>
          '_compressed',
        BatchToolKind.removeMetadata => '_clean',
        BatchToolKind.protect => '_protected',
        BatchToolKind.verify => '',
      };

  bool get writesFiles => this != BatchToolKind.verify;

  /// Historically qpdf-only; protect / strip-metadata now have Dart fallbacks.
  bool get needsQpdf => false;
}

class BatchOutputNaming {
  BatchOutputNaming({
    this.outputDirectory,
    this.suffix = '_compressed',
  });

  /// When null, outputs sit beside each input file.
  final String? outputDirectory;
  final String suffix;
  final Set<String> _claimed = {};

  /// Next free output path: never overwrites an existing file or another
  /// output from the same run (inputs with equal names from different
  /// folders), and never the input itself.
  String outputPathFor(LocalFileRef input) {
    final dir = outputDirectory ?? p.dirname(input.path);
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
      BatchToolKind.verify => 'Check files only',
    };
