import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio/core/desktop/desktop_engine_resolver.dart';
import 'package:document_studio/core/storage/storage_paths.dart';
import 'package:document_studio/infrastructure/ocr/android_tesseract_ocr_port.dart';
import 'package:document_studio_ocr/document_studio_ocr.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

/// Thrown when the user cancels a running OCR job.
class OcrCancelledException implements Exception {
  const OcrCancelledException();

  @override
  String toString() => 'OCR cancelled';
}

/// Cooperative cancellation for OCR jobs; kills running tesseract processes.
class OcrCancelToken {
  bool _cancelled = false;
  final Set<Process> _processes = {};

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final process in _processes.toList()) {
      process.kill();
    }
  }

  void throwIfCancelled() {
    if (_cancelled) throw const OcrCancelledException();
  }

  void _attach(Process process) {
    _processes.add(process);
    if (_cancelled) process.kill();
  }

  void _detach(Process process) => _processes.remove(process);
}

/// Resolved Tesseract binary + discovered traineddata languages.
class OcrEngineEnvironment {
  const OcrEngineEnvironment({
    required this.tesseractPath,
    required this.tesseractError,
    required this.languageDirs,
  });

  /// Absolute path of a runnable tesseract, or null.
  final String? tesseractPath;

  /// User-facing reason tesseract is unusable (null when runnable).
  final String? tesseractError;

  /// traineddata id → tessdata directory containing it (first match wins).
  final Map<String, String> languageDirs;

  bool get hasTesseract => tesseractPath != null;

  List<String> get installedLanguages {
    final codes = languageDirs.keys.where((c) => c != 'osd').toList();
    codes.sort((a, b) {
      if (a == 'eng') return -1;
      if (b == 'eng') return 1;
      return ocrLanguageLabel(a).compareTo(ocrLanguageLabel(b));
    });
    return codes;
  }

  List<String> missingLanguages(List<String> codes) => [
    for (final c in codes)
      if (!languageDirs.containsKey(c)) c,
  ];

  /// Orientation & script detection data (`osd.traineddata`) is installed.
  bool get hasOsd => languageDirs.containsKey('osd');

  /// Whether recognition should run Tesseract OSD (`--psm 1`) first.
  bool useOsd(OcrOptions options) => options.autoRotate && hasOsd;

  /// Page-segmentation args for [options]: `--psm 1` (auto + orientation
  /// detection) when OSD data is available, Tesseract's default otherwise.
  List<String> layoutArgs(OcrOptions options) =>
      useOsd(options) ? const ['--psm', '1'] : const [];

  /// One tessdata dir holding every code in [codes] (plus `osd` when
  /// [withOsd]); files spread across folders are merged into a temp dir of
  /// links. Null when a code is missing.
  String? tessdataDirFor(List<String> codes, {bool withOsd = false}) {
    if (codes.isEmpty || missingLanguages(codes).isNotEmpty) return null;
    final needed = [...codes, if (withOsd && hasOsd) 'osd'];
    final dirs = <String>{for (final c in needed) languageDirs[c]!};
    if (dirs.length == 1) return dirs.first;
    for (final dir in dirs) {
      if (needed.every(
        (c) => File(p.join(dir, '$c.traineddata')).existsSync(),
      )) {
        return dir;
      }
    }
    final key = needed.map((c) => '$c=${languageDirs[c]}').join('|').hashCode;
    final merged = p.join(
      Directory.systemTemp.path,
      'ds_tessdata_${key.toUnsigned(32).toRadixString(16)}',
    );
    try {
      Directory(merged).createSync(recursive: true);
      for (final c in needed) {
        final target = p.join(languageDirs[c]!, '$c.traineddata');
        final link = p.join(merged, '$c.traineddata');
        if (FileSystemEntity.typeSync(link, followLinks: false) !=
            FileSystemEntityType.notFound) {
          continue;
        }
        try {
          Link(link).createSync(target);
        } catch (_) {
          File(target).copySync(link);
        }
      }
      return merged;
    } catch (_) {
      return null;
    }
  }

