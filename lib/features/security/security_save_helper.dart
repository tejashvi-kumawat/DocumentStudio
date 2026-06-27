import 'dart:io';

import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:path/path.dart' as p;

/// Reads [source], prompts save-as, writes atomically.
///
/// Returns the saved [LocalFileRef], or `null` if the user cancelled.
Future<LocalFileRef?> promptSavePdfFromTemp({
  required FileStoragePort storage,
  required LocalFileRef source,
  required String suggestedBaseName,
}) async {
  final bytes = await storage.readBytes(source);
  final save = await storage.pickSavePath(
    suggestedName: suggestedBaseName.endsWith('.pdf')
        ? suggestedBaseName
        : '$suggestedBaseName.pdf',
    bytes: bytes,
    allowedExtensions: ['pdf'],
    mimeType: 'application/pdf',
  );
  if (save == null) return null;
  await storage.writeAtomic(
    destinationPath: save,
    writeToTemp: (t) async {
      await File(t).writeAsBytes(bytes, flush: true);
    },
  );
  final stat = await File(save).stat();
  return LocalFileRef(
    path: save,
    displayName: p.basename(save),
    sizeBytes: stat.size,
    lastModified: stat.modified,
  );
}
