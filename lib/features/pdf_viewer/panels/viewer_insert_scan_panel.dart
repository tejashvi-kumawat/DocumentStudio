import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/desktop/desktop_engine_resolver.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/panels/insert_scan_camera_page.dart';
import 'package:document_studio/features/pdf_viewer/panels/insert_scan_place.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_page_organize_export.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/infrastructure/conversion/images_to_pdf_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Insert a camera shot into the open PDF's session working copy.
///
/// The panel does not take a picture when it opens. Capture happens on the
/// camera screen's Capture button, and the PDF changes only after the
/// placement dialog is confirmed.
class ViewerInsertScanPanel extends ConsumerStatefulWidget {
  const ViewerInsertScanPanel({
    super.key,
    required this.handoff,
    this.pageCount,
  });

  final PdfViewerDocumentHandoff handoff;
  final int? pageCount;

  @override
  ConsumerState<ViewerInsertScanPanel> createState() =>
      _ViewerInsertScanPanelState();
}

class _ViewerInsertScanPanelState extends ConsumerState<ViewerInsertScanPanel> {
  bool _busy = false;
  String? _status;
  String? _ffmpegPath;
  bool _engineChecked = false;

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    if (_isMobile) {
      _engineChecked = true;
    } else {
      unawaited(_probe());
    }
  }

  Future<void> _probe() async {
    final path = await desktopEngineResolver.resolveFfmpeg();
    if (mounted) {
      setState(() {
        _ffmpegPath = path;
        _engineChecked = true;
      });
    }
  }

  Future<void> _openCamera() async {
    if (_busy) return;
    if (!_isMobile && (_ffmpegPath == null || !Platform.isLinux)) return;
    final total = widget.pageCount;
    if (total == null || total < 1) {
      _snack('Page count is not ready yet.');
      return;
    }
    final captureDirectory = await ref
        .read(fileStorageProvider)
        .getTempDirectory();
    if (!mounted) return;
    final shot = await Navigator.of(context, rootNavigator: true).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _isMobile
            ? InsertScanMobileCameraPage(captureDirectory: captureDirectory)
            : InsertScanDesktopCameraPage(
                ffmpegPath: _ffmpegPath!,
                captureDirectory: captureDirectory,
              ),
      ),
    );
    if (shot == null || shot.isEmpty) return;
    if (!mounted) {
      await _discard([shot]);
      return;
    }
    await _confirmAndInsert(
      images: [LocalFileRef(path: shot, displayName: p.basename(shot))],
      discardPaths: [shot],
      enhance: true,
    );
  }

  Future<void> _chooseFiles() async {
    if (_busy) return;
    final total = widget.pageCount;
    if (total == null || total < 1) {
      _snack('Page count is not ready yet.');
      return;
    }
    final picked = await ref
        .read(fileStorageProvider)
        .pickOpenFiles(
          allowedExtensions: ImagesToPdfService.supportedExtensions,
        );
    if (picked.isEmpty || !mounted) return;
    await _confirmAndInsert(
      images: picked,
      discardPaths: const [],
      enhance: false,
    );
  }

  Future<void> _confirmAndInsert({
    required List<LocalFileRef> images,
    required List<String> discardPaths,
    required bool enhance,
  }) async {
    final total = widget.pageCount;
    if (images.isEmpty || total == null || total < 1) {
      await _discard(discardPaths);
      return;
    }
    setState(() {
      _busy = true;
      _status = enhance ? 'Preparing the shot…' : null;
    });
    try {
      if (enhance) {
        await _enhanceInPlace(images.first.path);
      }
      if (!mounted) {
        await _discard(discardPaths);
        return;
      }
      final choice = await showScanInsertPlaceDialog(
        context: context,
        pageCount: total,
        currentPage1: widget.handoff.currentPage1,
        previewPath: images.first.path,
        imageCount: images.length,
      );
      if (!mounted) {
        await _discard(discardPaths);
        return;
      }
      if (choice == null) {
        await _discard(discardPaths);
        setState(() => _status = null);
        return;
      }
      setState(() => _status = 'Inserting page…');
      await _commit(images, choice, total);
      await _discard(discardPaths);
      if (mounted) setState(() => _status = null);
    } on DocumentStudioError catch (e) {
      await _discard(discardPaths);
      _snack(e.recoveryHint ?? e.message);
    } catch (e) {
      await _discard(discardPaths);
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commit(
    List<LocalFileRef> images,
    ScanInsertChoice choice,
    int total,
  ) async {
    final session = ref.read(documentTabsControllerProvider).activeSession;
    if (session == null) {
      throw StateError('No open document to update.');
    }
    final storage = ref.read(fileStorageProvider);
    final tempDir = await storage.getTempDirectory();
    final scanPdfPath = p.join(
      tempDir,
      'scan-insert-${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    final scanPdf = await ImagesToPdfService().fromImageFiles(
      images: images,
      outputPath: scanPdfPath,
    );
    try {
      final pages = pagesForScanInsert(
        document: session.file,
        totalPages: total,
        currentPage1: widget.handoff.currentPage1,
        insertFile: scanPdf,
        insertPageCount: images.length,
        anchor: choice.anchor,
        afterPageNumber: choice.afterPageNumber,
      );
      if (!mounted) return;
      await commitOrganizePagesInSession(
        ref: ref,
        context: context,
        handoff: widget.handoff,
        pages: pages,
        successMessage: scanInsertSuccessMessage(
          choice: choice,
          currentPage1: widget.handoff.currentPage1,
          pageCount: total,
          insertedCount: images.length,
        ),
      );
    } finally {
      try {
        await File(scanPdfPath).delete();
      } catch (_) {}
    }
  }

  Future<void> _enhanceInPlace(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return;
      final upright = img.bakeOrientation(decoded);
      final gray = img.grayscale(upright);
      final contrasted = img.contrast(gray, contrast: 110);
      final out = Uint8List.fromList(img.encodeJpg(contrasted, quality: 92));
      await File(path).writeAsBytes(out, flush: true);
    } catch (_) {}
  }

  Future<void> _discard(List<String> paths) async {
    for (final path in paths) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_engineChecked) {
      return const Padding(
        padding: EdgeInsets.all(DsSpacing.md),
        child: LinearProgressIndicator(),
      );
    }
    final camReady = _isMobile || (Platform.isLinux && _ffmpegPath != null);
    return ListView(
      padding: const EdgeInsets.all(DsSpacing.md),
      children: [
        Text(
          camReady
              ? 'Frame the page and tap Capture, or choose images. '
                    'Then pick where the pages go. The open copy updates '
                    'only after you insert. Cancel leaves the PDF unchanged.'
              : 'Choose an image, then pick where it goes. '
                    'The open copy updates only after you insert. '
                    'Cancel leaves the PDF unchanged.',
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
        ),
        const SizedBox(height: DsSpacing.md),
        if (camReady)
          DsPrimaryButton(
            label: _busy ? 'Working…' : 'Open camera',
            icon: Icons.photo_camera_outlined,
            onPressed: _busy ? null : () => unawaited(_openCamera()),
          ),
        if (camReady) const SizedBox(height: DsSpacing.sm),
        DsSecondaryButton(
          label: 'Choose images…',
          icon: Icons.image_outlined,
          onPressed: _busy ? null : () => unawaited(_chooseFiles()),
        ),
        if (_status != null) ...[
          const SizedBox(height: DsSpacing.md),
          Text(_status!, style: theme.textTheme.bodySmall),
          if (_busy) const LinearProgressIndicator(),
        ],
      ],
    );
  }
}
