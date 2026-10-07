export 'package:document_studio_qpdf/document_studio_qpdf.dart'
    show PdfCropRectPt;

/// Margin trim presets for lossless CropBox adjustment (qpdf).
enum PdfCropMarginPreset { none, small, medium }

extension PdfCropMarginPresetX on PdfCropMarginPreset {
  double get marginMm => switch (this) {
    PdfCropMarginPreset.none => 0,
    PdfCropMarginPreset.small => 5,
    PdfCropMarginPreset.medium => 12,
  };

  String get label => switch (this) {
    PdfCropMarginPreset.none => 'None',
    PdfCropMarginPreset.small => 'Small (5 mm)',
    PdfCropMarginPreset.medium => 'Medium (12 mm)',
  };
}

/// Target MediaBox sizes (qpdf named sizes where supported).
enum PdfPaperSize { letter, a4, legal }

extension PdfPaperSizeX on PdfPaperSize {
  String get qpdfName => name;

  /// Media box width/height in PDF points (72 pt = 1 in).
  (double, double) get mediaBoxPt => switch (this) {
    PdfPaperSize.letter => (612.0, 792.0),
    PdfPaperSize.a4 => (595.28, 841.89),
    PdfPaperSize.legal => (612.0, 1008.0),
  };

  String get label => switch (this) {
    PdfPaperSize.letter => 'US Letter (8.5 × 11 in)',
    PdfPaperSize.a4 => 'A4',
    PdfPaperSize.legal => 'US Legal (8.5 × 14 in)',
  };
}
