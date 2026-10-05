import 'qpdf_secure_args.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:document_studio_qpdf/src/qpdf_availability.dart';
import 'package:document_studio_qpdf/src/qpdf_page_spec.dart';
import 'package:path/path.dart' as p;

/// Axis-aligned crop rectangle in PDF user space (points, origin bottom-left).
class PdfCropRectPt {
  const PdfCropRectPt({
    required this.llx,
    required this.lly,
    required this.urx,
    required this.ury,
  });

  final double llx;
  final double lly;
  final double urx;
  final double ury;

  double get width => urx - llx;
  double get height => ury - lly;

  List<num> toJsonArray() => [
        _roundPt(llx),
        _roundPt(lly),
        _roundPt(urx),
        _roundPt(ury),
      ];

  static num _roundPt(double v) =>
      double.parse(v.toStringAsFixed(2));
}

/// Runs qpdf CLI for operations not yet in pdfrx FFI path.
class QpdfCliRunner {
  QpdfCliRunner({String? executable}) : _executableOverride = executable;

  final String? _executableOverride;
  String? _resolvedExecutable;

  Future<String> _exe() async {
    if (_executableOverride case final exe?) return exe;
    return _resolvedExecutable ??= await resolvedQpdfExecutable();
  }

  Future<void> mergeFiles({
    required List<String> inputPaths,
    required String outputPath,
    String? password,
    Map<String, String>? passwordsByPath,
  }) async {
    if (inputPaths.isEmpty) {
      throw ArgumentError('No input files');
    }
    await Directory(p.dirname(outputPath)).create(recursive: true);
    final args = <String>['--empty', '--pages'];
    // Syntax: --pages file [--password=pw] [range] file ... --  (single `--`).
    for (final path in inputPaths) {
      args.add(path);
      final pw = passwordsByPath?[path] ?? password;
      if (pw != null && pw.isNotEmpty) {
        args.add('--password=$pw');
      }
      args.add('1-z');
    }
    args.addAll(['--', outputPath]);
    await _run(args);
  }

  /// Encrypt [inputPath] with AES ([keyLength] 40, 128, or 256).
  Future<void> encrypt({
    required String inputPath,
    required String outputPath,
    required String userPassword,
    String ownerPassword = '',
    int keyLength = 256,
    String? inputPassword,
    bool allowPrinting = true,
    bool allowModify = false,
    bool allowExtract = false,
    bool allowAnnotate = false,
  }) async {
    if (!{40, 128, 256}.contains(keyLength)) {
      throw ArgumentError('keyLength must be 40, 128, or 256');
    }
    await Directory(p.dirname(outputPath)).create(recursive: true);
    final restricted =
        !allowPrinting || !allowModify || !allowExtract || !allowAnnotate;
    // qpdf refuses an empty owner password next to a user password. Without
    // an explicit one, restrictions get an unguessable owner password; with no
    // restrictions the open password doubles as the owner password.
    final owner = ownerPassword.isNotEmpty
        ? ownerPassword
        : (restricted ? _randomPassword() : userPassword);
    final args = <String>[];
    if (inputPassword != null && inputPassword.isNotEmpty) {
      args.add('--password=$inputPassword');
    }
    args.addAll(['--encrypt', userPassword, owner, '$keyLength']);
    if (keyLength == 40) {
      args.addAll([
        '--allow-weak-crypto',
        '--print=${allowPrinting ? 'y' : 'n'}',
        '--modify=${allowModify ? 'y' : 'n'}',
        '--extract=${allowExtract ? 'y' : 'n'}',
        '--annotate=${allowAnnotate ? 'y' : 'n'}',
      ]);
    } else {
      if (keyLength == 128) args.add('--use-aes=y');
      args.addAll([
        if (!allowPrinting) '--print=none',
        if (!allowModify) '--modify=none',
        if (!allowExtract) '--extract=n',
        if (!allowAnnotate) '--annotate=n',
      ]);
    }
    args.addAll(['--', inputPath, outputPath]);
    await _run(args);
  }

