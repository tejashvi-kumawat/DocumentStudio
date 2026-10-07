import 'dart:typed_data';

import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/infrastructure/image/image_processing_port.dart';

/// Image types the converter can read.
const kImageInputExtensions = [
  'png',
  'jpg',
  'jpeg',
  'webp',
  'bmp',
  'gif',
  'tif',
  'tiff',
  'ico',
  'tga',
  'pnm',
  'pgm',
  'ppm',
  'psd',
  'exr',
];

/// Injected dependencies for [ImageToolsScreen] so the feature avoids new Riverpod providers.
class ImageToolsDeps {
  const ImageToolsDeps({
    required this.fileStorage,
    required this.imageProcessing,
  });

  final FileStoragePort fileStorage;
  final ImageProcessingPort imageProcessing;

  Future<LocalFileRef?> pickOpenImage() {
    return fileStorage.pickOpenFile(allowedExtensions: kImageInputExtensions);
  }

  Future<Uint8List> readBytes(LocalFileRef ref) {
    return fileStorage.readBytes(ref);
  }

  Future<String?> saveImage({
    required String suggestedName,
    required Uint8List bytes,
    required ImageOutputFormat format,
  }) {
    return fileStorage.pickSavePath(
      suggestedName: suggestedName,
      bytes: bytes,
      allowedExtensions: [format.extension],
      mimeType: format.mimeType,
    );
  }
}
