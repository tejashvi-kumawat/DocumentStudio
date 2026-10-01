import 'dart:async';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_tool_form_layout.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/design_system/widgets/ds_tool_blocks.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/document_lifecycle/document_save_result_actions.dart';
import 'package:document_studio/features/image_tools/image_tools_deps.dart';
import 'package:document_studio/infrastructure/image/image_processing_port.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

/// Resize, rotate/flip, and convert a single image (JPEG / PNG output).
class ImageToolsScreen extends StatefulWidget {
  const ImageToolsScreen({super.key, required this.deps, this.initialFile});

  final ImageToolsDeps deps;
  final LocalFileRef? initialFile;

  @override
  State<ImageToolsScreen> createState() => _ImageToolsScreenState();
}

class _ImageToolsScreenState extends State<ImageToolsScreen> {
  static const _minWidth = 16;
  static const _renderDebounce = Duration(milliseconds: 350);

  LocalFileRef? _sourceRef;
  Uint8List? _sourceBytes;
  DecodedImage? _decoded;
  bool _loading = false;
  bool _saving = false;
  String? _error;

  int _quarterTurns = 0;
  bool _flipH = false;
  bool _flipV = false;
  int _targetWidth = 0;
  ImageOutputFormat _outputFormat = ImageOutputFormat.jpeg;
  int _jpegQuality = 85;

  RenderedImage? _result;
  String? _resultKey;
  String? _savedPath;
  bool _rendering = false;
  int _renderGen = 0;
  Timer? _debounce;

  final _widthCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _widthFocus = FocusNode();
  final _heightFocus = FocusNode();

  bool get _busy => _loading || _saving;

  int get _rotW {
    final d = _decoded!;
    return _quarterTurns.isOdd ? d.height : d.width;
  }

  int get _rotH {
    final d = _decoded!;
    return _quarterTurns.isOdd ? d.width : d.height;
  }

  int _heightFor(int width) =>
      (_rotH * width / _rotW).round().clamp(1, 1 << 20);

  ImageEditSpec get _spec => ImageEditSpec(
        width: _targetWidth >= _rotW ? null : _targetWidth,
        quarterTurns: _quarterTurns,
        flipHorizontal: _flipH,
        flipVertical: _flipV,
        format: _outputFormat,
        jpegQuality: _jpegQuality,
      );

  String get _specKey =>
      '$_targetWidth|$_quarterTurns|$_flipH|$_flipV|${_outputFormat.name}|'
      '${_outputFormat == ImageOutputFormat.jpeg ? _jpegQuality : 0}';

