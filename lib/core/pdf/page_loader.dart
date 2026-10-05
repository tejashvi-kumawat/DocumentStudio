import 'dart:async';

import 'package:pdfrx/pdfrx.dart';

/// Opens [path] without measuring every page (cheap for huge files).
Future<PdfDocument> openPdfLazily(String path, {String? password}) =>
    PdfDocument.openFile(
      path,
      passwordProvider: password == null ? null : () async => password,
      useProgressiveLoading: true,
    );

/// Loads just page [n] (1-based) of a document opened with [openPdfLazily].
///
/// Measuring starts at [n] and stops once it is loaded, so reading one page of
/// a 50 000-page file costs one page, not the whole document.
Future<PdfPage?> loadPageOnDemand(PdfDocument doc, int n) async {
  if (n < 1 || n > doc.pages.length) return null;
  final page = doc.pages[n - 1];
  if (page.isLoaded) return page;
  unawaited(
    doc.loadPagesProgressively(
      startPageNumber: n,
      loadUnitDuration: const Duration(milliseconds: 40),
      onPageLoadProgress: (_, _, _) => !doc.pages[n - 1].isLoaded,
    ),
  );
  return page.waitForLoaded(timeout: const Duration(seconds: 30));
}
