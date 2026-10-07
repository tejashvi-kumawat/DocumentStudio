import 'dart:math' as math;

import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_shell_page.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_scaffold.dart';
import 'package:document_studio/features/pdf_viewer/widgets/pdf_text_option_controls.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_layout.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_spec.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_templates.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_tokens.dart';
import 'package:document_studio/features/pdf_markup/header_footer/hf_preview_painter.dart';
import 'package:document_studio/features/pdf_markup/header_footer/hf_template_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const hfPalette = <int>[
  0x1F2937,
  0x6B7280,
  0x000000,
  0x1E3A5F,
  0x0066CC,
  0xC62828,
  0xD97706,
  0x2E7D32,
  0xFFFFFF,
];

const _bandPalette = <int>[
  0xC62828,
  0x1E3A5F,
  0x111827,
  0xE8EEF6,
  0xFEF3C7,
  0xF3F4F6,
];

/// Acrobat-style six-zone header & footer editor (options only; the preview
/// is painted by the host on real pages).
class HeaderFooterEditor extends StatefulWidget {
  const HeaderFooterEditor({
    super.key,
    required this.spec,
    required this.onChanged,
    required this.focusZone,
    required this.onFocusZone,
    required this.doc,
    required this.customTemplates,
    required this.onDeleteTemplate,
    this.enabled = true,
    this.padding = const EdgeInsets.all(DsSpacing.lg),
    this.header,
    this.footer,
  });

  final HeaderFooterSpec spec;
  final ValueChanged<HeaderFooterSpec> onChanged;
  final HfZone focusZone;
  final ValueChanged<HfZone> onFocusZone;
  final HfDocInfo doc;
  final List<HfTemplate> customTemplates;
  final Future<List<HfTemplate>> Function(String id) onDeleteTemplate;
  final bool enabled;
  final EdgeInsets padding;

  /// Extra content above / below the options (banners, actions).
  final Widget? header;
  final Widget? footer;

  @override
  State<HeaderFooterEditor> createState() => _HeaderFooterEditorState();
}

class _HeaderFooterEditorState extends State<HeaderFooterEditor> {
  late final Map<HfZone, TextEditingController> _ctrls = {
    for (final z in HfZone.values)
      z: TextEditingController(text: widget.spec.zone(z).text),
  };
  late final Map<HfZone, FocusNode> _focus = {
    for (final z in HfZone.values) z: FocusNode(),
  };
  String? _appliedTemplateId;
  final Set<String> _open = {};

  HeaderFooterSpec get spec => widget.spec;

  @override
  void didUpdateWidget(covariant HeaderFooterEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final z in HfZone.values) {
      final text = spec.zone(z).text;
      final c = _ctrls[z]!;
      if (c.text != text) {
        c.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _emit(HeaderFooterSpec next) {
    _appliedTemplateId = null;
    widget.onChanged(next);
  }

  void _setZone(HfZone z, HfZoneStyle style) => _emit(spec.withZone(z, style));

  void _insertToken(String token) {
    final z = widget.focusZone;
    final c = _ctrls[z]!;
    final sel = c.selection;
    final text = c.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final next = text.replaceRange(start, end, token);
    c.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    _setZone(z, spec.zone(z).copyWith(text: next));
    _focus[z]!.requestFocus();
  }

  void _applyTemplate(HfTemplate t) {
    // Keep the user's page range: a template is a look, not a scope.
    final next = t.spec.copyWith(
      range: spec.range,
      customRange: spec.customRange,
      skipFirstPage: t.spec.skipFirstPage || spec.skipFirstPage,
    );
    widget.onChanged(next);
    setState(() => _appliedTemplateId = t.id);
    final firstZone = HfZone.values.firstWhere(
      (z) => !next.zone(z).isEmpty,
      orElse: () => HfZone.footerCenter,
    );
    widget.onFocusZone(firstZone);
  }

  Future<void> _openGallery() async {
    final picked = await showHfTemplateGallery(
      context,
      custom: widget.customTemplates,
      onDelete: widget.onDeleteTemplate,
    );
    if (picked != null && mounted) _applyTemplate(picked);
  }

  String _sample(String template) {
    return resolveHfTemplate(
      template,
      spec: spec,
      doc: widget.doc,
      page: HfPageContext(page1Based: 1, batesValue: spec.bates.start),
    ).replaceAll('\n', ' · ');
  }

  bool _stacks(double width) => viewerToolFormStacks(context, width);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = dsUseCompactToolLayout(context);
    final gutter = math.max(
      compact ? DsSpacing.pagePaddingCompact : DsSpacing.xl,
      widget.padding.left,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final cap = compact
            ? constraints.maxWidth
            : math.min(constraints.maxWidth, DsSpacing.formMaxWidth);
        final side = math.max(0.0, (constraints.maxWidth - cap) / 2);
        return ListView(
          padding: EdgeInsets.fromLTRB(
            side + gutter,
            gutter,
            side + gutter,
            DsSpacing.lg,
          ),
          children: _editorChildren(theme),
        );
      },
    );
  }