  static String _randomPassword() {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789-_';
    final rnd = Random.secure();
    return List.generate(32, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  /// Stream / object optimization; optionally recompress images (lossy).
  Future<void> compressPdf({
    required String inputPath,
    required String outputPath,
    String? password,
    bool linearize = false,
    bool recompressFlate = true,
    bool optimizeImages = false,
    int? jpegQuality,
  }) async {
    await Directory(p.dirname(outputPath)).create(recursive: true);
    final args = <String>[];
    if (password != null && password.isNotEmpty) {
      args.add('--password=$password');
    }
    if (linearize) args.add('--linearize');
    if (recompressFlate) args.add('--recompress-flate');
    if (optimizeImages) {
      args.add('--optimize-images');
      if (jpegQuality != null) {
        args.add('--jpeg-quality=$jpegQuality');
      }
    }
    args.addAll([
      '--object-streams=generate',
      '--stream-data=compress',
      inputPath,
      outputPath,
    ]);
    await _run(args);
  }

  /// Trims visible margins by adjusting the CropBox (does not re-render content).
  Future<void> cropPages({
    required String inputPath,
    required String outputPath,
    required double marginMm,
    required Set<int> pages1Based,
    String? password,
  }) async {
    if (pages1Based.isEmpty) {
      throw ArgumentError('No pages selected');
    }
    if (marginMm <= 0) {
      await _copyFile(inputPath, outputPath);
      return;
    }
    final marginPt = marginMm * 72 / 25.4;
    await cropPagesToRects(
      inputPath: inputPath,
      outputPath: outputPath,
      pages1Based: pages1Based,
      password: password,
      rectForPage: (media) => PdfCropRectPt(
        llx: media.llx + marginPt,
        lly: media.lly + marginPt,
        urx: media.urx - marginPt,
        ury: media.ury - marginPt,
      ),
    );
  }

  /// Sets CropBox on [pages1Based] to an absolute rectangle in PDF points.
  Future<void> cropPagesToBox({
    required String inputPath,
    required String outputPath,
    required PdfCropRectPt box,
    required Set<int> pages1Based,
    String? password,
  }) async {
    if (pages1Based.isEmpty) {
      throw ArgumentError('No pages selected');
    }
    if (box.width <= 1 || box.height <= 1) {
      throw ArgumentError('Crop rectangle is too small');
    }
    await cropPagesToRects(
      inputPath: inputPath,
      outputPath: outputPath,
      pages1Based: pages1Based,
      password: password,
      rectForPage: (_) => box,
    );
  }

  /// Applies per-page CropBox updates via qpdf JSON (no --set-box required).
  Future<void> cropPagesToRects({
    required String inputPath,
    required String outputPath,
    required Set<int> pages1Based,
    required PdfCropRectPt Function(PdfCropRectPt mediaBox) rectForPage,
    String? password,
  }) async {
    await Directory(p.dirname(outputPath)).create(recursive: true);
    final tempDir = await Directory.systemTemp.createTemp('ds_qpdf_crop_');
    final jsonPath = p.join(tempDir.path, 'doc.json');
    final updatePath = p.join(tempDir.path, 'update.json');
    try {
      final dumpArgs = <String>[
        if (password != null && password.isNotEmpty) '--password=$password',
        '--json-output',
        '--json-key=pages',
        inputPath,
        jsonPath,
      ];
      await _run(dumpArgs);

      final root = jsonDecode(await File(jsonPath).readAsString())
          as Map<String, dynamic>;
      final qpdfList = root['qpdf'];
      if (qpdfList is! List || qpdfList.length < 2) {
        throw QpdfCliException(
          exitCode: 2,
          stderr: 'Unexpected qpdf JSON layout (missing objects)',
          stdout: '',
        );
      }
      final objects = Map<String, dynamic>.from(
        qpdfList[1] as Map<String, dynamic>,
      );

      PdfCropRectPt? mediaFromObj(Map<String, dynamic> value) {
        final box = value['/MediaBox'] ?? value['/CropBox'];
        if (box is! List || box.length < 4) return null;
        return PdfCropRectPt(
          llx: (box[0] as num).toDouble(),
          lly: (box[1] as num).toDouble(),
          urx: (box[2] as num).toDouble(),
          ury: (box[3] as num).toDouble(),
        );
      }

      Map<String, dynamic>? pageValue(String objKey) {
        final entry = objects[objKey];
        if (entry is! Map) return null;
        final value = entry['value'];
        if (value is Map<String, dynamic>) return value;
        if (value is Map) return Map<String, dynamic>.from(value);
        return null;
      }

      final pagesMeta = root['pages'];
      final pageObjKeys = <int, String>{};
      if (pagesMeta is List) {
        for (final page in pagesMeta) {
          if (page is! Map) continue;
          final pos = page['pageposfrom1'];
          final obj = page['object'];
          if (pos is int && obj is String) {
            pageObjKeys[pos] = 'obj:$obj';
          }
        }
      }
      if (pageObjKeys.isEmpty) {
        // Fallback: scan objects for /Type /Page
        var index = 0;
        for (final key in objects.keys) {
          final value = pageValue(key);
          if (value == null) continue;
          if (value['/Type'] == '/Page') {
            index += 1;
            pageObjKeys[index] = key;
          }
        }
      }

      final updateObjects = <String, dynamic>{};
      for (final pageNum in pages1Based) {
        final objKey = pageObjKeys[pageNum];
        if (objKey == null) {
          throw QpdfCliException(
            exitCode: 2,
            stderr: 'Page $pageNum not found for crop',
            stdout: '',
          );
        }
        final value = pageValue(objKey);
        if (value == null) {
          throw QpdfCliException(
            exitCode: 2,
            stderr: 'Page object $objKey missing value',
            stdout: '',
          );
        }
        var media = mediaFromObj(value);
        // Inherit MediaBox from parent Pages tree when absent on the page.
        if (media == null) {
          var parent = value['/Parent'];
          while (parent is String && media == null) {
            final parentValue = pageValue('obj:$parent');
            if (parentValue == null) break;
            media = mediaFromObj(parentValue);
            parent = parentValue['/Parent'];
          }
        }
        media ??= const PdfCropRectPt(llx: 0, lly: 0, urx: 612, ury: 792);
        final crop = rectForPage(media);
        final next = Map<String, dynamic>.from(value);
        next['/CropBox'] = crop.toJsonArray();
        updateObjects[objKey] = {'value': next};
      }

      final updateDoc = {
        'qpdf': [
          {'jsonversion': 2},
          updateObjects,
        ],
      };
      await File(updatePath).writeAsString(jsonEncode(updateDoc));

      final applyArgs = <String>[
        if (password != null && password.isNotEmpty) '--password=$password',
        inputPath,
        '--update-from-json=$updatePath',
        outputPath,
      ];
      await _run(applyArgs);
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Sets MediaBox and CropBox to a standard paper size (no content scaling).
  Future<void> setPageSize({
    required String inputPath,
    required String outputPath,
    required String paperSizeName,
    required Set<int> pages1Based,
    String? password,
  }) async {
    if (pages1Based.isEmpty) {
      throw ArgumentError('No pages selected');
    }
    if (!await _helpOptionAvailable('--set-box')) {
      throw QpdfCliException(
        exitCode: 2,
        stderr: 'qpdf on PATH does not support --set-box (page resize unavailable)',
        stdout: '',
      );
    }
    await Directory(p.dirname(outputPath)).create(recursive: true);
    final pageSpec = buildQpdfPageSpec(pages1Based);
    final size = paperSizeName.toLowerCase();
    final args = <String>[inputPath];
    if (password != null && password.isNotEmpty) {
      args.insert(0, '--password=$password');
    }
    args.addAll([
      '--pages',
      '.',
      '1-z',
      '--set-box=M=$size:$pageSpec',
      '--set-box=C=$size:$pageSpec',
      '--',
      outputPath,
    ]);
    await _run(args);
  }

  /// Writes an unencrypted copy. [password] may be empty for PDFs that only
  /// carry permission restrictions (no open password).
  Future<void> decryptPdf({
    required String inputPath,
    required String outputPath,
    required String password,
  }) async {
    await Directory(p.dirname(outputPath)).create(recursive: true);
    await _run([
      if (password.isNotEmpty) '--password=$password',
      '--decrypt',
      inputPath,
      outputPath,
    ]);
  }

  /// qpdf `--requires-password`: 0 = open password needed, 2 = not
  /// encrypted, 3 = encrypted but opens without a password (restrictions only).
  Future<int> requiresPasswordStatus(String inputPath) async {
    final result = await Process.run(await _exe(), [
      '--requires-password',
      inputPath,
    ]);
    return result.exitCode;
  }

  /// Page count via `--show-npages`, or null when qpdf cannot open the file.
  Future<int?> pageCount(String inputPath, {String? password}) async {
    final result = await _runProtected([
      if (password != null && password.isNotEmpty) '--password=$password',
      '--show-npages',
      inputPath,
    ]);
    if (result.exitCode != 0 && result.exitCode != 3) return null;
    return int.tryParse('${result.stdout}'.trim());
  }

  /// Clears the Info dictionary and XMP metadata streams.
  Future<void> removeAllMetadata({
    required String inputPath,
    required String outputPath,
    String? password,
  }) async {
    await Directory(p.dirname(outputPath)).create(recursive: true);
    final args = <String>[];
    if (password != null && password.isNotEmpty) {
      args.add('--password=$password');
    }
    args.addAll([
      '--remove-metadata',
      inputPath,
      outputPath,
    ]);
    await _run(args);
  }

  /// Sets or deletes Info dictionary keys ([fields]: empty value deletes the key).
  ///
  /// qpdf 11+ dropped `--set-info` / `--delete-info`. Metadata is rewritten via
  /// `--json-output` + `--update-from-json` against the trailer `/Info` object.
  Future<void> updateDocumentInfo({
    required String inputPath,
    required String outputPath,
    required Map<String, String> fields,
    String? password,
  }) async {
    if (fields.isEmpty) {
      throw ArgumentError('No metadata fields to update');
    }
    await Directory(p.dirname(outputPath)).create(recursive: true);

    final tempDir = await Directory.systemTemp.createTemp('ds_qpdf_meta_');
    final jsonPath = p.join(tempDir.path, 'doc.json');
    final updatePath = p.join(tempDir.path, 'update.json');
    try {
      await _run([
        if (password != null && password.isNotEmpty) '--password=$password',
        '--json-output',
        inputPath,
        jsonPath,
      ]);

      final root =
          jsonDecode(await File(jsonPath).readAsString()) as Map<String, dynamic>;
      final qpdfList = root['qpdf'];
      if (qpdfList is! List || qpdfList.length < 2) {
        throw QpdfCliException(
          exitCode: 2,
          stderr: 'Unexpected qpdf JSON layout while updating metadata.',
          stdout: '',
        );
      }
      final meta = Map<String, dynamic>.from(qpdfList[0] as Map);
      final objects = Map<String, dynamic>.from(qpdfList[1] as Map);
      final trailerEntry = objects['trailer'];
      if (trailerEntry is! Map || trailerEntry['value'] is! Map) {
        throw QpdfCliException(
          exitCode: 2,
          stderr: 'qpdf JSON missing trailer; cannot update Info metadata.',
          stdout: '',
        );
      }
      final trailer =
          Map<String, dynamic>.from(trailerEntry['value'] as Map);

      final updateObjects = <String, dynamic>{};
      String infoObjKey;
      Map<String, dynamic> infoValue;

      final infoRef = trailer['/Info'];
      if (infoRef is String && infoRef.isNotEmpty) {
        infoObjKey = infoRef.startsWith('obj:') ? infoRef : 'obj:$infoRef';
        final existing = objects[infoObjKey];
        if (existing is Map && existing['value'] is Map) {
          infoValue = Map<String, dynamic>.from(existing['value'] as Map);
        } else {
          infoValue = <String, dynamic>{};
        }
      } else {
        final maxId = meta['maxobjectid'];
        final newId = (maxId is int ? maxId : int.tryParse('$maxId') ?? 1) + 1;
        infoObjKey = 'obj:$newId 0 R';
        infoValue = <String, dynamic>{};
        trailer['/Info'] = '$newId 0 R';
        updateObjects['trailer'] = {'value': trailer};
      }

      for (final entry in fields.entries) {
        final key = entry.key.trim();
        if (key.isEmpty) continue;
        final pdfKey = key.startsWith('/') ? key : '/$key';
        final value = entry.value;
        if (value.isEmpty) {
          infoValue.remove(pdfKey);
        } else {
          infoValue[pdfKey] = 'u:$value';
        }
      }

      updateObjects[infoObjKey] = {'value': infoValue};
      final updateDoc = {
        'qpdf': [
          {'jsonversion': 2},
          updateObjects,
        ],
      };
      await File(updatePath).writeAsString(jsonEncode(updateDoc));

      await _run([
        if (password != null && password.isNotEmpty) '--password=$password',
        inputPath,
        '--update-from-json=$updatePath',
        outputPath,
      ]);
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Stamp [overlayPath] onto [inputPath] (1:1 page mapping).
  ///
  /// When [underlay] is true, uses qpdf `--underlay` (behind page content).
  Future<void> overlayPdf({
    required String inputPath,
    required String overlayPath,
    required String outputPath,
    String? password,
    bool repeatFirstOverlayPage = false,
    bool underlay = false,
  }) async {
    await Directory(p.dirname(outputPath)).create(recursive: true);
    final args = <String>[];
    if (password != null && password.isNotEmpty) {
      args.add('--password=$password');
    }
    args.addAll([
      inputPath,
      underlay ? '--underlay' : '--overlay',
      overlayPath,
    ]);
    if (repeatFirstOverlayPage) {
      args.add('--repeat=1');
    }
    args.addAll(['--', outputPath]);
    await _run(args);
  }

  Future<void> rotatePages({
    required String inputPath,
    required String outputPath,
    required int degrees,
    String pageSpec = '1-z',
    String? password,
  }) async {
    final normalized = ((degrees % 360) + 360) % 360;
    if (!{0, 90, 180, 270}.contains(normalized)) {
      throw ArgumentError('degrees must be multiple of 90');
    }
    final args = <String>[inputPath];
    if (password != null && password.isNotEmpty) {
      args.insert(0, '--password=$password');
    }
    args.addAll([
      '--rotate=$normalized:$pageSpec',
      '--',
      outputPath,
    ]);
    await _run(args);
  }

  Future<bool> _helpOptionAvailable(String option) async {
    try {
      final result = await Process.run(await _exe(), ['--help=$option']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> _copyFile(String inputPath, String outputPath) async {
    await Directory(p.dirname(outputPath)).create(recursive: true);
    await File(inputPath).copy(outputPath);
  }

  /// Runs arbitrary qpdf CLI args (bundle-resolved executable).
  ///
  /// qpdf exit `3` means success with warnings and is treated as OK.
  Future<void> runRaw(List<String> args) => _run(args);

  /// Process.run with passwords moved off the command line (see
  /// [runQpdfProtected]). Falls back to plain arguments only if this qpdf
  /// does not understand argument files.
  Future<ProcessResult> _runProtected(List<String> args) async {
    final exe = await _exe();
    return runQpdfProtected(args, (safe) async {
      final r = await Process.run(exe, safe);
      if (!identical(safe, args) &&
          r.exitCode == 2 &&
          '${r.stderr}'.contains('@')) {
        return Process.run(exe, args);
      }
      return r;
    });
  }

  Future<void> _run(List<String> args) async {
    final result = await _runProtected(args);
    // qpdf: 0 = ok, 3 = warnings but output written. Other codes are errors.
    if (result.exitCode != 0 && result.exitCode != 3) {
      throw QpdfCliException(
        exitCode: result.exitCode,
        stderr: '${result.stderr}',
        stdout: '${result.stdout}',
      );
    }
  }
}

class QpdfCliException implements Exception {
  QpdfCliException({
    required this.exitCode,
    required this.stderr,
    required this.stdout,
  });

  final int exitCode;
  final String stderr;
  final String stdout;

  @override
  String toString() => 'qpdf failed ($exitCode): $stderr';
}
