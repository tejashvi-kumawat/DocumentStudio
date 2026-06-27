import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:document_studio/core/desktop/desktop_engine_resolver.dart';
import 'package:document_studio/infrastructure/pdf/signing/cms_builder.dart';
import 'package:document_studio/infrastructure/pdf/signing/x509.dart';
import 'package:path/path.dart' as p;

class OpenSslP12Info {
  const OpenSslP12Info({
    required this.commonName,
    required this.organization,
    required this.email,
    required this.notAfter,
    required this.isSelfSigned,
    this.subjectDn = '',
    this.fingerprint = '',
  });

  final String commonName;
  final String organization;
  final String email;
  final DateTime? notAfter;
  final bool isSelfSigned;
  final String subjectDn;
  final String fingerprint;
}

/// Temporary unpacked identity (cert + key PEM paths). Call [dispose] when done.
class OpenSslIdentity {
  OpenSslIdentity({
    required this.workDir,
    required this.certPemPath,
    required this.keyPemPath,
    required this.certDer,
    required this.certificate,
  });

  final Directory workDir;
  final String certPemPath;
  final String keyPemPath;
  final Uint8List certDer;
  final X509Certificate certificate;

  Future<void> dispose() async {
    try {
      await workDir.delete(recursive: true);
    } catch (_) {}
  }
}

/// OpenSSL-backed helpers for PKCS#12 create/inspect and detached CMS signing.
class OpenSslPki {
  OpenSslPki({DesktopEngineResolver? resolver})
    : _resolver = resolver ?? desktopEngineResolver;

  final DesktopEngineResolver _resolver;

  Future<String> _openssl() async {
    final exe = await _resolver.resolveOpenSsl();
    if (exe == null) {
      throw StateError(
        'openssl was not found. Install OpenSSL or rebuild engines.',
      );
    }
    return exe;
  }

  Future<bool> supportsCades() async {
    try {
      final openssl = await _openssl();
      final r = await Process.run(openssl, ['cms', '-help']);
      final text = '${r.stdout}\n${r.stderr}'.toLowerCase();
      return text.contains('cms') || r.exitCode == 0 || text.contains('usage');
    } catch (_) {
      return false;
    }
  }