  bool get _resultCurrent => _result != null && _resultKey == _specKey;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialFile;
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(initial));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _renderGen++;
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    _widthFocus.dispose();
    _heightFocus.dispose();
    super.dispose();
  }

  Future<void> _openImage() async {
    final picked = await widget.deps.pickOpenImage();
    if (picked == null || !mounted) return;
    await _load(picked);
  }

  Future<void> _load(LocalFileRef picked) async {
    if (!mounted) return;
    _debounce?.cancel();
    _renderGen++;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await widget.deps.readBytes(picked);
      final decoded = await widget.deps.imageProcessing.decode(bytes);
      if (!mounted) return;
      final ext = picked.displayName.toLowerCase();
      setState(() {
        _sourceRef = picked;
        _sourceBytes = bytes;
        _decoded = decoded;
        _quarterTurns = 0;
        _flipH = false;
        _flipV = false;
        _targetWidth = decoded.width;
        _outputFormat = ext.endsWith('.png') ||
                ext.endsWith('.gif') ||
                ext.endsWith('.bmp')
            ? ImageOutputFormat.png
            : ImageOutputFormat.jpeg;
        _result = null;
        _resultKey = null;
        _savedPath = null;
        _loading = false;
      });
      _syncDimensionFields(force: true);
      _scheduleRender(immediate: true);
    } on DocumentStudioError catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not open this image: $e';
      });
    }
  }

  void _syncDimensionFields({bool force = false}) {
    if (_decoded == null) return;
    if (force || !_widthFocus.hasFocus) {
      _widthCtrl.text = '$_targetWidth';
    }
    if (force || !_heightFocus.hasFocus) {
      _heightCtrl.text = '${_heightFor(_targetWidth)}';
    }
  }

  void _setWidth(int width, {bool fromField = false}) {
    final clamped = width.clamp(_minWidth.clamp(1, _rotW), _rotW);
    final changed = clamped != _targetWidth;
    if (changed) setState(() => _targetWidth = clamped);
    _syncDimensionFields(force: fromField);
    if (changed) _scheduleRender();
  }

  void _rotate(int delta) {
    final fraction = _targetWidth / _rotW;
    setState(() {
      _quarterTurns = (_quarterTurns + delta) % 4;
      _targetWidth = (fraction * _rotW).round().clamp(1, _rotW);
    });
    _syncDimensionFields(force: true);
    _scheduleRender();
  }

  void _changed(VoidCallback update) {
    setState(update);
    _scheduleRender();
  }

  void _scheduleRender({bool immediate = false}) {
    _debounce?.cancel();
    if (_decoded == null) return;
    if (immediate) {
      unawaited(_render());
    } else {
      _debounce = Timer(_renderDebounce, () => unawaited(_render()));
    }
  }

  Future<void> _render() async {
    final decoded = _decoded;
    if (decoded == null || !mounted) return;
    final gen = ++_renderGen;
    final key = _specKey;
    setState(() {
      _rendering = true;
      _error = null;
    });
    try {
      final rendered =
          await widget.deps.imageProcessing.render(decoded, _spec);
      if (!mounted || gen != _renderGen) return;
      setState(() {
        _result = rendered;
        _resultKey = key;
        _rendering = false;
      });
    } on DocumentStudioError catch (e) {
      if (!mounted || gen != _renderGen) return;
      setState(() {
        _rendering = false;
        _error = e.message;
      });
    }
  }

  Future<void> _saveAs() async {
    final ref = _sourceRef;
    if (ref == null || _decoded == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (!_resultCurrent) {
        _debounce?.cancel();
        await _render();
      }
      final result = _result;
      if (!mounted || result == null || !_resultCurrent) {
        if (mounted) setState(() => _saving = false);
        return;
      }
      final ext = _outputFormat == ImageOutputFormat.png ? 'png' : 'jpg';
      final base = p.basenameWithoutExtension(ref.displayName);
      final path = await widget.deps.saveImage(
        suggestedName: '$base-edited.$ext',
        bytes: result.bytes,
        format: _outputFormat,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      if (path != null) _showSaved(path);
    } on DocumentStudioError catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save the image: $e';
      });
    }
  }

  void _showSaved(String path) => setState(() => _savedPath = path);

  @override
  Widget build(BuildContext context) {
    final hasImage = _decoded != null;
    return DsToolPage(
      title: 'Image tools',
      subtitle: 'Resize, rotate, and convert images to JPEG or PNG. '
          'Everything runs on this device.',
      icon: Icons.photo_size_select_large_outlined,
      iconColor: const Color(0xFFEC4899),
      onCancel: () => context.canPop() ? context.pop() : context.go('/'),
      primaryLabel: _saving ? 'Saving…' : 'Save as…',
      primaryIcon: Icons.save_alt,
      primaryEnabled: hasImage && !_busy,
      primaryBusy: _saving,
      onPrimary: _saveAs,
      busy: _loading,
      busyMessage: _loading ? 'Opening image…' : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSize(
            duration: DsMotion.switchDuration,
            curve: DsMotion.switchCurve,
            child: _error == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(bottom: DsSpacing.md),
                    child: _ErrorBanner(
                      message: _error!,
                      onDismiss: () => setState(() => _error = null),
                    ),
                  ),
          ),
          AnimatedSwitcher(
            duration: DsMotion.switchDuration,
            switchInCurve: DsMotion.switchCurve,
            transitionBuilder: (child, animation) =>
                DsMotion.fadeRiseTransition(animation, child),
            child: hasImage
                ? _buildEditor(context)
                : DsToolFileSource(
                    key: const ValueKey('empty'),
                    files: const [],
                    allowedExtensions: const [
                      'png',
                      'jpg',
                      'jpeg',
                      'webp',
                      'bmp',
                      'gif',
                    ],
                    enabled: !_busy,
                    loading: _loading,
                    onPick: _openImage,
                    onFilesDropped: (files) {
                      if (files.isNotEmpty) unawaited(_load(files.first));
                    },
                    emptyTitle: 'Drop an image here',
                    emptySubtitle: 'PNG, JPEG, WebP, BMP, or GIF',
                    pickLabel: 'Open image',
                    icon: Icons.image_outlined,
                  ),
          ),
          if (_savedPath case final saved?)
            Padding(
              padding: const EdgeInsets.only(top: DsSpacing.md),
              child: DsToolResultCard(
                title: 'Image saved',
                file: LocalFileRef(path: saved, displayName: p.basename(saved)),
                stats: [
                  if (_result case final r?) ...[
                    DsResultStat('Size', '${r.width} × ${r.height}'),
                    DsResultStat('File', dsFormatBytes(r.bytes.length),
                        highlight: true),
                  ],
                ],
                onShowInFolder: documentSaveResultCanRevealInFolder
                    ? () => revealToolResult(
                          context,
                          LocalFileRef(
                            path: saved,
                            displayName: p.basename(saved),
                          ),
                        )
                    : null,
                onDismiss: () => setState(() => _savedPath = null),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    return LayoutBuilder(
      key: const ValueKey('editor'),
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final preview = _buildPreview(context, wide: wide);
        final controls = _buildControls(context);
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [preview, controls],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: preview),
            const SizedBox(width: DsSpacing.xl),
            Expanded(flex: 4, child: controls),
          ],
        );
      },
    );
  }

  Widget _buildPreview(BuildContext context, {required bool wide}) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);
    final ref = _sourceRef!;
    final d = _decoded!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ref.displayName,
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${d.width} × ${d.height} px · '
                    '${_formatBytes(_sourceBytes!.length)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                    ),
                  ),
                ],
              ),
            ),
            DsSecondaryButton(
              label: 'Change',
              icon: Icons.swap_horiz,
              onPressed: _busy ? null : _openImage,
            ),
          ],
        ),
        const SizedBox(height: DsSpacing.md),
        Container(
          height: wide ? 380 : 280,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(DsSpacing.radiusCard),
          ),
          padding: const EdgeInsets.all(DsSpacing.md),
          child: AnimatedSwitcher(
            duration: DsMotion.switchDuration,
            switchInCurve: DsMotion.switchCurve,
            transitionBuilder: (child, animation) =>
                DsMotion.fadeScaleTransition(animation, child),
            child: Transform.flip(
              key: ValueKey('$_quarterTurns|$_flipH|$_flipV'),
              flipX: _flipH,
              flipY: _flipV,
              child: RotatedBox(
                quarterTurns: _quarterTurns,
                child: Image(
                  image: ResizeImage(
                    MemoryImage(_sourceBytes!),
                    width: 1600,
                    height: 1600,
                    policy: ResizeImagePolicy.fit,
                  ),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (context, error, stack) => Center(
                    child: Text(
                      'Preview not available for this format.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: DsSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Rotate left',
              icon: const Icon(Icons.rotate_left),
              onPressed: _busy ? null : () => _rotate(3),
            ),
            IconButton(
              tooltip: 'Rotate right',
              icon: const Icon(Icons.rotate_right),
              onPressed: _busy ? null : () => _rotate(1),
            ),
            const SizedBox(width: DsSpacing.sm),
            IconButton(
              tooltip: 'Flip horizontally',
              isSelected: _flipH,
              icon: const Icon(Icons.flip),
              onPressed: _busy ? null : () => _changed(() => _flipH = !_flipH),
            ),
            IconButton(
              tooltip: 'Flip vertically',
              isSelected: _flipV,
              icon: const RotatedBox(quarterTurns: 1, child: Icon(Icons.flip)),
              onPressed: _busy ? null : () => _changed(() => _flipV = !_flipV),
            ),
            if (_quarterTurns != 0 || _flipH || _flipV) ...[
              const SizedBox(width: DsSpacing.sm),
              TextButton(
                onPressed: _busy
                    ? null
                    : () {
                        final fraction = _targetWidth / _rotW;
                        setState(() {
                          _quarterTurns = 0;
                          _flipH = false;
                          _flipV = false;
                          _targetWidth =
                              (fraction * _rotW).round().clamp(1, _rotW);
                        });
                        _syncDimensionFields(force: true);
                        _scheduleRender();
                      },
                child: const Text('Reset'),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildControls(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);
    final rotW = _rotW;
    final minW = _minWidth.clamp(1, rotW);
    final canResize = rotW > minW;
    final percent = (_targetWidth * 100 / rotW).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DsToolSection(
          title: 'Size',
          subtitle: 'Aspect ratio is kept. Images are never enlarged.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _DimensionField(
                      label: 'Width',
                      controller: _widthCtrl,
                      focusNode: _widthFocus,
                      enabled: canResize && !_busy,
                      onSubmitted: (v) => _setWidth(v, fromField: true),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DsSpacing.sm,
                    ),
                    child: Icon(Icons.link, size: 18, color: secondary),
                  ),
                  Expanded(
                    child: _DimensionField(
                      label: 'Height',
                      controller: _heightCtrl,
                      focusNode: _heightFocus,
                      enabled: canResize && !_busy,
                      onSubmitted: (h) => _setWidth(
                        (h * _rotW / _rotH).round(),
                        fromField: true,
                      ),
                    ),
                  ),
                ],
              ),
              if (canResize) ...[
                const SizedBox(height: DsSpacing.sm),
                Slider.adaptive(
                  value: _targetWidth.clamp(minW, rotW).toDouble(),
                  min: minW.toDouble(),
                  max: rotW.toDouble(),
                  label: '$percent%',
                  onChanged: _busy ? null : (v) => _setWidth(v.round()),
                ),
                Wrap(
                  spacing: DsSpacing.sm,
                  runSpacing: DsSpacing.xs,
                  children: [
                    for (final pct in const [100, 75, 50, 25])
                      ChoiceChip(
                        label: Text('$pct%'),
                        selected: percent == pct,
                        onSelected: _busy
                            ? null
                            : (_) => _setWidth((rotW * pct / 100).round()),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        DsToolSection(
          title: 'Format',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<ImageOutputFormat>(
                segments: const [
                  ButtonSegment(
                    value: ImageOutputFormat.jpeg,
                    label: Text('JPEG'),
                    icon: Icon(Icons.photo_outlined),
                  ),
                  ButtonSegment(
                    value: ImageOutputFormat.png,
                    label: Text('PNG'),
                    icon: Icon(Icons.image_outlined),
                  ),
                ],
                selected: {_outputFormat},
                showSelectedIcon: false,
                onSelectionChanged: _busy
                    ? null
                    : (s) => _changed(() => _outputFormat = s.first),
              ),
              const SizedBox(height: DsSpacing.xs),
              Text(
                _outputFormat == ImageOutputFormat.jpeg
                    ? 'Smaller files, best for photos. Transparency becomes white.'
                    : 'Lossless and keeps transparency; larger for photos.',
                style: theme.textTheme.bodySmall?.copyWith(color: secondary),
              ),
              AnimatedSize(
                duration: DsMotion.switchDuration,
                curve: DsMotion.switchCurve,
                child: _outputFormat != ImageOutputFormat.jpeg
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: DsSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Quality',
                                  style: theme.textTheme.bodyMedium,
                                ),
                                const Spacer(),
                                Text(
                                  '$_jpegQuality · ${_qualityLabel(_jpegQuality)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: secondary,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Slider.adaptive(
                              value: _jpegQuality.toDouble(),
                              min: 10,
                              max: 100,
                              divisions: 18,
                              label: '$_jpegQuality',
                              onChanged: _busy
                                  ? null
                                  : (v) => _changed(
                                        () => _jpegQuality = v.round(),
                                      ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
        DsToolSection(
          title: 'Result',
          child: _ResultSummary(
            width: _targetWidth,
            height: _heightFor(_targetWidth),
            originalBytes: _sourceBytes!.length,
            result: _resultCurrent ? _result : null,
            pending: _rendering || !_resultCurrent,
          ),
        ),
      ],
    );
  }

  static String _qualityLabel(int q) => q >= 90
      ? 'Maximum'
      : q >= 75
          ? 'High'
          : q >= 55
              ? 'Medium'
              : 'Low';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _DimensionField extends StatelessWidget {
  const _DimensionField({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final ValueChanged<int> onSubmitted;

  @override
  Widget build(BuildContext context) {
    void submit() {
      final v = int.tryParse(controller.text.trim());
      if (v != null && v > 0) onSubmitted(v);
    }

    return Focus(
      onFocusChange: (has) {
        if (!has) submit();
      },
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(5),
        ],
        decoration: InputDecoration(
          labelText: label,
          suffixText: 'px',
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => submit(),
      ),
    );
  }
}

class _ResultSummary extends StatelessWidget {
  const _ResultSummary({
    required this.width,
    required this.height,
    required this.originalBytes,
    required this.result,
    required this.pending,
  });

  final int width;
  final int height;
  final int originalBytes;
  final RenderedImage? result;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);
    final r = result;
    String sizeText;
    Color? deltaColor;
    if (r == null) {
      sizeText = 'Calculating size…';
    } else {
      final delta = (r.bytes.length - originalBytes) * 100 / originalBytes;
      final sign = delta <= 0 ? '−' : '+';
      sizeText = '${_formatBytes(r.bytes.length)}  '
          '($sign${delta.abs().toStringAsFixed(0)}% vs original)';
      deltaColor = delta <= 0 ? DsColors.primary : theme.colorScheme.error;
    }
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$width × $height px',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              AnimatedSwitcher(
                duration: DsMotion.switchDuration,
                switchInCurve: DsMotion.switchCurve,
                child: Text(
                  sizeText,
                  key: ValueKey(sizeText),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: deltaColor ?? secondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        AnimatedOpacity(
          opacity: pending ? 1 : 0,
          duration: DsMotion.switchDuration,
          child: const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        DsSpacing.md,
        DsSpacing.sm,
        DsSpacing.xs,
        DsSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
          const SizedBox(width: DsSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            icon: Icon(Icons.close, color: scheme.onErrorContainer, size: 18),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
