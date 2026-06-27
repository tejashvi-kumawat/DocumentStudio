import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/print/print_exception.dart';
import 'package:document_studio/features/print/print_service.dart';
import 'package:flutter/material.dart';

/// Shared print handlers for screens that prefer a mixin over [PdfPrintButton].
mixin PrintActions {
  Future<void> printLocalPdf(
    BuildContext context,
    LocalFileRef file,
    PrintService printService,
  ) async {
    try {
      await printService.printPdf(file);
    } on PrintException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed: $e')),
      );
    }
  }

  Future<void> printLocalRasterImage(
    BuildContext context,
    LocalFileRef file,
    PrintService printService,
  ) async {
    try {
      await printService.printRasterImage(file);
    } on PrintException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed: $e')),
      );
    }
  }
}
