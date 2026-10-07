import 'dart:io';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/jobs/job_models.dart';
import 'package:document_studio/core/jobs/job_runner.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/infrastructure/pdf/pdf_compress_options.dart';
import 'package:document_studio/infrastructure/pdf/pdf_structure_port.dart';
import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:path/path.dart' as p;

class CompressResult {
  const CompressResult({
    required this.output,
    required this.beforeBytes,
    required this.afterBytes,
    required this.usedQpdf,
  });

  final LocalFileRef output;
  final int beforeBytes;
  final int afterBytes;
  final bool usedQpdf;

  double get percentSaved =>
      beforeBytes == 0 ? 0 : (1 - afterBytes / beforeBytes) * 100;
}

class CompressService {
  CompressService({
    required this._structure,
    required this._storage,
    required this._jobs,
  });

  final PdfStructurePort _structure;
  final FileStoragePort _storage;
  final JobRunner _jobs;

  Future<bool> isQpdfPreferredAvailable() => isQpdfCliAvailable();

  /// Writes compressed PDF to [outputPath] without a save dialog (batch / automation).
  Future<LocalFileRef> compressToPath({
    required LocalFileRef input,
    required String outputPath,
    required PdfCompressOptions options,
    String? password,
    JobHandle<LocalFileRef>? handle,
    void Function(JobProgress)? onProgress,
  }) async {
    final jobHandle = handle ?? JobHandle<LocalFileRef>();
    return _jobs.run(
      handle: jobHandle,
      work: (report, cancelToken) async {
        report(const JobProgress(fraction: 0.1, message: 'Optimizing PDF'));
        if (cancelToken.isCancelled) {
          throw const DocumentStudioError(
            code: DocumentStudioErrorCode.processCancelled,
            message: 'Cancelled',
          );
        }
        await _structure.compressPdf(
          input: input,
          outputPath: outputPath,
          options: options,
          password: password,
        );
        if (cancelToken.isCancelled) {
          throw const DocumentStudioError(
            code: DocumentStudioErrorCode.processCancelled,
            message: 'Cancelled',
          );
        }
        report(const JobProgress(fraction: 1, message: 'Done'));
        onProgress?.call(const JobProgress(fraction: 1, message: 'Done'));
        return LocalFileRef(
          path: outputPath,
          displayName: p.basename(outputPath),
        );
      },
    );
  }

  Future<CompressResult> compressAndPromptSave({
    required LocalFileRef input,
    required PdfCompressOptions options,
    String? password,
    JobHandle<CompressResult>? handle,
    void Function(JobProgress)? onProgress,
  }) async {
    final jobHandle = handle ?? JobHandle<CompressResult>();
    return _jobs.run(
      handle: jobHandle,
      work: (report, cancelToken) async {
        report(const JobProgress(fraction: 0.05, message: 'Reading file'));
        final before = await File(input.path).length();
        if (cancelToken.isCancelled) {
          throw const DocumentStudioError(
            code: DocumentStudioErrorCode.processCancelled,
            message: 'Cancelled',
          );
        }
        final tempDir = await _storage.getTempDirectory();
        final tempOut = p.join(
          tempDir,
          'compress-${DateTime.now().microsecondsSinceEpoch}.pdf',
        );
        report(const JobProgress(fraction: 0.35, message: 'Optimizing PDF'));
        await _structure.compressPdf(
          input: input,
          outputPath: tempOut,
          options: options,
          password: password,
        );
        if (cancelToken.isCancelled) {
          try {
            await File(tempOut).delete();
          } catch (_) {}
          throw const DocumentStudioError(
            code: DocumentStudioErrorCode.processCancelled,
            message: 'Cancelled',
          );
        }
        var after = await File(tempOut).length();
        if (after > before * 4) {
          throw const DocumentStudioError(
            code: DocumentStudioErrorCode.invalidPdf,
            message: 'Output grew unexpectedly; aborting as a safety measure.',
            recoveryHint:
                'Try a different profile or check if the PDF is damaged.',
          );
        }
        report(
          const JobProgress(fraction: 0.7, message: 'Choose save location'),
        );
        // Never save a copy that is bigger than the original.
        final grew = after >= before;
        final bytes = await File(grew ? input.path : tempOut).readAsBytes();
        if (grew) after = before;
        final savePath = await _storage.pickSavePath(
          suggestedName:
              '${p.basenameWithoutExtension(input.displayName)}-compressed.pdf',
          bytes: bytes,
          allowedExtensions: ['pdf'],
          mimeType: 'application/pdf',
        );
        if (savePath == null) {
          try {
            await File(tempOut).delete();
          } catch (_) {}
          throw const DocumentStudioError(
            code: DocumentStudioErrorCode.processCancelled,
            message: 'Save cancelled',
          );
        }
        await _storage.writeAtomic(
          destinationPath: savePath,
          writeToTemp: (temp) async {
            await File(temp).writeAsBytes(bytes, flush: true);
          },
        );
        try {
          await File(tempOut).delete();
        } catch (_) {}
        final usedQpdf = await isQpdfCliAvailable();
        report(const JobProgress(fraction: 1, message: 'Done'));
        onProgress?.call(const JobProgress(fraction: 1, message: 'Done'));
        return CompressResult(
          output: LocalFileRef(
            path: savePath,
            displayName: p.basename(savePath),
            sizeBytes: after,
          ),
          beforeBytes: before,
          afterBytes: after,
          usedQpdf: usedQpdf,
        );
      },
    );
  }

