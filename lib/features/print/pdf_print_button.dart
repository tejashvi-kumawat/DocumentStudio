import 'package:document_studio/app/providers.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/print/print_exception.dart';
import 'package:document_studio/features/print/print_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final printServiceProvider = Provider<PrintService>((ref) {
  return PrintService(storage: ref.watch(fileStorageProvider));
});

/// App bar action: system print dialog for a [LocalFileRef] PDF.
///
/// Viewer agent: add to `AppBar.actions`, e.g.
/// `PdfPrintButton(file: widget.file)`.
class PdfPrintButton extends ConsumerWidget {
  const PdfPrintButton({super.key, required this.file, this.printService});

  final LocalFileRef file;
  final PrintService? printService;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PrintService service = printService ?? ref.read(printServiceProvider);
    return IconButton(
      tooltip: 'Print',
      icon: const Icon(Icons.print),
      onPressed: file.isPdf ? () => _print(context, service) : null,
    );
  }

  Future<void> _print(BuildContext context, PrintService service) async {
    try {
      await service.printPdf(file);
    } on PrintException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Print failed: $e')));
    }
  }
}
