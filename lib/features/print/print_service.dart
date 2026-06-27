import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/print/print_exception.dart';
import 'package:document_studio/features/print/print_gateway.dart';
import 'package:document_studio/features/print/printable_raster.dart';
import 'package:document_studio/features/print/raster_image_print_pdf.dart';
import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:path/path.dart' as p;

/// Builds a one-page PDF from raster bytes for the print dialog.
typedef RasterPrintPdfBuilder = Future<Uint8List> Function(Uint8List imageBytes);

/// Sends a local PDF to the OS print dialog.
class PrintService {
  PrintService({
    required FileStoragePort storage,
    PrintGateway gateway = const PrintingGateway(),
    RasterPrintPdfBuilder? rasterPrintPdfBuilder,
    QpdfCliRunner? qpdf,
  })  : _storage = storage,
        _gateway = gateway,
        _rasterPrintPdfBuilder = rasterPrintPdfBuilder,
        _qpdf = qpdf ?? QpdfCliRunner();

  final FileStoragePort _storage;
  final PrintGateway _gateway;
  final RasterPrintPdfBuilder? _rasterPrintPdfBuilder;
  final QpdfCliRunner _qpdf;

  /// Opens the system print UI for [file]. Returns `false` if the user cancels.
  ///
  /// Encrypted PDFs are decrypted to a temporary copy first (the print backend
  /// cannot open them); [password] is required when the file has an open
  /// password.
  ///
  /// Throws if [file] is not a PDF, is missing, or read/print fails.
  Future<bool> printPdf(LocalFileRef file, {String? password}) async {
    if (!file.isPdf) {
      throw PrintException('Only PDF files can be printed.');
    }
    if (!await _storage.fileExists(file)) {
      throw PrintException('File not found.');
    }

    var bytes = await _loadPdfBytes(file);
    if (bytes.isEmpty) {
      throw PrintException('PDF file is empty.');
    }
    if (await _looksEncrypted(bytes)) {
      bytes = await _decryptForPrint(file, bytes, password);
    }

    final printable = bytes;
    return _gateway.layoutPdf(
      name: file.displayName,
      onLayout: (_) async => printable,
    );
  }

  /// Opens the system print UI for a local raster image (DS-PRT-002).
  ///
  /// The image is fitted to the paper chosen in the dialog and rotated to
  /// match its orientation.
  Future<bool> printRasterImage(LocalFileRef file) async {
    if (!file.isPrintableRaster) {
      throw PrintException(
        'Only JPEG, PNG, WebP, TIFF, and BMP images can be printed.',
      );
    }
    if (!await _storage.fileExists(file)) {
      throw PrintException('File not found.');
    }

    final imageBytes = await _storage.readBytes(file);
    if (imageBytes.isEmpty) {
      throw PrintException('Image file is empty.');
    }

    final custom = _rasterPrintPdfBuilder;
    if (custom != null) {
      final pdfBytes = await custom(imageBytes);
      return _gateway.layoutPdf(
        name: file.displayName,
        onLayout: (_) async => pdfBytes,
      );
    }

    final byFormat = <String, Future<Uint8List>>{};
    return _gateway.layoutPdf(
      name: file.displayName,
      onLayout: (format) {
        final w = format.width;
        final h = format.height;
        final key = '${w.toStringAsFixed(1)}x${h.toStringAsFixed(1)}';
        return byFormat[key] ??= buildPrintPdfFromRasterBytes(
          imageBytes,
          pageWidthPt: w.isFinite ? w : null,
          pageHeightPt: h.isFinite ? h : null,
        );
      },
    );
  }

  Future<Uint8List> _loadPdfBytes(LocalFileRef file) => _storage.readBytes(file);

  Future<Uint8List> _decryptForPrint(
    LocalFileRef file,
    Uint8List original,
    String? password,
  ) async {
    final int status;
    try {
      status = await _qpdf.requiresPasswordStatus(file.path);
    } catch (_) {
      return original;
    }
    if (status == 2) return original;
    if (status == 0 && (password == null || password.isEmpty)) {
      throw PrintException(
        'This PDF is password-protected. Decrypt it (Tools → Decrypt) '
        'or open it with its password, then print again.',
      );
    }
    final dir = await Directory.systemTemp.createTemp('ds_print_');
    try {
      final out = p.join(dir.path, 'print.pdf');
      try {
        await _qpdf.decryptPdf(
          inputPath: file.path,
          outputPath: out,
          password: status == 0 ? password! : (password ?? ''),
        );
      } on QpdfCliException catch (e) {
        if (e.stderr.toLowerCase().contains('password')) {
          throw PrintException('Incorrect password for this PDF.');
        }
        throw PrintException('Could not prepare this PDF for printing.');
      }
      return await File(out).readAsBytes();
    } finally {
      dir.delete(recursive: true).ignore();
    }
  }
}

Future<bool> _looksEncrypted(Uint8List bytes) {
  if (bytes.length < 4 * 1024 * 1024) {
    return Future.value(_containsEncryptKey(bytes));
  }
  return Isolate.run(() => _containsEncryptKey(bytes));
}

/// Cheap check for an `/Encrypt` entry (trailer or cross-reference stream
/// dictionaries are never compressed, so the key appears as plain bytes).
bool _containsEncryptKey(Uint8List b) {
  const key = [0x2F, 0x45, 0x6E, 0x63, 0x72, 0x79, 0x70, 0x74]; // /Encrypt
  final end = b.length - key.length;
  outer:
  for (var i = 0; i <= end; i++) {
    if (b[i] != 0x2F) continue;
    for (var k = 1; k < key.length; k++) {
      if (b[i + k] != key[k]) continue outer;
    }
    return true;
  }
  return false;
}