  /// Runs compression to a temp file and returns real before/after sizes (no save dialog).
  Future<CompressResult> estimateCompress({
    required LocalFileRef input,
    required PdfCompressOptions options,
    String? password,
  }) async {
    final before = await File(input.path).length();
    final tempDir = await _storage.getTempDirectory();
    final tempOut = p.join(
      tempDir,
      'compress-preview-${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    try {
      await _structure.compressPdf(
        input: input,
        outputPath: tempOut,
        options: options,
        password: password,
      );
      final after = await File(tempOut).length();
      final usedQpdf = await isQpdfCliAvailable();
      return CompressResult(
        output: LocalFileRef(
          path: tempOut,
          displayName: p.basename(tempOut),
          sizeBytes: after,
        ),
        beforeBytes: before,
        afterBytes: after,
        usedQpdf: usedQpdf,
      );
    } finally {
      try {
        await File(tempOut).delete();
      } catch (_) {}
    }
  }

  /// Finds the gentlest preset whose output fits [targetBytes] (Acrobat-style
  /// "reduce to about N MB"). Tries lossless → recommended → extreme →
  /// smallest → a harsher last resort, measuring each, and reports progress.
  /// Returns the options to use plus whether the target was reached.
  Future<({PdfCompressOptions options, bool reached, int? bestBytes})>
  chooseOptionsForTarget({
    required LocalFileRef input,
    required int targetBytes,
    String? password,
    void Function(JobProgress)? onProgress,
  }) async {
    final ladder = <PdfCompressOptions>[
      PdfCompressOptions.fromProfile(CompressProfile.highQuality),
      PdfCompressOptions.fromProfile(CompressProfile.balanced),
      PdfCompressOptions.fromProfile(CompressProfile.extreme),
      PdfCompressOptions.fromProfile(CompressProfile.smallest),
      const PdfCompressOptions(
        profile: CompressProfile.custom,
        recompressFlate: true,
        optimizeImages: true,
        jpegQuality: 30,
        downsampleMaxPx: 800,
        targetDpi: 72,
      ),
    ];
    PdfCompressOptions best = ladder.first;
    int? bestBytes;
    for (var i = 0; i < ladder.length; i++) {
      onProgress?.call(
        JobProgress(
          fraction: 0.05 + 0.6 * i / ladder.length,
          message: 'Trying level ${i + 1} of ${ladder.length}…',
        ),
      );
      final r = await estimateCompress(
        input: input,
        options: ladder[i],
        password: password,
      );
      if (bestBytes == null || r.afterBytes < bestBytes) {
        bestBytes = r.afterBytes;
        best = ladder[i];
      }
      if (r.afterBytes <= targetBytes) {
        return (options: ladder[i], reached: true, bestBytes: r.afterBytes);
      }
    }
    return (options: best, reached: false, bestBytes: bestBytes);
  }
}
