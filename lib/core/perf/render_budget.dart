import 'dart:io';

import 'package:flutter/foundation.dart';

enum DeviceTier { low, mid, high }

/// Device-adaptive limits for page rendering and caches.
///
/// Detected once (CPU count + physical RAM where `/proc/meminfo` is readable,
/// i.e. Linux and Android). Unknown RAM falls back to the CPU heuristic.
class RenderBudget {
  const RenderBudget._({
    required this.tier,
    required this.totalRamBytes,
    required this.viewerImageCacheBytes,
    required this.onePassRenderingScaleThreshold,
    required this.cacheExtent,
    required this.pageImageCachingDelay,
    required this.thumbnailMemoryBytes,
    required this.renderConcurrency,
  });

  final DeviceTier tier;
  final int? totalRamBytes;

  /// pdfrx page-image cache cap for one viewer.
  final int viewerImageCacheBytes;

  /// Above this scale pdfrx renders only the visible part of the page at full
  /// resolution (whole-page bitmaps stay small on weak GPUs / low RAM).
  final double onePassRenderingScaleThreshold;

  /// Viewport multiples pre-rendered ahead of scrolling.
  final double cacheExtent;

  /// Debounce before a page render starts; fast flings skip pages entirely.
  final Duration pageImageCachingDelay;

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
          viewerImageCacheBytes: 48 * _mb,
          onePassRenderingScaleThreshold: 1.6,
          cacheExtent: 0.5,
          pageImageCachingDelay: const Duration(milliseconds: 60),
          thumbnailMemoryBytes: 16 * _mb,
          renderConcurrency: 1,
        ),
      DeviceTier.mid => RenderBudget._(
          tier: tier,
          totalRamBytes: ram,
          viewerImageCacheBytes: 100 * _mb,
          onePassRenderingScaleThreshold: 200 / 72,
          cacheExtent: 1.0,
          pageImageCachingDelay: const Duration(milliseconds: 30),
          thumbnailMemoryBytes: 32 * _mb,
          renderConcurrency: 2,
        ),
      DeviceTier.high => RenderBudget._(
          tier: tier,
          totalRamBytes: ram,
          viewerImageCacheBytes: 192 * _mb,
          onePassRenderingScaleThreshold: 200 / 72,
          cacheExtent: 1.5,
          pageImageCachingDelay: const Duration(milliseconds: 20),
          thumbnailMemoryBytes: 64 * _mb,
          renderConcurrency: 2,
        ),
    };
    if (!kReleaseMode) {
      debugPrint(
        '[perf] render budget: ${tier.name} (cpus=$cpus, '
        'ram=${gb?.toStringAsFixed(1) ?? '?'} GB)',
      );
    }
    return budget;
  }

  static int? _readTotalRam() {
    if (!(Platform.isLinux || Platform.isAndroid)) return null;
    try {
      final line = File('/proc/meminfo')
          .readAsLinesSync()
          .firstWhere((l) => l.startsWith('MemTotal:'));
      final kb = int.parse(line.replaceAll(RegExp(r'[^0-9]'), ''));
      return kb * 1024;
    } catch (_) {
      return null;
    }
  }
}
