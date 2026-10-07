import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:document_studio/design_system/adaptive/ds_adaptive.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Shared building blocks for standalone tool pages (inside [DsToolPage]):
/// source picker with drag-and-drop, progress with cancel, and a result card.

bool get _desktopDrop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS);

String dsFormatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

IconData _iconFor(String path) {
  final ext = p.extension(path).toLowerCase();
  return switch (ext) {
    '.pdf' => Icons.picture_as_pdf_outlined,
    '.png' ||
    '.jpg' ||
    '.jpeg' ||
    '.webp' ||
    '.gif' ||
    '.bmp' ||
    '.tif' ||
    '.tiff' ||
    '.heic' => Icons.image_outlined,
    '.doc' ||
    '.docx' ||
    '.odt' ||
    '.rtf' ||
    '.txt' => Icons.description_outlined,
    '.xls' || '.xlsx' || '.ods' || '.csv' => Icons.table_chart_outlined,
    '.ppt' || '.pptx' || '.odp' => Icons.slideshow_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

/// Source file area: a dashed drop zone ("Drop a PDF or browse") when empty,
/// a file row with metadata and Change / Remove once chosen.
///
/// Drops are filtered by [allowedExtensions] (lowercase, without dot); with
/// [multiple] every matching dropped file is passed to [onFilesDropped].
class DsToolFileSource extends StatefulWidget {
  const DsToolFileSource({
    super.key,
    required this.files,
    required this.onPick,
    this.onFilesDropped,
    this.onRemove,
    this.allowedExtensions = const ['pdf'],
    this.multiple = false,
    this.loading = false,
    this.enabled = true,
    this.metaFor,
    this.emptyTitle,
    this.emptySubtitle,
    this.pickLabel,
    this.icon = Icons.upload_file_rounded,
  });

  final List<LocalFileRef> files;
  final VoidCallback onPick;
  final ValueChanged<List<LocalFileRef>>? onFilesDropped;
  final ValueChanged<LocalFileRef>? onRemove;
  final List<String> allowedExtensions;
  final bool multiple;
  final bool loading;
  final bool enabled;

  /// Secondary line under a file name ("12 pages · 2.4 MB").
  final String? Function(LocalFileRef file)? metaFor;
  final String? emptyTitle;
  final String? emptySubtitle;
  final String? pickLabel;
  final IconData icon;

  @override
  State<DsToolFileSource> createState() => _DsToolFileSourceState();
}

class _DsToolFileSourceState extends State<DsToolFileSource> {
  bool _dragging = false;
  bool _hovered = false;

  String get _kind {
    final exts = widget.allowedExtensions;
    if (exts.length == 1 && exts.first == 'pdf') {
      return widget.multiple ? 'PDFs' : 'a PDF';
    }
    if (exts.every(
      (e) => const {
        'png',
        'jpg',
        'jpeg',
        'webp',
        'heic',
        'bmp',
        'gif',
        'tif',
        'tiff',
      }.contains(e),
    )) {
      return widget.multiple ? 'images' : 'an image';
    }
    return widget.multiple ? 'files' : 'a file';
  }

  void _onDrop(DropDoneDetails details) {
    setState(() => _dragging = false);
    final handler = widget.onFilesDropped;
    if (handler == null || !widget.enabled) return;
    final allowed = widget.allowedExtensions
        .map((e) => e.toLowerCase())
        .toSet();
    final accepted = <LocalFileRef>[];
    for (final f in details.files) {
      final path = f.path;
      if (path.isEmpty || !File(path).existsSync()) continue;
      final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
      if (allowed.isNotEmpty && !allowed.contains(ext)) continue;
      accepted.add(LocalFileRef(path: path, displayName: p.basename(path)));
      if (!widget.multiple) break;
    }
    if (accepted.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            'Drop ${widget.allowedExtensions.map((e) => '.$e').join(', ')} files here.',
          ),
        ),
      );
      return;
    }
    handler(accepted);
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.files;
    Widget body = AnimatedSwitcher(
      duration: DsMotion.switchDuration,
      switchInCurve: DsMotion.switchCurve,
      // The default layout loosens the width, which shrank the drop zone to
      // its text; pass the page's width through instead.
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.passthrough,
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        // SizeTransition aligns its child loosely; ask for the full width.
        child: SizeTransition(
          sizeFactor: anim,
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
      child: files.isEmpty
          ? KeyedSubtree(key: const ValueKey('empty'), child: _empty(context))
          : KeyedSubtree(
              key: const ValueKey('files'),
              child: _fileList(context, files),
            ),
    );
    if (_desktopDrop && widget.onFilesDropped != null) {
      body = DropTarget(
        enable: widget.enabled,
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: _onDrop,
        child: body,
      );
    }
    return body;
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = DsColors.textSecondary(theme.brightness);
    final active = _dragging || _hovered;
    final title =
        widget.emptyTitle ??
        (_desktopDrop && widget.onFilesDropped != null
            ? 'Drop $_kind here'
            : 'Choose $_kind');
    final subtitle =
        widget.emptySubtitle ??
        (_desktopDrop && widget.onFilesDropped != null
            ? 'or browse your device'
            : 'Files stay on this device');
    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.enabled && !widget.loading ? widget.onPick : null,
        child: AnimatedContainer(
          duration: DsMotion.hoverDuration,
          curve: DsMotion.switchCurve,
          padding: const EdgeInsets.symmetric(
            horizontal: DsSpacing.lg,
            vertical: DsSpacing.xl,
          ),
          decoration: BoxDecoration(
            color: active
                ? DsColors.primary.withValues(alpha: isDark ? 0.14 : 0.06)
                : (isDark
                      ? Colors.white.withValues(alpha: 0.03)
                      : DsColors.groupedBackgroundLight),
            borderRadius: BorderRadius.circular(DsSpacing.radiusCard),
            border: Border.all(
              color: active
                  ? DsColors.primary.withValues(alpha: 0.7)
                  : DsColors.border(theme.brightness),
              width: active ? 1.4 : 1,
            ),
          ),
          child: Column(
            children: [
              AnimatedScale(
                scale: _dragging ? 1.12 : 1,
                duration: DsMotion.hoverDuration,
                curve: DsMotion.switchCurve,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: DsColors.primary.withValues(
                      alpha: isDark ? 0.2 : 0.1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: widget.loading
                      ? const Center(child: DsAdaptiveProgress(size: 18))
                      : Icon(widget.icon, color: DsColors.primary, size: 22),
                ),
              ),
              const SizedBox(height: DsSpacing.sm + 2),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: secondary),
              ),
              const SizedBox(height: DsSpacing.md),
              OutlinedButton.icon(
                onPressed: widget.enabled && !widget.loading
                    ? widget.onPick
                    : null,
                icon: const Icon(Icons.folder_open_rounded, size: 16),
                label: Text(widget.pickLabel ?? 'Browse'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: DsColors.primary,
                  side: BorderSide(
                    color: DsColors.primary.withValues(alpha: 0.5),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fileList(BuildContext context, List<LocalFileRef> files) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return AnimatedContainer(
      duration: DsMotion.hoverDuration,
      decoration: BoxDecoration(
        color: _dragging
            ? DsColors.primary.withValues(alpha: isDark ? 0.14 : 0.06)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(DsSpacing.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < files.length; i++) ...[
            if (i > 0) const SizedBox(height: DsSpacing.xs),
            _DsFileRow(
              file: files[i],
              meta: widget.metaFor?.call(files[i]),
              loading: widget.loading && i == files.length - 1,
              onRemove: widget.enabled && widget.onRemove != null
                  ? () => widget.onRemove!(files[i])
                  : null,
            ),
          ],
          const SizedBox(height: DsSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.enabled ? widget.onPick : null,
              icon: Icon(
                widget.multiple ? Icons.add_rounded : Icons.swap_horiz_rounded,
                size: 18,
              ),
              label: Text(
                widget.multiple
                    ? 'Add ${_kind == 'PDFs' ? 'PDFs' : 'files'}'
                    : 'Choose a different file',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DsFileRow extends StatelessWidget {
  const _DsFileRow({
    required this.file,
    required this.meta,
    required this.loading,
    required this.onRemove,
  });

  final LocalFileRef file;
  final String? meta;
  final bool loading;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = DsColors.textSecondary(theme.brightness);
    var size = '';
    try {
      size = dsFormatBytes(File(file.path).lengthSync());
    } catch (_) {}
    final line = loading
        ? 'Reading…'
        : [
            if (meta != null && meta!.isNotEmpty) meta!,
            if (size.isNotEmpty) size,
          ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DsSpacing.md,
        vertical: DsSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : DsColors.groupedBackgroundLight,
        borderRadius: BorderRadius.circular(DsSpacing.radiusGrouped),
        border: Border.all(
          color: DsColors.border(theme.brightness),
          width: isDark ? 1 : 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: DsColors.primary.withValues(alpha: isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(_iconFor(file.path), size: 19, color: DsColors.primary),
          ),
          const SizedBox(width: DsSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontSize: 13.5),
                ),
                if (line.isNotEmpty)
                  Text(
                    line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                    ),
                  ),
              ],
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(left: DsSpacing.sm),
              child: DsAdaptiveProgress(size: 16),
            )
          else if (onRemove != null)
            IconButton(
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, size: 18, color: secondary),
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}

/// Determinate / indeterminate progress with a message and optional Cancel.
class DsToolProgressCard extends StatelessWidget {
  const DsToolProgressCard({
    super.key,
    required this.message,
    this.fraction,
    this.detail,
    this.onCancel,
    this.cancelling = false,
  });

  final String message;
  final double? fraction;
  final String? detail;
  final VoidCallback? onCancel;
  final bool cancelling;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = DsColors.textSecondary(theme.brightness);
    final f = fraction;
    return Container(
      padding: const EdgeInsets.all(DsSpacing.md),
      decoration: BoxDecoration(
        color: DsColors.primary.withValues(alpha: isDark ? 0.10 : 0.04),
        borderRadius: BorderRadius.circular(DsSpacing.radiusCard),
        border: Border.all(
          color: DsColors.primary.withValues(alpha: 0.25),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const DsAdaptiveProgress(size: 16),
              const SizedBox(width: DsSpacing.sm),
              Expanded(
                child: AnimatedSwitcher(
                  duration: DsMotion.switchDuration,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previous, ?current],
                  ),
                  child: Text(
                    cancelling ? 'Cancelling…' : message,
                    key: ValueKey(cancelling ? 'cancel' : message),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              if (f != null)
                Padding(
                  padding: const EdgeInsets.only(left: DsSpacing.sm),
                  child: Text(
                    '${(f * 100).clamp(0, 100).round()}%',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: secondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              if (onCancel != null) ...[
                const SizedBox(width: DsSpacing.sm),
                TextButton(
                  onPressed: cancelling ? null : onCancel,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: DsColors.primary,
                  ),
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
          const SizedBox(height: DsSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: f ?? 0),
              duration: const Duration(milliseconds: 240),
              curve: DsMotion.switchCurve,
              builder: (context, v, _) => LinearProgressIndicator(
                value: f == null ? null : v,
                minHeight: 5,
                color: DsColors.primary,
                backgroundColor: DsColors.primary.withValues(
                  alpha: isDark ? 0.18 : 0.10,
                ),
              ),
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: DsSpacing.xs),
            Text(
              detail!,
              style: theme.textTheme.bodySmall?.copyWith(color: secondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// One "before → after" style figure on a result card.
class DsResultStat {
  const DsResultStat(this.label, this.value, {this.highlight = false});

  final String label;
  final String value;
  final bool highlight;
}

/// Success card: check badge, title, saved file, stats and actions
/// (Open, Show in folder, plus [extraActions]).
class DsToolResultCard extends StatelessWidget {
  const DsToolResultCard({
    super.key,
    required this.title,
    this.message,
    this.file,
    this.stats = const [],
    this.onOpen,
    this.openLabel = 'Open',
    this.onShowInFolder,
    this.extraActions = const [],
    this.onDismiss,
    this.tone = DsResultTone.success,
  });

  final String title;
  final String? message;
  final LocalFileRef? file;
  final List<DsResultStat> stats;
  final VoidCallback? onOpen;
  final String openLabel;
  final VoidCallback? onShowInFolder;
  final List<Widget> extraActions;
  final VoidCallback? onDismiss;
  final DsResultTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = DsColors.textSecondary(theme.brightness);
    final accent = switch (tone) {
      DsResultTone.success => const Color(0xFF16A34A),
      DsResultTone.info => DsColors.primary,
      DsResultTone.error => DsColors.error,
    };
    final icon = switch (tone) {
      DsResultTone.success => Icons.check_rounded,
      DsResultTone.info => Icons.info_outline_rounded,
      DsResultTone.error => Icons.error_outline_rounded,
    };
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.scale(
        scale: 0.96 + 0.04 * t,
        child: Opacity(opacity: t.clamp(0, 1), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.all(DsSpacing.md + 2),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: isDark ? 0.12 : 0.05),
          borderRadius: BorderRadius.circular(DsSpacing.radiusCard),
          border: Border.all(color: accent.withValues(alpha: 0.35), width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 18, color: Colors.white),
                ),
                const SizedBox(width: DsSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (message != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          message!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: secondary,
                          ),
                        ),
                      ],
                      if (file != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          file!.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    tooltip: 'Dismiss',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close_rounded, size: 18, color: secondary),
                    onPressed: onDismiss,
                  ),
              ],
            ),
            if (stats.isNotEmpty) ...[
              const SizedBox(height: DsSpacing.md),
              Wrap(
                spacing: DsSpacing.lg,
                runSpacing: DsSpacing.sm,
                children: [
                  for (final s in stats)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s.label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: secondary,
                          ),
                        ),
                        Text(
                          s.value,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: s.highlight ? accent : null,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
            if (onOpen != null ||
                onShowInFolder != null ||
                extraActions.isNotEmpty) ...[
              const SizedBox(height: DsSpacing.md),
              Wrap(
                spacing: DsSpacing.sm,
                runSpacing: DsSpacing.xs,
                children: [
                  if (onOpen != null)
                    FilledButton.icon(
                      onPressed: onOpen,
                      style: FilledButton.styleFrom(
                        backgroundColor: DsColors.primary,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: Text(openLabel),
                    ),
                  if (onShowInFolder != null)
                    OutlinedButton.icon(
                      onPressed: onShowInFolder,
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.folder_outlined, size: 16),
                      label: const Text('Show in folder'),
                    ),
                  ...extraActions,
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum DsResultTone { success, info, error }

/// One option in a single-choice group of preset cards (e.g. compression
/// level). Lay several out with [DsToolChoiceGroup].
class DsToolChoice<T> {
  const DsToolChoice({
    required this.value,
    required this.title,
    required this.icon,
    this.subtitle,
    this.badge,
  });

  final T value;
  final String title;
  final String? subtitle;
  final IconData icon;

  /// Short tag such as "Recommended".
  final String? badge;
}

/// Responsive row (wide) / column (narrow) of selectable preset cards.
class DsToolChoiceGroup<T> extends StatelessWidget {
  const DsToolChoiceGroup({
    super.key,
    required this.choices,
    required this.selected,
    required this.onChanged,
    this.minCardWidth = 180,
  });

  final List<DsToolChoice<T>> choices;
  final T selected;
  final ValueChanged<T>? onChanged;
  final double minCardWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal =
            constraints.maxWidth >= minCardWidth * choices.length;
        final cards = [
          for (final c in choices)
            _DsChoiceCard<T>(
              choice: c,
              selected: c.value == selected,
              onTap: onChanged == null ? null : () => onChanged!(c.value),
            ),
        ];
        if (!horizontal) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: DsSpacing.sm),
                cards[i],
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: DsSpacing.sm),
                Expanded(child: cards[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _DsChoiceCard<T> extends StatefulWidget {
  const _DsChoiceCard({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final DsToolChoice<T> choice;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<_DsChoiceCard<T>> createState() => _DsChoiceCardState<T>();
}

class _DsChoiceCardState<T> extends State<_DsChoiceCard<T>> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final selected = widget.selected;
    final enabled = widget.onTap != null;
    final borderColor = selected
        ? DsColors.primary
        : _hover && enabled
        ? DsColors.primary.withValues(alpha: 0.35)
        : DsColors.border(b);
    final fill = selected
        ? DsColors.primary.withValues(alpha: b == Brightness.dark ? 0.14 : 0.06)
        : DsColors.groupedCell(b);
    final c = widget.choice;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        selected: selected,
        button: true,
        label: c.title,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: DsMotion.hoverDuration,
            curve: DsMotion.switchCurve,
            padding: const EdgeInsets.all(DsSpacing.md),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
              boxShadow: selected || _hover
                  ? [
                      BoxShadow(
                        color: (selected ? DsColors.primary : Colors.black)
                            .withValues(alpha: selected ? 0.10 : 0.05),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : const [],
            ),
            child: Opacity(
              opacity: enabled ? 1 : 0.55,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    c.icon,
                    size: 20,
                    color: selected
                        ? DsColors.primary
                        : DsColors.textSecondary(b),
                  ),
                  const SizedBox(width: DsSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              c.title,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (c.badge != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: DsColors.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  c.badge!,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: DsColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (c.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            c.subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: DsColors.textSecondary(b),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  AnimatedScale(
                    duration: DsMotion.hoverDuration,
                    scale: selected ? 1 : 0.6,
                    child: AnimatedOpacity(
                      duration: DsMotion.hoverDuration,
                      opacity: selected ? 1 : 0,
                      child: const Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: DsColors.primary,
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
