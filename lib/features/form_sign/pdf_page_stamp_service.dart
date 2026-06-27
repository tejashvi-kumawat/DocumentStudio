import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/jobs/job_models.dart';
import 'package:document_studio/core/jobs/job_runner.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/pdf_stamp/pdf_page_stamp_models.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_service.dart';
import 'package:path/path.dart' as p;

class PdfPageStampService {
  PdfPageStampService({
    required PdfOverlayService overlay,
    required FileStoragePort storage,
    required JobRunner jobs,
  })  : _overlay = overlay,
        _storage = storage,
        _jobs = jobs;

  final PdfOverlayService _overlay;
  final FileStoragePort _storage;
  final JobRunner _jobs;

  Future<LocalFileRef> applyTypedSignatureAndPromptSave({
    required LocalFileRef input,
    required int pageIndex1Based,
    required String signatureText,
    PdfPageStampLayout layout = const PdfPageStampLayout(),
    String? password,
    JobHandle<LocalFileRef>? handle,
    void Function(JobProgress)? onProgress,
  }) {
    return _exportWithSaveDialog(
      input: input,
      handle: handle,
      onProgress: onProgress,
      suggestedName: 'signed-${input.displayName}',
      work: (tempOut) => _overlay.applyTypedSignatureOnPage(
        input: input,
        outputPath: tempOut,
        pageIndex1Based: pageIndex1Based,
        signatureText: signatureText,
        layout: layout,
        password: password,
      ),
    );
  }

  /// Writes stamped PDF to a temp path (caller commits via DocumentSession).
  Future<Uint8List> applyTypedSignatureToBytes({
    required LocalFileRef input,
    required int pageIndex1Based,
    required String signatureText,
    PdfPageStampLayout layout = const PdfPageStampLayout(),
    String? password,
  }) async {
    final tempDir = await _storage.getTempDirectory();
    final tempOut = p.join(
      tempDir,
      'stamp-${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    await _overlay.applyTypedSignatureOnPage(
      input: input,
      outputPath: tempOut,
      pageIndex1Based: pageIndex1Based,
      signatureText: signatureText,
      layout: layout,
      password: password,
    );
    final bytes = await File(tempOut).readAsBytes();
    try {
      await File(tempOut).delete();
    } catch (_) {}
    return Uint8List.fromList(bytes);
  }

  Future<Uint8List> applyImageStampToBytes({
    required LocalFileRef input,
    required int pageIndex1Based,
    required Uint8List imageBytes,
    PdfPageStampLayout layout = const PdfPageStampLayout(),
    String? password,
    Set<int>? pages1Based,
    double opacity = 1,
    double rotationDegrees = 0,
  }) async {
    final tempDir = await _storage.getTempDirectory();
    final tempOut = p.join(
      tempDir,
      'stamp-${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    await _overlay.applyImageStampOnPage(
      input: input,
      outputPath: tempOut,
      pageIndex1Based: pageIndex1Based,
      imageBytes: imageBytes,
      layout: layout,
      password: password,
      pages1Based: pages1Based,
      opacity: opacity,
      rotationDegrees: rotationDegrees,
    );
    final bytes = await File(tempOut).readAsBytes();
    try {
      await File(tempOut).delete();
    } catch (_) {}
    return Uint8List.fromList(bytes);
  }

  Future<LocalFileRef> applyImageStampAndPromptSave({
    required LocalFileRef input,
    required int pageIndex1Based,
    required Uint8List imageBytes,
    PdfPageStampLayout layout = const PdfPageStampLayout(),
    String? password,
    JobHandle<LocalFileRef>? handle,
    void Function(JobProgress)? onProgress,
  }) {
    return _exportWithSaveDialog(
      input: input,
      handle: handle,
      onProgress: onProgress,
      suggestedName: 'stamped-${input.displayName}',
      work: (tempOut) => _overlay.applyImageStampOnPage(
        input: input,
        outputPath: tempOut,
        pageIndex1Based: pageIndex1Based,
        imageBytes: imageBytes,
        layout: layout,
        password: password,
      ),
    );
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
          'stamp-${DateTime.now().microsecondsSinceEpoch}.pdf',
        );
        reportUi(const JobProgress(fraction: 0.35, message: 'Applying stamp'));
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
