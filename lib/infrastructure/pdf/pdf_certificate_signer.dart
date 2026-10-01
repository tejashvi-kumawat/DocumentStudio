import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/core/desktop/desktop_engine_resolver.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/infrastructure/pdf/pdf_signature_field_injector.dart';
import 'package:path/path.dart' as p;

/// Result of a certificate (DSC) signing attempt.
class PdfCertificateSignResult {
  const PdfCertificateSignResult({
    required this.signedBytes,
    required this.verifiedByTool,
    required this.verificationSummary,
  });

  final Uint8List signedBytes;

  /// True only when `pdfsig` (or equivalent) reported a valid signature.
  final bool verifiedByTool;

  final String verificationSummary;
}

/// Signs a PDF using a `.p12`/`.pfx` or an NSS nickname via bundled
/// `pdfsig` / `certutil` / `pk12util` / `openssl` (real PKCS#7).
///
/// Android/iOS: poppler CLI is not shipped; there is no fake mobile signer here.
/// A real mobile path would need a vendored PKCS#7 library that writes `/Sig`.
class PdfCertificateSigner {
  PdfCertificateSigner({
    DesktopEngineResolver? resolver,
    Future<ProcessResult> Function(String exe, List<String> args)? run,
    PdfSignatureFieldInjector? fieldInjector,
  })  : _resolver = resolver ?? desktopEngineResolver,
        _run = run ?? _defaultRun,
        _fieldInjector = fieldInjector ??
            PdfSignatureFieldInjector(resolver: resolver, run: run);

  final DesktopEngineResolver _resolver;
  final Future<ProcessResult> Function(String exe, List<String> args) _run;
  final PdfSignatureFieldInjector _fieldInjector;

  static Future<ProcessResult> _defaultRun(String exe, List<String> args) =>
      Process.run(exe, args, stdoutEncoding: systemEncoding, stderrEncoding: systemEncoding);

  Future<_DscToolPaths?> _resolveTools() async {
    final openssl = await _resolver.resolveOpenSsl();
    final pdfsig = await _resolver.resolvePdfsig();
    final certutil = await _resolver.resolveCertutil();
    final pk12util = await _resolver.resolvePk12util();
    if (openssl == null || pdfsig == null || certutil == null || pk12util == null) {
      return null;
    }
    return _DscToolPaths(
      openssl: openssl,
      pdfsig: pdfsig,
      certutil: certutil,
      pk12util: pk12util,
    );
  }

  /// True when openssl, pdfsig, certutil, and pk12util are resolvable (bundle first).
  Future<bool> isAvailable() async => await _resolveTools() != null;

  /// Whether a PKCS#11 module / `pkcs11-tool` appears present (optional path).
  Future<bool> isPkcs11Available() async {
    final tool = await _resolver.resolve('pkcs11-tool');
    return tool != null;
  }

  DocumentStudioError _missingToolsError() => const DocumentStudioError(
        code: DocumentStudioErrorCode.featureUnavailable,
        message:
            'Certificate signing tools were not found in the app engines bundle.',
        recoveryHint:
            'Rebuild the desktop app so engines/ includes pdfsig, certutil, '
            'pk12util, and openssl (scripts/bundle_linux_engines.sh on Linux).',
      );