  /// Null when OCR in [language] can run; otherwise a precise, actionable
  /// message naming the missing binary or traineddata file(s).
  String? readinessError(String language) {
    if (tesseractError != null) return tesseractError;
    final codes = [
      for (final part in language.split('+'))
        if (part.trim().isNotEmpty) part.trim(),
    ];
    if (codes.isEmpty) return 'Choose at least one OCR language.';
    final missing = missingLanguages(codes);
    if (missing.isNotEmpty) {
      final names = missing.map(ocrLanguageLabel).join(', ');
      return 'Language data for $names is not installed. Use '
          '"Add languages" to download it (${missing.map((c) => '$c.traineddata').join(', ')}).';
    }
    if (tessdataDirFor(codes) == null) {
      return 'Could not prepare the OCR language folder for '
          '${codes.map(ocrLanguageLabel).join(', ')}.';
    }
    return null;
  }
}

OcrEngineEnvironment? _cachedEnvironment;
Future<OcrEngineEnvironment>? _pendingEnvironment;

/// Drops the cached probe so the next call re-scans binaries and tessdata.
void invalidateOcrEngineEnvironment() {
  _cachedEnvironment = null;
  _pendingEnvironment = null;
}

/// Probes tesseract and tessdata once per session (cheap to call repeatedly).
Future<OcrEngineEnvironment> loadOcrEngineEnvironment({
  DesktopEngineResolver? resolver,
  bool refresh = false,
}) {
  if (refresh) invalidateOcrEngineEnvironment();
  final cached = _cachedEnvironment;
  if (cached != null) return Future.value(cached);
  return _pendingEnvironment ??= _probe(resolver ?? desktopEngineResolver)
      .then((env) => _cachedEnvironment = env)
      .whenComplete(() => _pendingEnvironment = null);
}

/// Shown when a build has no on-device OCR engine wired (e.g. web).
const kOcrMobileUnavailable =
    'Text recognition is not available in this build.';

/// Searchable-PDF / qpdf path is desktop-only.
const kOcrSearchablePdfMobileUnavailable =
    'Making a PDF searchable needs the qpdf tool, which runs on the '
    'desktop app (Windows, macOS, Linux). On this device you can still '
    'copy text from images with OCR.';

String _missingTesseractMessage() {
  if (Platform.isMacOS) {
    return 'OCR engine not found. Reinstall Document Studio so '
        'Contents/MacOS/engines includes tesseract. A Homebrew tesseract '
        'is used only when the app copy is missing.';
  }
  if (Platform.isWindows) {
    return 'OCR engine not found. Reinstall Document Studio so engines/ '
        'includes tesseract. A system tesseract is used only when the '
        'app copy is missing.';
  }
  return 'OCR engine not found: tesseract is not in the app engines folder. '
      'Reinstall Document Studio. A system tesseract is used only when '
      'the app copy is missing.';
}

Future<OcrEngineEnvironment> _probe(DesktopEngineResolver resolver) async {
  if (Platform.isAndroid || Platform.isIOS) {
    // On-device OCR uses flutter_tesseract_ocr (no CLI). Probe tessdata from
    // bundled assets (copied by the plugin) + user downloads.
    final languageDirs = await _probeMobileLanguageDirs();
    final hasEng = languageDirs.containsKey('eng');
    return OcrEngineEnvironment(
      tesseractPath: hasEng ? 'flutter_tesseract_ocr' : null,
      tesseractError: hasEng
          ? null
          : 'English OCR data (eng.traineddata) is missing from the app '
                'bundle (assets/tessdata/). Reinstall the app, or download eng '
                'via Add languages.',
      languageDirs: languageDirs,
    );
  }
  String? tessPath;
  String? tessError;
  final resolved = await resolver.resolveTesseract();
  if (resolved == null) {
    tessError = _missingTesseractMessage();
  } else {
    try {
      final v = await Process.run(resolved, [
        '--version',
      ]).timeout(const Duration(seconds: 10));
      if (v.exitCode == 0) {
        tessPath = resolved;
      } else {
        tessError =
            'OCR engine failed to start ($resolved, exit '
            '${v.exitCode}).';
      }
    } catch (e) {
      tessError = 'OCR engine failed to start ($resolved): $e';
    }
  }

  final dirs = <String>[
    ?resolver.resolveTessdataPrefix(),
    ocrUserTessdataDir(),
    _legacyUserTessdataDir(),
    ?Platform.environment['TESSDATA_PREFIX'],
    if (tessPath != null) p.join(p.dirname(tessPath), 'tessdata'),
    '/usr/share/tesseract-ocr/5/tessdata',
    '/usr/share/tesseract-ocr/4.00/tessdata',
    '/usr/share/tessdata',
    '/usr/local/share/tessdata',
    '/usr/local/share/tesseract-ocr/tessdata',
    '/opt/homebrew/share/tessdata',
  ];
  final languageDirs = <String, String>{};
  for (final dir in dirs) {
    final d = Directory(dir);
    if (!d.existsSync()) continue;
    try {
      for (final entity in d.listSync()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.endsWith('.traineddata')) continue;
        final code = name.substring(0, name.length - '.traineddata'.length);
        languageDirs.putIfAbsent(code, () => p.normalize(dir));
      }
    } catch (_) {}
  }
  return OcrEngineEnvironment(
    tesseractPath: tessPath,
    tesseractError: tessError,
    languageDirs: languageDirs,
  );
}

