import 'package:equatable/equatable.dart';

enum DocumentStudioErrorCode {
  fileNotFound,
  fileNotAccessible,
  permissionDenied,
  invalidFile,
  invalidPdf,
  corruptedPdf,
  passwordRequired,
  wrongPassword,
  unsupportedFormat,
  conversionFailed,
  ocrFailed,
  renderFailed,
  outOfMemory,
  diskFull,
  fileLocked,
  processCancelled,
  nativeEngineError,
  featureUnavailable,
  unknownError,
}

class DocumentStudioError extends Equatable implements Exception {
  const DocumentStudioError({
    required this.code,
    required this.message,
    this.cause,
    this.recoveryHint,
  });

  final DocumentStudioErrorCode code;
  final String message;
  final Object? cause;
  final String? recoveryHint;

  String get codeName => code.name;

  @override
  List<Object?> get props => [code, message, cause, recoveryHint];

  static DocumentStudioError from(Object error, {String? context}) {
    if (error is DocumentStudioError) {
      return error;
    }
    return DocumentStudioError(
      code: DocumentStudioErrorCode.unknownError,
      message: context ?? error.toString(),
      cause: error,
    );
  }
}

/// Maps common OS errno values to [DocumentStudioErrorCode].
DocumentStudioErrorCode documentStudioErrorCodeForOsError(int? errno) {
  switch (errno) {
    case 2: // ENOENT
      return DocumentStudioErrorCode.fileNotFound;
    case 13: // EACCES
      return DocumentStudioErrorCode.permissionDenied;
    case 28: // ENOSPC
    case 122: // EDQUOT (Linux)
    case 69: // EDQUOT (macOS)
    case 112: // ERROR_DISK_FULL (Windows)
      return DocumentStudioErrorCode.diskFull;
    case 11: // EAGAIN / resource busy on some platforms
    case 26: // ETXTBSY
      return DocumentStudioErrorCode.fileLocked;
    default:
      return DocumentStudioErrorCode.fileNotAccessible;
  }
}

extension DocumentStudioErrorCodeX on DocumentStudioErrorCode {
  String get userMessage => switch (this) {
        DocumentStudioErrorCode.fileNotFound =>
          'The file could not be found.',
        DocumentStudioErrorCode.fileNotAccessible =>
          'The file could not be accessed.',
        DocumentStudioErrorCode.permissionDenied =>
          'Permission was denied. Check file or storage access.',
        DocumentStudioErrorCode.invalidFile => 'This file is not valid.',
        DocumentStudioErrorCode.invalidPdf =>
          'This file is not a valid PDF.',
        DocumentStudioErrorCode.corruptedPdf =>
          'This PDF appears to be corrupted.',
        DocumentStudioErrorCode.passwordRequired =>
          'This PDF is password protected.',
        DocumentStudioErrorCode.wrongPassword => 'Incorrect password.',
        DocumentStudioErrorCode.unsupportedFormat =>
          'This format is not supported yet.',
        DocumentStudioErrorCode.conversionFailed => 'Conversion failed.',
        DocumentStudioErrorCode.ocrFailed => 'OCR failed.',
        DocumentStudioErrorCode.renderFailed => 'Could not render the document.',
        DocumentStudioErrorCode.outOfMemory =>
          'Not enough memory for this operation.',
        DocumentStudioErrorCode.diskFull => 'Not enough disk space.',
        DocumentStudioErrorCode.fileLocked =>
          'The file is in use by another application.',
        DocumentStudioErrorCode.processCancelled => 'Operation cancelled.',
        DocumentStudioErrorCode.nativeEngineError =>
          'The document engine reported an error.',
        DocumentStudioErrorCode.featureUnavailable =>
          'This feature is not available yet.',
        DocumentStudioErrorCode.unknownError => 'An unexpected error occurred.',
      };
}