  /// Signs [inputBytes] with [p12Path] + [password]. Returns bytes only if the
  /// output contains a `/ByteRange` signature; [verifiedByTool] is set from pdfsig.
  ///
  /// Prefer [signatureFieldName] (existing `/FT /Sig`). Otherwise when
  /// [appearancePdfRect] is set (llx, lly, urx, ury in PDF user space), an
  /// unsigned Sig widget is injected at that rect then signed. With neither,
  /// falls back to `pdfsig -add-signature`.
  Future<PdfCertificateSignResult> signWithP12({
    required Uint8List inputBytes,
    required String p12Path,
    required String password,
    String reason = '',
    String? signatureFieldName,
    ({double llx, double lly, double urx, double ury})? appearancePdfRect,
    int pageIndex1Based = 1,
  }) async {
    final tools = await _resolveTools();
    if (tools == null) throw _missingToolsError();

    final prepared = await _prepareInputForAppearance(
      inputBytes: inputBytes,
      signatureFieldName: signatureFieldName,
      appearancePdfRect: appearancePdfRect,
      pageIndex1Based: pageIndex1Based,
    );

    final work = await Directory.systemTemp.createTemp('ds_pdf_sign_');
    try {
      final inPdf = File(p.join(work.path, 'in.pdf'));
      final outPdf = File(p.join(work.path, 'out.pdf'));
      final p12Copy = File(p.join(work.path, 'cert.p12'));
      await inPdf.writeAsBytes(prepared.bytes, flush: true);
      await File(p12Path).copy(p12Copy.path);

      final nssDir = Directory(p.join(work.path, 'nssdb'));
      await nssDir.create();
      final nssSql = 'sql:${nssDir.path}';

      final init = await _run(tools.certutil, ['-N', '-d', nssSql, '--empty-password']);
      if (init.exitCode != 0) {
        throw DocumentStudioError(
          code: DocumentStudioErrorCode.nativeEngineError,
          message: 'Could not create temporary certificate store.',
          recoveryHint: init.stderr.toString().trim(),
        );
      }

      final import = await _run(tools.pk12util, [
        '-i',
        p12Copy.path,
        '-d',
        nssSql,
        '-W',
        password,
      ]);
      if (import.exitCode != 0) {
        throw DocumentStudioError(
          code: DocumentStudioErrorCode.wrongPassword,
          message: 'Could not open the certificate file (wrong password or damaged .p12).',
          recoveryHint: import.stderr.toString().trim().isEmpty
              ? 'Check the password and try again.'
              : import.stderr.toString().trim(),
        );
      }

      // pdfsig -list-nicks accepts sql: or a directory; -nssdir wants the DB directory.
      final nick = await _readNickname(tools.pdfsig, nssDir.path) ??
          await _readNicknameFromPk12(tools.openssl, p12Copy.path, password) ??
          'Signer';

      return await _signWithPdfsig(
        pdfsig: tools.pdfsig,
        nssDirArg: nssDir.path,
        nick: nick,
        keyPassword: password,
        reason: reason,
        inPdf: inPdf,
        outPdf: outPdf,
        signatureFieldName: prepared.fieldName,
      );
    } finally {
      try {
        await work.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Signs using an existing NSS database nickname (e.g. `~/.pki/nssdb`).
  Future<PdfCertificateSignResult> signWithNssNickname({
    required Uint8List inputBytes,
    required String nssDir,
    required String nickname,
    required String nssPassword,
    String reason = '',
    String? signatureFieldName,
    ({double llx, double lly, double urx, double ury})? appearancePdfRect,
    int pageIndex1Based = 1,
  }) async {
    final tools = await _resolveTools();
    if (tools == null) throw _missingToolsError();

    final prepared = await _prepareInputForAppearance(
      inputBytes: inputBytes,
      signatureFieldName: signatureFieldName,
      appearancePdfRect: appearancePdfRect,
      pageIndex1Based: pageIndex1Based,
    );

    final work = await Directory.systemTemp.createTemp('ds_pdf_sign_nss_');
    try {
      final inPdf = File(p.join(work.path, 'in.pdf'));
      final outPdf = File(p.join(work.path, 'out.pdf'));
      await inPdf.writeAsBytes(prepared.bytes, flush: true);

      // pdfsig -nssdir expects the DB directory path (not sql: prefix).
      return await _signWithPdfsig(
        pdfsig: tools.pdfsig,
        nssDirArg: nssDir,
        nick: nickname,
        keyPassword: nssPassword,
        reason: reason,
        inPdf: inPdf,
        outPdf: outPdf,
        nssDbPassword: nssPassword,
        signatureFieldName: prepared.fieldName,
      );
    } finally {
      try {
        await work.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<({Uint8List bytes, String? fieldName})> _prepareInputForAppearance({
    required Uint8List inputBytes,
    required String? signatureFieldName,
    required ({double llx, double lly, double urx, double ury})? appearancePdfRect,
    required int pageIndex1Based,
  }) async {
    final named = signatureFieldName?.trim();
    if (named != null && named.isNotEmpty) {
      return (bytes: inputBytes, fieldName: named);
    }
    final rect = appearancePdfRect;
    if (rect == null) {
      return (bytes: inputBytes, fieldName: null);
    }
    final llx = rect.llx < rect.urx ? rect.llx : rect.urx;
    final urx = rect.llx < rect.urx ? rect.urx : rect.llx;
    final lly = rect.lly < rect.ury ? rect.lly : rect.ury;
    final ury = rect.lly < rect.ury ? rect.ury : rect.lly;
    if ((urx - llx) < 2 || (ury - lly) < 2) {
      return (bytes: inputBytes, fieldName: null);
    }
    const fieldName = 'DS_Signature';
    final withField = await _fieldInjector.injectUnsignedField(
      inputBytes: inputBytes,
      llx: llx,
      lly: lly,
      urx: urx,
      ury: ury,
      pageIndex1Based: pageIndex1Based,
      fieldName: fieldName,
    );
    return (bytes: withField, fieldName: fieldName);
  }

  Future<PdfCertificateSignResult> _signWithPdfsig({
    required String pdfsig,
    required String nssDirArg,
    required String nick,
    required String keyPassword,
    required String reason,
    required File inPdf,
    required File outPdf,
    String? nssDbPassword,
    String? signatureFieldName,
  }) async {
    final field = signatureFieldName?.trim();
    final signArgs = <String>[
      '-nssdir',
      nssDirArg,
      if (nssDbPassword != null && nssDbPassword.isNotEmpty) ...[
        '-nss-pwd',
        nssDbPassword,
      ],
      if (field != null && field.isNotEmpty) ...[
        '-sign',
        field,
      ] else
        '-add-signature',
      '-nick',
      nick,
      if (keyPassword.isNotEmpty) ...['-kpw', keyPassword],
      if (reason.trim().isNotEmpty) ...['-reason', reason.trim()],
      inPdf.path,
      outPdf.path,
    ];
    final signed = await _run(pdfsig, signArgs);
    if (signed.exitCode != 0 || !await outPdf.exists()) {
      final detail = (signed.stderr.toString() + signed.stdout.toString()).trim();
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.nativeEngineError,
        message: 'Certificate signing failed.',
        recoveryHint: detail.isEmpty ? 'pdfsig exited ${signed.exitCode}.' : detail,
      );
    }

    final outBytes = await outPdf.readAsBytes();
    final asLatin = String.fromCharCodes(
      outBytes.take(outBytes.length.clamp(0, 2 << 20)),
    );
    if (!asLatin.contains('/ByteRange') ||
        !RegExp(r'/Type\s*/Sig').hasMatch(asLatin)) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.nativeEngineError,
        message: 'Signed output is missing a PDF signature dictionary.',
        recoveryHint: 'The signing tool did not produce a verifiable /Sig entry.',
      );
    }

    final verify = await _run(pdfsig, [
      '-nssdir',
      nssDirArg,
      '-nocert',
      '-no-ocsp',
      outPdf.path,
    ]);
    final summary = (verify.stdout.toString() + verify.stderr.toString()).trim();
    final ok = summary.contains('Signature is Valid') ||
        summary.contains('Signature Validation: Signature is Valid');

    return PdfCertificateSignResult(
      signedBytes: Uint8List.fromList(outBytes),
      verifiedByTool: ok,
      verificationSummary: summary.isEmpty
          ? (ok ? 'Signature is Valid.' : 'Could not verify with pdfsig.')
          : summary,
    );
  }

  Future<String?> _readNickname(String pdfsig, String nssDir) async {
    final r = await _run(pdfsig, ['-nssdir', nssDir, '-list-nicks']);
    final lines = r.stdout
        .toString()
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.toLowerCase().contains('nickname'))
        .toList();
    if (lines.isEmpty) return null;
    return lines.first;
  }

  Future<String?> _readNicknameFromPk12(
    String openssl,
    String p12Path,
    String password,
  ) async {
    final r = await _run(openssl, [
      'pkcs12',
      '-in',
      p12Path,
      '-nokeys',
      '-clcerts',
      '-passin',
      'pass:$password',
    ]);
    if (r.exitCode != 0) return null;
    final subj = RegExp(r'subject=.*?CN\s*=\s*([^,\n]+)').firstMatch(r.stdout.toString());
    return subj?.group(1)?.trim();
  }
}

class _DscToolPaths {
  const _DscToolPaths({
    required this.openssl,
    required this.pdfsig,
    required this.certutil,
    required this.pk12util,
  });

  final String openssl;
  final String pdfsig;
  final String certutil;
  final String pk12util;
}