  List<Widget> _editorChildren(ThemeData theme) {
    return [
      ?widget.header,
      _templatesStrip(theme),
      const SizedBox(height: DsSpacing.md),
      _label(theme, 'Position', trailing: _zoneCountBadge(theme)),
      _ZonePicker(
        spec: spec,
        focus: widget.focusZone,
        sample: _sample,
        onSelect: (z) {
          widget.onFocusZone(z);
          _focus[z]!.requestFocus();
        },
      ),
      const SizedBox(height: DsSpacing.sm),
      AnimatedSwitcher(
        duration: DsMotion.switchDuration,
        switchInCurve: DsMotion.switchCurve,
        switchOutCurve: DsMotion.switchCurve,
        transitionBuilder: (child, anim) =>
            DsMotion.fadeRiseTransition(anim, child, risePx: 4),
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, ?current],
        ),
        child: KeyedSubtree(
          key: ValueKey(widget.focusZone),
          child: _zoneEditor(theme, widget.focusZone),
        ),
      ),
      const SizedBox(height: DsSpacing.md),
      _section(
        theme,
        id: 'numbers',
        icon: Icons.format_list_numbered,
        title: 'Numbering, date & time',
        summary:
            '${spec.numberStyle.label} · starts at ${spec.startNumber} · ${hfFormatDate(DateTime.now(), spec.dateFormat)}',
        child: _numberingSection(theme),
      ),
      _section(
        theme,
        id: 'bates',
        icon: Icons.gavel_outlined,
        title: 'Bates numbering',
        summary: spec.usesBates
            ? spec.bates.format(spec.bates.start)
            : 'Insert {bates} into a zone to use',
        child: _batesSection(theme),
      ),
      _section(
        theme,
        id: 'pages',
        icon: Icons.filter_none,
        title: 'Page range',
        summary: _rangeSummary(),
        child: _rangeSection(theme),
      ),
      _section(
        theme,
        id: 'margins',
        icon: Icons.border_outer,
        title: 'Margins',
        summary:
            'T ${spec.margins.top.round()} · B ${spec.margins.bottom.round()} · L ${spec.margins.left.round()} · R ${spec.margins.right.round()} pt',
        child: _marginsSection(theme),
      ),
      _section(
        theme,
        id: 'appearance',
        icon: Icons.palette_outlined,
        title: 'Rules & bands',
        summary: _appearanceSummary(),
        child: _appearanceSection(theme),
      ),
      ?widget.footer,
    ];
  }

  Widget _zoneCountBadge(ThemeData theme) {
    final n = HfZone.values.where((z) => !spec.zone(z).isEmpty).length;
    return AnimatedSwitcher(
      duration: DsMotion.switchDuration,
      child: Text(
        n == 0 ? 'none used' : '$n of 6 used',
        key: ValueKey(n),
        style: theme.textTheme.bodySmall?.copyWith(
          color: DsColors.textSecondary(theme.brightness),
        ),
      ),
    );
  }

  String _rangeSummary() {
    final base = switch (spec.range) {
      HfPageRange.all => 'All pages',
      HfPageRange.odd => 'Odd pages',
      HfPageRange.even => 'Even pages',
      HfPageRange.custom =>
        spec.customRange.trim().isEmpty
            ? 'Custom'
            : 'Pages ${spec.customRange}',
    };
    final extras = [
      if (spec.skipFirstPage) 'skip first',
      if (spec.mirrorOnEvenPages) 'mirrored',
    ];
    return extras.isEmpty ? base : '$base · ${extras.join(' · ')}';
  }

  String _appearanceSummary() {
    final parts = [
      if (spec.header.ruleEnabled) 'header rule',
      if (spec.footer.ruleEnabled) 'footer rule',
      if (spec.header.bandRgb != null) 'header band',
      if (spec.footer.bandRgb != null) 'footer band',
    ];
    return parts.isEmpty ? 'None' : parts.join(' · ');
  }

  Widget _label(ThemeData theme, String text, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: DsSpacing.xs),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );

  Widget _templatesStrip(ThemeData theme) {
    final items = [...widget.customTemplates, ...builtInHfTemplates];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(
          theme,
          'Templates',
          trailing: TextButton.icon(
            onPressed: widget.enabled ? _openGallery : null,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: DsColors.primary,
            ),
            icon: const Icon(Icons.grid_view_rounded, size: 16),
            label: const Text('Browse all'),
          ),
        ),
        SizedBox(
          height: 128,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final t = items[i];
              final selected = _appliedTemplateId == t.id;
              return Tooltip(
                message: t.description,
                waitDuration: const Duration(milliseconds: 500),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: widget.enabled ? () => _applyTemplate(t) : null,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Column(
                      children: [
                        HfTemplateThumb(
                          spec: t.spec,
                          width: 72,
                          selected: selected,
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 76,
                          child: Text(
                            t.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: selected ? DsColors.primary : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _zoneEditor(ThemeData theme, HfZone z) {
    final style = spec.zone(z);
    final issues = validateHfTemplate(style.text);
    return Container(
      padding: const EdgeInsets.all(DsSpacing.sm + 2),
      decoration: BoxDecoration(
        color: DsColors.groupedBackground(theme.brightness),
        borderRadius: BorderRadius.circular(DsSpacing.radiusGrouped),
        border: Border.all(color: DsColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                z.isHeader
                    ? Icons.vertical_align_top
                    : Icons.vertical_align_bottom,
                size: 16,
                color: DsColors.primary,
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(z.label, style: theme.textTheme.titleSmall)),
              if (!style.isEmpty)
                IconButton(
                  tooltip: 'Clear zone',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: widget.enabled
                      ? () => _setZone(z, style.copyWith(text: ''))
                      : null,
                  icon: const Icon(Icons.backspace_outlined),
                ),
              _TokenMenu(enabled: widget.enabled, onPick: _insertToken),
            ],
          ),
          const PdfOptionHeading('Text', first: true),
          TextField(
            controller: _ctrls[z],
            focusNode: _focus[z],
            enabled: widget.enabled,
            minLines: 1,
            maxLines: 3,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              filled: true,
              fillColor: theme.colorScheme.surface,
              hintText: 'Type text or insert tokens…',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              errorText: issues.isEmpty ? null : issues.first,
            ),
            onChanged: (v) => _setZone(z, style.copyWith(text: v)),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final t in const [
                ('Page', '{page}'),
                ('Page X of Y', 'Page {page} of {pages}'),
                ('Date', '{date}'),
                ('File', '{file}'),
                ('Title', '{title}'),
                ('Bates', '{bates}'),
              ])
                ActionChip(
                  label: Text(t.$1),
                  onPressed: widget.enabled ? () => _insertToken(t.$2) : null,
                ),
            ],
          ),
          AnimatedSize(
            duration: DsMotion.switchDuration,
            curve: DsMotion.switchCurve,
            alignment: Alignment.topCenter,
            child: style.isEmpty
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Preview: ${_sample(style.text)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: DsColors.textSecondary(theme.brightness),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: DsSpacing.sm),
          PdfStandardFontField(
            font: style.font,
            onChanged: widget.enabled
                ? (font) => _setZone(z, style.copyWith(font: font))
                : null,
          ),
          const SizedBox(height: DsSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: _SizeStepper(
              value: style.sizePt,
              enabled: widget.enabled,
              onChanged: (v) => _setZone(z, style.copyWith(sizePt: v)),
            ),
          ),
          const SizedBox(height: DsSpacing.sm),
          PdfTextAlignGroup<HfAlign>(
            value: z.align,
            left: HfAlign.left,
            center: HfAlign.center,
            right: HfAlign.right,
            onChanged: widget.enabled
                ? (align) {
                    final next = HfZone.values.firstWhere(
                      (zone) =>
                          zone.isHeader == z.isHeader && zone.align == align,
                    );
                    widget.onFocusZone(next);
                    _focus[next]!.requestFocus();
                  }
                : null,
          ),
          const PdfOptionHeading('Appearance'),
          PdfCompactColorPicker<int>(
            colors: hfPalette,
            selected: style.colorRgb,
            swatch: hfColor,
            onChanged: widget.enabled
                ? (c) {
                    if (c != null) _setZone(z, style.copyWith(colorRgb: c));
                  }
                : null,
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: widget.enabled
                  ? () {
                      final zones = {
                        for (final other in HfZone.values)
                          other: spec
                              .zone(other)
                              .copyWith(
                                font: style.font,
                                sizePt: style.sizePt,
                                colorRgb: style.colorRgb,
                              ),
                      };
                      _emit(spec.copyWith(zones: zones));
                    }
                  : null,
              icon: const Icon(Icons.format_paint_outlined, size: 16),
              label: const Text('Use this style for all zones'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(
    ThemeData theme, {
    required String id,
    required IconData icon,
    required String title,
    required String summary,
    required Widget child,
  }) {
    final open = _open.contains(id);
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpacing.sm),
      child: AnimatedContainer(
        duration: DsMotion.switchDuration,
        curve: DsMotion.switchCurve,
        decoration: BoxDecoration(
          color: open
              ? DsColors.groupedBackground(theme.brightness)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(DsSpacing.radiusGrouped),
          border: Border.all(
            color: open
                ? DsColors.primary.withValues(alpha: 0.35)
                : DsColors.borderLight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(DsSpacing.radiusGrouped),
              onTap: () =>
                  setState(() => open ? _open.remove(id) : _open.add(id)),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DsSpacing.lg,
                  vertical: DsSpacing.md,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: open ? DsColors.primary : null),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: DsColors.textSecondary(theme.brightness),
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: DsMotion.switchDuration,
                      curve: DsMotion.switchCurve,
                      child: const Icon(Icons.expand_more, size: 20),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: DsMotion.switchDuration,
              curve: DsMotion.switchCurve,
              alignment: Alignment.topCenter,
              child: open
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(
                        DsSpacing.lg,
                        0,
                        DsSpacing.lg,
                        DsSpacing.lg,
                      ),
                      child: child,
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberingSection(ThemeData theme) {
    final now = DateTime.now();
    final styleField = DropdownButtonFormField<HfNumberStyle>(
      initialValue: spec.numberStyle,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Number style',
        border: OutlineInputBorder(),
      ),
      items: [
        for (final s in HfNumberStyle.values)
          DropdownMenuItem(value: s, child: Text(s.label)),
      ],
      onChanged: widget.enabled
          ? (s) => s == null ? null : _emit(spec.copyWith(numberStyle: s))
          : null,
    );
    final startField = _IntField(
      label: 'Start at',
      value: spec.startNumber,
      min: 0,
      enabled: widget.enabled,
      onChanged: (v) => _emit(spec.copyWith(startNumber: v)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (_stacks(constraints.maxWidth)) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  styleField,
                  const SizedBox(height: DsSpacing.lg),
                  startField,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: styleField),
                const SizedBox(width: DsSpacing.lg),
                Expanded(flex: 2, child: startField),
              ],
            );
          },
        ),
        const SizedBox(height: DsSpacing.lg),
        DropdownButtonFormField<String>(
          initialValue: hfDateFormats.contains(spec.dateFormat)
              ? spec.dateFormat
              : hfDateFormats.first,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Date format {date}',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final f in hfDateFormats)
              DropdownMenuItem(
                value: f,
                child: Text('${hfFormatDate(now, f)}   ($f)'),
              ),
          ],
          onChanged: widget.enabled
              ? (f) => f == null ? null : _emit(spec.copyWith(dateFormat: f))
              : null,
        ),
        const SizedBox(height: DsSpacing.lg),
        DropdownButtonFormField<String>(
          initialValue: hfTimeFormats.contains(spec.timeFormat)
              ? spec.timeFormat
              : hfTimeFormats.first,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Time format {time}',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final f in hfTimeFormats)
              DropdownMenuItem(
                value: f,
                child: Text('${hfFormatDate(now, f)}   ($f)'),
              ),
          ],
          onChanged: widget.enabled
              ? (f) => f == null ? null : _emit(spec.copyWith(timeFormat: f))
              : null,
        ),
        const SizedBox(height: 6),
        Text(
          'Tip: {date:yyyy} or {time:h:mm a} override the format inline.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: DsColors.textSecondary(theme.brightness),
          ),
        ),
      ],
    );
  }

  Widget _batesSection(ThemeData theme) {
    final b = spec.bates;
    final prefix = _TextSetting(
      label: 'Prefix',
      value: b.prefix,
      enabled: widget.enabled,
      onChanged: (v) => _emit(spec.copyWith(bates: b.copyWith(prefix: v))),
    );
    final suffix = _TextSetting(
      label: 'Suffix',
      value: b.suffix,
      enabled: widget.enabled,
      onChanged: (v) => _emit(spec.copyWith(bates: b.copyWith(suffix: v))),
    );
    final start = _IntField(
      label: 'Start number',
      value: b.start,
      min: 0,
      enabled: widget.enabled,
      onChanged: (v) => _emit(spec.copyWith(bates: b.copyWith(start: v))),
    );
    final digits = _IntField(
      label: 'Digits',
      value: b.digits,
      min: 1,
      max: 15,
      enabled: widget.enabled,
      onChanged: (v) => _emit(spec.copyWith(bates: b.copyWith(digits: v))),
    );
    Widget pair(Widget left, Widget right) {
      return LayoutBuilder(
        builder: (context, constraints) {
          if (_stacks(constraints.maxWidth)) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                left,
                const SizedBox(height: DsSpacing.lg),
                right,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: DsSpacing.lg),
              Expanded(child: right),
            ],
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pair(prefix, suffix),
        const SizedBox(height: DsSpacing.lg),
        pair(start, digits),
        const SizedBox(height: DsSpacing.md),
        Text(
          'Sample: ${b.format(b.start)} … ${b.format(b.start + math.max(0, widget.doc.pageCount - 1))}',
          style: theme.textTheme.bodyLarge?.copyWith(fontFamily: 'monospace'),
        ),
        if (!spec.usesBates)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: widget.enabled ? () => _insertToken('{bates}') : null,
              child: const Text('Insert {bates}'),
            ),
          ),
      ],
    );
  }

  Widget _rangeSection(ThemeData theme) {
    final invalid =
        spec.range == HfPageRange.custom &&
        parseHfPageRange(spec.customRange, widget.doc.pageCount) == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (_stacks(constraints.maxWidth)) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final r in HfPageRange.values) ...[
                    SizedBox(
                      height: DsSpacing.controlHeightComfortable,
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: spec.range == r
                              ? DsColors.primary.withValues(alpha: 0.1)
                              : null,
                          foregroundColor: spec.range == r
                              ? DsColors.primary
                              : null,
                          alignment: Alignment.centerLeft,
                        ),
                        onPressed: widget.enabled
                            ? () => _emit(spec.copyWith(range: r))
                            : null,
                        child: Text(r.label),
                      ),
                    ),
                    const SizedBox(height: DsSpacing.sm),
                  ],
                ],
              );
            }
            return SegmentedButton<HfPageRange>(
              showSelectedIcon: false,
              segments: [
                for (final r in HfPageRange.values)
                  ButtonSegment(value: r, label: Text(r.label)),
              ],
              selected: {spec.range},
              onSelectionChanged: widget.enabled
                  ? (s) => _emit(spec.copyWith(range: s.first))
                  : null,
            );
          },
        ),
        AnimatedSize(
          duration: DsMotion.switchDuration,
          curve: DsMotion.switchCurve,
          alignment: Alignment.topCenter,
          child: spec.range == HfPageRange.custom
              ? Padding(
                  padding: const EdgeInsets.only(top: DsSpacing.sm),
                  child: _TextSetting(
                    label: 'Pages (e.g. 1-3, 5, 8-)',
                    value: spec.customRange,
                    enabled: widget.enabled,
                    errorText: invalid ? 'Invalid range' : null,
                    onChanged: (v) => _emit(spec.copyWith(customRange: v)),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 4),
        _switchRow(
          theme,
          'Skip first page',
          'Leave the cover page clean',
          spec.skipFirstPage,
          (v) => _emit(spec.copyWith(skipFirstPage: v)),
        ),
        _switchRow(
          theme,
          'Alternate left/right',
          'Swap left and right zones on even pages',
          spec.mirrorOnEvenPages,
          (v) => _emit(spec.copyWith(mirrorOnEvenPages: v)),
        ),
      ],
    );
  }

  Widget _marginsSection(ThemeData theme) {
    final m = spec.margins;
    Widget field(String label, double v, HfMargins Function(double) set) =>
        _IntField(
          label: label,
          value: v.round(),
          min: 0,
          max: 288,
          suffix: 'pt',
          enabled: widget.enabled,
          onChanged: (n) => _emit(spec.copyWith(margins: set(n.toDouble()))),
        );
    Widget pair(Widget left, Widget right) {
      return LayoutBuilder(
        builder: (context, constraints) {
          if (_stacks(constraints.maxWidth)) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                left,
                const SizedBox(height: DsSpacing.lg),
                right,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: DsSpacing.lg),
              Expanded(child: right),
            ],
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pair(
          field('Top', m.top, (v) => m.copyWith(top: v)),
          field('Bottom', m.bottom, (v) => m.copyWith(bottom: v)),
        ),
        const SizedBox(height: DsSpacing.lg),
        pair(
          field('Left', m.left, (v) => m.copyWith(left: v)),
          field('Right', m.right, (v) => m.copyWith(right: v)),
        ),
        const SizedBox(height: DsSpacing.md),
        Text(
          '72 pt = 1 in = 25.4 mm. Margins are measured from the page edge '
          'to the text.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: DsColors.textSecondary(theme.brightness),
          ),
        ),
      ],
    );
  }

  Widget _appearanceSection(ThemeData theme) {
    Widget block(
      String title,
      HfDecoration d,
      void Function(HfDecoration) set,
    ) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _switchRow(
            theme,
            '$title rule',
            'Hairline between $title and body',
            d.ruleEnabled,
            (v) => set(d.copyWith(ruleEnabled: v)),
          ),
          AnimatedSize(
            duration: DsMotion.switchDuration,
            curve: DsMotion.switchCurve,
            alignment: Alignment.topCenter,
            child: d.ruleEnabled
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: PdfCompactColorPicker<int>(
                      colors: hfPalette.take(6).toList(),
                      selected: d.ruleRgb,
                      swatch: hfColor,
                      onChanged: widget.enabled
                          ? (c) {
                              if (c != null) set(d.copyWith(ruleRgb: c));
                            }
                          : null,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          Text('$title band', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          PdfCompactColorPicker<int>(
            colors: _bandPalette,
            selected: d.bandRgb,
            allowNone: true,
            swatch: hfColor,
            onChanged: widget.enabled
                ? (c) => set(
                    c == null
                        ? d.copyWith(clearBand: true)
                        : d.copyWith(bandRgb: c),
                  )
                : null,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        block('Header', spec.header, (d) => _emit(spec.copyWith(header: d))),
        const Divider(height: 20),
        block('Footer', spec.footer, (d) => _emit(spec.copyWith(footer: d))),
      ],
    );
  }

  Widget _switchRow(
    ThemeData theme,
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.bodyLarge),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: DsColors.textSecondary(theme.brightness),
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: DsColors.primary,
          onChanged: widget.enabled ? onChanged : null,
        ),
      ],
    );
  }
}

