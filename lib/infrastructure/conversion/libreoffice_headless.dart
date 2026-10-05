import 'dart:async';
import 'dart:io';

import 'package:document_studio/core/storage/storage_paths.dart';
import 'package:path/path.dart' as p;

/// Shared LibreOffice headless convert helpers.
///
/// All scratch dirs (output + UserInstallation profile) live under
/// [StoragePaths.temp] so converts do not depend on a full `/tmp`.
class LibreOfficeHeadless {
  LibreOfficeHeadless._();

  static const timeout = Duration(seconds: 240);

  static const diskFullUserMessage = 'Not enough disk space to convert';

  /// Fresh work directory under the app temp box.
  static Future<Directory> createWorkDir({String prefix = 'office-'}) =>
      StoragePaths.createTempDir(prefix);

  // One soffice at a time may own a profile, so runs are queued. The profile
  // is kept between runs: creating it is what made every conversion take
  // many extra seconds.
  static Future<void> _queue = Future.value();
  static Directory? _profile;

  static Future<Directory> _sharedProfile() async {
    final cached = _profile;
    if (cached != null && cached.existsSync()) return cached;
    final root = StoragePaths.maybeInstance?.root.path ?? Directory.systemTemp.path;
    final dir = Directory(p.join(root, 'engines', 'lo_profile'));
    await dir.create(recursive: true);
    return _profile = dir;
  }

  static Future<void> _resetProfile() async {
    final dir = _profile;
    _profile = null;
    try {
      await dir?.delete(recursive: true);
    } catch (_) {}
  }

  /// Starts LibreOffice once in the background so the first real conversion
  /// does not pay the first-launch cost. Safe to call repeatedly.
  static Future<void> prewarm(String exe) async {
    if (_warmed) return;
    _warmed = true;
    try {
      final dir = await createWorkDir(prefix: 'office-warm-');
      await run(
        exe: exe,
        args: const ['--terminate_after_init'],
        workDir: dir.path,
        runTimeout: const Duration(seconds: 60),
      );
      deleteQuietly(dir);
    } catch (_) {
      _warmed = false;
    }
  }

  static bool _warmed = false;