/// Bundled asset eng + anything in app-support `ocr-languages/` or the
/// plugin's documents `tessdata/` folder.
Future<Map<String, String>> _probeMobileLanguageDirs() async {
  final languageDirs = <String, String>{
    // Shipped in assets/tessdata/; flutter_tesseract_ocr installs it on use.
    'eng': 'assets/tessdata',
  };
  final scan = <String>[ocrUserTessdataDir(), _legacyUserTessdataDir()];
  try {
    final docs = await getApplicationDocumentsDirectory();
    scan.add(p.join(docs.path, 'tessdata'));
  } catch (_) {}
  for (final dir in scan) {
    final d = Directory(dir);
    if (!d.existsSync()) continue;
    try {
      for (final entity in d.listSync()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.endsWith('.traineddata')) continue;
        final code = name.substring(0, name.length - '.traineddata'.length);
        languageDirs.putIfAbsent(code, () => p.normalize(dir));
      }
    } catch (_) {}
  }
  return languageDirs;
}

/// Last OCR language chosen in an OCR tool; background Find indexing uses it.
String ocrPreferredLanguage = 'eng';

/// `cache/ocr` inside the app storage box (size-capped, cleared by
/// Settings › Clear cache).
String ocrCacheDir() {
  final paths = StoragePaths.maybeInstance;
  if (paths != null) return paths.ocr.path;
  return _legacyOcrCacheDir();
}

String _legacyOcrCacheDir() {
  final env = Platform.environment;
  final home = env['HOME'] ?? env['USERPROFILE'] ?? Directory.systemTemp.path;
  if (Platform.isWindows) {
    return p.join(env['LOCALAPPDATA'] ?? home, 'DocumentStudio', 'ocr');
  }
  if (Platform.isMacOS) {
    return p.join(home, 'Library', 'Caches', 'DocumentStudio', 'ocr');
  }
  final xdg = env['XDG_CACHE_HOME'];
  final base = (xdg != null && xdg.isNotEmpty) ? xdg : p.join(home, '.cache');
  return p.join(base, 'document_studio', 'ocr');
}

/// Writable folder for downloaded traineddata: `ocr-languages/` in the app
/// storage box (inside the sandbox on macOS / iOS / Android).
String ocrUserTessdataDir() {
  final paths = StoragePaths.maybeInstance;
  if (paths != null) return paths.ocrLanguages.path;
  return _legacyUserTessdataDir();
}

/// Where older builds downloaded traineddata; still scanned so nothing has
/// to be downloaded again.
String _legacyUserTessdataDir() {
  final env = Platform.environment;
  final home = env['HOME'] ?? env['USERPROFILE'] ?? Directory.systemTemp.path;
  if (Platform.isWindows) {
    return p.join(env['APPDATA'] ?? home, 'DocumentStudio', 'tessdata');
  }
  if (Platform.isMacOS) {
    return p.join(
      home,
      'Library',
      'Application Support',
      'DocumentStudio',
      'tessdata',
    );
  }
  final xdg = env['XDG_DATA_HOME'];
  final base = (xdg != null && xdg.isNotEmpty)
      ? xdg
      : p.join(home, '.local', 'share');
  return p.join(base, 'document_studio', 'tessdata');
}

