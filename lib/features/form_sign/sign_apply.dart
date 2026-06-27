import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/design_system/adaptive/ds_adaptive.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/pdf_stamp/pdf_page_stamp_models.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/form_sign/sign_placement_bridge.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/features/pdf_viewer/widgets/page_placement_canvas.dart';
import 'package:document_studio/infrastructure/pdf/signing/pdf_cos.dart';
import 'package:document_studio/infrastructure/pdf/signing/pdf_visual_stamp_writer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// Result of [applyPlacedSignItems] for the panel's status line.
enum SignApplyOutcome { applied, cancelled, nothing, failed }

/// Writes every placed signature / stamp into the open document exactly
/// where it is shown (same box, same rotation), then reloads the viewer.
///
/// Uses the pure-Dart incremental writer (all platforms). Encrypted files
/// fall back to the qpdf stamp service (desktop).
Future<SignApplyOutcome> applyPlacedSignItems({
  required BuildContext context,
  required WidgetRef ref,
  required SignPlacementController controller,
  void Function(String message)? onMessage,
}) async {
  final items = controller.items;
  if (items.isEmpty) return SignApplyOutcome.nothing;
  final tabs = ref.read(documentTabsControllerProvider);
  final session = tabs.activeSession;
  if (session == null) return SignApplyOutcome.failed;

  final signed = controller.statuses.where((s) => s.intact).length;
  if (signed > 0) {
    final ok = await showDsAdaptiveConfirm(
      context,
      title: 'Document is digitally signed',
      message: signed == 1
          ? 'Adding signatures or stamps now changes the document after it '
              'was signed. The existing signature stays verifiable, but '
              'viewers will report changes made after signing.'
          : 'Adding signatures or stamps now changes the document after it '
              'was signed. The $signed existing signatures stay verifiable, '
              'but viewers will report changes made after signing.',
      confirmLabel: 'Add anyway',
    );
    if (!ok) return SignApplyOutcome.cancelled;
  }
  if (!context.mounted) return SignApplyOutcome.cancelled;

  final burn = [
    for (final i in items)
      PdfBurnItem(
        page1Based: i.page1Based,
        png: i.png,
        left: i.rectNorm.left,
        top: i.rectNorm.top,
        width: i.rectNorm.width,
        height: i.rectNorm.height,
        rotationDegrees: i.rotationDegrees,
      ),
  ];
  try {
    final input = await File(session.file.path).readAsBytes();
    Uint8List out;
    try {
      out = await burnImagesIntoPdf(input, burn);
    } on PdfEncryptedException {
      out = await _burnWithQpdf(ref, session.file, session.password, items);
    }
    if (!context.mounted) return SignApplyOutcome.failed;
    final pages = {for (final i in items) i.page1Based}.toList()..sort();
    final what = items.length == 1 ? items.first.source.label : '${items.length} items';
    await commitBytesToSession(
      context: context,
      storage: ref.read(fileStorageProvider),
      tabs: tabs,
      session: session,
      bytes: out,
      successMessage: pages.length == 1
          ? 'Added $what to page ${pages.first}.'
          : 'Added $what to pages ${pages.join(', ')}.',
    );
    controller.clearItems();
    return SignApplyOutcome.applied;
  } on DocumentStudioError catch (e) {
    onMessage?.call(e.recoveryHint ?? e.message);
  } catch (e) {
    onMessage?.call('Could not add to the PDF: $e');
  }
  return SignApplyOutcome.failed;
}

Future<Uint8List> _burnWithQpdf(
  WidgetRef ref,
  LocalFileRef file,
  String? password,
  List<SignPlacedItem> items,
) async {
  final svc = ref.read(pdfPageStampServiceProvider);
  final ctl = ref.read(signPlacementControllerProvider);
  var input = file;
  Uint8List? bytes;
  final temps = <File>[];
  try {
    for (final i in items) {
      final size = ctl.pageSizePt(i.page1Based) ?? const Size(612, 792);
      final rect = PagePlacementNorm(
        left: i.rectNorm.left,
        top: i.rectNorm.top,
        width: i.rectNorm.width,
        height: i.rectNorm.height,
      ).toPdfStampRect(pageWidthPt: size.width, pageHeightPt: size.height);
      bytes = await svc.applyImageStampToBytes(
        input: input,
        pageIndex1Based: i.page1Based,
        imageBytes: i.png,
        layout: PdfPageStampLayout(absoluteRect: rect),
        password: password,
        rotationDegrees: -i.rotationDegrees,
      );
      final tmp = File(p.join(
        Directory.systemTemp.path,
        'ds-sign-${DateTime.now().microsecondsSinceEpoch}.pdf',
      ));
      await tmp.writeAsBytes(bytes, flush: true);
      temps.add(tmp);
      input = LocalFileRef(path: tmp.path, displayName: file.displayName);
    }
    return bytes!;
  } finally {
    for (final t in temps) {
      try {
        await t.delete();
      } catch (_) {}
    }
  }
}
