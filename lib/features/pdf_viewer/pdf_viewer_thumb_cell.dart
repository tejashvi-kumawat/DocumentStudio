import 'dart:async';
import 'dart:ui' as ui;

import 'package:document_studio/features/page_management/page_thumb_render_gate.dart';
import 'package:document_studio/features/pdf_viewer/pdf_approach_decoder.dart';
import 'package:document_studio/features/pdf_viewer/pdf_approach_pages.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// One thumbnail. Shows this page's pixels, or its page number.
///
/// The bitmap is the cell size. A recycled cell never keeps another page's
/// image. At most [kPdfThumbMaxDecodes] run at once, and they wait while the
/// main view is decoding the page under the scroll.
class PdfViewerThumbCell extends StatefulWidget {
  const PdfViewerThumbCell({
    super.key,
    required this.document,
    required this.pageNumber,
    required this.gate,
    this.approach,
  });

  final PdfDocument document;
  final int pageNumber;
  final PageThumbRenderGate gate;
  final PdfApproachDecoder? approach;

  @override
  State<PdfViewerThumbCell> createState() => _PdfViewerThumbCellState();
}

class _PdfViewerThumbCellState extends State<PdfViewerThumbCell> {
  ui.Image? _image;
  int _generation = 0;
  Size? _decodedSize;
  PageThumbPermit? _permit;
  PdfPageRenderCancellationToken? _token;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    widget.approach?.addListener(_onApproach);
  }

  @override
  void didUpdateWidget(covariant PdfViewerThumbCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.approach, widget.approach)) {
      oldWidget.approach?.removeListener(_onApproach);
      widget.approach?.addListener(_onApproach);
    }
    if (oldWidget.pageNumber != widget.pageNumber ||
        !identical(oldWidget.document, widget.document)) {
      _dropImage();
      _decodedSize = null;
      _cancelLoad();
    }
  }

  @override
  void dispose() {
    widget.approach?.removeListener(_onApproach);
    _cancelLoad();
    _dropImage();
    super.dispose();
  }

  void _onApproach() {
    if (!mounted) return;
    if (widget.approach?.blocksThumbnails == true) {
      if (_image == null) _cancelLoad();
      return;
    }
    if (_image == null) _decodedSize = null;
  }

  void _dropImage() {
    _image?.dispose();
    _image = null;
  }

  void _cancelLoad() {
    _generation++;
    _token?.cancel();
    _token = null;
    final permit = _permit;
    _permit = null;
    if (permit != null) {
      if (permit.isHolding) {
        permit.release();
      } else {
        permit.cancel();
      }
    }
    _running = false;
  }

  void _kick(Size pixel) {
    if (_running) return;
    if (widget.approach?.blocksThumbnails == true) return;
    if (!pixel.width.isFinite || !pixel.height.isFinite || pixel.isEmpty) {
      return;
    }
    if (_decodedSize == pixel) return;
    unawaited(_load(pixel));
  }

  Future<void> _load(Size pixel) async {
    final pageNumber = widget.pageNumber;
    final document = widget.document;
    if (pageNumber < 1 || pageNumber > document.pages.length) return;
    final page = document.pages[pageNumber - 1];
    if (page.pageNumber != pageNumber) return;
    final generation = ++_generation;
    _running = true;
    final permit = widget.gate.acquire(priority: 1);
    _permit = permit;
    try {
      await permit.ready;
      if (!mounted || generation != _generation || permit.isCancelled) return;
      if (widget.approach?.blocksThumbnails == true) return;
      final token = page.createCancellationToken();
      _token = token;
      final rendered = await page.render(
        fullWidth: pixel.width,
        fullHeight: pixel.height,
        backgroundColor: 0xffffffff,
        flags: PdfPageRenderFlags.limitedImageCache,
        cancellationToken: token,
      );
      if (rendered == null) {
        if (generation == _generation) _decodedSize = pixel;
        return;
      }
      try {
        final image = await rendered.createImage();
        if (!mounted ||
            generation != _generation ||
            token.isCanceled ||
            page.pageNumber != pageNumber) {
          image.dispose();
          return;
        }
        final previous = _image;
        _image = image;
        _decodedSize = pixel;
        previous?.dispose();
        setState(() {});
      } finally {
        rendered.dispose();
      }
    } catch (_) {
      if (generation == _generation) _decodedSize = pixel;
    } finally {
      if (identical(_permit, permit)) {
        if (permit.isHolding) {
          permit.release();
        } else {
          permit.cancel();
        }
        _permit = null;
      }
      if (generation == _generation) {
        _token = null;
        _running = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final pixel = constraints.biggest * (dpr > 0 ? dpr : 1);
        final blocked = widget.approach?.blocksThumbnails == true;
        if (!blocked && _decodedSize != pixel && !_running) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _kick(pixel);
          });
        }
        return _pixels();
      },
    );
  }

  Widget _pixels() {
    final image = _image;
    if (image == null) {
      return _ThumbNumber(pageNumber: widget.pageNumber);
    }
    return RawImage(
      image: image,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.low,
    );
  }
}

class _ThumbNumber extends StatelessWidget {
  const _ThumbNumber({required this.pageNumber});

  final int pageNumber;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFE8EEF4),
      child: Center(
        child: Text(
          '$pageNumber',
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
