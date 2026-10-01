import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/jobs/job_models.dart';
import 'package:document_studio/core/jobs/job_runner.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/pdf_markup/pdf_markup_models.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_service.dart';
import 'package:path/path.dart' as p;

class PdfMarkupService {
  PdfMarkupService({
    required PdfOverlayService overlay,
    required FileStoragePort storage,
    required JobRunner jobs,
  })  : _overlay = overlay,
        _storage = storage,
        _jobs = jobs;

  final PdfOverlayService _overlay;
  final FileStoragePort _storage;
  final JobRunner _jobs;

  Future<LocalFileRef> applyHeaderFooterAndPromptSave({
    required LocalFileRef input,
    required HeaderFooterOptions options,
    String? password,
    JobHandle<LocalFileRef>? handle,
    void Function(JobProgress)? onProgress,
  }) {
    return _exportWithSaveDialog(
      input: input,
      handle: handle,
      onProgress: onProgress,
      work: (tempOut) => _overlay.applyHeaderFooter(
        input: input,
        outputPath: tempOut,
        options: options,
        password: password,
      ),
      suggestedName: 'marked-${input.displayName}',
    );
  }

  /// Applies header/footer to a temp file and returns bytes (no save dialog).
  Future<Uint8List> applyHeaderFooterToBytes({
    required LocalFileRef input,
    required HeaderFooterOptions options,
    String? password,
  }) {
    return _exportToBytes(
      work: (tempOut) => _overlay.applyHeaderFooter(
        input: input,
        outputPath: tempOut,
        options: options,
        password: password,
      ),
    );
  }

  Future<LocalFileRef> applyWatermarkAndPromptSave({
    required LocalFileRef input,
    required WatermarkOptions options,
    String? password,
    JobHandle<LocalFileRef>? handle,
    void Function(JobProgress)? onProgress,
  }) {
    return _exportWithSaveDialog(
      input: input,
      handle: handle,
      onProgress: onProgress,
      work: (tempOut) => _overlay.applyTextWatermark(
        input: input,
        outputPath: tempOut,
        options: options,
        password: password,
      ),
      suggestedName: 'watermarked-${input.displayName}',
    );
  }

  /// Applies watermark to a temp file and returns bytes (no save dialog).
  Future<Uint8List> applyWatermarkToBytes({
    required LocalFileRef input,
    required WatermarkOptions options,
    String? password,
  }) {
    return _exportToBytes(
      work: (tempOut) => _overlay.applyTextWatermark(
        input: input,
        outputPath: tempOut,
        options: options,
        password: password,
      ),
    );
  }

  /// Image watermark burn-in (opacity/rotation baked; qpdf overlay or underlay).
  Future<Uint8List> applyImageWatermarkToBytes({
    required LocalFileRef input,
    required Uint8List imageBytes,
    required double opacity,
    required double rotationDegrees,
    required double heightFrac,
    required bool tiled,
    Set<int>? pages1Based,
    bool behindContent = false,
    String? password,
  }) {
    return _exportToBytes(
      work: (tempOut) => _overlay.applyImageWatermark(
        input: input,
        outputPath: tempOut,
        imageBytes: imageBytes,
        opacity: opacity,
        rotationDegrees: rotationDegrees,
        heightFrac: heightFrac,
        tiled: tiled,
        pages1Based: pages1Based,
        behindContent: behindContent,
        password: password,
      ),
    );
  }

  Future<LocalFileRef> applyPageNumbersAndPromptSave({
    required LocalFileRef input,
    required PageNumberOptions options,
    String? password,
    JobHandle<LocalFileRef>? handle,
    void Function(JobProgress)? onProgress,
  }) {
    return _exportWithSaveDialog(
      input: input,
      handle: handle,
      onProgress: onProgress,
      work: (tempOut) => _overlay.applyPageNumbers(
        input: input,
        outputPath: tempOut,
        options: options,
        password: password,
      ),
      suggestedName: 'numbered-${input.displayName}',
    );
  }

  /// Applies page numbers to a temp file and returns bytes (no save dialog).
  Future<Uint8List> applyPageNumbersToBytes({
    required LocalFileRef input,
    required PageNumberOptions options,
    String? password,
  }) {
    return _exportToBytes(
      work: (tempOut) => _overlay.applyPageNumbers(
        input: input,
        outputPath: tempOut,
        options: options,
        password: password,
      ),
    );
  }

  Future<Uint8List> _exportToBytes({
    required Future<LocalFileRef> Function(String tempOut) work,
  }) async {
    final tempDir = await _storage.getTempDirectory();
    final tempOut = p.join(
      tempDir,
      'markup-${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    await work(tempOut);
    final bytes = await File(tempOut).readAsBytes();
    try {
      await File(tempOut).delete();
    } catch (_) {}
    return Uint8List.fromList(bytes);
  }

  Future<LocalFileRef> _exportWithSaveDialog({
    required LocalFileRef input,
    required Future<LocalFileRef> Function(String tempOut) work,
    required String suggestedName,
    JobHandle<LocalFileRef>? handle,
    void Function(JobProgress)? onProgress,
  }) async {
    final jobHandle = handle ?? JobHandle<LocalFileRef>();
    return _jobs.run(
      handle: jobHandle,
      work: (report, cancelToken) async {
        void reportUi(JobProgress progress) {
          report(progress);
          onProgress?.call(progress);
        }

        reportUi(const JobProgress(fraction: 0.05, message: 'Preparing'));
        if (cancelToken.isCancelled) {
          throw const DocumentStudioError(
            code: DocumentStudioErrorCode.processCancelled,
            message: 'Cancelled',
          );
        }
        final tempDir = await _storage.getTempDirectory();
        final tempOut = p.join(
          tempDir,
          'markup-${DateTime.now().microsecondsSinceEpoch}.pdf',
        );
        reportUi(const JobProgress(fraction: 0.35, message: 'Applying overlay'));
        await work(tempOut);
        reportUi(const JobProgress(fraction: 0.7, message: 'Choose save location'));
        final bytes = await File(tempOut).readAsBytes();
        final savePath = await _storage.pickSavePath(
          suggestedName: suggestedName,
          bytes: bytes,
          allowedExtensions: ['pdf'],
          mimeType: 'application/pdf',
        );
        if (savePath == null) {
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
        reportUi(const JobProgress(fraction: 1, message: 'Done'));
        return LocalFileRef(
          path: savePath,
          displayName: p.basename(savePath),
        );
      },
    );
  }
}
