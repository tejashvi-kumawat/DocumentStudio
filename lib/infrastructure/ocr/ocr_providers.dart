import 'dart:io';

import 'package:document_studio/infrastructure/ocr/android_searchable_pdf_service.dart';
import 'package:document_studio/infrastructure/ocr/android_tesseract_ocr_port.dart';
import 'package:document_studio/infrastructure/ocr/desktop_tesseract_ocr_port.dart';
import 'package:document_studio/infrastructure/ocr/ocr_port.dart';
import 'package:document_studio/infrastructure/ocr/tesseract_searchable_pdf_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// OCR engines register here when Tesseract FFI or CLI fallback is available.
final ocrPortProvider = Provider<OcrPort>((ref) {
  if (kIsWeb) return const BlockedOcrPort();
  if (Platform.isAndroid || Platform.isIOS) {
    return const AndroidTesseractOcrPort();
  }
  return DesktopTesseractOcrPort();
});

final searchablePdfPortProvider = Provider<SearchablePdfPort>((ref) {
  if (kIsWeb) return const BlockedSearchablePdfPort();
  if (Platform.isAndroid || Platform.isIOS) {
    // On-device: Android Tesseract + pure-Dart invisible text layer (no qpdf).
    return AndroidSearchablePdfService();
  }
  // Desktop: Tesseract CLI PDF output + qpdf overlay (Linux/Windows/macOS).
  return TesseractSearchablePdfService();
});

/// True when [port] exposes makeSearchable / probeEngine (desktop or mobile).
bool searchablePdfPortSupportsJobs(SearchablePdfPort port) =>
    port is TesseractSearchablePdfService || port is AndroidSearchablePdfService;
