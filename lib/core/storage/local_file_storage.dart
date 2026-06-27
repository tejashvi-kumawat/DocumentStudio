import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/core/storage/linux_document_portal.dart';
import 'package:document_studio/core/storage/storage_paths.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Maps OS errno from [FileSystemException] to app error codes (DS-EDGE-001 / DS-EDGE-005).
DocumentStudioErrorCode documentStudioErrorCodeFromFileSystemException(
  FileSystemException e,
) {
  final code = e.osError?.errorCode;
  if (code == 13) {
    return DocumentStudioErrorCode.permissionDenied;
  }
  if (code == 11 || code == 16 || code == 26) {
    return DocumentStudioErrorCode.fileLocked;
  }
  return documentStudioErrorCodeForOsError(code);
}

class LocalFileStorage implements FileStoragePort {
  @override
  Future<LocalFileRef?> pickOpenFile({List<String>? allowedExtensions}) async {
    final file = await FilePicker.pickFile(
      type: allowedExtensions == null ? FileType.any : FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    if (file == null) {
      return null;
    }
    final path = file.path;
    if (path == null) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.fileNotAccessible,
        message: 'Could not resolve file path',
      );
    }
    return _refFromPath(path, name: file.name);
  }

  @override
  Future<List<LocalFileRef>> pickOpenFiles({
    List<String>? allowedExtensions,
    bool allowMultiple = true,
  }) async {
    if (!allowMultiple) {
      final single = await pickOpenFile(allowedExtensions: allowedExtensions);
      return single == null ? const [] : [single];
    }
    final files = await FilePicker.pickFiles(
      type: allowedExtensions == null ? FileType.any : FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    if (files.isEmpty) {
      return const [];
    }
    final refs = <LocalFileRef>[];
    for (final file in files) {
      final path = file.path;
      if (path == null) {
        throw const DocumentStudioError(
          code: DocumentStudioErrorCode.fileNotAccessible,
          message: 'Could not resolve file path',
        );
      }
      refs.add(await _refFromPath(path, name: file.name));
    }
    return refs;
  }

  @override
  Future<String?> pickSavePath({
    required String suggestedName,
    required Uint8List bytes,
    List<String>? allowedExtensions,
    String mimeType = 'application/octet-stream',
  }) async {
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save as',
      fileName: suggestedName,
      bytes: bytes,
      mimeType: mimeType,
      type: allowedExtensions == null ? FileType.any : FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    if (uri == null) return null;
    return uri.toFilePath();
  }

  @override
  Future<String?> pickOutputDirectory({String? dialogTitle}) async {
    return FilePicker.getDirectoryPath(
      dialogTitle: dialogTitle ?? 'Choose output folder',
    );
  }

  @override
  Future<Uint8List> readBytes(LocalFileRef ref) async {
    final file = File(ref.path);
    if (!await file.exists()) {
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.fileNotFound,
        message: ref.displayName,
      );
    }
    try {
      return await file.readAsBytes();
    } on FileSystemException catch (e) {
      throw DocumentStudioError(
        code: documentStudioErrorCodeFromFileSystemException(e),
        message: e.message,
        cause: e,
        recoveryHint: e.osError?.errorCode == 13
            ? 'Check app storage permissions or choose the file again.'
            : 'Close other apps using this file and try again.',
      );
    }
  }

  @override
  Future<void> writeAtomic({
    required String destinationPath,
    required Future<void> Function(String tempPath) writeToTemp,
  }) async {
    final dir = p.dirname(destinationPath);
    await Directory(dir).create(recursive: true);
    final tempPath = p.join(
      dir,
      '.${p.basename(destinationPath)}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await writeToTemp(tempPath);
      final tempFile = File(tempPath);
      if (!await tempFile.exists()) {
        throw const DocumentStudioError(
          code: DocumentStudioErrorCode.invalidFile,
          message: 'Temporary output was not created',
        );
      }
      await tempFile.rename(destinationPath);
    } catch (e) {
      try {
        await File(tempPath).delete();
      } catch (_) {}
      rethrow;
    }
  }

  @override
  Future<String> createTempFile({
    required String prefix,
    String? suffix,
  }) async {
    final dir = await getTempDirectory();
    final name =
        '$prefix-${DateTime.now().microsecondsSinceEpoch}${suffix ?? ''}';
    final path = p.join(dir, name);
    await File(path).create(recursive: true);
    return path;
  }

  @override
  Future<String> getAppSupportDirectory() async {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  }

  @override
  Future<String> getTempDirectory() async {
    // Prefer the app storage box (…/com.documentstudio…/temp) over OS /tmp,
    // which can hit quota while $HOME still has space.
    try {
      final root = StoragePaths.tempRoot;
      if (!await root.exists()) await root.create(recursive: true);
      return root.path;
    } catch (_) {
      final dir = await getTemporaryDirectory();
      return dir.path;
    }
  }

  @override
  Future<bool> fileExists(LocalFileRef ref) => File(ref.path).exists();

  @override
  Future<void> deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<LocalFileRef> copyToTemp(LocalFileRef source,
      {required String prefix}) async {
    final bytes = await readBytes(source);
    final tempPath = await createTempFile(
      prefix: prefix,
      suffix: p.extension(source.displayName),
    );
    await File(tempPath).writeAsBytes(bytes, flush: true);
    return _refFromPath(tempPath, name: source.displayName);
  }

  Future<LocalFileRef> _refFromPath(String path, {String? name}) async {
    path = await LinuxDocumentPortal.resolve(path);
    final file = File(path);
    final stat = await file.stat();
    return LocalFileRef(
      path: path,
      displayName: name ?? p.basename(path),
      lastModified: stat.modified,
      sizeBytes: stat.size,
    );
  }
}
