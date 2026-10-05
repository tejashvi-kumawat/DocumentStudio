import 'dart:isolate';
import 'dart:typed_data';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/infrastructure/image/image_processing_port.dart';
import 'package:image/image.dart' as img;

/// [ImageProcessingPort] backed by `package:image`; all pixel work runs in
/// background isolates.
class ImagePackageAdapter implements ImageProcessingPort {
  ImagePackageAdapter({this.maxDimension = 12000});

  final int maxDimension;

  @override
  Future<DecodedImage> decode(Uint8List bytes) async {
    img.Image? decoded;
    try {
      decoded = await Isolate.run(() {
        final image = img.decodeImage(bytes);
        return image == null ? null : img.bakeOrientation(image);
      });
    } catch (e) {
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.invalidFile,
        message: 'Could not decode image',
        cause: e,
      );
    }
    if (decoded == null) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.unsupportedFormat,
        message: 'Could not decode image',
      );
    }
    _guardDimensions(decoded.width, decoded.height);
    return DecodedImage(
      width: decoded.width,
      height: decoded.height,
      internal: decoded,
    );
  }

  @override
  Future<DecodedImage> resize(
    DecodedImage source, {
    required int width,
    int? height,
  }) async {
    final image = _asImage(source);
    if (width < 1 || (height != null && height < 1)) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.invalidFile,
        message: 'Resize dimensions must be positive',
      );
    }
    final targetHeight = height ??
        (source.height * width / source.width).round().clamp(1, maxDimension);
    _guardDimensions(width, targetHeight);
    try {
      final resized = await Isolate.run(
        () => _resize(image, width, targetHeight),
      );
      return DecodedImage(
        width: resized.width,
        height: resized.height,
        internal: resized,
      );
    } catch (e) {
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.conversionFailed,
        message: 'Resize failed',
        cause: e,
      );
    }
  }

  @override
  Future<Uint8List> encode(
    DecodedImage image, {
    required ImageOutputFormat format,
    int jpegQuality = 85,
  }) async {
    final src = _asImage(image);
    try {
      return await Isolate.run(() => _encode(src, format, jpegQuality));
    } catch (e) {
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.conversionFailed,
        message: 'Encode failed',
        cause: e,
      );
    }
  }

  @override
  Future<RenderedImage> render(DecodedImage source, ImageEditSpec spec) async {
    final src = _asImage(source);
    try {
      return await Isolate.run(() {
        var image = src;
        final turns = ((spec.quarterTurns % 4) + 4) % 4;
        if (turns != 0) image = img.copyRotate(image, angle: 90 * turns);
        if (spec.flipHorizontal && spec.flipVertical) {
          image = img.copyFlip(image, direction: img.FlipDirection.both);
        } else if (spec.flipHorizontal) {
          image = img.copyFlip(image, direction: img.FlipDirection.horizontal);
        } else if (spec.flipVertical) {
          image = img.copyFlip(image, direction: img.FlipDirection.vertical);
        }
        final w = spec.width;
        if (w != null && w >= 1 && w < image.width) {
          final h = (image.height * w / image.width).round().clamp(1, 1 << 20);
          image = _resize(image, w, h);
        }
        return RenderedImage(
          bytes: _encode(image, spec.format, spec.jpegQuality),
          width: image.width,
          height: image.height,
        );
      });
    } catch (e) {
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.conversionFailed,
        message: 'Could not process image',
        cause: e,
      );
    }
  }

  img.Image _asImage(DecodedImage handle) {
    if (handle.internal is! img.Image) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.invalidFile,
        message: 'Invalid image handle',
      );
    }
    return handle.internal as img.Image;
  }

  void _guardDimensions(int width, int height) {
    if (width > maxDimension || height > maxDimension) {
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.outOfMemory,
        message: 'Image is too large to edit ($width×$height px). '
            'The maximum is $maxDimension px per side.',
      );
    }
  }
}

img.Image _resize(img.Image image, int width, int height) {
  return img.copyResize(
    image,
    width: width,
    height: height,
    interpolation: width < image.width
        ? img.Interpolation.average
        : img.Interpolation.cubic,
  );
}

Uint8List _encode(img.Image src, ImageOutputFormat format, int jpegQuality) {
  img.Image flat(img.Image image) {
    if (!image.hasAlpha) return image;
    final bg = img.Image(width: image.width, height: image.height);
    img.fill(bg, color: img.ColorRgb8(255, 255, 255));
    return img.compositeImage(bg, image);
  }

  switch (format) {
    case ImageOutputFormat.png:
      return Uint8List.fromList(img.encodePng(src, level: 6));
    case ImageOutputFormat.jpeg:
      return Uint8List.fromList(
        img.encodeJpg(flat(src), quality: jpegQuality.clamp(1, 100)),
      );
    case ImageOutputFormat.gif:
      return Uint8List.fromList(img.encodeGif(src));
    case ImageOutputFormat.bmp:
      return Uint8List.fromList(img.encodeBmp(flat(src)));
    case ImageOutputFormat.tiff:
      return Uint8List.fromList(img.encodeTiff(src));
    case ImageOutputFormat.ico:
      var icon = src;
      final longest = icon.width > icon.height ? icon.width : icon.height;
      if (longest > 256) {
        final k = 256 / longest;
        icon = _resize(
          icon,
          (icon.width * k).round().clamp(1, 256),
          (icon.height * k).round().clamp(1, 256),
        );
      }
      return Uint8List.fromList(img.encodeIco(icon));
  }
}