/// Source for [downloadOcrLanguageData] (small, fast LSTM models).
const kTessdataDownloadBase =
    'https://github.com/tesseract-ocr/tessdata_fast/raw/main';

/// Approximate download sizes (MB) shown before downloading.
const kOcrLanguageDownloadMb = <String, int>{
  'osd': 10,
  'chi_sim': 3,
  'chi_tra': 3,
  'jpn': 3,
  'kor': 2,
};

/// Downloads `<code>.traineddata` into [ocrUserTessdataDir] and refreshes the
/// cached environment. [onProgress] receives a 0–1 fraction when the size is
/// known.
Future<void> downloadOcrLanguageData(
  String code, {
  void Function(double? fraction)? onProgress,
  OcrCancelToken? cancelToken,
}) async {
  if (!RegExp(r'^[a-z][a-z_]{1,15}$').hasMatch(code)) {
    throw ArgumentError.value(code, 'code', 'Invalid language id');
  }
  final dir = Directory(ocrUserTessdataDir());
  await dir.create(recursive: true);
  final target = File(p.join(dir.path, '$code.traineddata'));
  final part = File('${target.path}.part');
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..userAgent = 'DocumentStudio';
  try {
    final request = await client.getUrl(
      Uri.parse('$kTessdataDownloadBase/$code.traineddata'),
    );
    final response = await request.close();
    if (response.statusCode == 404) {
      throw OcrEngineBlockedException(
        'No OCR language data is published for "${ocrLanguageLabel(code)}".',
      );
    }
    if (response.statusCode != 200) {
      throw OcrEngineBlockedException(
        'Download failed (HTTP ${response.statusCode}). Check your internet '
        'connection and try again.',
      );
    }
    final total = response.contentLength > 0 ? response.contentLength : null;
    final sink = part.openWrite();
    var received = 0;
    try {
      await for (final chunk in response) {
        if (cancelToken?.isCancelled ?? false) {
          throw const OcrCancelledException();
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(total == null ? null : received / total);
      }
    } finally {
      await sink.close();
    }
    if (received < 64 * 1024 || (total != null && received != total)) {
      throw OcrEngineBlockedException(
        'The download of ${ocrLanguageLabel(code)} was incomplete. Try again.',
      );
    }
    await part.rename(target.path);
  } on SocketException {
    throw OcrEngineBlockedException(
      'Could not reach the download server. Check your internet connection.',
    );
  } on HandshakeException {
    throw OcrEngineBlockedException(
      'Secure connection to the download server failed.',
    );
  } finally {
    client.close(force: true);
    if (part.existsSync()) {
      try {
        part.deleteSync();
      } catch (_) {}
    }
  }
  invalidateOcrEngineEnvironment();
  if (Platform.isAndroid || Platform.isIOS) {
    AndroidTesseractOcrPort.invalidateLanguageSync();
  }
}

/// Runs tesseract with [args], returning stdout. Honors [cancelToken].
///
/// [singleThread] limits OpenMP to one thread so several pages can run in
/// parallel without oversubscribing the CPU.
Future<String> runTesseractProcess({
  required String executable,
  required List<String> args,
  required String? tessdataDir,
  OcrCancelToken? cancelToken,
  bool singleThread = false,
}) async {
  cancelToken?.throwIfCancelled();
  final env = <String, String>{
    'TESSDATA_PREFIX': ?tessdataDir,
    if (singleThread) 'OMP_THREAD_LIMIT': '1',
  };
  final fullArgs = [
    ...args,
    if (tessdataDir != null) ...['--tessdata-dir', tessdataDir],
  ];
  final process = await Process.start(executable, fullArgs, environment: env);
  cancelToken?._attach(process);
  try {
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    final code = await process.exitCode;
    final out = await stdoutFuture;
    final err = await stderrFuture;
    cancelToken?.throwIfCancelled();
    if (code != 0) {
      throw OcrEngineBlockedException(_friendlyTesseractError(err, code));
    }
    return out;
  } finally {
    cancelToken?._detach(process);
  }
}

String _friendlyTesseractError(String stderr, int code) {
  final lang = RegExp(r"Failed loading language '([^']+)'").firstMatch(stderr);
  if (lang != null) {
    return 'Missing OCR language data: ${lang.group(1)}.traineddata.';
  }
  final trimmed = stderr
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('Estimating resolution'))
      .join(' ');
  return trimmed.isEmpty
      ? 'OCR engine failed (exit $code).'
      : 'OCR engine failed: $trimmed';
}

