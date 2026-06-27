import 'package:document_studio/app/keyboard/text_input_guard.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/domain/pdf_stamp/pdf_page_stamp_models.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/pdf_viewer/live_draw_burn.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_placement_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

/// Options for placing an image on the live page (Acrobat Add Image).
///
/// Gestures live on the page: click to drop, drag to move, handles to resize
/// (Shift frees aspect), rotate knob above the box. Enter or the floating
/// Place button writes it into the page; the tool stays active.
class ViewerPlaceImagePanel extends ConsumerStatefulWidget {
  const ViewerPlaceImagePanel({super.key, required this.handoff});

  final PdfViewerDocumentHandoff handoff;

  @override
  ConsumerState<ViewerPlaceImagePanel> createState() =>
      _ViewerPlaceImagePanelState();
}

class _ViewerPlaceImagePanelState extends ConsumerState<ViewerPlaceImagePanel> {
  bool _busy = false;
  String? _imageName;
  Uint8List? _lastBytes;
  double _lastAspect = 1;
  ViewerLiveToolSession? _live;
  int _seenApply = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final live = ref.read(viewerLiveToolSessionProvider);
      _live = live;
      if (live.toolId != ViewerToolId.placeImage) {
        live.activate(
          ViewerToolId.placeImage,
          pageIndex1Based: widget.handoff.currentPage1,
        );
      }
      _seenApply = live.applyRequestId;
      live.addListener(_onLive);
    });
  }

  @override
  void dispose() {
    _live?.removeListener(_onLive);
    super.dispose();
  }

  void _onLive() {
    final live = _live;
    if (!mounted || live == null || live.toolId != ViewerToolId.placeImage) {
      return;
    }
    if (live.applyRequestId != _seenApply) {
      _seenApply = live.applyRequestId;
      unawaited(_apply());
    }
  }

  Future<void> _pickImage() async {
    final storage = ref.read(fileStorageProvider);
    final picked = await storage.pickOpenFile(
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
    );
    if (picked == null) return;
    final bytes = await storage.readBytes(picked);
    if (!mounted) return;
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      _toast('That file is not a supported image');
      return;
    }
    _lastBytes = bytes;
    _lastAspect = decoded.width / math.max(1, decoded.height);
    _placeLast();
    setState(() => _imageName = picked.displayName);
  }

  void _placeLast() {
    final bytes = _lastBytes;
    if (bytes == null) return;
    final live = ref.read(viewerLiveToolSessionProvider);
    placeLiveImage(live, bytes: bytes, aspectWidthOverHeight: _lastAspect);
    live.setAwaitingClickPlacement(true);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isOpen = (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyO;
    if (!isOpen) return KeyEventResult.ignored;
    unawaited(_pickImage());
    return KeyEventResult.handled;
  }

  Future<void> _apply() async {
    final live = ref.read(viewerLiveToolSessionProvider);
    final bytes = live.imageBytes;
    if (_busy) return;
    if (bytes == null) {
      _toast('Choose an image first');
      return;
    }
    final page = live.pageIndex1Based;
    final size = live.pageSizePtFor(page);
    if (size == null) {
      _toast('Page is still loading — try again');
      return;
    }
    final tabs = ref.read(documentTabsControllerProvider);
    final session = tabs.activeSession;
    if (session == null) return;
    final rect = live.placement.toPdfStampRect(
      pageWidthPt: size.width,
      pageHeightPt: size.height,
    );
    final opacity = live.opacity;
    final rotation = live.rotationDegrees;
    setState(() => _busy = true);
    try {
      final outBytes = await ref.read(pdfPageStampServiceProvider).applyImageStampToBytes(
            input: session.file,
            pageIndex1Based: page,
            imageBytes: bytes,
            layout: PdfPageStampLayout(absoluteRect: rect),
            password: session.password,
            opacity: opacity,
            // Screen degrees are clockwise (Flutter); PDF user space is CCW.
            rotationDegrees: -rotation,
          );
      if (!mounted) return;
      await commitBytesToSession(
        context: context,
        storage: ref.read(fileStorageProvider),
        tabs: tabs,
        session: session,
        bytes: outBytes,
        successMessage: 'Image placed on page $page.',
      );
      await Future<void>.delayed(kLiveBurnHandoverDelay);
      if (identical(live.imageBytes, bytes)) {
        live.setImageBytes(null);
        live.setAwaitingClickPlacement(true);
      }
    } on DocumentStudioError catch (e) {
      _toast(e.recoveryHint ?? e.message);
    } catch (e) {
      _toast('Could not place image: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final live = ref.read(viewerLiveToolSessionProvider);
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: Focus(
        autofocus: true,
        onKeyEvent: TextInputGuard.guardFocusHandler(_onKey),
        child: ListenableBuilder(
          listenable: live,
          builder: (context, _) {
            final hasImage = live.imageBytes != null;
            return ListView(
              padding: const EdgeInsets.all(DsSpacing.md),
              children: [
                Text(
                  'Choose an image — it follows the cursor; click on any page to '
                  'drop it. Drag to '
                  'move, handles to resize (Shift frees aspect), knob to rotate '
                  '(Shift snaps). Enter places it, Delete removes it.',
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
                ),
                const SizedBox(height: DsSpacing.md),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: Text(
                    key: ValueKey('$hasImage$_imageName'),
                    hasImage ? (_imageName ?? 'Image ready') : 'No image',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
                  ),
                ),
                const SizedBox(height: DsSpacing.sm),
                OutlinedButton.icon(
                  key: const Key('viewer_place_image_choose'),
                  onPressed: _busy ? null : _pickImage,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: Text(hasImage ? 'Replace image' : 'Choose image…'),
                ),
                if (!hasImage && _lastBytes != null) ...[
                  const SizedBox(height: DsSpacing.xs),
                  TextButton.icon(
                    onPressed: _busy ? null : _placeLast,
                    icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                    label: const Text('Place same image again'),
                  ),
                ],
                const SizedBox(height: DsSpacing.md),
                Text(
                  'Opacity ${(live.opacity * 100).round()}%',
                  style: theme.textTheme.labelLarge,
                ),
                Slider(
                  key: const Key('viewer_place_image_opacity'),
                  value: live.opacity.clamp(0.05, 1.0),
                  min: 0.05,
                  max: 1.0,
                  onChanged: _busy ? null : live.setOpacity,
                ),
                const SizedBox(height: DsSpacing.xs),
                OutlinedButton.icon(
                  key: const Key('viewer_place_image_rotate90'),
                  onPressed: _busy || !hasImage
                      ? null
                      : () => live.rotatePlacementBy90Clockwise(),
                  icon: const Icon(Icons.rotate_90_degrees_cw, size: 18),
                  label: const Text('Rotate 90°'),
                ),
                const SizedBox(height: DsSpacing.md),
                DsPrimaryButton(
                  key: const Key('viewer_place_image_apply'),
                  onPressed: _busy || !hasImage ? null : _apply,
                  label: _busy ? 'Placing…' : 'Place on page ${live.pageIndex1Based}',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
