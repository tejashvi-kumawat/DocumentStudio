import 'dart:io';

import 'package:document_studio/core/jobs/job_models.dart';
import 'package:document_studio/core/jobs/job_runner.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/infrastructure/pdf/pdf_structure_port.dart';
import 'package:path/path.dart' as p;

class PageOrganizeService {
  PageOrganizeService({
    required PdfStructurePort structure,
    required FileStoragePort storage,
    required JobRunner jobs,
  })  : _structure = structure,
        _storage = storage,
        _jobs = jobs;

  final PdfStructurePort _structure;
  final FileStoragePort _storage;
  final JobRunner _jobs;

  Future<LocalFileRef> mergeWithSaveDialog({
    required List<LocalFileRef> inputs,
    required String suggestedName,
    void Function(JobProgress)? onProgress,
  }) async {
    final handle = JobHandle<LocalFileRef>();
    return _jobs.run(
      handle: handle,
      work: (report, _) async {
        report(const JobProgress(fraction: 0.1, message: 'Preparing merge'));
        final tempDir = await _storage.getTempDirectory();
        final outPath = p.join(tempDir, suggestedName);
        report(const JobProgress(fraction: 0.4, message: 'Merging pages'));
        final merged = await _structure.merge(
          inputs: inputs,
          outputPath: outPath,
        );
        report(const JobProgress(fraction: 0.8, message: 'Save as'));
        final bytes = await _storage.readBytes(merged);
        final savePath = await _storage.pickSavePath(
          suggestedName: suggestedName,
          bytes: bytes,
          allowedExtensions: ['pdf'],
          mimeType: 'application/pdf',
        );
        if (savePath == null) {
          throw StateError('Save cancelled');
        }
        await _storage.writeAtomic(
          destinationPath: savePath,
          writeToTemp: (temp) async {
            await _storage.readBytes(merged); // ensure readable
            await _writeBytes(temp, bytes);
          },
        );
        return LocalFileRef(
          path: savePath,
          displayName: p.basename(savePath),
        );
      },
    );
  }

  Future<LocalFileRef> saveReordered({
    required LocalFileRef input,
    required List<int> newOrder1Based,
    required String suggestedName,
  }) async {
    final tempDir = await _storage.getTempDirectory();
    final outPath = p.join(tempDir, suggestedName);
    final result = await _structure.reorderPages(
      input: input,
      newOrder1Based: newOrder1Based,
      outputPath: outPath,
    );
    final bytes = await _storage.readBytes(result);
    final savePath = await _storage.pickSavePath(
      suggestedName: suggestedName,
      bytes: bytes,
      allowedExtensions: ['pdf'],
      mimeType: 'application/pdf',
    );
    if (savePath == null) throw StateError('Save cancelled');
    await _storage.writeAtomic(
      destinationPath: savePath,
      writeToTemp: (temp) => _writeBytes(temp, bytes),
    );
    return LocalFileRef(path: savePath, displayName: p.basename(savePath));
  }

  Future<void> _writeBytes(String path, List<int> bytes) async {
    await File(path).writeAsBytes(bytes, flush: true);
  }
}