/// Result of rasterizing a PDF page for OCR.
class OcrPageRaster {
  const OcrPageRaster({
    required this.path,
    required this.width,
    required this.height,
    required this.dpi,
  });

  final String path;
  final int width;
  final int height;

  /// Effective DPI (may be lower than requested for very large pages).
  final int dpi;
}

/// Longest bitmap side for OCR; larger pages get a lower effective DPI.
const int kOcrMaxRasterSidePx = 7000;

/// Renders [page] (display orientation, annotations excluded) to a grayscale
/// PGM at [dpi]. Pixel conversion runs on a background isolate.
///
/// Bitmap size is `round(pt * dpi / 72)`, so a Tesseract PDF produced with
/// `--dpi <dpi>` has the same point size as the page.
Future<OcrPageRaster> renderPdfPageForOcr(
  PdfPage page, {
  required int dpi,
  required String path,
  bool enhance = false,
}) async {
  final longestPt = math.max(page.width, page.height);
  var effectiveDpi = dpi;
  if (longestPt * effectiveDpi / 72 > kOcrMaxRasterSidePx) {
    effectiveDpi = (kOcrMaxRasterSidePx * 72 / longestPt).floor();
    effectiveDpi = effectiveDpi.clamp(72, dpi);
  }
  final w = math.max(1, (page.width * effectiveDpi / 72).round());
  final h = math.max(1, (page.height * effectiveDpi / 72).round());
  final image = await page.render(
    width: w,
    height: h,
    fullWidth: w.toDouble(),
    fullHeight: h.toDouble(),
    backgroundColor: 0xffffffff,
    annotationRenderingMode: PdfAnnotationRenderingMode.none,
  );
  if (image == null) {
    throw OcrEngineBlockedException(
      'Could not render page ${page.pageNumber} for OCR.',
    );
  }
  try {
    final pixels = image.pixels;
    final iw = image.width;
    final ih = image.height;
    await Isolate.run(() => _writeGrayPgm(path, pixels, iw, ih, enhance));
    return OcrPageRaster(path: path, width: iw, height: ih, dpi: effectiveDpi);
  } finally {
    image.dispose();
  }
}

/// Converts BGRA pixels to an 8-bit PGM; [enhance] stretches contrast using
/// the 1st/99th luminance percentiles (helps faded or gray scans).
void _writeGrayPgm(
  String path,
  Uint8List bgra,
  int width,
  int height,
  bool enhance,
) {
  final count = width * height;
  final gray = Uint8List(count);
  for (var i = 0, j = 0; i < count; i++, j += 4) {
    gray[i] = (bgra[j] * 29 + bgra[j + 1] * 150 + bgra[j + 2] * 77) >> 8;
  }
  if (enhance && count > 0) {
    final hist = List<int>.filled(256, 0);
    for (final v in gray) {
      hist[v]++;
    }
    final lowTarget = count ~/ 100;
    final highTarget = count - count ~/ 100;
    var acc = 0;
    var lo = 0;
    var hi = 255;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc <= lowTarget) lo = v;
      if (acc >= highTarget) {
        hi = v;
        break;
      }
    }
    if (hi - lo >= 32) {
      final lut = Uint8List(256);
      for (var v = 0; v < 256; v++) {
        lut[v] = ((v - lo) * 255 / (hi - lo)).round().clamp(0, 255);
      }
      for (var i = 0; i < count; i++) {
        gray[i] = lut[gray[i]];
      }
    }
  }
  final header = ascii.encode('P5\n$width $height\n255\n');
  final file = File(path).openSync(mode: FileMode.write);
  try {
    file.writeFromSync(header);
    file.writeFromSync(gray);
  } finally {
    file.closeSync();
  }
}

/// Number of pages to OCR concurrently (one tesseract thread each).
int ocrParallelism() {
  final cpus = Platform.numberOfProcessors;
  return (cpus - 1).clamp(1, 6);
}
