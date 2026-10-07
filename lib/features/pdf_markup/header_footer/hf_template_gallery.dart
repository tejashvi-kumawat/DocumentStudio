import 'dart:math' as math;

import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/widgets/ds_hover_lift.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_layout.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_spec.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_templates.dart';
import 'package:document_studio/features/pdf_markup/header_footer/hf_preview_painter.dart';
import 'package:flutter/material.dart';

/// Letter-size page thumbnail with faux body text and the header/footer
/// painted by the shared layout function.
class HfTemplateThumb extends StatelessWidget {
  const HfTemplateThumb({
    super.key,
    required this.spec,
    this.width = 96,
    this.selected = false,
  });

  final HeaderFooterSpec spec;
  final double width;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: DsMotion.hoverDuration,
      curve: DsMotion.switchCurve,
      width: width,
      height: width * 792 / 612,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: selected ? DsColors.primary : Colors.black12,
          width: selected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: selected ? 0.16 : 0.07),
            blurRadius: selected ? 10 : 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: CustomPaint(painter: _ThumbPainter(spec)),
      ),
    );
  }
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.spec);

  final HeaderFooterSpec spec;

  @override
  void paint(Canvas canvas, Size size) {
    const w = 612.0;
    const h = 792.0;
    final scale = size.width / w;
    final bar = Paint()..color = const Color(0xFFE5E7EB);
    final rnd = math.Random(7);
    var y = 118.0;
    while (y < h - 120) {
      final len = 0.55 + rnd.nextDouble() * 0.45;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            72 * scale,
            y * scale,
            (w - 144) * len * scale,
            math.max(7 * scale, 1.5),
          ),
          Radius.circular(2 * scale),
        ),
        bar,
      );
      y += rnd.nextInt(6) == 0 ? 34 : 17;
    }
    final page = spec.skipFirstPage ? 2 : 1;
    final layout = layoutHeaderFooterPage(
      spec: spec,
      doc: hfSampleDocInfo.withNow(DateTime(2026, 9, 28, 9, 41)),
      page1Based: page,
      pageWidthPt: w,
      pageHeightPt: h,
    );
    paintHeaderFooterLayout(canvas, size, layout: layout, pageWidthPt: w);
  }

  @override
  bool shouldRepaint(covariant _ThumbPainter old) => old.spec != spec;
}

/// Full gallery of built-in and saved templates. Resolves to the chosen one.
Future<HfTemplate?> showHfTemplateGallery(
  BuildContext context, {
  required List<HfTemplate> custom,
  required Future<List<HfTemplate>> Function(String id) onDelete,
}) {
  return showGeneralDialog<HfTemplate>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Templates',
    barrierColor: Colors.black38,
    transitionDuration: DsMotion.dialogDuration,
    transitionBuilder: (context, anim, _, child) =>
        DsMotion.fadeScaleTransition(anim, child),
    pageBuilder: (context, _, _) =>
        _TemplateGallery(custom: custom, onDelete: onDelete),
  );
}

class _TemplateGallery extends StatefulWidget {
  const _TemplateGallery({required this.custom, required this.onDelete});

  final List<HfTemplate> custom;
  final Future<List<HfTemplate>> Function(String id) onDelete;

  @override
  State<_TemplateGallery> createState() => _TemplateGalleryState();
}

class _TemplateGalleryState extends State<_TemplateGallery> {
  late List<HfTemplate> _custom = widget.custom;
  String _category = 'All';
  String _query = '';

  List<HfTemplate> get _all => [..._custom, ...builtInHfTemplates];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = <String>{
      'All',
      if (_custom.isNotEmpty) 'My templates',
      for (final t in builtInHfTemplates) t.category,
    }.toList();
    final q = _query.trim().toLowerCase();
    final visible = [
      for (final t in _all)
        if ((_category == 'All' || t.category == _category) &&
            (q.isEmpty ||
                t.name.toLowerCase().contains(q) ||
                t.description.toLowerCase().contains(q)))
          t,
    ];
    final size = MediaQuery.sizeOf(context);
    return Center(
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(DsSpacing.radiusDialog),
        clipBehavior: Clip.antiAlias,
        elevation: 12,
        child: SizedBox(
          width: math.min(880, size.width - 48),
          height: math.min(640, size.height - 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome_mosaic_outlined,
                      color: DsColors.primary,
                    ),
                    const SizedBox(width: DsSpacing.sm),
                    Expanded(
                      child: Text(
                        'Header & footer templates',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: TextField(
                        autofocus: true,
                        onChanged: (v) => setState(() => _query = v),
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(Icons.search, size: 18),
                          hintText: 'Search templates',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final c in categories)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(c, style: const TextStyle(fontSize: 12)),
                          selected: _category == c,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setState(() => _category = c),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: AnimatedSwitcher(
                  duration: DsMotion.switchDuration,
                  child: visible.isEmpty
                      ? Center(
                          key: const ValueKey('empty'),
                          child: Text(
                            'No templates match',
                            style: theme.textTheme.bodyMedium,
                          ),
                        )
                      : GridView.builder(
                          key: ValueKey('$_category|$q|${_custom.length}'),
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 200,
                                mainAxisExtent: 250,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                              ),
                          itemCount: visible.length,
                          itemBuilder: (context, i) => DsMotion.fadeRiseIn(
                            duration: Duration(
                              milliseconds: 160 + math.min(i, 10) * 25,
                            ),
                            child: _GalleryCard(
                              template: visible[i],
                              onTap: () =>
                                  Navigator.of(context).pop(visible[i]),
                              onDelete: visible[i].builtIn
                                  ? null
                                  : () async {
                                      final next = await widget.onDelete(
                                        visible[i].id,
                                      );
                                      if (mounted) {
                                        setState(() => _custom = next);
                                      }
                                    },
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GalleryCard extends StatelessWidget {
  const _GalleryCard({
    required this.template,
    required this.onTap,
    this.onDelete,
  });

  final HfTemplate template;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DsHoverLift(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DsSpacing.radiusCard),
      child: Container(
        decoration: BoxDecoration(
          color: DsColors.groupedBackground(theme.brightness),
          borderRadius: BorderRadius.circular(DsSpacing.radiusCard),
          border: Border.all(color: DsColors.borderLight),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, c) => HfTemplateThumb(
                    spec: template.spec,
                    width: math.min(c.maxWidth, c.maxHeight * 612 / 792),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    template.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onDelete != null)
                  InkResponse(
                    radius: 16,
                    onTap: onDelete,
                    child: const Tooltip(
                      message: 'Delete template',
                      child: Icon(Icons.delete_outline, size: 16),
                    ),
                  ),
              ],
            ),
            Text(
              template.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: DsColors.textSecondary(theme.brightness),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
