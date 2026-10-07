import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Summary of an image downsampling pass.
class PdfImageDownsampleResult {
  const PdfImageDownsampleResult({
    required this.imagesFound,
    required this.imagesReplaced,
    required this.bytesSaved,
  });

  final int imagesFound;
  final int imagesReplaced;
  final int bytesSaved;
}

/// Downscales and re-encodes embedded JPEG (DCTDecode) images with qpdf JSON.
///
/// qpdf's `--optimize-images` only converts non-JPEG images and never
/// resamples, so scanned/photo PDFs barely shrink without this pass. Images are
/// replaced only when the new stream is at least 10% smaller; page content,
/// text, and vector graphics are untouched.
Future<PdfImageDownsampleResult> downsamplePdfJpegImages({
  required String inputPath,
  required String outputPath,
  required int maxSidePx,
  required int jpegQuality,
  String? password,
  void Function(double fraction, String message)? onProgress,
  bool Function()? isCancelled,
}) async {
  final exe = await resolvedQpdfExecutable();
  final pw = [
    if (password != null && password.isNotEmpty) '--password=$password',
  ];

  final dump = await runQpdfProtected([
    ...pw,
    '--json=2',
    '--json-key=qpdf',
    '--json-stream-data=none',
    inputPath,
  ], (a) => Process.run(exe, a, stdoutEncoding: utf8));
  if (dump.exitCode != 0 && dump.exitCode != 3) {
    throw QpdfCliException(
      exitCode: dump.exitCode,
      stderr: '${dump.stderr}',
      stdout: '',
    );
  }
  final plan = await Isolate.run(() => _planFromDump(dump.stdout as String));
  if (plan.candidates.isEmpty) {
    await File(inputPath).copy(outputPath);
    return const PdfImageDownsampleResult(
      imagesFound: 0,
      imagesReplaced: 0,
      bytesSaved: 0,
    );
  }

  final workDir = await Directory.systemTemp.createTemp('ds_downsample_');
  try {
    final updates = <String, Object?>{};
    var saved = 0;
    var done = 0;
    final total = plan.candidates.length;
    final queue = List<_Candidate>.of(plan.candidates);

    Future<void> processOne(_Candidate c) async {
      final raw = await runQpdfProtected([
        ...pw,
        inputPath,
        '--show-object=${c.objectNumber}',
        '--raw-stream-data',
      ], (a) => Process.run(exe, a, stdoutEncoding: null));
      if (raw.exitCode != 0 && raw.exitCode != 3) return;
      final original = Uint8List.fromList(raw.stdout as List<int>);
      final encoded = await Isolate.run(
        () => _recompressJpeg(original, maxSidePx, jpegQuality),
      );
      if (encoded == null || encoded.bytes.length > original.length * 0.9) {
        return;
      }
      final dataPath = p.join(workDir.path, 'img_${c.objectNumber}.jpg');
      await File(dataPath).writeAsBytes(encoded.bytes, flush: true);
      final dict = Map<String, Object?>.of(c.dict)
        ..remove('/Length')
        ..remove('/DecodeParms')
        ..['/Filter'] = '/DCTDecode'
        ..['/BitsPerComponent'] = 8
        ..['/Width'] = encoded.width
        ..['/Height'] = encoded.height
        ..['/ColorSpace'] = encoded.components == 1
            ? '/DeviceGray'
            : '/DeviceRGB';
      updates[c.key] = {
        'stream': {'dict': dict, 'datafile': dataPath},
      };
      saved += original.length - encoded.bytes.length;
    }

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        if (isCancelled?.call() ?? false) return;
        await processOne(queue.removeAt(0));
        done++;
        onProgress?.call(done / total, 'Optimizing images · $done of $total');
      }
    }

    final parallel = (Platform.numberOfProcessors - 1).clamp(1, 6);
    await Future.wait([for (var i = 0; i < parallel; i++) worker()]);

    if (updates.isEmpty || (isCancelled?.call() ?? false)) {
      await File(inputPath).copy(outputPath);
      return PdfImageDownsampleResult(
        imagesFound: plan.candidates.length,
        imagesReplaced: 0,
        bytesSaved: 0,
      );
    }

    onProgress?.call(1, 'Writing optimized images');
    final updatePath = p.join(workDir.path, 'update.json');
    await File(updatePath).writeAsString(
      jsonEncode({
        'qpdf': [plan.header, updates],
      }),
    );
    final result = await runQpdfProtected([
      ...pw,
      inputPath,
      '--update-from-json=$updatePath',
      outputPath,
    ], (a) => Process.run(exe, a));
    if (result.exitCode != 0 && result.exitCode != 3) {
      throw QpdfCliException(
        exitCode: result.exitCode,
        stderr: '${result.stderr}',
        stdout: '${result.stdout}',
      );
    }
    return PdfImageDownsampleResult(
      imagesFound: plan.candidates.length,
      imagesReplaced: updates.length,
      bytesSaved: saved,
    );
  } finally {
    try {
      await workDir.delete(recursive: true);
    } catch (_) {}
  }
}

