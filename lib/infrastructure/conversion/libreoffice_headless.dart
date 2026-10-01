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

  static const timeout = Duration(seconds: 90);

  static const diskFullUserMessage = 'Not enough disk space to convert';

  /// Fresh work directory under the app temp box.
  static Future<Directory> createWorkDir({String prefix = 'office-'}) =>
      StoragePaths.createTempDir(prefix);

  /// Runs `soffice` with a private UserInstallation under app temp.
  static Future<ProcessResult> run({
    required String exe,
    required List<String> args,
    required String workDir,
    Duration runTimeout = LibreOfficeHeadless.timeout,
  }) async {
    final profile = await StoragePaths.createTempDir('ds_lo_profile_');
    // LibreOffice requires a file:// URI with an absolute path (three slashes).
    final userInstallUri = Uri.directory(profile.path).toString();
    try {
      final process = await Process.start(
        exe,
        [
          '--headless',
          '--norestore',
          '--nolockcheck',
          '--nodefault',
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
    } finally {
      try {
        await profile.delete(recursive: true);
      } catch (_) {}
    }
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
