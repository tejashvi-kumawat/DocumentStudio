/// User-facing compression preset.
enum CompressProfile {
  /// JPEG quality 40, longest edge 1000px.
  smallest,

  /// JPEG quality 45, longest edge 1200px.
  extreme,

  /// JPEG quality 60, longest edge 1600px.
  balanced,

  /// Deflate and unused-object cleanup only. Images are not re-encoded.
  highQuality,

  custom,
}

/// Presets shown in the compress panel, strongest first.
const List<CompressProfile> kCompressPanelProfiles = [
  CompressProfile.smallest,
  CompressProfile.extreme,
  CompressProfile.balanced,
  CompressProfile.highQuality,
];

class PdfCompressOptions {
  const PdfCompressOptions({
    this.profile = CompressProfile.balanced,
    this.linearize = false,
    this.recompressFlate = true,
    this.optimizeImages = false,
    this.jpegQuality,
    this.downsampleMaxPx,
    this.targetDpi,
  });

  final CompressProfile profile;
  final bool linearize;
  final bool recompressFlate;
  final bool optimizeImages;
  final int? jpegQuality;

  /// Longest edge cap for image XObjects, in pixels.
  final int? downsampleMaxPx;

  /// Resolution images are reduced to where they are drawn (like Acrobat's
  /// "downsample to N ppi"). Applied per image from its on-page size, on top
  /// of [downsampleMaxPx].
  final int? targetDpi;

  /// True when this preset re-encodes images (every preset except lossless).
  bool get lossyImages =>
      jpegQuality != null || downsampleMaxPx != null || optimizeImages;

  factory PdfCompressOptions.fromProfile(CompressProfile profile) {
    return switch (profile) {
      CompressProfile.smallest => const PdfCompressOptions(
        profile: CompressProfile.smallest,
        recompressFlate: true,
        optimizeImages: true,
        jpegQuality: 40,
        downsampleMaxPx: 1000,
        targetDpi: 96,
      ),
      CompressProfile.extreme => const PdfCompressOptions(
        profile: CompressProfile.extreme,
        recompressFlate: true,
        optimizeImages: true,
        jpegQuality: 45,
        downsampleMaxPx: 1200,
        targetDpi: 110,
      ),
      CompressProfile.balanced => const PdfCompressOptions(
        profile: CompressProfile.balanced,
        recompressFlate: true,
        optimizeImages: true,
        jpegQuality: 60,
        downsampleMaxPx: 1600,
        targetDpi: 150,
      ),
      CompressProfile.highQuality => const PdfCompressOptions(
        profile: CompressProfile.highQuality,
        recompressFlate: true,
      ),
      CompressProfile.custom => const PdfCompressOptions(
        profile: CompressProfile.custom,
        recompressFlate: true,
      ),
    };
  }

  String get userLabel => switch (profile) {
    CompressProfile.smallest => 'Smallest',
    CompressProfile.extreme => 'Extreme',
    CompressProfile.balanced => 'Recommended',
    CompressProfile.highQuality => 'Lossless',
    CompressProfile.custom => 'Custom',
  };

  /// Plain-language description of what this preset does.
  String get effectDescription => switch (profile) {
    CompressProfile.smallest =>
      'Strongest shrink. Photos are re-encoded as JPEG at quality 40 '
          'with the longest edge at most 1000px. Images still over '
          '400 KB get a second pass. Text pages stay selectable.',
    CompressProfile.extreme =>
      'Very small. Photos are re-encoded as JPEG at quality 45 with the '
          'longest edge at most 1200px. Images still over 400 KB get a '
          'second pass. Text pages stay selectable.',
    CompressProfile.balanced =>
      'Recommended. Photos are re-encoded as JPEG at quality 60 with the '
          'longest edge at most 1600px. Images still over 400 KB get a '
          'second pass. Text stays sharp and selectable.',
    CompressProfile.highQuality =>
      'Lossless. Recompresses streams with deflate and drops unused '
          'objects. Images are not re-encoded, and text stays selectable.',
    CompressProfile.custom => 'Choose exactly which optimizations run.',
  };

  PdfCompressOptions mergeCustom({
    required bool recompressFlate,
    required bool linearize,
    bool optimizeImages = false,
    int? jpegQuality,
    int? downsampleMaxPx,
  }) {
    return PdfCompressOptions(
      profile: CompressProfile.custom,
      recompressFlate: recompressFlate,
      linearize: linearize,
      optimizeImages: optimizeImages,
      jpegQuality: jpegQuality,
      downsampleMaxPx: downsampleMaxPx,
    );
  }
}