class _Candidate {
  const _Candidate(this.key, this.objectNumber, this.dict);

  final String key;
  final int objectNumber;
  final Map<String, Object?> dict;
}

class _Plan {
  const _Plan(this.header, this.candidates);

  final Map<String, Object?> header;
  final List<_Candidate> candidates;
}

/// Picks 8-bit DCT images in Gray/RGB/ICC color spaces with no /Decode array.
_Plan _planFromDump(String json) {
  final root = jsonDecode(json) as Map<String, Object?>;
  final qpdf = root['qpdf'] as List<Object?>;
  final header = Map<String, Object?>.of(qpdf[0] as Map<String, Object?>)
    ..remove('pdfversion');
  final objects = qpdf[1] as Map<String, Object?>;

  bool colorSpaceOk(Object? cs) {
    if (cs == '/DeviceRGB' || cs == '/DeviceGray') return true;
    if (cs is String && cs.endsWith(' R')) {
      final resolved = objects['obj:$cs'];
      if (resolved is Map) return colorSpaceOk(resolved['value']);
      return false;
    }
    if (cs is List && cs.isNotEmpty && cs.first == '/ICCBased') return true;
    return false;
  }

  final out = <_Candidate>[];
  for (final entry in objects.entries) {
    final v = entry.value;
    if (v is! Map || v['stream'] is! Map) continue;
    final dict = (v['stream'] as Map)['dict'];
    if (dict is! Map<String, Object?>) continue;
    if (dict['/Subtype'] != '/Image') continue;
    final filter = dict['/Filter'];
    final isDct =
        filter == '/DCTDecode' ||
        (filter is List && filter.length == 1 && filter.first == '/DCTDecode');
    if (!isDct) continue;
    if (dict['/ImageMask'] == true || dict.containsKey('/Decode')) continue;
    if (dict['/BitsPerComponent'] != 8) continue;
    if (!colorSpaceOk(dict['/ColorSpace'])) continue;
    final w = dict['/Width'];
    final h = dict['/Height'];
    if (w is! int || h is! int || w * h > 80000000 || w * h < 90000) continue;
    final match = RegExp(r'^obj:(\d+) 0 R$').firstMatch(entry.key);
    if (match == null) continue;
    out.add(_Candidate(entry.key, int.parse(match.group(1)!), dict));
  }
  return _Plan(header, out);
}

class _Encoded {
  const _Encoded(this.bytes, this.width, this.height, this.components);

  final Uint8List bytes;
  final int width;
  final int height;
  final int components;
}

_Encoded? _recompressJpeg(Uint8List source, int maxSidePx, int quality) {
  final srcComponents = _jpegComponents(source);
  if (srcComponents != 1 && srcComponents != 3) return null;
  final decoded = img.decodeJpg(source);
  if (decoded == null) return null;
  var frame = decoded;
  final longest = math.max(frame.width, frame.height);
  if (longest > maxSidePx) {
    final scale = maxSidePx / longest;
    frame = img.copyResize(
      frame,
      width: math.max(1, (frame.width * scale).round()),
      height: math.max(1, (frame.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
  }
  final bytes = img.encodeJpg(frame, quality: quality);
  final components = _jpegComponents(bytes);
  if (components != 1 && components != 3) return null;
  return _Encoded(bytes, frame.width, frame.height, components);
}

/// Component count from the first SOF marker, or -1.
int _jpegComponents(Uint8List b) {
  var i = 2;
  while (i + 9 < b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = b[i + 1];
    if (marker == 0xD8 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      i += 2;
      continue;
    }
    final len = (b[i + 2] << 8) | b[i + 3];
    final isSof =
        marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isSof) return b[i + 9];
    i += 2 + len;
  }
  return -1;
}
