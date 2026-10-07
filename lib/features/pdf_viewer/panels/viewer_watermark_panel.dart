import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:document_studio/app/tree_unlock.dart';
import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/pdf/pdf_document_cache.dart';
import 'package:document_studio/core/storage/linux_document_portal.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_spec.dart';
import 'package:document_studio/domain/pdf_markup/pdf_markup_models.dart';
import 'package:document_studio/domain/pdf_stamp/watermark_layout.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_scaffold.dart';
import 'package:document_studio/features/pdf_viewer/pdf_page_scope.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio/features/pdf_viewer/widgets/pdf_page_scope_field.dart';
import 'package:document_studio/features/pdf_viewer/widgets/pdf_text_option_controls.dart';
import 'package:document_studio/features/pdf_viewer/widgets/watermark_preview_painter.dart';
import 'package:document_studio/infrastructure/pdf/stamp/pdf_stamp_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

enum _Layer { above, behind }

const _palette = <(double, double, double)>[
  (0.5, 0.5, 0.5),
  (0.1, 0.1, 0.1),
  (0.894, 0.0, 0.169),
  (0.0, 0.4, 0.8),
  (0.18, 0.49, 0.2),
  (0.93, 0.49, 0.0),
];

const _anglePresets = <double>[0, 45, 90, -45];

const _scopeKinds = [
  PdfPageScopeKind.thisPage,
  PdfPageScopeKind.allPages,
  PdfPageScopeKind.range,
];

/// Watermark options. The watermark is previewed live on exactly the pages in
/// scope (viewer overlay + thumbnail strip), painted from the same
/// [layoutWatermark] geometry the pure-Dart writer burns, so Apply matches it.
class ViewerWatermarkPanel extends ConsumerStatefulWidget {
  const ViewerWatermarkPanel({
    super.key,
    required this.handoff,
    this.pageCount,
    this.selectedPages1Based = const {},
    this.onDeliver,
    this.previewSink,
    this.livePreview = true,
  });

  final PdfViewerDocumentHandoff handoff;
  final int? pageCount;
  final Set<int> selectedPages1Based;

  /// Receives the stamped PDF; `null` commits it to the open viewer tab.
  /// Returns the file now holding the result (to re-inspect), if any.
  final Future<String?> Function(Uint8List bytes, String suggestedName)?
  onDeliver;

  /// Mirrors the preview state (e.g. for a standalone page preview).
  final ValueNotifier<WatermarkPreviewState?>? previewSink;

  /// Paint the preview on the live viewer pages.
  final bool livePreview;

  @override
  ConsumerState<ViewerWatermarkPanel> createState() =>
      _ViewerWatermarkPanelState();
}

class _ViewerWatermarkPanelState extends ConsumerState<ViewerWatermarkPanel> {
  final _spec = ValueNotifier<WatermarkSpec>(const WatermarkSpec());
  final _preview = ValueNotifier<WatermarkPreviewState?>(null);
  late final _textCtrl = TextEditingController(text: _spec.value.text);

  ViewerLiveToolSession? _live;
  late String _path = widget.handoff.file.path;
  late int _currentPage = widget.handoff.currentPage1;

  PdfStampInspection? _inspection;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  _Layer _layer = _Layer.above;
  bool _replaceExisting = true;
  PdfPageScopeKind _scope = PdfPageScopeKind.allPages;
  String _range = '';

  Uint8List? _imageBytes;
  ui.Image? _image;
  String? _imageName;

  /// Hidden after Apply so it doesn't double up with the burned result.
  bool _justApplied = false;
  int _thumbRevision = 0;

