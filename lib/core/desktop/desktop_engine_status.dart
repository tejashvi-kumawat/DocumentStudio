import 'dart:io';

import 'package:document_studio/core/desktop/desktop_engine_resolver.dart';
import 'package:flutter/foundation.dart';

/// Which bundled CLI engines are present beside the running app.
class DesktopEngineStatus {
  const DesktopEngineStatus({
    required this.qpdfReady,
    required this.tesseractReady,
    required this.libreOfficeReady,
  });

  final bool qpdfReady;
  final bool tesseractReady;
  final bool libreOfficeReady;

  /// Shipped inside a complete desktop installer (qpdf + OCR).
  bool get corePdfToolsReady => qpdfReady && tesseractReady;

  bool get allRecommendedReady =>
      corePdfToolsReady && (!needsLibreOffice || libreOfficeReady);

  /// Office conversion with layout needs LibreOffice on desktop; optional otherwise.
  static bool get needsLibreOffice =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  static Future<DesktopEngineStatus> probe({
    DesktopEngineResolver? resolver,
  }) async {
    final r = resolver ?? DesktopEngineResolver();
    final qpdf = await r.resolveQpdf();
    final tess = await r.resolveTesseract();
    final tessdata = r.resolveTessdataPrefix();
    final soffice = await r.resolveSoffice();
    return DesktopEngineStatus(
      qpdfReady: qpdf != null,
      tesseractReady: tess != null && tessdata != null,
      libreOfficeReady: soffice != null,
    );
  }
}
