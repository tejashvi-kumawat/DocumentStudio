import 'package:document_studio/design_system/shell/ds_tool_chrome.dart';

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio/app/tree_unlock.dart';
import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_shell_page.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_layout.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_spec.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_tokens.dart';
import 'package:document_studio/features/document_lifecycle/document_save_result_actions.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/pdf_markup/header_footer/hf_controller.dart';
import 'package:document_studio/features/pdf_markup/header_footer/hf_editor.dart';
import 'package:document_studio/features/pdf_markup/header_footer/hf_preview_painter.dart';
import 'package:document_studio/features/pdf_viewer/widgets/pdf_text_option_controls.dart';
import 'package:document_studio/features/pdf_markup/header_footer/hf_panel_parts.dart';
import 'package:document_studio/features/pdf_markup/headers_footers_screen.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/infrastructure/pdf/stamp/pdf_stamp_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _defaultPageNumberSpec = HeaderFooterSpec(
  zones: {
    HfZone.footerCenter: HfZoneStyle(
      text: '{page}',
      sizePt: 10,
      colorRgb: 0x1F2937,
    ),
  },
);

/// Quick number formats (templates for the shared header/footer engine).
const _formats = <(String, String)>[
  ('1', '{page}'),
  ('Page 1', 'Page {page}'),
  ('Page 1 of N', 'Page {page} of {pages}'),
  ('1 / N', '{page} / {pages}'),
  ('– 1 –', '– {page} –'),
  ('Bates', '{bates}'),
];

/// Page numbers: a focused preset of the header & footer engine (same layout,
/// same writer, same live page preview), stamped as its own `PageNumbers`
/// family so it can live alongside a header/footer and be replaced/removed.
class PageNumbersScreen extends ConsumerStatefulWidget {
  const PageNumbersScreen({
    super.key,
    this.initialFile,
    this.initialPassword,
    this.embedInViewerPanel = false,
  });

  final LocalFileRef? initialFile;
  final String? initialPassword;
  final bool embedInViewerPanel;

  @override
  ConsumerState<PageNumbersScreen> createState() => _PageNumbersScreenState();
}

