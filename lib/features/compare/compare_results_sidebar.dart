import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/widgets/ds_hover_lift.dart';
import 'package:document_studio/domain/compare/compare_models.dart';
import 'package:document_studio/features/compare/compare_controller.dart';
import 'package:document_studio/features/compare/compare_page_painter.dart';
import 'package:flutter/material.dart';

/// Summary, category filters, legend and the clickable change list. Used as
/// the sidebar on wide layouts and inside a bottom sheet on phones.
class CompareResultsSidebar extends StatefulWidget {
  const CompareResultsSidebar({
    super.key,
    required this.controller,
    required this.onOpenChange,
    this.scrollController,
    this.showHandle = false,
  });

  final CompareController controller;
  final ValueChanged<CompareChange> onOpenChange;

  /// Supplied by a draggable bottom sheet so dragging the list resizes it.
  final ScrollController? scrollController;
  final bool showHandle;

  @override
  State<CompareResultsSidebar> createState() => _CompareResultsSidebarState();
}

class _CompareResultsSidebarState extends State<CompareResultsSidebar> {
  final _ownList = ScrollController();
  int? _lastSelected;

  static const _itemExtent = 96.0;

  ScrollController get _list => widget.scrollController ?? _ownList;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
  }

  @override
  void didUpdateWidget(CompareResultsSidebar old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _ownList.dispose();
    super.dispose();
  }

  void _onController() {
    if (!mounted) return;
    setState(() {});
    _revealSelected();
  }

  void _revealSelected() {
    final c = widget.controller;
    if (c.selectedId == _lastSelected) return;
    _lastSelected = c.selectedId;
    final i = c.selectedVisibleIndex;
    if (i < 0 || widget.scrollController != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_list.hasClients) return;
      final pos = _list.position;
      final top = DsSpacing.sm + i * _itemExtent;
      if (top < pos.pixels ||
          top + _itemExtent > pos.pixels + pos.viewportDimension) {
        _list.animateTo(
          (top - pos.viewportDimension / 2 + _itemExtent / 2)
              .clamp(0, pos.maxScrollExtent),
          duration: DsMotion.contentReveal,
          curve: DsMotion.switchCurve,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final r = c.result;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    if (r == null) return const SizedBox.shrink();
    final visible = c.visibleChanges;
    final secondary = DsColors.textSecondary(brightness);

    final header = <Widget>[
      if (widget.showHandle)
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: DsSpacing.sm),
            width: 36,
            height: 5,
            decoration: BoxDecoration(
              color: DsColors.border(brightness),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
            DsSpacing.lg, DsSpacing.md, DsSpacing.lg, DsSpacing.sm),
        child: _SummaryCard(result: r),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: DsSpacing.lg),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final cat in CompareCategory.values)
              _FilterChip(
                category: cat,
                count: r.count(cat),
                available: c.categoryAvailable(cat),
                selected: c.filters.contains(cat),
                onTap: () => c.toggleFilter(cat),
                onLongPress: () => c.showOnly(cat),
              ),
          ],
        ),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(
            DsSpacing.lg, DsSpacing.md, DsSpacing.lg, DsSpacing.xs),
        child: _Legend(),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
            DsSpacing.lg, DsSpacing.xs, DsSpacing.sm, DsSpacing.xs),
        child: SizedBox(
          height: 32,
          child: Row(
            children: [
              Text(
                '${visible.length} of ${r.changes.length} shown',
                style: theme.textTheme.labelMedium?.copyWith(color: secondary),
              ),
              const Spacer(),
              if (c.filters.length != CompareCategory.values.length)
                TextButton(onPressed: c.showAll, child: const Text('Show all')),
            ],
          ),
        ),
      ),
      const Divider(height: 1),
    ];

    Widget tile(int i) {
      final ch = visible[i];
      return SizedBox(
        height: _itemExtent,
        child: _ChangeTile(
          change: ch,
          selected: ch.id == c.selectedId,
          onTap: () => widget.onOpenChange(ch),
        ),
      );
    }

    // In a bottom sheet (or a short window) everything scrolls together.
    Widget combined(ScrollController controller, Color background) {
      return ColoredBox(
        color: background,
        child: CustomScrollView(
          controller: controller,
          slivers: [
            SliverList.list(children: header),
            if (visible.isEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 180,
                  child: _EmptyList(identical: r.identical),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(vertical: DsSpacing.sm),
                sliver: SliverFixedExtentList.builder(
                  itemExtent: _itemExtent,
                  itemCount: visible.length,
                  itemBuilder: (context, i) => tile(i),
                ),
              ),
          ],
        ),
      );
    }

    final sheet = widget.scrollController;
    if (sheet != null) {
      return combined(sheet, DsColors.groupedBackground(brightness));
    }

    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxHeight < 560) {
          return combined(_ownList, DsColors.sidebar(brightness));
        }
        return _split(header, visible, r, tile, brightness);
      },
    );
  }

  Widget _split(
    List<Widget> header,
    List<CompareChange> visible,
    CompareResult r,
    Widget Function(int) tile,
    Brightness brightness,
  ) {
    final c = widget.controller;
    return ColoredBox(
      color: DsColors.sidebar(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...header,
          Expanded(
            child: AnimatedSwitcher(
              duration: DsMotion.switchDuration,
              child: visible.isEmpty
                  ? _EmptyList(identical: r.identical)
                  : Scrollbar(
                      controller: _list,
                      child: ListView.builder(
                        key: ValueKey(c.filters.length * 131 + visible.length),
                        controller: _list,
                        padding: const EdgeInsets.symmetric(
                            vertical: DsSpacing.sm),
                        itemExtent: _itemExtent,
                        itemCount: visible.length,
                        itemBuilder: (context, i) => tile(i),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.result});

  final CompareResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final secondary = DsColors.textSecondary(brightness);
    final total = result.changes.length;
    final ok = total == 0;
    final affected = result.pagesAffected;
    final kinds = [
      for (final (k, _) in compareLegend)
        (k, k == CompareChangeKind.changed
            ? result.countOfKind(k) + result.countOfKind(CompareChangeKind.moved)
            : result.countOfKind(k)),
    ];
    return Container(
      padding: const EdgeInsets.all(DsSpacing.md),
      decoration: BoxDecoration(
        color: DsColors.groupedCell(brightness),
        borderRadius: BorderRadius.circular(DsSpacing.radiusCard),
        border: Border.all(color: DsColors.border(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (ok ? compareInsertColor : compareChangedColor)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  ok ? Icons.check_rounded : Icons.difference_outlined,
                  color: ok ? compareInsertColor : compareChangedColor,
                ),
              ),
              const SizedBox(width: DsSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: total.toDouble()),
                      duration: const Duration(milliseconds: 600),
                      curve: DsMotion.switchCurve,
                      builder: (context, v, _) => Text(
                        ok
                            ? 'Documents match'
                            : '${v.round()} change${total == 1 ? '' : 's'}',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '${result.oldDoc.pageCount} → ${result.newDoc.pageCount} pages · '
                      '${result.elapsed.inMilliseconds} ms',
                      style: theme.textTheme.bodySmall?.copyWith(color: secondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!ok) ...[
            const SizedBox(height: DsSpacing.sm),
            Wrap(
              spacing: DsSpacing.md,
              runSpacing: 4,
              children: [
                for (final (k, n) in kinds)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: compareKindColor(k),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text('$n ${k.label.toLowerCase()}',
                          style: theme.textTheme.labelSmall),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Pages affected: ${affected.oldPages} original · '
              '${affected.newPages} revised',
              style: theme.textTheme.labelSmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.category,
    required this.count,
    required this.available,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final CompareCategory category;
  final int count;
  final bool available;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final primary = DsColors.textPrimary(brightness);
    final secondary = DsColors.textSecondary(brightness);
    final on = selected && available;
    final tooltip = available
        ? '${category.description}\nClick to toggle · long-press to show only this'
        : '${category.label} changes can’t be detected: this PDF backend '
            'exposes no ${category == CompareCategory.formatting ? 'font data' : 'image objects'}.';
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Opacity(
        opacity: available ? 1 : 0.5,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: available ? onTap : null,
            onLongPress: available ? onLongPress : null,
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: DsMotion.hoverDuration,
              curve: DsMotion.switchCurve,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: on
                    ? primary.withValues(alpha: 0.08)
                    : DsColors.groupedCell(brightness),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: on
                      ? primary.withValues(alpha: 0.45)
                      : DsColors.border(brightness),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(compareCategoryIcon(category),
                      size: 14, color: on ? primary : secondary),
                  const SizedBox(width: 5),
                  Text(
                    category.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: on ? primary : secondary,
                      decoration: on || !available
                          ? null
                          : TextDecoration.lineThrough,
                      decorationColor: secondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: on && count > 0
                          ? primary
                          : secondary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      available ? '$count' : 'n/a',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: on && count > 0
                            ? DsColors.groupedCell(brightness)
                            : secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [
        for (final (k, label) in compareLegend)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 10,
                decoration: BoxDecoration(
                  color: compareKindColor(k).withValues(alpha: 0.28),
                  border: Border(
                    bottom: BorderSide(color: compareKindColor(k), width: 1.6),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(label, style: style),
            ],
          ),
      ],
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.identical});

  final bool identical;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DsSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              identical ? Icons.verified_outlined : Icons.filter_alt_off_outlined,
              size: 40,
              color: identical ? compareInsertColor : theme.disabledColor,
            ),
            const SizedBox(height: DsSpacing.sm),
            Text(
              identical ? 'No differences found' : 'No changes match the filters',
              style: theme.textTheme.titleSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChangeTile extends StatelessWidget {
  const _ChangeTile({
    required this.change,
    required this.selected,
    required this.onTap,
  });

  final CompareChange change;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final color = compareColor(change);
    final secondary = DsColors.textSecondary(brightness);
    final pages = [
      if (change.aPage != null) 'p.${change.aPage! + 1}',
      if (change.bPage != null) 'p.${change.bPage! + 1}',
    ].join(' → ');

    final preview = <InlineSpan>[];
    final same = change.oldText == change.newText;
    if (change.oldText.isNotEmpty && !same) {
      preview.add(TextSpan(
        text: change.oldText,
        style: const TextStyle(
          color: compareDeleteColor,
          decoration: TextDecoration.lineThrough,
          decorationColor: compareDeleteColor,
        ),
      ));
    }
    if (change.newText.isNotEmpty && !same) {
      if (preview.isNotEmpty) preview.add(const TextSpan(text: '  '));
      preview.add(TextSpan(
        text: change.newText,
        style: const TextStyle(color: compareInsertColor),
      ));
    }
    if (same && change.oldText.isNotEmpty) {
      preview.add(TextSpan(text: change.oldText));
    }
    final detail = change.detail;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DsSpacing.sm, vertical: 3),
      child: DsHoverLift(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
        child: AnimatedContainer(
          duration: DsMotion.hoverDuration,
          curve: DsMotion.switchCurve,
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.10)
                : DsColors.groupedCell(brightness),
            borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
            border: Border.all(
              color: selected ? color : DsColors.border(brightness),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedContainer(
                duration: DsMotion.hoverDuration,
                width: selected ? 5 : 3,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(DsSpacing.radiusButton),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(compareCategoryIcon(change.category),
                              size: 14, color: color),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              change.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          Text(
                            pages,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: secondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              ...preview,
                              if (detail != null && detail.isNotEmpty) ...[
                                if (preview.isNotEmpty)
                                  const TextSpan(text: '\n'),
                                TextSpan(
                                  text: detail,
                                  style: TextStyle(
                                    color: secondary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            height: 1.3,
                            color: DsColors.textPrimary(brightness),
                          ),
                        ),
                      ),
                    ],
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
