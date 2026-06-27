import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

/// Abstraction over [Printing] for tests and alternate backends.
abstract class PrintGateway {
  Future<bool> layoutPdf({
    required Future<Uint8List> Function(PdfPageFormat format) onLayout,
    required String name,
  });
}

/// Default gateway that opens the platform print UI via the `printing` package.
class PrintingGateway implements PrintGateway {
  const PrintingGateway();

  @override
  Future<bool> layoutPdf({
    required Future<Uint8List> Function(PdfPageFormat format) onLayout,
    required String name,
  }) {
    return Printing.layoutPdf(onLayout: onLayout, name: name);
  }
}
