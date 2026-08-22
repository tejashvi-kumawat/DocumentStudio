import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

enum DeviceTier { low, mid, high }

/// Device-adaptive limits for page rendering and caches.
///
/// Detected once from the CPU count and physical RAM (`/proc/meminfo` on
/// Linux and Android, `sysctl hw.memsize` on macOS). Unknown RAM falls back to
/// the CPU heuristic.
class RenderBudget {
  const RenderBudget._({
    required this.tier,
    required this.totalRamBytes,
    required this.viewerImageCacheBytes,
    required this.cacheExtent,
    required this.pageImageCachingDelay,
    required this.limitPdfiumImageCache,
    required this.thumbnailMemoryBytes,
    required this.renderConcurrency,
  });

  final DeviceTier tier;
  final int? totalRamBytes;

  /// pdfrx page-image cache cap for one viewer. Pages scrolled away from stay
  /// decoded up to this size, so scrolling back shows them at once.
  final int viewerImageCacheBytes;

  /// Viewport multiples pre-rendered around the visible area.
  final double cacheExtent;

  /// Debounce before a cached page is re-rendered at a new zoom.
  final Duration pageImageCachingDelay;

  /// Whether PDFium drops decoded page resources (images, fonts) after each
  /// render. Keeping them makes a re-render at a new zoom much cheaper.
  final bool limitPdfiumImageCache;

  /// In-memory decoded thumbnail cap (organize grid, previews).
  final int thumbnailMemoryBytes;

  /// Parallel thumbnail renders.
  final int renderConcurrency;

  static RenderBudget? _current;

  static RenderBudget get current => _current ??= _detect();

  static const _mb = 1024 * 1024;

  static RenderBudget _detect() {
    final cpus = Platform.numberOfProcessors;
    final ram = _readTotalRam();
    final gb = ram == null ? null : ram / (1024 * _mb);
    final DeviceTier tier;
    if ((gb != null && gb < 3.5) || cpus <= 4) {
      tier = DeviceTier.low;
    } else if ((gb != null && gb < 7.5) || cpus <= 6) {
      tier = DeviceTier.mid;
    } else {
      tier = DeviceTier.high;
    }
    final budget = switch (tier) {
      DeviceTier.low => RenderBudget._(
          tier: tier,
          totalRamBytes: ram,
          viewerImageCacheBytes: 64 * _mb,
          cacheExtent: 0.5,
          pageImageCachingDelay: const Duration(milliseconds: 40),
          limitPdfiumImageCache: true,
          thumbnailMemoryBytes: 16 * _mb,
          renderConcurrency: 1,
        ),
      DeviceTier.mid => RenderBudget._(
          tier: tier,
          totalRamBytes: ram,
          viewerImageCacheBytes: 160 * _mb,
          cacheExtent: 0.75,
          pageImageCachingDelay: const Duration(milliseconds: 20),
          limitPdfiumImageCache: false,
          thumbnailMemoryBytes: 32 * _mb,
          renderConcurrency: 2,
        ),
      DeviceTier.high => RenderBudget._(
          tier: tier,
          totalRamBytes: ram,
          // About 1/24 of RAM: 330 MB on 8 GB, 512 MB from 12 GB up.
          viewerImageCacheBytes: ram == null
              ? 256 * _mb
              : (ram ~/ 24).clamp(256 * _mb, 512 * _mb),
          cacheExtent: 1.0,
          pageImageCachingDelay: const Duration(milliseconds: 12),
          limitPdfiumImageCache: false,
          thumbnailMemoryBytes: 64 * _mb,
          renderConcurrency: math.min(3, math.max(2, cpus ~/ 4)),
        ),
    };
    if (!kReleaseMode) {
      debugPrint(
        '[perf] render budget: ${tier.name} (cpus=$cpus, '
        'ram=${gb?.toStringAsFixed(1) ?? '?'} GB, '
        'page cache=${budget.viewerImageCacheBytes ~/ _mb} MB)',
      );
    }
    return budget;
  }

  static int? _readTotalRam() {
    try {
      if (Platform.isLinux || Platform.isAndroid) {
        final line = File('/proc/meminfo')
            .readAsLinesSync()
            .firstWhere((l) => l.startsWith('MemTotal:'));
        final kb = int.parse(line.replaceAll(RegExp(r'[^0-9]'), ''));
        return kb * 1024;
      }
      if (Platform.isMacOS) {
        final out = Process.runSync('/usr/sbin/sysctl', ['-n', 'hw.memsize']);
        return int.tryParse('${out.stdout}'.trim());
      }
    } catch (_) {}
    return null;
  }
}