  @override
  void initState() {
    super.initState();
    _spec.addListener(_onSpecChanged);
    _preview.addListener(_mirrorPreview);
    if (widget.livePreview) {
      final live = ref.read(viewerLiveToolSessionProvider);
      _live = live;
      if (live.toolId == ViewerToolId.watermark && live.pageIndex1Based > 0) {
        _currentPage = live.pageIndex1Based;
      }
      live.addListener(_onSession);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (live.toolId != ViewerToolId.watermark) {
          live.activate(
            ViewerToolId.watermark,
            pageIndex1Based: _currentPage,
            labelText: _spec.value.text,
          );
        }
        _pushPreview();
      });
    }
    unawaited(_inspect());
  }

  @override
  void didUpdateWidget(covariant ViewerWatermarkPanel old) {
    super.didUpdateWidget(old);
    if (old.handoff.file.path != widget.handoff.file.path) {
      _path = widget.handoff.file.path;
      _thumbRevision++;
      unawaited(_inspect());
    }
    if (old.handoff.currentPage1 != widget.handoff.currentPage1) {
      _currentPage = widget.handoff.currentPage1;
      _pushPreview();
    }
  }

  @override
  void dispose() {
    _live?.removeListener(_onSession);
    final live = _live;
    final sink = widget.previewSink;
    final pushed = _preview.value;
    runWhenTreeUnlocked(() {
      // A replacement panel may already have pushed its own preview.
      if (live != null &&
          identical(live.watermarkPreviewNotifier.value, pushed)) {
        live.setWatermarkPreview(null);
      }
      if (sink != null && identical(sink.value, pushed)) sink.value = null;
    });
    _spec.removeListener(_onSpecChanged);
    _preview.removeListener(_mirrorPreview);
    _spec.dispose();
    _preview.dispose();
    _textCtrl.dispose();
    _image?.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- state

  int get _pageCount =>
      _inspection?.pageCount ?? math.max(widget.pageCount ?? 1, 1);

  bool get _hasExisting => _inspection?.has(PdfStampKind.watermark) ?? false;

  /// Target pages, or null when the scope is invalid / empty.
  Set<int>? get _targets {
    final n = _pageCount;
    return switch (_scope) {
      PdfPageScopeKind.thisPage => {_currentPage.clamp(1, n)},
      PdfPageScopeKind.range => parsePdfPageRangeExpression(_range, n).pages,
      _ => {for (var i = 1; i <= n; i++) i},
    };
  }

  String? get _rangeError => _scope == PdfPageScopeKind.range
      ? parsePdfPageRangeExpression(_range, _pageCount).error
      : null;

  bool get _contentReady {
    final s = _spec.value;
    return s.isImage ? _imageBytes != null : s.text.trim().isNotEmpty;
  }

  String _resolve(String template, int page) {
    final file = widget.handoff.file;
    return PdfMarkupTemplateContext(
      file: file,
      pageIndex1Based: page,
      pageCount: _pageCount,
      documentTitle:
          _inspection?.title ?? p.basenameWithoutExtension(file.path),
      date: DateTime.now(),
    ).resolve(template);
  }

  void _onSpecChanged() {
    if (_justApplied) setState(() => _justApplied = false);
    _pushPreview();
  }

  void _onSession() {
    final live = _live;
    if (live == null || live.toolId != ViewerToolId.watermark) return;
    final page = live.pageIndex1Based;
    if (page > 0 && page != _currentPage) {
      _currentPage = page;
      if (_scope == PdfPageScopeKind.thisPage) {
        _pushPreview();
        if (mounted) setState(() {});
      }
    }
  }

  void _pushPreview() {
    final targets = _targets;
    _preview.value = WatermarkPreviewState(
      spec: _spec.value,
      pages1Based: _scope == PdfPageScopeKind.allPages ? null : targets ?? {},
      image: _image,
      visible: !_justApplied && _contentReady && targets != null,
      resolveText: _resolve,
    );
  }

  void _mirrorPreview() {
    final v = _preview.value;
    _live?.setWatermarkPreview(v);
    widget.previewSink?.value = v;
  }

  void _setScope(PdfPageScopeKind kind, {String? range}) {
    setState(() {
      _scope = kind;
      if (range != null) _range = range;
      _justApplied = false;
    });
    _pushPreview();
  }

  void _toggleThumb(int page) {
    final pages = {...?_targets};
    if (!pages.remove(page)) pages.add(page);
    if (pages.length == _pageCount) {
      _setScope(PdfPageScopeKind.allPages);
    } else {
      _setScope(PdfPageScopeKind.range, range: formatPdfPageRange(pages));
    }
  }

  // ------------------------------------------------------------- I/O

  Future<void> _inspect() async {
    if (!_loading || _error != null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final bytes = await File(_path).readAsBytes();
      final info = await PdfStampEngine.inspect(bytes);
      if (!mounted) return;
      setState(() {
        _inspection = info;
        _currentPage = _currentPage.clamp(1, math.max(info.pageCount, 1));
      });
    } on DocumentStudioError catch (e) {
      if (mounted) setState(() => _error = e.recoveryHint ?? e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not read this PDF: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
      _pushPreview();
    }
  }

  Future<void> _pickImage() async {
    final picked = await ref
        .read(fileStorageProvider)
        .pickOpenFile(allowedExtensions: ['png', 'jpg', 'jpeg']);
    if (picked == null) return;
    try {
      final bytes = await File(picked.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      final img = frame.image;
      _image?.dispose();
      setState(() {
        _imageBytes = bytes;
        _image = img;
        _imageName = picked.displayName;
      });
      _spec.value = _spec.value.copyWith(
        imageAspect: img.width / math.max(1, img.height),
      );
    } catch (_) {
      _snack('That image could not be read. Use a PNG or JPEG.');
    }
  }

  Future<void> _apply() async {
    final targets = _targets;
    if (targets == null || targets.isEmpty || !_contentReady) return;
    final spec = _spec.value;
    await _run(
      (bytes) => PdfStampEngine.applyWatermark(
        bytes,
        WatermarkStampRequest(
          spec: spec,
          pages1Based: targets,
          textForPage: spec.isImage
              ? const {}
              : {for (final pg in targets) pg: _resolve(spec.text, pg)},
          imageBytes: spec.isImage ? _imageBytes : null,
          behind: _layer == _Layer.behind,
          replaceExisting: _hasExisting && _replaceExisting,
        ),
      ),
      prefix: 'watermarked',
      message:
          'Watermark applied to ${targets.length} '
          'page${targets.length == 1 ? '' : 's'}.',
    );
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove watermark?'),
        content: const Text(
          'Removes the watermark Document Studio added to this PDF. '
          'Other page content is not touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: DsColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      (bytes) => PdfStampEngine.remove(bytes, PdfStampKind.watermark),
      prefix: 'clean',
      message: 'Watermark removed.',
    );
  }

  Future<void> _run(
    Future<Uint8List> Function(Uint8List bytes) edit, {
    required String prefix,
    required String message,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = ref.read(documentTabsControllerProvider).activeSession;
      final path = widget.onDeliver == null && session != null
          ? session.file.path
          : _path;
      final input = await File(path).readAsBytes();
      final out = await edit(input);
      final savedPath = await _deliver(
        out,
        '$prefix-${widget.handoff.file.displayName}',
        message,
      );
      if (!mounted) return;
      if (savedPath != null) {
        _path = savedPath;
        setState(() {
          _justApplied = true;
          _thumbRevision++;
        });
        await _inspect();
      }
    } on DocumentStudioError catch (e) {
      if (mounted) setState(() => _error = e.recoveryHint ?? e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not update the PDF: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      _pushPreview();
    }
  }

  Future<String?> _deliver(Uint8List bytes, String name, String message) async {
    final custom = widget.onDeliver;
    if (custom != null) return custom(bytes, name);
    final tabs = ref.read(documentTabsControllerProvider);
    final session = tabs.activeSession;
    if (session == null || !mounted) return null;
    final saved = await commitBytesToSession(
      context: context,
      storage: ref.read(fileStorageProvider),
      tabs: tabs,
      session: session,
      bytes: bytes,
      successMessage: message,
    );
    return saved?.path;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------- UI

  Widget _choice<T>({
    required List<(T, String, IconData?)> options,
    required T selected,
    required ValueChanged<T>? onChanged,
  }) {
    return SegmentedButton<T>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        for (final option in options)
          ButtonSegment<T>(
            value: option.$1,
            icon: option.$3 == null ? null : Icon(option.$3, size: 18),
            label: Text(option.$2),
          ),
      ],
      selected: {selected},
      onSelectionChanged: onChanged == null
          ? null
          : (next) => onChanged(next.first),
    );
  }

  /// Rebuilds only [builder] when the spec changes (keeps sliders smooth).
  Widget _specBuilder(Widget Function(WatermarkSpec spec) builder) =>
      ValueListenableBuilder<WatermarkSpec>(
        valueListenable: _spec,
        builder: (_, spec, _) => builder(spec),
      );

  void _edit(WatermarkSpec Function(WatermarkSpec s) f) =>
      _spec.value = f(_spec.value);

  HfAlign _hAlign(WatermarkPosition position) => switch (position) {
    WatermarkPosition.topLeft ||
    WatermarkPosition.centerLeft ||
    WatermarkPosition.bottomLeft => HfAlign.left,
    WatermarkPosition.topRight ||
    WatermarkPosition.centerRight ||
    WatermarkPosition.bottomRight => HfAlign.right,
    _ => HfAlign.center,
  };

  WatermarkPosition _withHAlign(WatermarkPosition position, HfAlign align) {
    final top = switch (position) {
      WatermarkPosition.topLeft ||
      WatermarkPosition.topCenter ||
      WatermarkPosition.topRight => true,
      _ => false,
    };
    final bottom = switch (position) {
      WatermarkPosition.bottomLeft ||
      WatermarkPosition.bottomCenter ||
      WatermarkPosition.bottomRight => true,
      _ => false,
    };
    return switch ((top, bottom, align)) {
      (true, _, HfAlign.left) => WatermarkPosition.topLeft,
      (true, _, HfAlign.center) => WatermarkPosition.topCenter,
      (true, _, HfAlign.right) => WatermarkPosition.topRight,
      (_, true, HfAlign.left) => WatermarkPosition.bottomLeft,
      (_, true, HfAlign.center) => WatermarkPosition.bottomCenter,
      (_, true, HfAlign.right) => WatermarkPosition.bottomRight,
      (_, _, HfAlign.left) => WatermarkPosition.centerLeft,
      (_, _, HfAlign.right) => WatermarkPosition.centerRight,
      _ => WatermarkPosition.center,
    };
  }

  List<Widget> _controls(ThemeData theme) {
    final enabled = !_busy;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: DsColors.textSecondary(theme.brightness),
    );
    final labelStyle = theme.textTheme.bodyLarge;
    return [
      if (_error != null)
        _Banner(
          icon: Icons.error_outline,
          color: DsColors.error,
          text: _error!,
        ),
      if (_hasExisting) ...[
        _Banner(
          icon: Icons.water_drop_outlined,
          color: DsColors.primary,
          text:
              'Document Studio watermark found on '
              '${_inspection!.pagesWith(PdfStampKind.watermark).length} '
              'page(s).',
          trailing: TextButton(
            onPressed: enabled ? _remove : null,
            style: TextButton.styleFrom(foregroundColor: DsColors.error),
            child: const Text('Remove'),
          ),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text('Replace existing watermark', style: labelStyle),
          subtitle: Text(
            _replaceExisting
                ? 'The old watermark is removed from every page.'
                : 'The new watermark is added on top of the old one.',
            style: muted,
          ),
          value: _replaceExisting,
          activeTrackColor: DsColors.primary,
          onChanged: enabled
              ? (v) => setState(() => _replaceExisting = v)
              : null,
        ),
      ],
      const PdfOptionHeading('Text', first: true),
      _specBuilder(
        (spec) => _choice<bool>(
          options: const [
            (false, 'Text', Icons.text_fields),
            (true, 'Image', Icons.image_outlined),
          ],
          selected: spec.isImage,
          onChanged: !enabled
              ? null
              : (image) {
                  if (image) {
                    final img = _image;
                    if (img == null) {
                      unawaited(_pickImage());
                    } else {
                      _edit(
                        (x) => x.copyWith(
                          imageAspect: img.width / math.max(1, img.height),
                        ),
                      );
                    }
                  } else {
                    _edit((x) => x.copyWith(clearImage: true));
                  }
                },
        ),
      ),
      const SizedBox(height: DsSpacing.sm),
      _specBuilder((spec) {
        if (spec.isImage) return _imageControls(theme, spec, enabled, muted);
        return _textControls(spec, enabled);
      }),
      const PdfOptionHeading('Appearance'),
      _specBuilder((spec) {
        if (spec.isImage) return const SizedBox.shrink();
        return PdfCompactColorPicker<(double, double, double)>(
          colors: _palette,
          selected: spec.colorRgb,
          swatch: (c) {
            final (r, g, b) = c;
            return Color.from(alpha: 1, red: r, green: g, blue: b);
          },
          onChanged: enabled
              ? (c) {
                  if (c != null) _edit((x) => x.copyWith(colorRgb: c));
                }
              : null,
        );
      }),
      _specBuilder(
        (spec) => _SliderRow(
          leading: 'Opacity',
          value: spec.opacity.clamp(0.05, 1.0),
          min: 0.05,
          max: 1,
          divisions: 19,
          label: '${(spec.opacity * 100).round()}%',
          onChanged: enabled
              ? (v) => _edit((x) => x.copyWith(opacity: v))
              : null,
        ),
      ),
      _specBuilder(
        (spec) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SliderRow(
              leading: 'Rotation',
              value: spec.rotationDegrees.clamp(-90, 90),
              min: -90,
              max: 90,
              divisions: 36,
              label: '${spec.rotationDegrees.round()}°',
              onChanged: enabled
                  ? (v) => _edit((x) => x.copyWith(rotationDegrees: v))
                  : null,
            ),
            Wrap(
              spacing: DsSpacing.sm,
              runSpacing: DsSpacing.sm,
              children: [
                for (final a in _anglePresets)
                  ChoiceChip(
                    label: Text('${a.round()}°'),
                    selected: spec.rotationDegrees == a,
                    showCheckmark: false,
                    selectedColor: DsColors.primary.withValues(alpha: 0.14),
                    onSelected: enabled
                        ? (_) => _edit((x) => x.copyWith(rotationDegrees: a))
                        : null,
                  ),
              ],
            ),
          ],
        ),
      ),
      const PdfOptionHeading('Position'),
      _specBuilder(
        (spec) => LayoutBuilder(
          builder: (context, constraints) {
            final grid = _PositionGrid(
              selected: spec.position,
              enabled: enabled && !spec.tiled,
              onSelect: (pos) => _edit((x) => x.copyWith(position: pos)),
            );
            final tile = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Tile across page', style: labelStyle),
                  subtitle: Text(
                    spec.tiled
                        ? 'Repeats in a grid over the whole page.'
                        : 'One mark at the chosen spot.',
                    style: muted,
                  ),
                  value: spec.tiled,
                  activeTrackColor: DsColors.primary,
                  onChanged: enabled
                      ? (v) => _edit((x) => x.copyWith(tiled: v))
                      : null,
                ),
              ],
            );
            if (viewerToolFormStacks(context, constraints.maxWidth)) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(alignment: Alignment.centerLeft, child: grid),
                  const SizedBox(height: DsSpacing.sm),
                  tile,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                grid,
                const SizedBox(width: DsSpacing.lg),
                Expanded(child: tile),
              ],
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: DsSpacing.sm, bottom: DsSpacing.xs),
        child: Text(
          'Layer',
          style: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
        ),
      ),
      _choice<_Layer>(
        options: const [
          (_Layer.above, 'In front', null),
          (_Layer.behind, 'Behind content', null),
        ],
        selected: _layer,
        onChanged: enabled ? (layer) => setState(() => _layer = layer) : null,
      ),
      if (_layer == _Layer.behind)
        Padding(
          padding: const EdgeInsets.only(top: DsSpacing.xs),
          child: Text(
            'Hidden where pages have an opaque background (e.g. scans).',
            style: muted,
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(top: DsSpacing.sm, bottom: DsSpacing.xs),
        child: Text(
          'Page range',
          style: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
        ),
      ),
      PdfPageScopeField(
        title: null,
        kinds: _scopeKinds,
        labels: {PdfPageScopeKind.thisPage: 'Current ($_currentPage)'},
        kind: _scope,
        enabled: enabled,
        rangeExpression: _range,
        rangeError: _rangeError,
        onKindChanged: (k) => _setScope(k),
        onRangeExpressionChanged: (v) => _setScope(_scope, range: v),
      ),
      const SizedBox(height: DsSpacing.sm),
      Text('Tap thumbnails to add or remove pages.', style: muted),
      const SizedBox(height: DsSpacing.xs),
      SizedBox(
        height: 148,
        child: _ThumbStrip(
          key: ValueKey('$_path#$_thumbRevision'),
          path: _path,
          password: widget.handoff.password,
          preview: _preview,
          onTap: enabled ? _toggleThumb : null,
        ),
      ),
      const SizedBox(height: DsSpacing.lg),
    ];
  }

  Widget _textControls(WatermarkSpec spec, bool enabled) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _textCtrl,
          enabled: enabled,
          decoration: const InputDecoration(
            labelText: 'Text',
            helperText: 'Tokens: {page} {pages} {date} {file} {title}',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => _edit((x) => x.copyWith(text: v)),
        ),
        const SizedBox(height: DsSpacing.sm),
        PdfStandardFontField(
          font: spec.font,
          onChanged: enabled
              ? (font) => _edit((x) => x.copyWith(font: font))
              : null,
        ),
        _SliderRow(
          leading: 'Size',
          value: spec.fontSizePt.clamp(12, 200),
          min: 12,
          max: 200,
          divisions: 94,
          label: '${spec.fontSizePt.round()} pt',
          onChanged: enabled
              ? (v) => _edit((x) => x.copyWith(fontSizePt: v.roundToDouble()))
              : null,
        ),
        PdfTextAlignGroup<HfAlign>(
          value: _hAlign(spec.position),
          left: HfAlign.left,
          center: HfAlign.center,
          right: HfAlign.right,
          onChanged: enabled && !spec.tiled
              ? (align) => _edit(
                  (x) => x.copyWith(position: _withHAlign(x.position, align)),
                )
              : null,
        ),
      ],
    );
  }

  Widget _imageControls(
    ThemeData theme,
    WatermarkSpec spec,
    bool enabled,
    TextStyle? muted,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final name = Text(
              _imageName ?? 'No image chosen',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge,
            );
            final pick = OutlinedButton.icon(
              onPressed: enabled ? _pickImage : null,
              icon: const Icon(Icons.image_outlined),
              label: Text(_imageName == null ? 'Choose image' : 'Change image'),
            );
            if (viewerToolFormStacks(context, constraints.maxWidth)) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  name,
                  const SizedBox(height: DsSpacing.sm),
                  SizedBox(
                    height: DsSpacing.controlHeightComfortable,
                    child: pick,
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: name),
                const SizedBox(width: DsSpacing.md),
                pick,
              ],
            );
          },
        ),
        Text('PNG (with transparency) or JPEG.', style: muted),
        _SliderRow(
          leading: 'Size',
          value: spec.imageHeightFrac.clamp(0.05, 0.9),
          min: 0.05,
          max: 0.9,
          divisions: 17,
          label: '${(spec.imageHeightFrac * 100).round()}% of page',
          onChanged: enabled
              ? (v) => _edit((x) => x.copyWith(imageHeightFrac: v))
              : null,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targets = _targets;
    final n = targets?.length ?? 0;
    final canApply =
        !_busy && !_loading && _error == null && n > 0 && _contentReady;
    return ViewerToolFormScaffold(
      primaryKey: const Key('watermark_apply_button'),
      primaryLabel: _busy ? 'Applying…' : 'Apply',
      primaryIcon: Icons.water_drop_outlined,
      primaryEnabled: canApply,
      primaryBusy: _busy,
      onPrimary: () => unawaited(_apply()),
      notice: _justApplied
          ? Text(
              'Applied. Change any option to preview again.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: DsColors.success,
              ),
            )
          : null,
      children: _controls(theme),
    );
  }
}

