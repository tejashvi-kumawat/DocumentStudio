import 'dart:typed_data';

import 'package:document_studio/domain/models/local_file_ref.dart';

/// Platform-agnostic file access. UI must use this port, not direct IO.
abstract class FileStoragePort {
  Future<LocalFileRef?> pickOpenFile({
    List<String>? allowedExtensions,
  });

  /// Multi-select open dialog (desktop/mobile file picker).
  Future<List<LocalFileRef>> pickOpenFiles({
    List<String>? allowedExtensions,
    bool allowMultiple = true,
  });

  Future<String?> pickSavePath({
    required String suggestedName,
    required Uint8List bytes,
    List<String>? allowedExtensions,
    String mimeType,
  });

  /// Choose an output folder (desktop). Returns null if cancelled.
  Future<String?> pickOutputDirectory({String? dialogTitle});

  Future<Uint8List> readBytes(LocalFileRef ref);

  Future<void> writeAtomic({
    required String destinationPath,
    required Future<void> Function(String tempPath) writeToTemp,
  });

  Future<String> createTempFile({required String prefix, String? suffix});

  Future<String> getAppSupportDirectory();

  Future<String> getTempDirectory();

  Future<bool> fileExists(LocalFileRef ref);

  Future<void> deleteIfExists(String path);

  Future<LocalFileRef> copyToTemp(LocalFileRef source, {required String prefix});
}
