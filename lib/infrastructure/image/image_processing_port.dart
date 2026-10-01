import 'dart:typed_data';

/// Output format for [ImageProcessingPort.encode].
enum ImageOutputFormat {
  png,
  jpeg,
}

/// Decoded image handle; [internal] is owned by [ImageProcessingPort] implementations.
class DecodedImage {
  const DecodedImage({
    required this.width,
    required this.height,
    required this.internal,
  });

  final int width;
  final int height;

  /// Implementation-specific (e.g. `package:image` [Image]).
  final Object internal;
}

/// Edits applied by [ImageProcessingPort.render], in order: rotate, flip,
/// resize to [width] (aspect preserved), encode.
class ImageEditSpec {
  const ImageEditSpec({
    this.width,
    this.quarterTurns = 0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.format = ImageOutputFormat.jpeg,
    this.jpegQuality = 85,
  });

  /// Output width after rotation; null keeps the full size.
  final int? width;

  /// Clockwise quarter turns.
  final int quarterTurns;
  final bool flipHorizontal;
  final bool flipVertical;
  final ImageOutputFormat format;
  final int jpegQuality;
}

class RenderedImage {
  const RenderedImage({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Abstraction over Dart `image` (and future codecs). Features depend on this, not on `image` directly.
abstract class ImageProcessingPort {
  Future<DecodedImage> decode(Uint8List bytes);

  Future<DecodedImage> resize(
    DecodedImage source, {
    required int width,
    int? height,
  });

  Future<Uint8List> encode(
    DecodedImage image, {
    required ImageOutputFormat format,
    int jpegQuality = 85,
  });

  /// Applies [spec] to [source] and encodes it, off the UI thread.
  Future<RenderedImage> render(DecodedImage source, ImageEditSpec spec);
}