/// 2 × 3 grid of the zones laid out like a page.
class _ZonePicker extends StatelessWidget {
  const _ZonePicker({
    required this.spec,
    required this.focus,
    required this.sample,
    required this.onSelect,
  });

  final HeaderFooterSpec spec;
  final HfZone focus;
  final String Function(String) sample;
  final ValueChanged<HfZone> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(List<HfZone> zones) => Row(
      children: [
        for (final z in zones)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: _ZoneTile(
                zone: z,
                style: spec.zone(z),
                selected: focus == z,
                sample: sample,
                onTap: () => onSelect(z),
              ),
            ),
          ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DsColors.borderLight),
        boxShadow: DsSpacing.cardShadowLight(opacity: 0.04),
      ),
      child: Column(
        children: [
          row(const [
            HfZone.headerLeft,
            HfZone.headerCenter,
            HfZone.headerRight,
          ]),
          Container(
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: CustomPaint(
              painter: _BodyLinesPainter(
                color: theme.brightness == Brightness.dark
                    ? Colors.white24
                    : const Color(0xFFE5E7EB),
              ),
              size: Size.infinite,
            ),
          ),
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

class _BodyLinesPainter extends CustomPainter {
  _BodyLinesPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    const widths = [1.0, 0.92, 0.97, 0.6];
    for (var i = 0; i < widths.length; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, i * 9.0, size.width * widths[i], 4),
          const Radius.circular(2),
        ),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BodyLinesPainter old) => old.color != color;
}

