/// Last explicit fit/zoom intent for status-bar chrome (not engine matrix state).
enum PdfViewerFitDisplay { custom, fitWidth, fitPage, fitHeight }

extension PdfViewerFitDisplayLabel on PdfViewerFitDisplay {
  String get statusLabel => switch (this) {
    PdfViewerFitDisplay.custom => 'Custom',
    PdfViewerFitDisplay.fitWidth => 'Fit width',
    PdfViewerFitDisplay.fitPage => 'Fit page',
    PdfViewerFitDisplay.fitHeight => 'Fit height',
  };
}