  /// Runs `soffice` with the shared profile (queued; one at a time).
  static Future<ProcessResult> run({
    required String exe,
    required List<String> args,
    required String workDir,
    Duration runTimeout = LibreOfficeHeadless.timeout,
  }) {
    final done = Completer<ProcessResult>();
    _queue = _queue.then((_) async {
      try {
        var result = await _runOnce(exe, args, workDir, runTimeout);
        // A profile damaged by a killed run makes soffice exit at once with
        // nothing produced; rebuild it and try one more time.
        if (result.exitCode != 0 &&
            !looksLikeDiskFull(result.stderr.toString())) {
          await _resetProfile();
          result = await _runOnce(exe, args, workDir, runTimeout);
        }
        done.complete(result);
      } catch (e, st) {
        if (e is TimeoutException) await _resetProfile();
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  static Future<ProcessResult> _runOnce(
    String exe,
    List<String> args,
    String workDir,
    Duration runTimeout,
  ) async {
    final profile = await _sharedProfile();
    // LibreOffice requires a file:// URI with an absolute path (three slashes).
    final userInstallUri = Uri.directory(profile.path).toString();
    final process = await Process.start(
      exe,
      [
        '--headless',
        '--norestore',
        '--nolockcheck',
        '--nodefault',
        '--nologo',
        '--nofirststartwizard',
        '-env:UserInstallation=$userInstallUri',
        ...args,
      ],
      workingDirectory: workDir,
      environment: {
        ...Platform.environment,
        'SAL_USE_VCLPLUGIN': 'svp',
        'SAL_NO_QUERYIME': '1',
        'DBUS_SESSION_BUS_ADDRESS': 'disabled:',
      },
    );
    final stdoutBuf = StringBuffer();
    final stderrBuf = StringBuffer();
    process.stdout.transform(SystemEncoding().decoder).listen(stdoutBuf.write);
    process.stderr.transform(SystemEncoding().decoder).listen(stderrBuf.write);
    final exitCode = await process.exitCode.timeout(
      runTimeout,
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    if (exitCode == -1) {
      throw TimeoutException(
        'LibreOffice timed out after ${runTimeout.inSeconds}s.\n'
        '${stderrBuf.toString().trim()}',
      );
    }
    return ProcessResult(
      process.pid,
      exitCode,
      stdoutBuf.toString(),
      stderrBuf.toString(),
    );
  }

  /// PDF → Word / Excel / PowerPoint with the import filter each target
  /// needs (Writer for docx, Impress for pptx, HTML→Calc for xlsx). Returns
  /// the produced file; throws [StateError] with a readable message.
  static Future<File> convertPdf({
    required String exe,
    required String pdfPath,
    required String target, // docx | xlsx | pptx
    required String outDir,
  }) async {
    final stem = p.basenameWithoutExtension(pdfPath);
    Future<ProcessResult> go(List<String> args) =>
        run(exe: exe, workDir: outDir, args: args);

    Never fail(ProcessResult r, String what) => throw StateError(
          formatConvertError(
            'LibreOffice $what failed (exit ${r.exitCode})',
            stderr: r.stderr.toString(),
            exitCode: r.exitCode,
          ),
        );

    if (target == 'xlsx') {
      // Calc cannot open a PDF as a spreadsheet: go through HTML tables.
      final r1 = await go([
        pdfWriterInfilter,
        '--convert-to',
        'html:HTML (StarWriter)',
        '--outdir',
        outDir,
        pdfPath,
      ]);
      final html = await findProduced(outDir, stem, 'html');
      if (r1.exitCode != 0 || html == null) fail(r1, 'PDF read');
      final r2 = await go([
        '--infilter=HTML (StarCalc)',
        '--convert-to',
        'xlsx:Calc MS Excel 2007 XML',
        '--outdir',
        outDir,
        html.path,
      ]);
      final out = await findProduced(outDir, stem, 'xlsx');
      if (r2.exitCode != 0 || out == null) fail(r2, 'spreadsheet export');
      return out;
    }
    final isDoc = target == 'docx';
    final r = await go([
      isDoc ? pdfWriterInfilter : '--infilter=impress_pdf_import',
      '--convert-to',
      isDoc
          ? 'docx:MS Word 2007 XML'
          : 'pptx:Impress MS PowerPoint 2007 XML',
      '--outdir',
      outDir,
      pdfPath,
    ]);
    final out = await findProduced(outDir, stem, target);
    if (r.exitCode != 0 || out == null) fail(r, 'conversion');
    return out;
  }

  /// PDF import filter so Writer (not Draw) owns the document before DOCX export.
  /// Without this, `--convert-to docx` fails with SfxBaseModel::impl_store.
  static const pdfWriterInfilter = '--infilter=writer_pdf_import';

  /// True when [text] looks like ENOSPC / EDQUOT / LibreOffice write Io failure.
  static bool looksLikeDiskFull(String text) {
    final t = text.toLowerCase();
    if (t.contains('no space left') ||
        t.contains('disk quota exceeded') ||
        t.contains('not enough space') ||
        t.contains('enospc') ||
        t.contains('edquot')) {
      return true;
    }
    // LibreOffice: Error Area:Io Class:Write (often Code:16) when the store fails.
    if (t.contains('sfxbasemodel::impl_store') &&
        (t.contains('class:write') || t.contains('area:io'))) {
      // Filter/format bugs also use impl_store; prefer quota wording only when
      // errno-like tokens appear, otherwise still treat Io Write as space when
      // paired with common OS phrases above. For pure filter failures the
      // message usually includes "please verify input parameters" without
      // space tokens — those are NOT disk-full (Draw→docx). Keep those raw
      // unless we also see write/space signals from the OS.
      return t.contains('quota') ||
          t.contains('no space') ||
          t.contains('enospc') ||
          t.contains('edquot') ||
          t.contains('errno = 28') ||
          t.contains('errno = 122') ||
          t.contains('errno=28') ||
          t.contains('errno=122');
    }
    return false;
  }

  static bool isDiskFullException(Object error) {
    if (error is FileSystemException) {
      final code = error.osError?.errorCode;
      // 28 ENOSPC, 122 EDQUOT (Linux), 69 EDQUOT (macOS), 112 ERROR_DISK_FULL (Win).
      if (code == 28 || code == 122 || code == 69 || code == 112) return true;
      return looksLikeDiskFull('${error.message} ${error.osError}');
    }
    return looksLikeDiskFull(error.toString());
  }

  /// Short UI string for convert failures (never the raw SfxBaseModel blob when
  /// the cause is disk pressure).
  static String formatConvertError(
    Object error, {
    String? stderr,
    int? exitCode,
  }) {
    final combined = [
      error.toString(),
      if (stderr != null && stderr.trim().isNotEmpty) stderr.trim(),
    ].join('\n');
    if (isDiskFullException(error) || looksLikeDiskFull(combined)) {
      return diskFullUserMessage;
    }
    final lower = combined.toLowerCase();
    if (lower.contains('sfxbasemodel::impl_store') ||
        lower.contains('please verify input parameters')) {
      return 'LibreOffice could not write the converted file. '
          'Try freeing disk space, or convert to a different format.';
    }
    var msg = stderr?.trim();
    if (msg == null || msg.isEmpty) {
      msg = error
          .toString()
          .replaceFirst(RegExp(r'^(Bad state|StateError):\s*'), '')
          .trim();
    } else {
      msg = msg.replaceFirst(RegExp(r'^(Error:\s*)+'), 'Error: ').trim();
    }
    if (msg.isEmpty && exitCode != null) {
      return 'LibreOffice convert failed (exit $exitCode)';
    }
    return msg;
  }

  static void deleteQuietly(Directory? dir) {
    if (dir == null) return;
    dir.delete(recursive: true).then((_) {}, onError: (_) {});
  }

  static Future<File?> findProduced(
    String outDir,
    String stem,
    String ext, {
    String? altStem,
  }) async {
    final primary = File(p.join(outDir, '$stem.$ext'));
    if (await primary.exists()) return primary;
    if (altStem != null && altStem.isNotEmpty) {
      final alt = File(p.join(outDir, '$altStem.$ext'));
      if (await alt.exists()) return alt;
    }
    return null;
  }
}