// ---------------------------------------------------------------- widgets

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.text,
    this.trailing,
  });

  final IconData icon;
  final Color color;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: DsSpacing.sm),
      padding: const EdgeInsets.fromLTRB(
        DsSpacing.sm,
        DsSpacing.xs,
        DsSpacing.xs,
        DsSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(DsSpacing.radiusGrouped),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: DsSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontSize: 12.5),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
    this.divisions,
    this.leading,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String label;
  final String? leading;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (leading != null)
              Expanded(
                child: Text(
                  leading!,
                  style: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
                ),
              )
            else
              const Spacer(),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            ),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: min,
          max: max,
          divisions: divisions,
          activeColor: DsColors.primary,
          label: label,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _PositionGrid extends StatelessWidget {
  const _PositionGrid({
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  final WatermarkPosition selected;
  final bool enabled;
  final ValueChanged<WatermarkPosition> onSelect;

  @override
  Widget build(BuildContext context) {
    const values = WatermarkPosition.values;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Container(
        width: 132,
        height: 160,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: DsColors.borderLight),
          boxShadow: DsSpacing.cardShadowLight(opacity: 0.06),
        ),
        child: Column(
          children: [
            for (var row = 0; row < 3; row++)
              Expanded(
                child: Row(
                  children: [
                    for (var col = 0; col < 3; col++)
                      Expanded(
                        child: _PositionCell(
                          selected: values[row * 3 + col] == selected,
                          onTap: enabled
                              ? () => onSelect(values[row * 3 + col])
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PositionCell extends StatelessWidget {
  const _PositionCell({required this.selected, this.onTap});

  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Center(
        child: AnimatedContainer(
          duration: DsMotion.hoverDuration,
          curve: DsMotion.switchCurve,
          width: selected ? 14 : 8,
          height: selected ? 14 : 8,
          decoration: BoxDecoration(
            color: selected ? DsColors.primary : Colors.black26,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// Horizontal page thumbnails; in-scope pages are outlined and show the
/// watermark, repainted straight from the preview notifier.
class _ThumbStrip extends StatefulWidget {
  const _ThumbStrip({
    super.key,
    required this.path,
    required this.password,
    required this.preview,
    required this.onTap,
  });

  final String path;
  final String? password;
  final ValueNotifier<WatermarkPreviewState?> preview;
  final ValueChanged<int>? onTap;

  @override
  State<_ThumbStrip> createState() => _ThumbStripState();
}

class _ThumbStripState extends State<_ThumbStrip> {
  PdfDocumentLease? _lease;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void didUpdateWidget(covariant _ThumbStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.password != widget.password) {
      unawaited(_open());
    }
  }

  @override
  void dispose() {
    _lease?.release();
    _lease = null;
    super.dispose();
  }

  Future<void> _open() async {
    _lease?.release();
    _lease = null;
    try {
      // Shared cache, progressive — never walk all pages for the strip.
      var path = LinuxDocumentPortal.resolveSync(widget.path);
      if (LinuxDocumentPortal.isPortalPath(path)) {
        path = await LinuxDocumentPortal.resolve(path);
      }
      final lease = await PdfDocumentCache.instance.acquire(
        path,
        password: widget.password,
        loadAllPages: false,
      );
      if (!mounted) {
        lease.release();
        return;
      }
      setState(() {
        _lease = lease;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lease = null;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lease = _lease;
    if (_error != null) return const SizedBox.shrink();
    if (lease == null) {
      return const Center(
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final document = lease.document;
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: document.pages.length,
      separatorBuilder: (_, _) => const SizedBox(width: DsSpacing.sm),
      itemBuilder: (context, i) {
        final page = document.pages[i];
        return _Thumb(
          document: document,
          page: page,
          preview: widget.preview,
          onTap: widget.onTap == null
              ? null
              : () => widget.onTap!(page.pageNumber),
        );
      },
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.document,
    required this.page,
    required this.preview,
    this.onTap,
  });

  final PdfDocument document;
  final PdfPage page;
  final ValueNotifier<WatermarkPreviewState?> preview;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final aspect = page.width / math.max(page.height, 1);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: aspect,
              child: ValueListenableBuilder<WatermarkPreviewState?>(
                valueListenable: preview,
                builder: (context, state, child) {
                  final inScope =
                      state != null &&
                      state.visible &&
                      state.appliesTo(page.pageNumber);
                  return AnimatedContainer(
                    duration: DsMotion.hoverDuration,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(
                        color: inScope
                            ? DsColors.primary
                            : DsColors.borderLight,
                        width: inScope ? 2 : 1,
                      ),
                    ),
                    child: child,
                  );
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PdfPageView(
                      document: document,
                      pageNumber: page.pageNumber,
                      maximumDpi: 36,
                    ),
                    CustomPaint(
                      painter: _ThumbWatermarkPainter(
                        preview: preview,
                        page1Based: page.pageNumber,
                        pageWidthPt: page.width,
                        pageHeightPt: page.height,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${page.pageNumber}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _ThumbWatermarkPainter extends CustomPainter {
  _ThumbWatermarkPainter({
    required this.preview,
    required this.page1Based,
    required this.pageWidthPt,
    required this.pageHeightPt,
  }) : super(repaint: preview);

  final ValueNotifier<WatermarkPreviewState?> preview;
  final int page1Based;
  final double pageWidthPt;
  final double pageHeightPt;

  @override
  void paint(Canvas canvas, Size size) {
    final state = preview.value;
    if (state == null || !state.appliesTo(page1Based)) return;
    paintWatermarkMarks(
      canvas,
      size,
      spec: state.spec,
      pageWidthPt: pageWidthPt,
      pageHeightPt: pageHeightPt,
      text: state.textFor(page1Based),
      image: state.image,
    );
  }

  @override
  bool shouldRepaint(covariant _ThumbWatermarkPainter old) =>
      old.preview != preview ||
      old.page1Based != page1Based ||
      old.pageWidthPt != pageWidthPt ||
      old.pageHeightPt != pageHeightPt;
}
