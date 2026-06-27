import 'dart:io';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';

/// Maximum on-disk PDF size before open/validate ([DS-EDGE-004] partial).
const kPdfMaxOpenFileBytes = 512 * 1024 * 1024;

/// Rejects oversize files before native parse to reduce decompression-bomb risk.
DocumentStudioError? pdfOpenLimitErrorForFile(
  LocalFileRef file, {
  int maxBytes = kPdfMaxOpenFileBytes,
}) {
  final int length;
  try {
    length = File(file.path).lengthSync();
  } on FileSystemException {
    // Content URIs and vanished files are reported by the engine instead.
    return null;
  }
  if (length <= maxBytes) return null;
  final mb = (length / (1024 * 1024)).toStringAsFixed(0);
  final capMb = (maxBytes / (1024 * 1024)).toStringAsFixed(0);
  return DocumentStudioError(
    code: DocumentStudioErrorCode.outOfMemory,
    message: 'This PDF is too large to open safely ($mb MB; limit $capMb MB).',
    recoveryHint: 'Try compressing or splitting the file on a desktop tool first.',
  );
}
