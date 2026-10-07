import 'package:document_studio/app/providers.dart';
import 'package:document_studio/app/shell/shell_navigation_context.dart';
import 'package:document_studio/features/home/home_pdf_open_flow.dart';
import 'package:document_studio/features/home/home_pdf_open_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the page workspace, using the active shell document or a file picker.
Future<void> homeLaunchEditPages(BuildContext context, WidgetRef ref) async {
  final active = ref.read(shellNavigationContextProvider).activeDocument;
  if (active != null) {
    await homeOpenPdfWithMode(
      context,
      ref,
      active.file,
      HomePdfOpenMode.editPages,
      password: active.password,
    );
    return;
  }
  final storage = ref.read(fileStorageProvider);
  final picked = await storage.pickOpenFile(allowedExtensions: ['pdf']);
  if (picked == null || !context.mounted) return;
  await homeOpenPdfWithMode(context, ref, picked, HomePdfOpenMode.editPages);
}
