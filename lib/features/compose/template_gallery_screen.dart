import 'dart:async';
import 'dart:ui' as ui;

import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/features/compose/compose_model.dart';
import 'package:document_studio/features/compose/compose_screen.dart';
import 'package:document_studio/features/compose/compose_templates.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart';

const templateGalleryRoutePath = '/templates';

/// Location that opens the editor with template [id].
String composeTemplateLocation(ComposeTemplate t) =>
    '$composeRoutePath?lang=${t.language.extension}&template=${t.id}';

/// Grouped gallery of every template with a real preview of each.
class TemplateGalleryScreen extends StatefulWidget {
  const TemplateGalleryScreen({super.key, this.initialCategory});

  final TemplateCategory? initialCategory;

  @override
  State<TemplateGalleryScreen> createState() => _TemplateGalleryScreenState();
}

class _TemplateGalleryScreenState extends State<TemplateGalleryScreen> {
  TemplateCategory? _cat;
  String _q = '';
  ComposeTemplate? _selected;

  @override
  void initState() {
    super.initState();
    _cat = widget.initialCategory;
  }

  List<ComposeTemplate> get _visible {
    final q = _q.toLowerCase();
    return [
      for (final t in kComposeTemplates)
        if ((_cat == null || t.category == _cat) &&
            (q.isEmpty ||
                t.name.toLowerCase().contains(q) ||
                t.description.toLowerCase().contains(q)))
          t,
    ];
  }

  void _use(ComposeTemplate t) => context.push(composeTemplateLocation(t));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 1100;
    final narrow = width < 700;
    final list = _visible;
    final sel = _selected ?? (list.isEmpty ? null : list.first);

