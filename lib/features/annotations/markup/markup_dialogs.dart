import 'package:document_studio/core/isolate/run_isolated.dart';

import 'dart:math' as math;

import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/domain/pdf_markup/markup_objects.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:url_launcher/url_launcher.dart';

/// Link editor: web address / e-mail, or a page in this document.
Future<LinkMarkup?> showMarkupLinkDialog(
  BuildContext context, {
  required LinkMarkup link,
  required int pageCount,
  required bool isNew,
}) {
  return showDialog<LinkMarkup>(
    context: context,
    builder: (context) =>
        _LinkDialog(link: link, pageCount: pageCount, isNew: isNew),
  );
}

class _LinkDialog extends StatefulWidget {
  const _LinkDialog({
    required this.link,
    required this.pageCount,
    required this.isNew,
  });

  final LinkMarkup link;
  final int pageCount;
  final bool isNew;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late bool _toPage = widget.link.destPage != null && !widget.link.isUri;
  late final TextEditingController _text = TextEditingController(
    text: widget.link.text,
  );
  late final TextEditingController _url = TextEditingController(
    text: widget.link.uri ?? '',
  );
  late final TextEditingController _page = TextEditingController(
    text:
        '${widget.link.destPage ?? math.min(widget.pageCount, widget.link.page + 1)}',
  );
  late bool _border = widget.link.showBorder;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    _url.dispose();
    _page.dispose();
    super.dispose();
  }

  void _submit() {
    final linkText = _text.text.trim();
    if (widget.isNew && linkText.isEmpty) {
      setState(() => _error = 'Enter the link text');
      return;
    }
    if (_toPage) {
      final n = int.tryParse(_page.text.trim());
      if (n == null || n < 1 || n > widget.pageCount) {
        setState(() => _error = 'Enter a page from 1 to ${widget.pageCount}');
        return;
      }
      Navigator.pop(
        context,
        widget.link.copyWith(
          text: linkText,
          uri: () => null,
          destPage: () => n,
          showBorder: _border,
        ),
      );
      return;
    }
    final u = _url.text.trim();
    if (u.isEmpty) {
      setState(() => _error = 'Enter a URL');
      return;
    }
    if (u.contains(' ')) {
      setState(() => _error = 'Enter a web address or e-mail');
      return;
    }
    Navigator.pop(
      context,
      widget.link.copyWith(
        text: linkText,
        uri: () => u,
        destPage: () => null,
        showBorder: _border,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isNew ? 'Add link' : 'Edit link'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _text,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Link text',
                hintText: 'Words shown on the page',
                errorText: _error == 'Enter the link text' ? _error : null,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.public),
                  label: Text('Web URL'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.description_outlined),
                  label: Text('Page'),
                ),
              ],
              selected: {_toPage},
              onSelectionChanged: (v) => setState(() {
                _toPage = v.first;
                _error = null;
              }),
            ),
            const SizedBox(height: 16),
            if (_toPage)
              TextField(
                controller: _page,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Go to page (1–${widget.pageCount})',
                  errorText: _error != null && _error != 'Enter the link text'
                      ? _error
                      : null,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              )
            else
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'URL',
                  hintText: 'example.com or name@example.com',
                  errorText: _error != null && _error != 'Enter the link text'
                      ? _error
                      : null,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _border,
              onChanged: (v) => setState(() => _border = v ?? false),
              title: const Text('Show a visible border'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.isNew ? 'Add link' : 'Save'),
        ),
      ],
    );
  }
}