class _ZoneTile extends StatefulWidget {
  const _ZoneTile({
    required this.zone,
    required this.style,
    required this.selected,
    required this.sample,
    required this.onTap,
  });

  final HfZone zone;
  final HfZoneStyle style;
  final bool selected;
  final String Function(String) sample;
  final VoidCallback onTap;

  @override
  State<_ZoneTile> createState() => _ZoneTileState();
}

class _ZoneTileState extends State<_ZoneTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final empty = widget.style.isEmpty;
    final align = switch (widget.zone.align) {
      HfAlign.left => TextAlign.left,
      HfAlign.center => TextAlign.center,
      HfAlign.right => TextAlign.right,
    };
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: DsMotion.hoverDuration,
          curve: DsMotion.switchCurve,
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: switch (widget.zone.align) {
            HfAlign.left => Alignment.centerLeft,
            HfAlign.center => Alignment.center,
            HfAlign.right => Alignment.centerRight,
          },
          decoration: BoxDecoration(
            color: widget.selected
                ? DsColors.primary.withValues(alpha: 0.08)
                : _hover
                ? Colors.black.withValues(alpha: 0.04)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.selected
                  ? DsColors.primary
                  : empty
                  ? Colors.black12
                  : Colors.black26,
              width: widget.selected ? 1.5 : 1,
            ),
          ),
          child: empty
              ? Icon(
                  Icons.add,
                  size: 14,
                  color: widget.selected ? DsColors.primary : Colors.black38,
                )
              : Text(
                  widget.sample(widget.style.text),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: align,
                  style: hfPreviewTextStyle(
                    widget.style.font,
                    13,
                    hfColor(
                      widget.style.colorRgb == 0xFFFFFF
                          ? 0x6B7280
                          : widget.style.colorRgb,
                    ),
                  ).copyWith(height: 1.15),
                ),
        ),
      ),
    );
  }
}

