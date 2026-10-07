import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
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
    required this.oversample,
    required this.maxRenderLongEdgePx,
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

  /// Minimum pixels per screen pixel for page bitmaps. Above 1 keeps text
  /// crisp at fractional zooms, where a 1:1 bitmap is resampled and softens.
  final double oversample;

  /// Long-edge cap of a whole-page bitmap.
  final double maxRenderLongEdgePx;

  static RenderBudget? _current;

  /// Settings → Viewing → Render quality: `auto`, `high`, `fast`.
  static String userQuality = 'auto';

  /// Pixels per screen pixel actually used (tier default unless overridden).
  double get effectiveOversample => switch (userQuality) {
    'high' => math.max(oversample, 1.5),
    'fast' => 1.0,
    _ => oversample,
  };

  static RenderBudget get current => _current ??= _detect();

  /// Fixed 1:1, 4096 px budget so scale tests do not depend on the host.
  @visibleForTesting
  static void debugUseFixedBudget() {
    _current = const RenderBudget._(
      tier: DeviceTier.mid,
      totalRamBytes: null,
      viewerImageCacheBytes: 160 * 1024 * 1024,
      cacheExtent: 0.75,
      pageImageCachingDelay: Duration(milliseconds: 20),
      limitPdfiumImageCache: false,
      thumbnailMemoryBytes: 32 * 1024 * 1024,
      renderConcurrency: 2,
      oversample: 1,
      maxRenderLongEdgePx: 4096,
    );
  }

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
        oversample: 1.0,
        maxRenderLongEdgePx: 4096,
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
        oversample: 1.5,
        maxRenderLongEdgePx: 6144,
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
        oversample: 1.5,
        maxRenderLongEdgePx: 8192,
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
      if (Platform.isWindows) return _windowsTotalRam();
    } catch (_) {}
    return null;
  }

  /// `GlobalMemoryStatusEx` (kernel32). Without it Windows fell to the CPU
  /// heuristic and often landed on the slowest tier.
  static int? _windowsTotalRam() {
    final status = calloc<Uint8>(64);
    try {
      status.cast<Uint32>().value = 64; // dwLength
      final kernel = DynamicLibrary.open('kernel32.dll');
      final call = kernel
          .lookupFunction<
            Int32 Function(Pointer<Uint8>),
            int Function(Pointer<Uint8>)
          >('GlobalMemoryStatusEx');
      if (call(status) == 0) return null;
      // ullTotalPhys sits at byte offset 8.
      return (status + 8).cast<Uint64>().value;
    } catch (_) {
      return null;
    } finally {
      calloc.free(status);
    }
  }
}