class _PageNumbersScreenState extends ConsumerState<PageNumbersScreen> {
  final _ctrl = HeaderFooterController(
    kind: PdfStampKind.pageNumbers,
    defaultSpec: _defaultPageNumberSpec,
  );
  final _formatCtrl = TextEditingController();
  final _formatFocus = FocusNode();
  LocalFileRef? _file;
  String? _password;
  int _page = 1;
  int _revision = 0;
  ViewerLiveToolSession? _live;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChanged);
    if (widget.embedInViewerPanel) {
      _live = ref.read(viewerLiveToolSessionProvider);
    }
    final file = widget.initialFile;
    if (file != null) {
      _file = file;
      final pw = widget.initialPassword;
      if (pw != null && pw.isNotEmpty) _password = pw;
      unawaited(_ctrl.load(file));
    }
  }

  @override
  void dispose() {
    final live = _live;
    final pushed = live?.headerFooterPreviewNotifier.value;
    if (live != null) {
      runWhenTreeUnlocked(() {
        if (identical(live.headerFooterPreviewNotifier.value, pushed)) {
          live.setHeaderFooterPagePreview(null);
        }
      });
    }
    _ctrl.removeListener(_onChanged);
    _ctrl.dispose();
    _formatCtrl.dispose();
    _formatFocus.dispose();
    super.dispose();
  }

  void _onChanged() {
    final live = _live;
    if (live != null) {
      final ready = _ctrl.document != null && !_ctrl.loading;
      live.setHeaderFooterPagePreview(
        ready ? _ctrl.previewState(_file, showFocus: false) : null,
      );
    }
    if (!_formatFocus.hasFocus && _formatCtrl.text != _style.text) {
      _formatCtrl.text = _style.text;
    }
    if (mounted) setState(() {});
  }

  HeaderFooterSpec get _spec => _ctrl.spec;

  HfZone get _zone => HfZone.values.firstWhere(
    (z) => !_spec.zone(z).isEmpty,
    orElse: () => HfZone.footerCenter,
  );

  HfZoneStyle get _style {
    final s = _spec.zone(_zone);
    return s.isEmpty ? _defaultPageNumberSpec.zone(HfZone.footerCenter) : s;
  }

  void _set({HfZone? zone, HfZoneStyle? style}) {
    _ctrl.update(_spec.copyWith(zones: {zone ?? _zone: style ?? _style}));
  }

  void _setText(String text) => _set(style: _style.copyWith(text: text));

  Future<void> _pick() async {
    final picked = await ref
        .read(fileStorageProvider)
        .pickOpenFile(allowedExtensions: ['pdf']);
    if (picked == null) return;
    setState(() {
      _file = picked;
      _password = null;
      _page = 1;
      _revision++;
    });
    await _ctrl.load(picked);
  }

  Future<void> _apply() async {
    final file = _file;
    if (file == null) return;
    try {
      final bytes = await _ctrl.applyToBytes(file);
      await _deliver(
        bytes,
        'numbered-${file.displayName}',
        'Page numbers applied.',
      );
    } on DocumentStudioError catch (e) {
      _snack(e.recoveryHint ?? e.message);
    } catch (e) {
      _snack('Could not add page numbers: $e');
    }
  }

  Future<void> _remove() async {
    final file = _file;
    if (file == null || !await confirmHfRemove(context, noun: 'page numbers')) {
      return;
    }
    try {
      final bytes = await _ctrl.removeToBytes(file);
      await _deliver(
        bytes,
        'clean-${file.displayName}',
        'Page numbers removed.',
      );
    } on DocumentStudioError catch (e) {
      _snack(e.recoveryHint ?? e.message);
    } catch (e) {
      _snack('Could not remove page numbers: $e');
    }
  }

  Future<void> _deliver(
    Uint8List bytes,
    String suggested,
    String message,
  ) async {
    final storage = ref.read(fileStorageProvider);
    if (widget.embedInViewerPanel) {
      final tabs = ref.read(documentTabsControllerProvider);
      final session = tabs.activeSession;
      if (session == null || !mounted) return;
      final saved = await commitBytesToSession(
        context: context,
        storage: storage,
        tabs: tabs,
        session: session,
        bytes: bytes,
        successMessage: message,
      );
      if (saved != null && mounted) {
        _file = saved;
        await _ctrl.refresh(saved);
      }
      return;
    }
    final path = await storage.pickSavePath(
      suggestedName: suggested,
      bytes: bytes,
      allowedExtensions: const ['pdf'],
      mimeType: 'application/pdf',
    );
    if (path == null) return;
    await storage.writeAtomic(
      destinationPath: path,
      writeToTemp: (temp) => File(temp).writeAsBytes(bytes, flush: true),
    );
    if (!mounted) return;
    final out = LocalFileRef(
      path: path,
      displayName: path.split(Platform.pathSeparator).last,
    );
    showDocumentSaveResultActions(
      context,
      file: out,
      password: _password,
      message: 'Saved ${out.displayName}',
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------ UI

  Widget _label(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(top: DsSpacing.md, bottom: DsSpacing.xs),
    child: Text(
      text,
      style: theme.textTheme.labelLarge?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _options(ThemeData theme) {
    final enabled = !_ctrl.busy;
    final style = _style;
    final spec = _spec;
    final muted = theme.textTheme.bodySmall?.copyWith(
      fontSize: 11.5,
      color: DsColors.textSecondary(theme.brightness),
    );
    final sample = resolveHfTemplate(
      style.text,
      spec: spec,
      doc: _ctrl.docInfo(_file),
      page: HfPageContext(page1Based: 1, batesValue: spec.bates.start),
    );
    final rangeInvalid =
        spec.range == HfPageRange.custom &&
        parseHfPageRange(spec.customRange, _ctrl.pageCount) == null;
    return ListView(
      padding: const EdgeInsets.all(DsSpacing.pagePaddingCompact),
      children: [
        if (widget.embedInViewerPanel)
          Text(
            'Previewed live on the pages — exactly what Apply writes.',
            style: muted,
          ),
        const SizedBox(height: DsSpacing.sm),
        HfExistingBanner(
          controller: _ctrl,
          onRemove: _remove,
          noun: 'page numbers',
        ),
        const PdfOptionHeading('Text', first: true),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (label, template) in _formats)
              ChoiceChip(
                label: Text(label, style: const TextStyle(fontSize: 12)),
                selected: style.text == template,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                selectedColor: DsColors.primary.withValues(alpha: 0.14),
                onSelected: enabled ? (_) => _setText(template) : null,
              ),
          ],
        ),
        const SizedBox(height: DsSpacing.sm),
        TextField(
          controller: _formatCtrl,
          focusNode: _formatFocus,
          enabled: enabled,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            labelText: 'Custom format',
            helperText: 'Tokens: {page} {pages} {bates} {date} {file}',
            errorText: validateHfTemplate(style.text).firstOrNull,
          ),
          onChanged: _setText,
        ),
        const SizedBox(height: DsSpacing.xs),
        Text('Sample on page 1: $sample', style: muted),
        const SizedBox(height: DsSpacing.sm),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<HfNumberStyle>(
                key: ValueKey('ns-${spec.numberStyle}'),
                initialValue: spec.numberStyle,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Style',
                ),
                items: [
                  for (final s in HfNumberStyle.values)
                    DropdownMenuItem(
                      value: s,
                      child: Text(
                        s.label,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                ],
                onChanged: enabled
                    ? (s) {
                        if (s != null) {
                          _ctrl.update(spec.copyWith(numberStyle: s));
                        }
                      }
                    : null,
              ),
            ),
            const SizedBox(width: DsSpacing.sm),
            SizedBox(
              width: 96,
              child: _NumberField(
                label: 'Start at',
                value: style.text.contains('{bates')
                    ? spec.bates.start
                    : spec.startNumber,
                enabled: enabled,
                onChanged: (v) => _ctrl.update(
                  style.text.contains('{bates')
                      ? spec.copyWith(bates: spec.bates.copyWith(start: v))
                      : spec.copyWith(startNumber: v),
                ),
              ),
            ),
          ],
        ),
        AnimatedSize(
          duration: DsMotion.switchDuration,
          curve: DsMotion.switchCurve,
          alignment: Alignment.topCenter,
          child: !style.text.contains('{bates')
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: DsSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: _TextField(
                          label: 'Prefix',
                          value: spec.bates.prefix,
                          enabled: enabled,
                          onChanged: (v) => _ctrl.update(
                            spec.copyWith(
                              bates: spec.bates.copyWith(prefix: v),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: DsSpacing.sm),
                      Expanded(
                        child: _TextField(
                          label: 'Suffix',
                          value: spec.bates.suffix,
                          enabled: enabled,
                          onChanged: (v) => _ctrl.update(
                            spec.copyWith(
                              bates: spec.bates.copyWith(suffix: v),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: DsSpacing.sm),
                      SizedBox(
                        width: 72,
                        child: _NumberField(
                          label: 'Digits',
                          value: spec.bates.digits,
                          min: 1,
                          max: 15,
                          enabled: enabled,
                          onChanged: (v) => _ctrl.update(
                            spec.copyWith(
                              bates: spec.bates.copyWith(digits: v),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: DsSpacing.sm),
        PdfStandardFontField(
          font: style.font,
          onChanged: enabled
              ? (font) => _set(style: style.copyWith(font: font))
              : null,
        ),
        Row(
          children: [
            Text(
              'Size',
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
            ),
            Expanded(
              child: Slider(
                value: style.sizePt.clamp(6, 36),
                min: 6,
                max: 36,
                divisions: 60,
                activeColor: DsColors.primary,
                label: '${style.sizePt.toStringAsFixed(1)} pt',
                onChanged: enabled
                    ? (v) => _set(
                        style: style.copyWith(sizePt: (v * 2).round() / 2),
                      )
                    : null,
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(
                '${style.sizePt.toStringAsFixed(style.sizePt % 1 == 0 ? 0 : 1)} pt',
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
        PdfTextAlignGroup<HfAlign>(
          value: _zone.align,
          left: HfAlign.left,
          center: HfAlign.center,
          right: HfAlign.right,
          onChanged: enabled
              ? (align) {
                  final next = HfZone.values.firstWhere(
                    (z) => z.isHeader == _zone.isHeader && z.align == align,
                  );
                  if (next != _zone) _set(zone: next);
                }
              : null,
        ),
        const PdfOptionHeading('Appearance'),
        PdfCompactColorPicker<int>(
          colors: hfPalette.take(8).toList(),
          selected: style.colorRgb,
          swatch: hfColor,
          onChanged: enabled
              ? (c) {
                  if (c != null) _set(style: style.copyWith(colorRgb: c));
                }
              : null,
        ),
        const PdfOptionHeading('Position'),
        _ZoneGrid(
          selected: _zone,
          enabled: enabled,
          onSelect: (z) => _set(zone: z),
        ),
        const SizedBox(height: DsSpacing.sm),
        Text(
          'Page range',
          style: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
        ),
        const SizedBox(height: DsSpacing.xs),
        SegmentedButton<HfPageRange>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            for (final r in HfPageRange.values)
              ButtonSegment(
                value: r,
                label: Text(r.label, style: const TextStyle(fontSize: 12)),
              ),
          ],
          selected: {spec.range},
          onSelectionChanged: enabled
              ? (s) => _ctrl.update(spec.copyWith(range: s.first))
              : null,
        ),
        AnimatedSize(
          duration: DsMotion.switchDuration,
          curve: DsMotion.switchCurve,
          alignment: Alignment.topCenter,
          child: spec.range != HfPageRange.custom
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: DsSpacing.sm),
                  child: _TextField(
                    label: 'Pages (e.g. 1-3, 5, 8-)',
                    value: spec.customRange,
                    enabled: enabled,
                    errorText: rangeInvalid ? 'Invalid range' : null,
                    onChanged: (v) =>
                        _ctrl.update(spec.copyWith(customRange: v)),
                  ),
                ),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Skip first page', style: TextStyle(fontSize: 13)),
          value: spec.skipFirstPage,
          activeTrackColor: DsColors.primary,
          onChanged: enabled
              ? (v) => _ctrl.update(spec.copyWith(skipFirstPage: v))
              : null,
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text(
            'Alternate left/right (book)',
            style: TextStyle(fontSize: 13),
          ),
          value: spec.mirrorOnEvenPages,
          activeTrackColor: DsColors.primary,
          onChanged: enabled
              ? (v) => _ctrl.update(spec.copyWith(mirrorOnEvenPages: v))
              : null,
        ),
        _label(theme, 'Margins'),
        Row(
          children: [
            Expanded(
              child: _NumberField(
                label: _zone.isHeader ? 'From top' : 'From bottom',
                suffix: 'pt',
                value: (_zone.isHeader ? spec.margins.top : spec.margins.bottom)
                    .round(),
                max: 288,
                enabled: enabled,
                onChanged: (v) => _ctrl.update(
                  spec.copyWith(
                    margins: _zone.isHeader
                        ? spec.margins.copyWith(top: v.toDouble())
                        : spec.margins.copyWith(bottom: v.toDouble()),
                  ),
                ),
              ),
            ),
            const SizedBox(width: DsSpacing.sm),
            Expanded(
              child: _NumberField(
                label: 'Sides',
                suffix: 'pt',
                value: spec.margins.left.round(),
                max: 288,
                enabled: enabled,
                onChanged: (v) => _ctrl.update(
                  spec.copyWith(
                    margins: spec.margins.copyWith(
                      left: v.toDouble(),
                      right: v.toDouble(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: DsSpacing.lg),
      ],
    );
  }

  Widget _editor(ThemeData theme) {
    final file = _file;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!(widget.embedInViewerPanel && file != null))
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DsSpacing.md,
              DsSpacing.md,
              DsSpacing.md,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    file?.displayName ?? 'No PDF selected',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
                  ),
                ),
                DsSecondaryButton(
                  label: file == null ? 'Choose PDF' : 'Change',
                  icon: Icons.folder_open,
                  onPressed: _ctrl.busy ? null : _pick,
                ),
              ],
            ),
          ),
        Expanded(child: _options(theme)),
        HfActionBar(
          controller: _ctrl,
          applyLabel: file == null
              ? 'Choose a PDF first'
              : widget.embedInViewerPanel
              ? 'Apply'
              : 'Apply & save as…',
          onApply: () => unawaited(_apply()),
        ),
      ],
    );
  }

  Widget _preview() {
    final file = _file;
    if (file == null) {
      return DsEmptyState(
        title: 'Choose a PDF to preview',
        subtitle: 'Page numbers preview on your real pages.',
        action: DsPrimaryButton(
          label: 'Choose PDF',
          icon: Icons.folder_open,
          onPressed: _pick,
        ),
      );
    }
    return HfPagePreview(
      key: ValueKey('${file.path}#$_revision'),
      file: file,
      password: _password,
      page: _page,
      pageCount: _ctrl.pageCount,
      state: _ctrl.previewState(file, showGuides: true, showFocus: false),
      onPage: (p) => setState(() => _page = p),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = LayoutBuilder(
      builder: (context, c) {
        if (widget.embedInViewerPanel) return _editor(theme);
        // Android / phone: always stack — never desktop side-by-side.
        if (dsUseCompactToolLayout(context) || c.maxWidth < 820) {
          return Column(
            children: [
              SizedBox(
                height: math.min(360, c.maxHeight * 0.42),
                child: _preview(),
              ),
              const Divider(height: 1),
              Expanded(child: _editor(theme)),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 360, child: _editor(theme)),
            const VerticalDivider(width: 1),
            Expanded(child: _preview()),
          ],
        );
      },
    );
    if (widget.embedInViewerPanel) return body;
    return Scaffold(
      appBar: DsToolAppBar(
        title: 'Page numbers',
        subtitle: 'Number the pages of your PDF',
        icon: Icons.pin_outlined,
        backEnabled: !_ctrl.busy,
      ),
      body: SafeArea(top: false, child: DsMotion.fadeRiseIn(child: body)),
    );
  }
}

/// Mini page with the six header/footer slots.
class _ZoneGrid extends StatelessWidget {
  const _ZoneGrid({
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  final HfZone selected;
  final bool enabled;
  final ValueChanged<HfZone> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(List<HfZone> zones) => Row(
      children: [
        for (final z in zones)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: _ZoneCell(
                zone: z,
                selected: z == selected,
                onTap: enabled ? () => onSelect(z) : null,
              ),
            ),
          ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: DsColors.groupedBackground(theme.brightness),
        borderRadius: BorderRadius.circular(DsSpacing.radiusGrouped),
        border: Border.all(color: DsColors.borderLight),
      ),
      child: Column(
        children: [
          row(const [
            HfZone.headerLeft,
            HfZone.headerCenter,
            HfZone.headerRight,
          ]),
          const SizedBox(height: 18),
          row(const [
            HfZone.footerLeft,
            HfZone.footerCenter,
            HfZone.footerRight,
          ]),
        ],
      ),
    );
  }
}

class _ZoneCell extends StatelessWidget {
  const _ZoneCell({required this.zone, required this.selected, this.onTap});

  final HfZone zone;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final align = switch (zone.align) {
      HfAlign.left => Alignment.centerLeft,
      HfAlign.center => Alignment.center,
      HfAlign.right => Alignment.centerRight,
    };
    return Tooltip(
      message: zone.label,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: AnimatedContainer(
          duration: DsMotion.hoverDuration,
          curve: DsMotion.switchCurve,
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: align,
          decoration: BoxDecoration(
            color: selected
                ? DsColors.primary.withValues(alpha: 0.12)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? DsColors.primary : DsColors.borderLight,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            '#',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? DsColors.primary : Colors.black38,
            ),
          ),
        ),
      ),
    );
  }
}

/// Integer field that commits valid values and keeps typing stable.
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 999999,
    this.suffix,
    this.enabled = true,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final String? suffix;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final _ctrl = TextEditingController(text: '${widget.value}');
  final _focus = FocusNode();

  @override
  void didUpdateWidget(covariant _NumberField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _ctrl.text != '${widget.value}') {
      _ctrl.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      focusNode: _focus,
      enabled: widget.enabled,
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        labelText: widget.label,
        suffixText: widget.suffix,
      ),
      onChanged: (v) {
        final n = int.tryParse(v.trim());
        if (n != null && n >= widget.min && n <= widget.max) {
          widget.onChanged(n);
        }
      },
    );
  }
}

class _TextField extends StatefulWidget {
  const _TextField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.errorText,
  });

  final String label;
  final String value;
  final bool enabled;
  final String? errorText;
  final ValueChanged<String> onChanged;

  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late final _ctrl = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void didUpdateWidget(covariant _TextField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _ctrl.text != widget.value) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      focusNode: _focus,
      enabled: widget.enabled,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        labelText: widget.label,
        errorText: widget.errorText,
      ),
      onChanged: widget.onChanged,
    );
  }
}
