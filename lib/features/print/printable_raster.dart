import 'package:document_studio/domain/models/local_file_ref.dart';

/// Raster formats accepted for [PrintService.printRasterImage] (DS-PRT-002).
const printableRasterExtensions = <String>{
  'jpg',
  'jpeg',
  'png',
  'webp',
  'tif',
  'tiff',
  'bmp',
};

bool isPrintableRasterExtension(String extension) =>
    printableRasterExtensions.contains(extension.toLowerCase());

extension PrintableRasterLocalFile on LocalFileRef {
  bool get isPrintableRaster => isPrintableRasterExtension(extension);
}