  Future<void> createSelfSigned({
    required String outP12Path,
    required String password,
    required String commonName,
    String organization = '',
    String email = '',
    int days = 825,
  }) async {
    final openssl = await _openssl();
    final work = await Directory.systemTemp.createTemp('ds_pki_ss_');
    try {
      final key = p.join(work.path, 'key.pem');
      final cert = p.join(work.path, 'cert.pem');
      final conf = p.join(work.path, 'openssl.cnf');
      final cn = commonName.trim().isEmpty
          ? 'Document Studio ID'
          : commonName.trim();
      final org = organization.trim();
      final mail = email.trim();
      await File(conf).writeAsString('''
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $cn
${org.isEmpty ? '' : 'O = $org'}
${mail.isEmpty ? '' : 'emailAddress = $mail'}
[ext]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, nonRepudiation
extendedKeyUsage = emailProtection, clientAuth
''');
      var r = await Process.run(openssl, [
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-keyout',
        key,
        '-out',
        cert,
        '-days',
        '$days',
        '-nodes',
        '-config',
        conf,
      ]);
      if (r.exitCode != 0) {
        throw StateError('Failed to create certificate: ${r.stderr}');
      }
      r = await Process.run(openssl, [
        'pkcs12',
        '-export',
        '-inkey',
        key,
        '-in',
        cert,
        '-out',
        outP12Path,
        '-passout',
        'pass:$password',
        '-name',
        cn,
      ]);
      if (r.exitCode != 0) {
        throw StateError('Failed to export PKCS#12: ${r.stderr}');
      }
    } finally {
      try {
        await work.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<OpenSslP12Info> inspectP12(String p12Path, String password) async {
    final id = await unpack(p12Path, password);
    try {
      final c = id.certificate;
      return OpenSslP12Info(
        commonName: c.commonName,
        organization: c.organization ?? '',
        email: c.email ?? '',
        notAfter: c.notAfter,
        isSelfSigned: c.isSelfIssued,
        subjectDn: c.subjectDn,
        fingerprint: c.fingerprintSha256,
      );
    } finally {
      await id.dispose();
    }
  }

  Future<OpenSslIdentity> unpack(String p12Path, String password) async {
    final openssl = await _openssl();
    final work = await Directory.systemTemp.createTemp('ds_pki_id_');
    final key = p.join(work.path, 'key.pem');
    final cert = p.join(work.path, 'cert.pem');
    final derPath = p.join(work.path, 'cert.der');

    var r = await Process.run(openssl, [
      'pkcs12',
      '-in',
      p12Path,
      '-passin',
      'pass:$password',
      '-nocerts',
      '-nodes',
      '-out',
      key,
    ]);
    if (r.exitCode != 0) {
      await work.delete(recursive: true);
      final err = r.stderr.toString();
      if (err.toLowerCase().contains('mac verify') ||
          err.toLowerCase().contains('invalid password') ||
          err.toLowerCase().contains('password')) {
        throw StateError('Wrong password for digital ID.');
      }
      throw StateError('Could not unlock PKCS#12: $err');
    }
    r = await Process.run(openssl, [
      'pkcs12',
      '-in',
      p12Path,
      '-passin',
      'pass:$password',
      '-clcerts',
      '-nokeys',
      '-out',
      cert,
    ]);
    if (r.exitCode != 0) {
      await work.delete(recursive: true);
      throw StateError('Could not read certificate from PKCS#12: ${r.stderr}');
    }
    r = await Process.run(openssl, [
      'x509',
      '-in',
      cert,
      '-outform',
      'DER',
      '-out',
      derPath,
    ]);
    if (r.exitCode != 0) {
      await work.delete(recursive: true);
      throw StateError('Could not convert certificate: ${r.stderr}');
    }
    final der = await File(derPath).readAsBytes();
    final certificate = X509Certificate.parse(der);
    return OpenSslIdentity(
      workDir: work,
      certPemPath: cert,
      keyPemPath: key,
      certDer: der,
      certificate: certificate,
    );
  }

  /// Detached CMS/CAdES signature over [data] using [identity]'s private key.
  Future<Uint8List> signDetached({
    required OpenSslIdentity identity,
    required Uint8List data,
    bool cades = true,
  }) async {
    final openssl = await _openssl();
    return CmsBuilder.buildDetached(
      content: data,
      signer: identity.certificate,
      sign: (attrs, digest) async {
        final attrsPath = p.join(identity.workDir.path, 'attrs.bin');
        final sigPath = p.join(identity.workDir.path, 'sig.bin');
        await File(attrsPath).writeAsBytes(attrs, flush: true);
        final r = await Process.run(openssl, [
          'dgst',
          '-sha256',
          '-sign',
          identity.keyPemPath,
          '-out',
          sigPath,
          attrsPath,
        ]);
        if (r.exitCode != 0) {
          throw StateError('OpenSSL sign failed: ${r.stderr}');
        }
        return File(sigPath).readAsBytes();
      },
    );
  }
}

String? rdnValue(String dn, String key) {
  final parts = <String>[];
  final cur = StringBuffer();
  var escape = false;
  for (var i = 0; i < dn.length; i++) {
    final c = dn[i];
    if (escape) {
      cur.write(c);
      escape = false;
    } else if (c == '\\') {
      escape = true;
    } else if (c == ',' || c == '+') {
      parts.add(cur.toString());
      cur.clear();
    } else {
      cur.write(c);
    }
  }
  parts.add(cur.toString());
  for (final part in parts) {
    final eq = part.indexOf('=');
    if (eq <= 0) continue;
    if (part.substring(0, eq).trim().toLowerCase() == key.toLowerCase()) {
      final v = part.substring(eq + 1).trim();
      return v.isEmpty ? null : v;
    }
  }
  return null;
}

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

/// `Sep 28 07:12:00 2026 GMT` → local DateTime.
DateTime? parseOpenSslDate(String? s) {
  if (s == null) return null;
  final m = RegExp(
    r'([A-Za-z]{3})\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})\s+(\d{4})',
  ).firstMatch(s);
  if (m == null) return null;
  final month = _months[m.group(1)!.toLowerCase()];
  if (month == null) return null;
  return DateTime.utc(
    int.parse(m.group(6)!),
    month,
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
  ).toLocal();
}

/// Hex fingerprint helper used by credential backends.
String sha256Fingerprint(Uint8List der) => sha256
    .convert(der)
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join(':')
    .toUpperCase();

String describeOpenSslError(Object error) {
  final text = error.toString();
  if (text.startsWith('DocumentStudioError')) return text;
  return text
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceFirst(RegExp(r'^Bad state:\s*'), '');
}