    final categories = ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        _catTile(
          null,
          'All templates',
          Icons.apps_rounded,
          kComposeTemplates.length,
        ),
        for (final c in TemplateCategory.values)
          _catTile(
            c,
            c.label,
            c.icon,
            kComposeTemplates.where((t) => t.category == c).length,
          ),
      ],
    );

    final grid = LayoutBuilder(
      builder: (context, c) {
        final cols = (c.maxWidth / 230).floor().clamp(1, 6);
        return GridView.builder(
          padding: const EdgeInsets.all(20),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 18,
            crossAxisSpacing: 18,
            childAspectRatio: 0.62,
          ),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final t = list[i];
            final on = wide && identical(t, sel);
            return _TemplateCard(
              template: t,
              selected: on,
              onTap: () =>
                  wide ? setState(() => _selected = t) : _showPreview(t),
              onUse: () => _use(t),
            );
          },
        );
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Templates'),
        actions: [
          SizedBox(
            width: narrow ? 160 : 280,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Search templates',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        bottom: narrow
            ? PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: const Text('All'),
                          selected: _cat == null,
                          onSelected: (_) => setState(() => _cat = null),
                        ),
                      ),
                      for (final c in TemplateCategory.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(c.label),
                            selected: _cat == c,
                            onSelected: (_) => setState(() => _cat = c),
                          ),
                        ),
                    ],
                  ),
                ),
              )
            : null,
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!narrow) SizedBox(width: 220, child: categories),
          if (!narrow) const VerticalDivider(width: 1),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      'No template matches "$_q"',
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                : grid,
          ),
          if (wide && sel != null) ...[
            const VerticalDivider(width: 1),
            SizedBox(
              width: 420,
              child: _PreviewPane(template: sel, onUse: () => _use(sel)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _catTile(
    TemplateCategory? c,
    String label,
    IconData icon,
    int count,
  ) => ListTile(
    dense: true,
    selected: _cat == c,
    leading: Icon(icon, size: 20),
    title: Text(label),
    trailing: Text('$count', style: Theme.of(context).textTheme.labelSmall),
    onTap: () => setState(() {
      _cat = c;
      _selected = null;
    }),
  );

  void _showPreview(ComposeTemplate t) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 460,
          height: MediaQuery.sizeOf(ctx).height * 0.85,
          child: _PreviewPane(
            template: t,
            onUse: () {
              Navigator.pop(ctx);
              _use(t);
            },
          ),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatefulWidget {
  const _TemplateCard({
    required this.template,
    required this.selected,
    required this.onTap,
    required this.onUse,
  });
  final ComposeTemplate template;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onUse;

  @override
  State<_TemplateCard> createState() => _TemplateCardState();
}

class _TemplateCardState extends State<_TemplateCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = widget.template;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onUse,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: widget.selected
                          ? DsColors.primary
                          : const Color(0x1F000000),
                      width: widget.selected ? 2 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: _hover ? 0.16 : 0.07,
                        ),
                        blurRadius: _hover ? 16 : 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      TemplateThumbnail(template: t),
                      Positioned(
                        left: 8,
                        top: 8,
                        child: _LangBadge(t.language),
                      ),
                      if (_hover)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 10,
                          child: Center(
                            child: FilledButton(
                              onPressed: widget.onUse,
                              child: const Text('Use template'),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t.name,
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                t.description,
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LangBadge extends StatelessWidget {
  const _LangBadge(this.l);
  final ComposeLanguage l;

  @override
  Widget build(BuildContext context) {
    final color = switch (l) {
      ComposeLanguage.latex => const Color(0xFF008080),
      ComposeLanguage.markdown => const Color(0xFF37474F),
      ComposeLanguage.html => const Color(0xFFE65100),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        l.label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PreviewPane extends StatelessWidget {
  const _PreviewPane({required this.template, required this.onUse});
  final ComposeTemplate template;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(template.name, style: theme.textTheme.titleMedium),
              ),
              _LangBadge(template.language),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(template.description, style: theme.textTheme.bodySmall),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            color: const Color(0xFF525659),
            padding: const EdgeInsets.all(16),
            child: TemplatePagesPreview(
              key: ValueKey(template.id),
              template: template,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: onUse,
            icon: const Icon(Icons.edit_note),
            label: const Text('Use this template'),
          ),
        ),
      ],
    );
  }
}

/// Renders template pages to images (cached).
class _TemplateRender {
  static final Map<String, List<ui.Image>> _cache = {};
  static Future<void> _queue = Future.value();

  static Future<List<ui.Image>> pages(
    ComposeTemplate t, {
    int maxPages = 1,
    double width = 460,
  }) {
    final key = '${t.id}|$maxPages|${width.round()}';
    final hit = _cache[key];
    if (hit != null) return Future.value(hit);
    final c = Completer<List<ui.Image>>();
    _queue = _queue.then((_) async {
      try {
        final (bytes, _) = await compileCompose(t.language, t.source);
        final doc = await PdfDocument.openData(bytes, sourceName: 'tpl-$key');
        final out = <ui.Image>[];
        for (final page in doc.pages.take(maxPages)) {
          final img = await page.render(
            fullWidth: width,
            fullHeight: width * page.height / page.width,
            backgroundColor: 0xffffffff,
          );
          if (img == null) continue;
          out.add(await img.createImage());
          img.dispose();
        }
        await doc.dispose();
        _cache[key] = out;
        c.complete(out);
      } catch (e) {
        c.complete(const []);
      }
    });
    return c.future;
  }
}

/// First page of [template] as a card thumbnail.
class TemplateThumbnail extends StatelessWidget {
  const TemplateThumbnail({super.key, required this.template});
  final ComposeTemplate template;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ui.Image>>(
      future: _TemplateRender.pages(template, width: 420),
      builder: (context, s) {
        final img = s.data?.firstOrNull;
        if (img == null) {
          return Center(
            child: Icon(
              template.category.icon,
              size: 36,
              color: Colors.black26,
            ),
          );
        }
        return RawImage(
          image: img,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          filterQuality: FilterQuality.medium,
        );
      },
    );
  }
}

/// All pages of [template] (up to 6) for the preview pane.
class TemplatePagesPreview extends StatelessWidget {
  const TemplatePagesPreview({super.key, required this.template});
  final ComposeTemplate template;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ui.Image>>(
      future: _TemplateRender.pages(template, maxPages: 6, width: 900),
      builder: (context, s) {
        final pages = s.data;
        if (pages == null)
          return const Center(child: CircularProgressIndicator());
        return ListView.separated(
          itemCount: pages.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) => DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Color(0x55000000), blurRadius: 8)],
            ),
            child: RawImage(
              image: pages[i],
              fit: BoxFit.fitWidth,
              filterQuality: FilterQuality.high,
            ),
          ),
        );
      },
    );
  }
}
