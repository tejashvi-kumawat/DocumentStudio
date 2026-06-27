import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' show Pdfrx;
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;

/// Document-level metadata from PDFium ([FPDF_GetMetaText]).
Future<({String? title, String? author, String? subject})>
    readPdfrxDocumentMetadata(
  PdfDocument document,
) async {
  try {
    return await document.useNativeDocumentHandle(_readFromNativeHandle);
  } catch (_) {
    return (title: null, author: null, subject: null);
  }
}

({String? title, String? author, String? subject}) _readFromNativeHandle(
  int nativeDocumentHandle,
) {
  final pdfDoc = pdfium_bindings.FPDF_DOCUMENT.fromAddress(nativeDocumentHandle);
  return (
    title: readPdfiumMetaText(pdfDoc, 'Title'),
    author: readPdfiumMetaText(pdfDoc, 'Author'),
    subject: readPdfiumMetaText(pdfDoc, 'Subject'),
  );
}

/// Reads one PDF info-dictionary string tag via PDFium.
String? readPdfiumMetaText(pdfium_bindings.FPDF_DOCUMENT document, String tag) {
  final pdfium = pdfium_bindings.getPdfium(modulePath: Pdfrx.pdfiumModulePath);
  return using((arena) {
    final tagPtr = tag.toNativeUtf8(allocator: arena);
    final length = pdfium.FPDF_GetMetaText(
      document,
      tagPtr.cast(),
      nullptr,
      0,
    );
    if (length <= 2) return null;
    final buffer = arena<Uint8>(length);
    pdfium.FPDF_GetMetaText(
      document,
      tagPtr.cast(),
      buffer.cast(),
      length,
    );
    final value = buffer.cast<Utf16>().toDartString().trim();
    if (value.isEmpty) return null;
    return value;
  });
}