class _TokenMenu extends StatelessWidget {
  const _TokenMenu({required this.enabled, required this.onPick});

  final bool enabled;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      enabled: enabled,
      tooltip: 'Insert token',
      onSelected: onPick,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        for (final t in hfTokenCatalog)
          PopupMenuItem(
            value: t.token,
            height: 40,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(t.label, style: const TextStyle(fontSize: 13)),
                      Text(
                        t.description,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  t.token,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: DsColors.primary,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: DsColors.primary.withValues(alpha: enabled ? 0.1 : 0.04),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.data_object, size: 14, color: DsColors.primary),
            SizedBox(width: 4),
            Text(
              'Insert',
              style: TextStyle(fontSize: 12, color: DsColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _SizeStepper extends StatelessWidget {
  const _SizeStepper({
    required this.value,
    required this.onChanged,
    required this.enabled,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final step = value < 12 ? 0.5 : 1.0;
    String fmt(double v) =>
        v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
    return Container(
      height: DsSpacing.controlHeightComfortable,
      decoration: BoxDecoration(
        border: Border.all(color: DsColors.borderLight),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Smaller',
            onPressed: enabled && value > 4
                ? () => onChanged(math.max(4, value - step))
                : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 64,
            child: Text(
              '${fmt(value)} pt',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Larger',
            onPressed: enabled && value < 72
                ? () => onChanged(math.min(72, value + step))
                : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

/// Integer field that commits on every valid edit (keeps its own controller).
class _IntField extends StatefulWidget {
  const _IntField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 999999999,
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
  State<_IntField> createState() => _IntFieldState();
}

class _IntFieldState extends State<_IntField> {
  late final _ctrl = TextEditingController(text: '${widget.value}');

  @override
  void didUpdateWidget(covariant _IntField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (int.tryParse(_ctrl.text) != widget.value) {
      _ctrl.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      enabled: widget.enabled,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: widget.suffix,
        border: const OutlineInputBorder(),
      ),
      onChanged: (v) {
        final n = int.tryParse(v);
        if (n == null) return;
        widget.onChanged(n.clamp(widget.min, widget.max));
      },
    );
  }
}

class _TextSetting extends StatefulWidget {
  const _TextSetting({
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
  State<_TextSetting> createState() => _TextSettingState();
}

class _TextSettingState extends State<_TextSetting> {
  late final _ctrl = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant _TextSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_ctrl.text != widget.value) _ctrl.text = widget.value;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      enabled: widget.enabled,
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.errorText,
        border: const OutlineInputBorder(),
      ),
      onChanged: widget.onChanged,
    );
  }
}
