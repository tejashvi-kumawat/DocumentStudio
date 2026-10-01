import 'package:document_studio/app/keyboard/text_input_guard.dart';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/image_tools/image_tools_route.dart';
import 'package:document_studio/features/image_viewer/image_viewer_route.dart';
import 'package:document_studio/features/print/print_actions.dart';
import 'package:document_studio/features/print/printable_raster.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

const _viewerExtensions = ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'];

/// DS-IMG-001 — local image viewer with pan/zoom (no editing).
class ImageViewerScreen extends StatefulWidget {
  const ImageViewerScreen({super.key, required this.deps, this.initialFile});

  final ImageViewerDeps deps;
  final LocalFileRef? initialFile;

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen>
    with PrintActions, SingleTickerProviderStateMixin {
  static const _minScale = 0.1;
  static const _maxScale = 16.0;

  LocalFileRef? _file;
  Uint8List? _bytes;
  Size? _imageSize;
  bool _busy = false;
  String? _error;
  int _quarterTurns = 0;
  List<String> _siblings = const [];

  final _transform = TransformationController();
  late final AnimationController _zoomAnim;
  Animation<Matrix4>? _zoomTween;
  Size _viewport = Size.zero;
  Offset? _doubleTapAt;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _zoomAnim = AnimationController(vsync: this, duration: DsMotion.dialogDuration)
      ..addListener(() {
        final t = _zoomTween;
        if (t != null) _transform.value = t.value;
      });
    _transform.addListener(_onTransform);
    final initial = widget.initialFile;
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(initial));
    }
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _transform.dispose();
    _zoomAnim.dispose();
    _focus.dispose();
    super.dispose();
  }

  double _lastScale = 1;

  void _onTransform() {
    final s = _transform.value.getMaxScaleOnAxis();
    if ((s - _lastScale).abs() > 0.001) {
      _lastScale = s;
      setState(() {});
    }
  }

  Future<void> _open() async {
    final picked = await widget.deps.fileStorage.pickOpenFile(
      allowedExtensions: _viewerExtensions,
    );
    if (picked == null || !mounted) return;
    await _load(picked);
  }

  Future<void> _load(LocalFileRef file) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await widget.deps.fileStorage.readBytes(file);
      final size = await _probeSize(bytes);
      if (!mounted) return;
      if (size == null) {
        setState(() {
          _busy = false;
          _error = '${file.displayName} could not be displayed. '
              'The file may be damaged or in an unsupported format.';
        });
        return;
      }
      _zoomAnim.stop();
      _transform.value = Matrix4.identity();
      setState(() {
        _file = file;
        _bytes = bytes;
        _imageSize = size;
        _quarterTurns = 0;
        _busy = false;
      });
      _focus.requestFocus();
      _loadSiblings(file);
    } on DocumentStudioError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not open ${file.displayName}: $e';
      });
    }
  }

  /// Reads dimensions from the header without decoding pixels.
  Future<Size?> _probeSize(Uint8List bytes) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final size = Size(
        descriptor.width.toDouble(),
        descriptor.height.toDouble(),
      );
      descriptor.dispose();
      buffer.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadSiblings(LocalFileRef file) async {
    try {
      final dir = Directory(p.dirname(file.path));
      final names = <String>[];
      await for (final e in dir.list(followLinks: false)) {
        if (e is! File) continue;
        final ext = p.extension(e.path).replaceFirst('.', '').toLowerCase();
        if (_viewerExtensions.contains(ext)) names.add(e.path);
      }
      names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (!mounted || _file?.path != file.path) return;
      setState(() => _siblings = names);
    } catch (_) {
      if (mounted) setState(() => _siblings = const []);
    }
  }

  int get _siblingIndex => _file == null ? -1 : _siblings.indexOf(_file!.path);

  void _step(int delta) {
    final i = _siblingIndex;
    if (i < 0 || _busy) return;
    final next = i + delta;
    if (next < 0 || next >= _siblings.length) return;
    final path = _siblings[next];
    _load(LocalFileRef(path: path, displayName: p.basename(path)));
  }

  // ---- zoom ---------------------------------------------------------------

  Size? get _rotatedImageSize {
    final s = _imageSize;
    if (s == null) return null;
    return _quarterTurns.isOdd ? Size(s.height, s.width) : s;
  }

  /// Scale at which the image fits the viewport (BoxFit.contain, no upscale
  /// beyond 1:1 is applied by the layout itself).
  double get _fitScale {
    final s = _rotatedImageSize;
    if (s == null || _viewport.isEmpty) return 1;
    return math.min(_viewport.width / s.width, _viewport.height / s.height);
  }

  double get _actualPercent =>
      _transform.value.getMaxScaleOnAxis() * _fitScale * 100;

  void _animateTo(Matrix4 target) {
    _zoomTween = Matrix4Tween(begin: _transform.value, end: target).animate(
      CurvedAnimation(parent: _zoomAnim, curve: DsMotion.switchCurve),
    );
    _zoomAnim.forward(from: 0);
  }

  Matrix4 _scaledAbout(Offset focal, double factor) {
    final current = _transform.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(_minScale, _maxScale);
    final f = target / current;
    return Matrix4.identity()
      ..translateByDouble(focal.dx, focal.dy, 0, 1)
      ..scaleByDouble(f, f, 1, 1)
      ..translateByDouble(-focal.dx, -focal.dy, 0, 1)
      ..multiply(_transform.value);
  }

  Offset get _center => Offset(_viewport.width / 2, _viewport.height / 2);

  void _zoomBy(double factor) => _animateTo(_scaledAbout(_center, factor));

  void _fit() => _animateTo(Matrix4.identity());

  void _actualSize() {
    final fit = _fitScale;
    if (fit <= 0) return;
    final targetScale = (1 / fit).clamp(_minScale, _maxScale);
    final c = _center;
    _animateTo(
      Matrix4.identity()
        ..translateByDouble(c.dx, c.dy, 0, 1)
        ..scaleByDouble(targetScale, targetScale, 1, 1)
        ..translateByDouble(-c.dx, -c.dy, 0, 1),
    );
  }

  void _onDoubleTap() {
    final at = _doubleTapAt ?? _center;
    if (_transform.value.getMaxScaleOnAxis() > 1.05) {
      _fit();
    } else {
      _animateTo(_scaledAbout(at, math.max(2.5, 1 / _fitScale)));
    }
  }

  void _rotate() {
    setState(() => _quarterTurns = (_quarterTurns + 1) % 4);
    _zoomAnim.stop();
    _transform.value = Matrix4.identity();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_bytes == null) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.equal ||
        k == LogicalKeyboardKey.add ||
        k == LogicalKeyboardKey.numpadAdd) {
      _zoomBy(1.25);
    } else if (k == LogicalKeyboardKey.minus ||
        k == LogicalKeyboardKey.numpadSubtract) {
      _zoomBy(0.8);
    } else if (k == LogicalKeyboardKey.digit0 ||
        k == LogicalKeyboardKey.numpad0) {
      _fit();
    } else if (k == LogicalKeyboardKey.digit1 ||
        k == LogicalKeyboardKey.numpad1) {
      _actualSize();
    } else if (k == LogicalKeyboardKey.keyR) {
      _rotate();
    } else if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.pageDown) {
      _step(1);
    } else if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.pageUp) {
      _step(-1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ---- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = _file;
    final size = _imageSize;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              file?.displayName ?? 'Image viewer',
              overflow: TextOverflow.ellipsis,
            ),
            if (file != null && size != null && _bytes != null)
              Text(
                '${size.width.toInt()} × ${size.height.toInt()} px · '
                '${_formatBytes(_bytes!.length)}'
                '${_siblings.length > 1 && _siblingIndex >= 0 ? ' · ${_siblingIndex + 1} of ${_siblings.length}' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: DsColors.textSecondary(theme.brightness),
                ),
              ),
          ],
        ),
        actions: [
          if (file != null)
            IconButton(
              tooltip: 'Edit in Image tools',
              icon: const Icon(Icons.tune),
              onPressed: _busy
                  ? null
                  : () => context.push(imageToolsRoutePath, extra: file),
            ),
          if (file != null && file.isPrintableRaster)
            IconButton(
              tooltip: 'Print image',
              icon: const Icon(Icons.print_outlined),
              onPressed: _busy
                  ? null
                  : () => printLocalRasterImage(
                        context,
                        file,
                        widget.deps.printService,
                      ),
            ),
          IconButton(
            tooltip: 'Open image',
            icon: const Icon(Icons.folder_open),
            onPressed: _busy ? null : _open,
          ),
        ],
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: TextInputGuard.guardFocusHandler(_onKey),
        child: AnimatedSwitcher(
          duration: DsMotion.switchDuration,
          switchInCurve: DsMotion.switchCurve,
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_busy && _bytes == null) {
      return const Center(
        key: ValueKey('loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_bytes == null) {
      return _buildEmpty(context);
    }
    return Column(
      key: const ValueKey('image'),
      children: [
        if (_error != null) _buildInlineError(context),
        Expanded(child: _buildCanvas(context)),
        _buildToolbar(context),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);
    return Center(
      key: const ValueKey('empty'),
      child: Padding(
        padding: const EdgeInsets.all(DsSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library_outlined, size: 48, color: secondary),
            const SizedBox(height: DsSpacing.md),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: DsSpacing.lg),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            FilledButton.icon(
              onPressed: _open,
              icon: const Icon(Icons.image_outlined),
              label: const Text('Open image'),
            ),
            const SizedBox(height: DsSpacing.sm),
            Text(
              'PNG, JPEG, WebP, BMP, or GIF',
              style: theme.textTheme.bodySmall?.copyWith(color: secondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineError(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: ListTile(
        dense: true,
        leading: Icon(Icons.error_outline, color: scheme.onErrorContainer),
        title: Text(
          _error!,
          style: TextStyle(color: scheme.onErrorContainer),
        ),
        trailing: IconButton(
          tooltip: 'Dismiss',
          icon: Icon(Icons.close, color: scheme.onErrorContainer),
          onPressed: () => setState(() => _error = null),
        ),
      ),
    );
  }

  Widget _buildCanvas(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.brightness == Brightness.dark
          ? const Color(0xFF1C1C1E)
          : const Color(0xFFF2F2F7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          _viewport = constraints.biggest;
          return GestureDetector(
            onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
            onDoubleTap: _onDoubleTap,
            child: InteractiveViewer(
              key: const Key('image_viewer_interactive'),
              transformationController: _transform,
              minScale: _minScale,
              maxScale: _maxScale,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              onInteractionStart: (_) => _zoomAnim.stop(),
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: AnimatedSwitcher(
                  duration: DsMotion.switchDuration,
                  switchInCurve: DsMotion.switchCurve,
                  child: RotatedBox(
                    key: ValueKey('${_file?.path}|$_quarterTurns'),
                    quarterTurns: _quarterTurns,
                    child: Image.memory(
                      _bytes!,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      filterQuality: _transform.value.getMaxScaleOnAxis() *
                                  _fitScale >
                              2
                          ? FilterQuality.none
                          : FilterQuality.medium,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final theme = Theme.of(context);
    final hasSiblings = _siblings.length > 1 && _siblingIndex >= 0;
    final percent = _actualPercent;
    return Material(
      color: theme.colorScheme.surface,
      elevation: 0,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: DsSpacing.sm,
            vertical: DsSpacing.xs,
          ),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: DsSpacing.xs,
            children: [
              if (hasSiblings)
                IconButton(
                  tooltip: 'Previous image (←)',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _siblingIndex > 0 && !_busy ? () => _step(-1) : null,
                ),
              IconButton(
                tooltip: 'Zoom out (−)',
                icon: const Icon(Icons.zoom_out),
                onPressed: () => _zoomBy(0.8),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  '${percent.round()}%',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Zoom in (+)',
                icon: const Icon(Icons.zoom_in),
                onPressed: () => _zoomBy(1.25),
              ),
              IconButton(
                tooltip: 'Fit to window (0)',
                icon: const Icon(Icons.fit_screen_outlined),
                onPressed: _fit,
              ),
              IconButton(
                tooltip: 'Actual size (1)',
                icon: const Icon(Icons.crop_free),
                onPressed: _actualSize,
              ),
              IconButton(
                tooltip: 'Rotate view (R)',
                icon: const Icon(Icons.rotate_right),
                onPressed: _rotate,
              ),
              if (hasSiblings)
                IconButton(
                  tooltip: 'Next image (→)',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _siblingIndex < _siblings.length - 1 && !_busy
                      ? () => _step(1)
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
