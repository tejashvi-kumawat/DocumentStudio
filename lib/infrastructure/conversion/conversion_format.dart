import 'package:document_studio/infrastructure/conversion/images_to_pdf_service.dart';
import 'package:document_studio/infrastructure/conversion/pdf_to_images_service.dart';

/// Route/query options for format-specific image → PDF entry points ([DS-CNV-FMT-*]).
class ImagesToPdfRouteOptions {
  const ImagesToPdfRouteOptions({
    required this.title,
    required this.subtitle,
    required this.pickExtensions,
    this.scanHandoff = false,
  });

  final String title;
  final String subtitle;
  final List<String> pickExtensions;

  /// When true, UI copy reflects a scan → PDF handoff.
  final bool scanHandoff;

  static ImagesToPdfRouteOptions fromQuery(String? format) {
    switch (format?.toLowerCase()) {
      case 'jpeg':
      case 'jpg':
        return const ImagesToPdfRouteOptions(
          title: 'JPG to PDF',
          subtitle: 'Combine JPEG photos into one PDF',
          pickExtensions: ['jpg', 'jpeg'],
        );
      case 'png':
        return const ImagesToPdfRouteOptions(
          title: 'PNG to PDF',
          subtitle: 'Combine PNG images into one PDF',
          pickExtensions: ['png'],
        );
      case 'webp':
        return const ImagesToPdfRouteOptions(
          title: 'WEBP to PDF',
          subtitle: 'Combine WebP images into one PDF',
          pickExtensions: ['webp'],
        );
      case 'tiff':
      case 'tif':
        return const ImagesToPdfRouteOptions(
          title: 'TIFF to PDF',
          subtitle: 'Combine TIFF images into one PDF (first frame per file)',
          pickExtensions: ['tiff', 'tif'],
        );
      case 'bmp':
        return const ImagesToPdfRouteOptions(
          title: 'BMP to PDF',
          subtitle: 'Combine bitmap images into one PDF',
          pickExtensions: ['bmp'],
        );
      case 'scan':
        return ImagesToPdfRouteOptions(
          title: 'Scan to PDF',
          subtitle: 'Combine photos of paper pages into one PDF',
          pickExtensions: List.of(ImagesToPdfService.supportedExtensions),
          scanHandoff: true,
        );
      default:
        return ImagesToPdfRouteOptions(
          title: 'Images to PDF',
          subtitle: 'One page per image',
          pickExtensions: List.of(ImagesToPdfService.supportedExtensions),
        );
    }
  }
}

/// Route/query options for PDF → image format entry points ([DS-CNV-FMT-013]).
class PdfToImagesRouteOptions {
  const PdfToImagesRouteOptions({
    required this.title,
    required this.subtitle,
    required this.initialFormat,
  });

  final String title;
  final String subtitle;
  final PdfToImageFormat initialFormat;

  static PdfToImagesRouteOptions fromQuery(String? format) {
    switch (format?.toLowerCase()) {
      case 'jpeg':
      case 'jpg':
        return const PdfToImagesRouteOptions(
          title: 'PDF to JPG',
          subtitle: 'Export pages as JPEG',
          initialFormat: PdfToImageFormat.jpeg,
        );
      case 'png':
        return const PdfToImagesRouteOptions(
          title: 'PDF to PNG',
          subtitle: 'Export pages as PNG',
          initialFormat: PdfToImageFormat.png,
        );
      case 'webp':
        return const PdfToImagesRouteOptions(
          title: 'PDF to WEBP',
          subtitle: 'Export pages as WebP',
          initialFormat: PdfToImageFormat.webp,
        );
      case 'tiff':
      case 'tif':
        return const PdfToImagesRouteOptions(
          title: 'PDF to TIFF',
          subtitle: 'Export pages as TIFF',
          initialFormat: PdfToImageFormat.tiff,
        );
      default:
        return const PdfToImagesRouteOptions(
          title: 'PDF to images',
          subtitle: 'Local page rendering',
          initialFormat: PdfToImageFormat.png,
        );
    }
  }
}
