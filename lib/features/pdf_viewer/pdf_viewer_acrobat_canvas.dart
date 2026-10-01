import 'package:flutter/material.dart';

/// Medium-gray backdrop behind the PDF page (classic desktop reader).
Color pdfViewerAcrobatCanvasColor(
  Brightness brightness, {
  bool presentationMode = false,
}) {
  if (presentationMode) {
    return Colors.black;
  }
  return brightness == Brightness.dark
      ? const Color(0xFF4A4A4A)
      : const Color(0xFF939393);
}
