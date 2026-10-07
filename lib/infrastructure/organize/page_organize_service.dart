import 'dart:io';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/jobs/job_models.dart';
import 'package:document_studio/core/jobs/job_runner.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/organize/organize_page_ref.dart';
import 'package:document_studio/domain/organize/page_box_export_password.dart';
import 'package:document_studio/infrastructure/pdf/dart_pdf_page_box.dart';
import 'package:document_studio/infrastructure/pdf/page_source.dart';
import 'package:document_studio/infrastructure/pdf/pdf_page_box_options.dart';
import 'package:document_studio/infrastructure/pdf/pdf_structure_port.dart';
import 'package:document_studio/infrastructure/pdf/pdfrx_error_mapping.dart';
import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

class PageOrganizeService {
  PageOrganizeService({
    required this._structure,
    required this._storage,
    required this._jobs,
  });

  final PdfStructurePort _structure;
  final FileStoragePort _storage;
  final JobRunner _jobs;

  /// Assembles [pages] to a temp PDF without prompting save (post-export actions).
  ///
  /// When [unlockMismatchedPasswords] is set and the page list spans more
  /// than one file, each file that does not share a single password with the
  /// others is unlocked to a temp first. Assemble then does not stamp one
  /// password onto every file.
  Future<({String tempPath, List<int> bytes})> assembleWorkspaceExport({
    required List<OrganizePageRef> pages,
    Map<String, String>? passwordsByPath,
    bool unlockMismatchedPasswords = false,
    void Function(JobProgress)? onProgress,
    JobHandle<({String tempPath, List<int> bytes})>? handle,
  }) async {
    if (pages.isEmpty) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.invalidPdf,
        message: 'No pages to export',
      );
    }
    final jobHandle =
        handle ?? JobHandle<({String tempPath, List<int> bytes})>();
    return _jobs.run(
      handle: jobHandle,
      work: (report, cancelToken) async {
        onProgress?.call(
          const JobProgress(fraction: 0.1, message: 'Assembling pages'),
        );
        report(const JobProgress(fraction: 0.1, message: 'Assembling pages'));
        final prepared = unlockMismatchedPasswords
            ? await _unlockMismatchedPasswords(pages, passwordsByPath)
            : (pages: pages, passwords: passwordsByPath);
        final tempOut = await _assemblePagesToTempPath(
          pages: prepared.pages,
          passwordsByPath: prepared.passwords,
          cancelToken: cancelToken,
        );
        final bytes = await File(tempOut).readAsBytes();
        report(const JobProgress(fraction: 0.85, message: 'Export ready'));
        onProgress?.call(
          const JobProgress(fraction: 0.85, message: 'Export ready'),
        );
        return (tempPath: tempOut, bytes: bytes);
      },
    );
  }

  Future<LocalFileRef> exportWorkspace({
    required List<OrganizePageRef> pages,
    required String suggestedName,
    Map<String, String>? passwordsByPath,
    void Function(JobProgress)? onProgress,
    JobHandle<LocalFileRef>? handle,
  }) async {
    final jobHandle = handle ?? JobHandle<LocalFileRef>();
    return _jobs.run(
      handle: jobHandle,
      work: (report, cancelToken) async {
        onProgress?.call(
          const JobProgress(fraction: 0.1, message: 'Assembling pages'),
        );
        report(const JobProgress(fraction: 0.1, message: 'Assembling pages'));
        final tempOut = await _assemblePagesToTempPath(
          pages: pages,
          passwordsByPath: passwordsByPath,
          cancelToken: cancelToken,
        );
        final bytes = await File(tempOut).readAsBytes();
        report(
          const JobProgress(fraction: 0.65, message: 'Choose save location'),
        );
        onProgress?.call(
          const JobProgress(fraction: 0.65, message: 'Choose save location'),
        );
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
        report(const JobProgress(fraction: 1, message: 'Saved'));
        onProgress?.call(const JobProgress(fraction: 1, message: 'Saved'));
        final stat = await File(savePath).stat();
        return LocalFileRef(
          path: savePath,
          displayName: p.basename(savePath),
          sizeBytes: stat.size,
          lastModified: stat.modified,
        );
      },
    );
  }

  Future<String> _assemblePagesToTempPath({
    required List<OrganizePageRef> pages,
    Map<String, String>? passwordsByPath,
    required JobCancelToken cancelToken,
  }) async {
    final tempDir = await _storage.getTempDirectory();
    final tempOut = p.join(
      tempDir,
      'organize-${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    final sources = [
      for (final page in pages)
        PageSource(
          page.file,
          page.pageNumber1Based,
          rotationDegrees: page.rotationDegrees,
        ),
    ];
    String? password;
    for (final page in pages) {
      final pw = passwordsByPath?[page.file.path];
      if (pw != null && pw.isNotEmpty) {
        password = pw;
        break;
      }
    }
    if (cancelToken.isCancelled) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.processCancelled,
        message: 'Cancelled',
      );
    }
    await _structure.assemblePageSources(
      sources: sources,
      outputPath: tempOut,
      password: password,
    );
    return tempOut;
  }

  /// Unlocks files whose passwords are not shared by every path in [pages].
  ///
  /// qpdf `--pages` applies one `--password` to every file. A foreign PDF
  /// with a different password (or none) is written to an unlocked temp so
  /// the open document can still be assembled.
  Future<({List<OrganizePageRef> pages, Map<String, String>? passwords})>
  _unlockMismatchedPasswords(
    List<OrganizePageRef> pages,
    Map<String, String>? passwordsByPath,
  ) async {
    final paths = {for (final page in pages) page.file.path};
    final passwords = passwordsByPath ?? const <String, String>{};
    if (paths.length < 2 || _everyPathSharesOnePassword(paths, passwords)) {
      return (pages: pages, passwords: passwordsByPath);
    }
    final replacements = <String, LocalFileRef>{};
    for (final path in paths) {
      final password = passwords[path];
      if (password == null || password.isEmpty) continue;
      final displayName = pages
          .firstWhere((page) => page.file.path == path)
          .file
          .displayName;
      replacements[path] = await _unlockPdfToTemp(
        path,
        password,
        displayName: displayName,
      );
    }
    if (replacements.isEmpty) {
      return (pages: pages, passwords: passwordsByPath);
    }
    final next = [
      for (final page in pages)
        replacements[page.file.path] == null
            ? page
            : page.copyWith(file: replacements[page.file.path]!),
    ];
    final remaining = Map<String, String>.from(passwords)
      ..removeWhere((path, _) => replacements.containsKey(path));
    return (pages: next, passwords: remaining.isEmpty ? null : remaining);
  }

  bool _everyPathSharesOnePassword(
    Set<String> paths,
    Map<String, String> passwords,
  ) {
    String? shared;
    for (final path in paths) {
      final password = passwords[path];
      if (password == null || password.isEmpty) return false;
      shared ??= password;
      if (password != shared) return false;
    }
    return shared != null;
  }

  Future<LocalFileRef> _unlockPdfToTemp(
    String path,
    String password, {
    required String displayName,
  }) async {
    try {
      final doc = await PdfDocument.openFile(
        path,
        passwordProvider: () async => password,
      );
      try {
        final bytes = await doc.encodePdf(removeSecurity: true);
        final temp = await _storage.createTempFile(
          prefix: 'unlock-src',
          suffix: '.pdf',
        );
        await File(temp).writeAsBytes(bytes, flush: true);
        return LocalFileRef(path: temp, displayName: displayName);
      } finally {
        await doc.dispose();
      }
    } catch (e) {
      throw documentStudioErrorFromPdfrxOpen(e, password: password);
    }
  }

  Future<LocalFileRef> mergeAndPromptSave({
    required List<LocalFileRef> inputs,
    required String suggestedName,
    Map<String, String>? passwordsByPath,
    void Function(JobProgress)? onProgress,
    JobHandle<LocalFileRef>? handle,
  }) async {
    final jobHandle = handle ?? JobHandle<LocalFileRef>();
    return _jobs.run(
      handle: jobHandle,
      work: (report, cancelToken) async {
        report(const JobProgress(fraction: 0.2, message: 'Merging'));
        onProgress?.call(const JobProgress(fraction: 0.2, message: 'Merging'));
        if (cancelToken.isCancelled) {
          throw const DocumentStudioError(
            code: DocumentStudioErrorCode.processCancelled,
            message: 'Cancelled',
          );
        }
        final tempDir = await _storage.getTempDirectory();
        final tempOut = p.join(
          tempDir,
          'merge-${DateTime.now().microsecondsSinceEpoch}.pdf',
        );
        final mergePassword = _firstPassword(passwordsByPath, inputs);
        await _structure.merge(
          inputs: inputs,
          outputPath: tempOut,
          password: mergePassword,
          passwordsByPath: passwordsByPath,
        );
        if (cancelToken.isCancelled) {
          throw const DocumentStudioError(
            code: DocumentStudioErrorCode.processCancelled,
            message: 'Cancelled',
          );
        }
        final bytes = await File(tempOut).readAsBytes();
        report(
          const JobProgress(fraction: 0.7, message: 'Choose save location'),
        );
        onProgress?.call(
          const JobProgress(fraction: 0.7, message: 'Choose save location'),
        );
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
        report(const JobProgress(fraction: 1, message: 'Saved'));
        onProgress?.call(const JobProgress(fraction: 1, message: 'Saved'));
        final stat = await File(savePath).stat();
        return LocalFileRef(
          path: savePath,
          displayName: p.basename(savePath),
          sizeBytes: stat.size,
          lastModified: stat.modified,
        );
      },
    );
  }

  /// Merges [inputs] into a temporary PDF and returns its bytes.
  ///
  /// Does not prompt for a path and does not replace any input file.
  Future<List<int>> mergeToBytes({
    required List<LocalFileRef> inputs,
    Map<String, String>? passwordsByPath,
  }) async {
    if (inputs.length < 2) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.invalidPdf,
        message: 'Add at least two PDFs to merge',
      );
    }
    final tempDir = await _storage.getTempDirectory();
    final tempOut = p.join(
      tempDir,
      'merge-${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    try {
      await _structure.merge(
        inputs: inputs,
        outputPath: tempOut,
        password: _firstPassword(passwordsByPath, inputs),
        passwordsByPath: passwordsByPath,
      );
      return await File(tempOut).readAsBytes();
    } finally {
      try {
        await File(tempOut).delete();
      } catch (_) {}
    }
  }

  /// Splits [input] into temporary PDFs. Does not write the user's files.
  Future<List<LocalFileRef>> splitByRangesToTemp({
    required LocalFileRef input,
    required List<List<int>> rangesPages1Based,
    required String namePrefix,
    String? password,
    Map<String, String>? passwordsByPath,
  }) async {
    if (rangesPages1Based.isEmpty) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.invalidPdf,
        message: 'Nothing to split',
      );
    }
    password ??= pageBoxPasswordForExportPath(
      passwordsByPath: passwordsByPath,
      filePath: input.path,
    );
    final tempDir = await _storage.getTempDirectory();
    final outDir = p.join(
      tempDir,
      'split-${DateTime.now().microsecondsSinceEpoch}',
    );
    await Directory(outDir).create(recursive: true);
    return _structure.splitByRanges(
      input: input,
      rangesPages1Based: rangesPages1Based,
      outputDirectory: outDir,
      namePrefix: namePrefix,
      password: password,
    );
  }

  String? _firstPassword(Map<String, String>? map, List<LocalFileRef> files) {
    if (map == null) return null;
    for (final f in files) {
      final pw = map[f.path];
      if (pw != null && pw.isNotEmpty) return pw;
    }
    return null;
  }

  Future<LocalFileRef> reorderAndPromptSave({
    required LocalFileRef input,
    required List<int> newOrder1Based,
    required String suggestedName,
  }) async {
    final tempDir = await _storage.getTempDirectory();
    final tempOut = p.join(
      tempDir,
      'reorder-${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    await _structure.reorderPages(
      input: input,
      newOrder1Based: newOrder1Based,
      outputPath: tempOut,
    );
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
    return LocalFileRef(path: savePath, displayName: p.basename(savePath));
  }

  Future<List<LocalFileRef>> splitEveryNAndPromptSave({
    required LocalFileRef input,
    required int pagesPerFile,
    required String namePrefix,
    String? password,
    Map<String, String>? passwordsByPath,
    void Function(JobProgress)? onProgress,
  }) async {
    password ??= pageBoxPasswordForExportPath(
      passwordsByPath: passwordsByPath,
      filePath: input.path,
    );
    final handle = JobHandle<List<LocalFileRef>>();
    return _jobs.run(
      handle: handle,
      work: (report, cancelToken) async {
        report(
          JobProgress(
            fraction: 0.15,
            message: 'Splitting every $pagesPerFile pages',
          ),
        );
        onProgress?.call(JobProgress(fraction: 0.15, message: 'Splitting'));
        final tempDir = await _storage.getTempDirectory();
        final parts = await _structure.splitEveryNPages(
          input: input,
          pagesPerFile: pagesPerFile,
          outputDirectory: tempDir,
          namePrefix: namePrefix,
          password: password,
        );
        if (cancelToken.isCancelled) {
          throw const DocumentStudioError(
            code: DocumentStudioErrorCode.processCancelled,
            message: 'Cancelled',
          );
        }
        final saved = <LocalFileRef>[];
        for (var i = 0; i < parts.length; i++) {
          final part = parts[i];
          final bytes = await File(part.path).readAsBytes();
          report(
            JobProgress(
              fraction: 0.2 + 0.7 * (i + 1) / parts.length,
              message: 'Save part ${i + 1} of ${parts.length}',
            ),
          );
          final savePath = await _storage.pickSavePath(
            suggestedName: '$namePrefix-part${i + 1}.pdf',
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
          saved.add(
            LocalFileRef(path: savePath, displayName: p.basename(savePath)),
          );
        }
        return saved;
      },
    );
  }

  Future<List<LocalFileRef>> splitByRangesAndPromptSave({
    required LocalFileRef input,
    required List<List<int>> rangesPages1Based,
    required String namePrefix,
    String? password,
    Map<String, String>? passwordsByPath,
    void Function(JobProgress)? onProgress,
    JobHandle<List<LocalFileRef>>? handle,
  }) async {
    password ??= pageBoxPasswordForExportPath(
      passwordsByPath: passwordsByPath,
      filePath: input.path,
    );
    final jobHandle = handle ?? JobHandle<List<LocalFileRef>>();
    return _jobs.run(
      handle: jobHandle,
      work: (report, cancelToken) async {
        report(
          JobProgress(
            fraction: 0.15,
            message: 'Splitting into ${rangesPages1Based.length} parts',
          ),
        );
        onProgress?.call(JobProgress(fraction: 0.15, message: 'Splitting'));
        final tempDir = await _storage.getTempDirectory();
        final parts = await _structure.splitByRanges(
          input: input,
          rangesPages1Based: rangesPages1Based,
          outputDirectory: tempDir,
          namePrefix: namePrefix,
          password: password,
        );
        if (cancelToken.isCancelled) {
          throw const DocumentStudioError(
            code: DocumentStudioErrorCode.processCancelled,
            message: 'Cancelled',
          );
        }
        final saved = <LocalFileRef>[];
        for (var i = 0; i < parts.length; i++) {
          final part = parts[i];
          final bytes = await File(part.path).readAsBytes();
          report(
            JobProgress(
              fraction: 0.2 + 0.7 * (i + 1) / parts.length,
              message: 'Save part ${i + 1} of ${parts.length}',
            ),
          );
          onProgress?.call(
            JobProgress(
              fraction: 0.2 + 0.7 * (i + 1) / parts.length,
              message: 'Save part ${i + 1} of ${parts.length}',
            ),
          );
          final savePath = await _storage.pickSavePath(
            suggestedName: '$namePrefix-part${i + 1}.pdf',
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
          saved.add(
            LocalFileRef(path: savePath, displayName: p.basename(savePath)),
          );
        }
        return saved;
      },
    );
  }

  /// Writes all parts into one folder (single directory picker).
  Future<List<LocalFileRef>> splitByRangesToDirectory({
    required LocalFileRef input,
    required List<List<int>> rangesPages1Based,
    required String namePrefix,
    String? password,
    void Function(JobProgress)? onProgress,
    JobHandle<List<LocalFileRef>>? handle,
  }) async {
    final jobHandle = handle ?? JobHandle<List<LocalFileRef>>();
    return _jobs.run(
      handle: jobHandle,
      work: (report, cancelToken) async {
        final outDir = await _storage.pickOutputDirectory(
          dialogTitle: 'Save split PDFs to folder',
        );
        if (outDir == null) {
          throw const DocumentStudioError(
            code: DocumentStudioErrorCode.processCancelled,
            message: 'Folder selection cancelled',
          );
        }
        report(const JobProgress(fraction: 0.1, message: 'Splitting'));
        onProgress?.call(
          const JobProgress(fraction: 0.1, message: 'Splitting'),
        );
        final tempDir = await _storage.getTempDirectory();
        final parts = await _structure.splitByRanges(
          input: input,
          rangesPages1Based: rangesPages1Based,
          outputDirectory: tempDir,
          namePrefix: namePrefix,
          password: password,
        );
        if (cancelToken.isCancelled) {
          throw const DocumentStudioError(
            code: DocumentStudioErrorCode.processCancelled,
            message: 'Cancelled',
          );
        }
        final saved = <LocalFileRef>[];
        for (var i = 0; i < parts.length; i++) {
          final dest = p.join(outDir, '$namePrefix-part${i + 1}.pdf');
          final bytes = await File(parts[i].path).readAsBytes();
          await _storage.writeAtomic(
            destinationPath: dest,
            writeToTemp: (temp) async {
              await File(temp).writeAsBytes(bytes, flush: true);
            },
          );
          saved.add(LocalFileRef(path: dest, displayName: p.basename(dest)));
          report(
            JobProgress(
              fraction: 0.2 + 0.75 * (i + 1) / parts.length,
              message: 'Wrote part ${i + 1} of ${parts.length}',
            ),
          );
          onProgress?.call(
            JobProgress(
              fraction: 0.2 + 0.75 * (i + 1) / parts.length,
              message: 'Wrote part ${i + 1} of ${parts.length}',
            ),
          );
        }
        return saved;
      },
    );
  }

  Future<LocalFileRef> cropPagesAndPromptSave({
    required LocalFileRef input,
    required Set<int> pageNumbers1Based,
    required PdfCropMarginPreset margin,
    required String suggestedName,
    Map<String, String>? passwordsByPath,
    void Function(JobProgress)? onProgress,
    JobHandle<LocalFileRef>? handle,
  }) async {
    final jobHandle = handle ?? JobHandle<LocalFileRef>();
    return _jobs.run(
      handle: jobHandle,
      work: (report, cancelToken) async {
        report(const JobProgress(fraction: 0.1, message: 'Cropping'));
        onProgress?.call(const JobProgress(fraction: 0.1, message: 'Cropping'));
        if (cancelToken.isCancelled) {
          throw const DocumentStudioError(
            code: DocumentStudioErrorCode.processCancelled,
            message: 'Cancelled',
          );
        }
        final tempOut = await _storage.createTempFile(
          prefix: 'crop',
          suffix: '.pdf',
        );
        final password = pageBoxExportPassword(
          passwordsByPath: passwordsByPath,
          input: input,
        );
        await _structure.cropPages(
          input: input,
          pageNumbers1Based: pageNumbers1Based,
          margin: margin,
          outputPath: tempOut,
          password: password,
        );
        if (cancelToken.isCancelled) {
          throw const DocumentStudioError(
            code: DocumentStudioErrorCode.processCancelled,
            message: 'Cancelled',
          );
        }
        report(
          const JobProgress(fraction: 0.65, message: 'Choose save location'),
        );
        onProgress?.call(
          const JobProgress(fraction: 0.65, message: 'Choose save location'),
        );
        final outRef = LocalFileRef(
          path: tempOut,
          displayName: 'crop-temp.pdf',
        );
        final bytes = await _storage.readBytes(outRef);
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
        report(const JobProgress(fraction: 1, message: 'Saved'));
        onProgress?.call(const JobProgress(fraction: 1, message: 'Saved'));
        final stat = await File(savePath).stat();
        return LocalFileRef(
          path: savePath,
          displayName: p.basename(savePath),
          sizeBytes: stat.size,
          lastModified: stat.modified,
        );
      },
    );
  }

  Future<LocalFileRef> setPageSizeAndPromptSave({
    required LocalFileRef input,
    required Set<int> pageNumbers1Based,
    required PdfPaperSize paperSize,
    required String suggestedName,
    Map<String, String>? passwordsByPath,
    void Function(JobProgress)? onProgress,
    JobHandle<LocalFileRef>? handle,
  }) async {
    final jobHandle = handle ?? JobHandle<LocalFileRef>();
    return _jobs.run(
      handle: jobHandle,
      work: (report, cancelToken) async {
        report(const JobProgress(fraction: 0.1, message: 'Resizing'));
        onProgress?.call(const JobProgress(fraction: 0.1, message: 'Resizing'));
        if (cancelToken.isCancelled) {
          throw const DocumentStudioError(
            code: DocumentStudioErrorCode.processCancelled,
            message: 'Cancelled',
          );
        }
        final tempOut = await _storage.createTempFile(
          prefix: 'resize',
          suffix: '.pdf',
        );
        final password = pageBoxExportPassword(
          passwordsByPath: passwordsByPath,
          input: input,
        );
        await _structure.setPageSize(
          input: input,
          pageNumbers1Based: pageNumbers1Based,
          paperSize: paperSize,
          outputPath: tempOut,
          password: password,
        );
        if (cancelToken.isCancelled) {
          throw const DocumentStudioError(
            code: DocumentStudioErrorCode.processCancelled,
            message: 'Cancelled',
          );
        }
        report(
          const JobProgress(fraction: 0.65, message: 'Choose save location'),
        );
        onProgress?.call(
          const JobProgress(fraction: 0.65, message: 'Choose save location'),
        );
        final outRef = LocalFileRef(
          path: tempOut,
          displayName: 'resize-temp.pdf',
        );
        final bytes = await _storage.readBytes(outRef);
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
        report(const JobProgress(fraction: 1, message: 'Saved'));
        onProgress?.call(const JobProgress(fraction: 1, message: 'Saved'));
        final stat = await File(savePath).stat();
        return LocalFileRef(
          path: savePath,
          displayName: p.basename(savePath),
          sizeBytes: stat.size,
          lastModified: stat.modified,
        );
      },
    );
  }

  Future<LocalFileRef> cropPagesToBoxTemp({
    required LocalFileRef input,
    required Set<int> pageNumbers1Based,
    required PdfCropRectPt box,
    Map<String, String>? passwordsByPath,
  }) async {
    final tempOut = await _storage.createTempFile(
      prefix: 'crop-box',
      suffix: '.pdf',
    );
    final password = pageBoxPasswordForExportPath(
      passwordsByPath: passwordsByPath,
      filePath: input.path,
    );
    await _structure.cropPagesToBox(
      input: input,
      pageNumbers1Based: pageNumbers1Based,
      box: box,
      outputPath: tempOut,
      password: password,
    );
    return LocalFileRef(path: tempOut, displayName: p.basename(tempOut));
  }

  /// Crops [pageNumbers1Based] to [fraction] of each page's own visible box.
  ///
  /// One shared rectangle uses qpdf when the CLI can edit page boxes. When
  /// the pages differ, each page gets its own CropBox. Content outside the
  /// crop stays in the file.
  Future<LocalFileRef> cropVisibleFractionToTemp({
    required LocalFileRef input,
    required Set<int> pageNumbers1Based,
    required PdfVisibleFraction fraction,
    Map<String, String>? passwordsByPath,
  }) async {
    final password = pageBoxPasswordForExportPath(
      passwordsByPath: passwordsByPath,
      filePath: input.path,
    );
    final shared = await DartPdfPageBox.sharedBoxForVisibleFraction(
      input: input,
      pageNumbers1Based: pageNumbers1Based,
      fraction: fraction,
      password: password,
    );
    if (shared != null && await isQpdfCliPageBoxEditAvailable()) {
      return cropPagesToBoxTemp(
        input: input,
        pageNumbers1Based: pageNumbers1Based,
        box: shared,
        passwordsByPath: passwordsByPath,
      );
    }
    final tempOut = await _storage.createTempFile(
      prefix: 'crop-box',
      suffix: '.pdf',
    );
    return DartPdfPageBox.cropVisibleFraction(
      input: input,
      pageNumbers1Based: pageNumbers1Based,
      fraction: fraction,
      outputPath: tempOut,
      password: password,
    );
  }

  Future<LocalFileRef> cropPagesToBoxAndPromptSave({
    required LocalFileRef input,
    required Set<int> pageNumbers1Based,
    required PdfCropRectPt box,
    required String suggestedName,
    Map<String, String>? passwordsByPath,
    void Function(JobProgress)? onProgress,
    JobHandle<LocalFileRef>? handle,
  }) async {
    final temp = await cropPagesToBoxTemp(
      input: input,
      pageNumbers1Based: pageNumbers1Based,
      box: box,
      passwordsByPath: passwordsByPath,
    );
    final bytes = await File(temp.path).readAsBytes();
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
      writeToTemp: (path) async {
        await File(path).writeAsBytes(bytes, flush: true);
      },
    );
    try {
      await File(temp.path).delete();
    } catch (_) {}
    onProgress?.call(const JobProgress(fraction: 1, message: 'Saved'));
    final stat = await File(savePath).stat();
    return LocalFileRef(
      path: savePath,
      displayName: p.basename(savePath),
      sizeBytes: stat.size,
      lastModified: stat.modified,
    );
  }

  Future<LocalFileRef> setPageSizeToTemp({
    required LocalFileRef input,
    required Set<int> pageNumbers1Based,
    required PdfPaperSize paperSize,
    Map<String, String>? passwordsByPath,
  }) async {
    final tempOut = await _storage.createTempFile(
      prefix: 'resize',
      suffix: '.pdf',
    );
    final password = pageBoxPasswordForExportPath(
      passwordsByPath: passwordsByPath,
      filePath: input.path,
    );
    await _structure.setPageSize(
      input: input,
      pageNumbers1Based: pageNumbers1Based,
      paperSize: paperSize,
      outputPath: tempOut,
      password: password,
    );
    return LocalFileRef(path: tempOut, displayName: p.basename(tempOut));
  }
}
