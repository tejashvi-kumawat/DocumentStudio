import 'dart:io';

import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/home/home_thumbnail_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Just now", "5 min ago", "Yesterday", "Mar 4", "Mar 4, 2024".
String homeRelativeTime(DateTime time, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final d = n.difference(time);
  if (d.inSeconds < 60) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24 && n.day == time.day) return '${d.inHours} h ago';
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(time.year, time.month, time.day);
  final days = today.difference(day).inDays;
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final md = '${months[time.month - 1]} ${time.day}';
  return time.year == n.year ? md : '$md, ${time.year}';
}

String homeFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// "12 pages · 2 h ago" style meta line.
String homeThumbnailMeta(HomeThumbnail? t) {
  if (t == null) return '';
  final parts = <String>[
    if (t.locked) 'Locked',
    if (t.pageCount != null)
      '${t.pageCount} ${t.pageCount == 1 ? 'page' : 'pages'}',
    homeRelativeTime(t.modified),
  ];
  return parts.join(' · ');
}

/// Loads [HomeThumbnail] for [file] from the shared cache.
class HomeThumbnailLoader extends ConsumerStatefulWidget {
  const HomeThumbnailLoader({
    super.key,
    required this.file,
    required this.builder,
  });

  final LocalFileRef file;
  final Widget Function(BuildContext context, HomeThumbnail? thumbnail) builder;

  @override
  ConsumerState<HomeThumbnailLoader> createState() =>
      _HomeThumbnailLoaderState();
}

class _HomeThumbnailLoaderState extends ConsumerState<HomeThumbnailLoader> {
  HomeThumbnail? _thumb;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(HomeThumbnailLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) _load();
  }

  void _load() {
    final cache = ref.read(homeThumbnailCacheProvider);
    final path = widget.file.path;
    _thumb = cache.peek(path);
    cache
        .load(widget.file, isWanted: () => mounted && widget.file.path == path)
        .then((t) {
          if (!mounted || widget.file.path != path) return;
          if (!identical(t, _thumb)) setState(() => _thumb = t);
        });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _thumb);
}

/// A page-shaped preview: real first page when cached, paper placeholder
/// otherwise. Fades the image in when it arrives.
class HomePagePreview extends StatelessWidget {
  const HomePagePreview({
    super.key,
    required this.file,
    required this.thumbnail,
    this.iconSize = 28,
    this.radius = 4,
    this.shadow = true,
  });

  final LocalFileRef file;
  final HomeThumbnail? thumbnail;
  final double iconSize;
  final double radius;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final png = thumbnail?.image;
    final isImage = const {
      'png',
      'jpg',
      'jpeg',
      'webp',
      'gif',
      'bmp',
    }.contains(file.extension);

    Widget content;
    if (png != null) {
      content = Image.memory(
        png,
        key: ValueKey(png.hashCode),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
    } else if (isImage) {
      content = Image.file(
        File(file.path),
        key: const ValueKey('image'),
        fit: BoxFit.cover,
        cacheWidth: 320,
        errorBuilder: (_, _, _) => _placeholder(isDark),
      );
    } else {
      content = KeyedSubtree(
        key: const ValueKey('placeholder'),
        child: _placeholder(isDark),
      );
    }

    return AnimatedSwitcher(
      duration: DsMotion.switchDuration,
      switchInCurve: DsMotion.switchCurve,
      child: DecoratedBox(
        key: ValueKey(png != null ? 'png' : 'ph'),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: shadow
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.10),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: content,
        ),
      ),
    );
  }

  Widget _placeholder(bool isDark) {
    final locked = thumbnail?.locked ?? false;
    return AspectRatio(
      aspectRatio: 1 / 1.3,
      child: ColoredBox(
        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        child: Center(
          child: Icon(
            locked
                ? Icons.lock_outline_rounded
                : file.isPdf
                ? Icons.picture_as_pdf_outlined
                : Icons.insert_drive_file_outlined,
            size: iconSize,
            color: locked
                ? DsColors.textSecondary(
                    isDark ? Brightness.dark : Brightness.light,
                  )
                : DsColors.primary.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}