/// Opens a link annotation's web address.
Future<void> openMarkupLinkUri(BuildContext context, LinkMarkup link) async {
  final uri = link.normalizedUri;
  if (uri == null) return;
  final parsed = Uri.tryParse(uri);
  var ok = false;
  if (parsed != null) {
    try {
      ok = await launchUrl(parsed, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
  }
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Could not open $uri')));
  }
}

/// Grows a too-small frame so [link]'s text is readable on the page.
LinkMarkup fitMarkupLinkFrame(LinkMarkup link) {
  final label = link.text.trim();
  if (label.isEmpty) return link;
  final tp = TextPainter(
    text: TextSpan(
      text: label,
      style: const TextStyle(
        fontSize: LinkMarkup.textFontSize,
        height: 1.15,
        decoration: TextDecoration.underline,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 4,
  )..layout(maxWidth: math.max(link.linkFrame.width, 200));
  const padX = 2.0;
  const padY = 1.0;
  final w = math.max(link.linkFrame.width, tp.width + padX * 2);
  final h = math.max(link.linkFrame.height, tp.height + padY * 2);
  if (w == link.linkFrame.width && h == link.linkFrame.height) return link;
  return link.copyWith(
    linkFrame: Rect.fromLTWH(link.linkFrame.left, link.linkFrame.top, w, h),
  );
}

/// Picks an image, downscaling very large ones so the PDF stays small.
/// Returns encoded bytes + aspect ratio (width / height).
Future<(Uint8List, double)?> pickMarkupImage(
  BuildContext context,
  FileStoragePort storage,
) async {
  final picked = await storage.pickOpenFile(
    allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'],
  );
  if (picked == null) return null;
  final raw = await storage.readBytes(picked);
  final result = await runIsolated(_prepareImage, raw);
  if (result == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That file is not a supported image')),
      );
    }
    return null;
  }
  return result;
}

(Uint8List, double)? _prepareImage(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) return null;
  final aspect = decoded.width / math.max(1, decoded.height);
  const maxSide = 2400;
  final isJpeg = raw.length > 3 && raw[0] == 0xFF && raw[1] == 0xD8;
  final isPng = raw.length > 8 && raw[0] == 0x89 && raw[1] == 0x50;
  if (math.max(decoded.width, decoded.height) <= maxSide && (isJpeg || isPng)) {
    return (raw, aspect);
  }
  var image = decoded;
  if (math.max(image.width, image.height) > maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxSide)
        : img.copyResize(image, height: maxSide);
  }
  final hasAlpha = image.hasAlpha;
  final out = hasAlpha
      ? img.encodePng(image, level: 6)
      : img.encodeJpg(image, quality: 88);
  return (Uint8List.fromList(out), aspect);
}

/// Crop editor for an image object. [crop] and the result are normalized
/// (0..1) rectangles of the source image; null means cancelled.
Future<Rect?> showMarkupCropDialog(
  BuildContext context, {
  required Uint8List bytes,
  required Size imageSize,
  required Rect crop,
}) {
  return showDialog<Rect>(
    context: context,
    builder: (context) =>
        _CropDialog(bytes: bytes, imageSize: imageSize, initial: crop),
  );
}

enum _CropAspect {
  free('Free', null),
  original('Original', -1),
  square('1:1', 1),
  fourThree('4:3', 4 / 3),
  threeFour('3:4', 3 / 4),
  sixteenNine('16:9', 16 / 9);

  const _CropAspect(this.label, this.ratio);
  final String label;

  /// Width / height in pixels; -1 = the image's own ratio.
  final double? ratio;
}

class _CropDialog extends StatefulWidget {
  const _CropDialog({
    required this.bytes,
    required this.imageSize,
    required this.initial,
  });

  final Uint8List bytes;
  final Size imageSize;
  final Rect initial;

  @override
  State<_CropDialog> createState() => _CropDialogState();
}

class _CropDialogState extends State<_CropDialog> {
  late Rect _crop = widget.initial;
  _CropAspect _aspect = _CropAspect.free;
  int? _handle; // 0..7 like the page handles, 8 = move
  Rect _dragStartCrop = Rect.zero;
  Offset _dragStart = Offset.zero;

  static const double _minSide = 0.04;

  double? get _ratioNorm {
    final r = _aspect.ratio;
    if (r == null) return null;
    final px = r < 0 ? widget.imageSize.width / widget.imageSize.height : r;
    // Normalized w/h so that pixel ratio == px.
    return px * widget.imageSize.height / widget.imageSize.width;
  }

  void _setAspect(_CropAspect a) {
    setState(() {
      _aspect = a;
      final rn = _ratioNorm;
      if (rn == null) return;
      var w = _crop.width, h = _crop.height;
      if (w / h > rn) {
        w = h * rn;
      } else {
        h = w / rn;
      }
      if (w > 1) {
        w = 1;
        h = w / rn;
      }
      if (h > 1) {
        h = 1;
        w = h * rn;
      }
      _crop = _clampInside(
        Rect.fromCenter(center: _crop.center, width: w, height: h),
      );
    });
  }

  Rect _clampInside(Rect r) {
    var dx = 0.0, dy = 0.0;
    if (r.left < 0) dx = -r.left;
    if (r.right > 1) dx = 1 - r.right;
    if (r.top < 0) dy = -r.top;
    if (r.bottom > 1) dy = 1 - r.bottom;
    return r.shift(Offset(dx, dy));
  }

  void _onPanStart(Offset local, Size box) {
    final r = _toBox(_crop, box);
    final pts = [
      r.topLeft,
      r.topCenter,
      r.topRight,
      r.centerRight,
      r.bottomRight,
      r.bottomCenter,
      r.bottomLeft,
      r.centerLeft,
    ];
    _handle = null;
    for (var i = 0; i < pts.length; i++) {
      if ((pts[i] - local).distance <= 18) {
        _handle = i;
        break;
      }
    }
    if (_handle == null && r.contains(local)) _handle = 8;
    _dragStart = local;
    _dragStartCrop = _crop;
  }

  void _onPanUpdate(Offset local, Size box) {
    final h = _handle;
    if (h == null) return;
    final d = Offset(
      (local.dx - _dragStart.dx) / box.width,
      (local.dy - _dragStart.dy) / box.height,
    );
    final c0 = _dragStartCrop;
    if (h == 8) {
      setState(() => _crop = _clampInside(c0.shift(d)));
      return;
    }
    var l = c0.left, t = c0.top, r = c0.right, b = c0.bottom;
    final left = h == 0 || h == 6 || h == 7;
    final right = h == 2 || h == 3 || h == 4;
    final top = h == 0 || h == 1 || h == 2;
    final bottom = h == 4 || h == 5 || h == 6;
    if (left) l = (l + d.dx).clamp(0.0, r - _minSide);
    if (right) r = (r + d.dx).clamp(l + _minSide, 1.0);
    if (top) t = (t + d.dy).clamp(0.0, b - _minSide);
    if (bottom) b = (b + d.dy).clamp(t + _minSide, 1.0);
    final rn = _ratioNorm;
    if (rn != null) {
      var w = r - l, hh = b - t;
      final byWidth = left || right;
      if (byWidth && !(top || bottom)) {
        hh = w / rn;
      } else if (!byWidth) {
        w = hh * rn;
      } else if (w / hh > rn) {
        w = hh * rn;
      } else {
        hh = w / rn;
      }
      final ax = left ? r : (right ? l : (l + r) / 2);
      final ay = top ? b : (bottom ? t : (t + b) / 2);
      l = left ? ax - w : (right ? ax : ax - w / 2);
      r = l + w;
      t = top ? ay - hh : (bottom ? ay : ay - hh / 2);
      b = t + hh;
      if (l < 0 || t < 0 || r > 1 || b > 1) return;
    }
    setState(() => _crop = Rect.fromLTRB(l, t, r, b));
  }

  static Rect _toBox(Rect n, Size box) => Rect.fromLTRB(
    n.left * box.width,
    n.top * box.height,
    n.right * box.width,
    n.bottom * box.height,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aspect =
        widget.imageSize.width / math.max(1, widget.imageSize.height);
    final pxW = (_crop.width * widget.imageSize.width).round();
    final pxH = (_crop.height * widget.imageSize.height).round();
    return AlertDialog(
      title: const Text('Crop image'),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 380),
              child: Center(
                child: AspectRatio(
                  aspectRatio: aspect,
                  child: LayoutBuilder(
                    builder: (context, cons) {
                      final box = cons.biggest;
                      return GestureDetector(
                        onPanStart: (e) => _onPanStart(e.localPosition, box),
                        onPanUpdate: (e) => _onPanUpdate(e.localPosition, box),
                        onPanEnd: (_) => _handle = null,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(
                              widget.bytes,
                              fit: BoxFit.fill,
                              gaplessPlayback: true,
                            ),
                            CustomPaint(
                              painter: _CropOverlayPainter(
                                _toBox(_crop, box),
                                theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final a in _CropAspect.values)
                  ChoiceChip(
                    label: Text(a.label),
                    selected: _aspect == a,
                    onSelected: (_) => _setAspect(a),
                    visualDensity: VisualDensity.compact,
                  ),
                const SizedBox(width: 8),
                Text(
                  '$pxW × $pxH px',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            _crop = kFullCrop;
            _aspect = _CropAspect.free;
          }),
          child: const Text('Reset'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _crop),
          child: const Text('Crop'),
        ),
      ],
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  _CropOverlayPainter(this.rect, this.accent);

  final Rect rect;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(rect);
    canvas.drawPath(outside, Paint()..color = const Color(0x99000000));
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white;
    canvas.drawRect(rect, line);
    final third = Paint()
      ..strokeWidth = 0.8
      ..color = Colors.white.withValues(alpha: 0.55);
    for (final f in [1 / 3, 2 / 3]) {
      final x = rect.left + rect.width * f;
      final y = rect.top + rect.height * f;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), third);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), third);
    }
    final fill = Paint()..color = Colors.white;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = accent;
    for (final p in [
      rect.topLeft,
      rect.topCenter,
      rect.topRight,
      rect.centerRight,
      rect.bottomRight,
      rect.bottomCenter,
      rect.bottomLeft,
      rect.centerLeft,
    ]) {
      canvas.drawCircle(p, 6, fill);
      canvas.drawCircle(p, 6, ring);
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter old) =>
      old.rect != rect || old.accent != accent;
}
