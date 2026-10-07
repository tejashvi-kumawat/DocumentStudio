import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/core/isolate/run_isolated.dart';
import 'package:document_studio/infrastructure/pdf/signing/dart_pki.dart';
import 'package:document_studio/infrastructure/pdf/signing/pdf_cos.dart';
import 'package:document_studio/infrastructure/pdf/signing/pdf_incremental_signer.dart';
import 'package:document_studio/infrastructure/pdf/signing/x509.dart';

enum PdfSignatureTrust { trusted, selfSigned, unknown }

enum PdfSignatureVerdict {
  /// Intact and the signer is trusted.
  valid,

  /// Intact, but the signer's identity could not be verified.
  identityUnknown,

  /// Intact at signing, but the document changed afterwards.
  modified,

  /// Digest or signature does not match.
  invalid,

  /// Could not be checked (unsupported algorithm / malformed).
  unknown,
}

class PdfSignatureStatus {
  const PdfSignatureStatus({
    required this.index,
    required this.fieldName,
    required this.verdict,
    required this.intact,
    required this.trust,
    required this.summary,
    this.signerName,
    this.signingTime,
    this.reason,
    this.location,
    this.subFilter,
    this.coversWholeDocument = false,
    this.signedAgainOnly = false,
    this.timestamped = false,
    this.certificate,
    this.chain = const [],
    this.page1Based = 0,
    this.normRect,
    this.visible = false,
  });

  final int index;
  final String fieldName;
  final PdfSignatureVerdict verdict;

  /// Digest and signature value check out.
  final bool intact;
  final PdfSignatureTrust trust;
  final String summary;
  final String? signerName;
  final DateTime? signingTime;
  final String? reason;
  final String? location;
  final String? subFilter;
  final bool coversWholeDocument;

  /// Later revisions only add more signatures (allowed change).
  final bool signedAgainOnly;
  final bool timestamped;
  final CertificateInfo? certificate;
  final List<CertificateInfo> chain;
  final int page1Based;

  /// Displayed-page normalized [left, top, right, bottom].
  final List<double>? normRect;
  final bool visible;

  bool get valid => verdict == PdfSignatureVerdict.valid;
}

class PdfSignatureReport {
  const PdfSignatureReport({required this.signatures, this.error});

  final List<PdfSignatureStatus> signatures;
  final String? error;

  bool get hasSignatures => signatures.isNotEmpty;
  bool get anyInvalid => signatures.any(
    (s) =>
        s.verdict == PdfSignatureVerdict.invalid ||
        s.verdict == PdfSignatureVerdict.modified,
  );
  bool get allValid =>
      hasSignatures &&
      signatures.every((s) => s.verdict == PdfSignatureVerdict.valid);
}

/// Validates embedded PDF signatures in pure Dart (no pdfsig / OpenSSL).
class PdfSignatureValidator {
  PdfSignatureValidator();

  static List<Uint8List>? _systemRoots;

  static Future<List<Uint8List>> _loadSystemRoots() async {
    final cached = _systemRoots;
    if (cached != null) return cached;
    final out = <Uint8List>[];
    final files = <String>[
      '/etc/ssl/certs/ca-certificates.crt',
      '/etc/pki/tls/certs/ca-bundle.crt',
      '/etc/ssl/cert.pem',
      '/etc/ssl/ca-bundle.pem',
    ];
    for (final f in files) {
      try {
        final file = File(f);
        if (!await file.exists()) continue;
        out.addAll(_pemCerts(await file.readAsString()));
        if (out.isNotEmpty) break;
      } catch (_) {}
    }
    if (out.isEmpty) {
      try {
        final dir = Directory('/system/etc/security/cacerts');
        if (await dir.exists()) {
          await for (final e in dir.list()) {
            if (e is File) out.addAll(_pemCerts(await e.readAsString()));
          }
        }
      } catch (_) {}
    }
    return _systemRoots = out;
  }

  static List<Uint8List> _pemCerts(String text) {
    final re = RegExp(
      r'-----BEGIN CERTIFICATE-----([\s\S]*?)-----END CERTIFICATE-----',
    );
    return [
      for (final m in re.allMatches(text))
        base64.decode(m.group(1)!.replaceAll(RegExp(r'\s'), '')),
    ];
  }

  Future<PdfSignatureReport> validateFile(
    String path, {
    Set<String> trustedFingerprints = const {},
  }) async {
    final bytes = await File(path).readAsBytes();
    return validateBytes(bytes, trustedFingerprints: trustedFingerprints);
  }

  Future<PdfSignatureReport> validateBytes(
    Uint8List bytes, {
    Set<String> trustedFingerprints = const {},
  }) async {
    final roots = await _loadSystemRoots();
    return runIsolated(_validateEntry, (
      bytes,
      roots,
      trustedFingerprints,
    ), debugName: 'pdf-signature-validate');
  }

  static PdfSignatureReport _validateEntry(
    (Uint8List, List<Uint8List>, Set<String>) a,
  ) => validateSync(a.$1, roots: a.$2, trusted: a.$3);

  static PdfSignatureReport validateSync(
    Uint8List bytes, {
    List<Uint8List> roots = const [],
    Set<String> trusted = const {},
  }) {
    PdfCosDocument doc;
    try {
      doc = PdfCosDocument.parse(bytes);
    } catch (e) {
      return PdfSignatureReport(signatures: const [], error: '$e');
    }
    if (doc.isEncrypted) {
      return const PdfSignatureReport(
        signatures: [],
        error: 'Encrypted PDFs cannot be checked yet.',
      );
    }
    final fields = PdfIncrementalSigner.listSignatureFieldsSync(bytes)
        .where((f) => f.signed)
        .toList();
    final entries = <(PdfSignatureFieldInfo, PdfDict, List<int>)>[];
    final seenSig = <String>{};
    for (final f in fields) {
      final fd = doc.resolveDict(PdfRef(f.fieldObj));
      final sig = doc.resolveDict(fd?['V']);
      if (sig == null) continue;
      final br = doc.resolve(sig['ByteRange']);
      if (br is! PdfArray || br.length < 4) continue;
      final range = [
        for (final x in br.items.take(4)) (doc.resolve(x) as PdfNum).i,
      ];
      if (!seenSig.add(range.join(','))) continue;
      entries.add((f, sig, range));
    }
    entries.sort((a, b) => (a.$3[2] + a.$3[3]).compareTo(b.$3[2] + b.$3[3]));
    final sigEnds = [for (final e in entries) e.$3[2] + e.$3[3]];
    final revisionEnds = _revisionEnds(bytes);

    final rootCerts = <X509Certificate>[];
    for (final r in roots) {
      try {
        rootCerts.add(X509Certificate.parse(r));
      } catch (_) {}
    }

    final out = <PdfSignatureStatus>[];
    for (var i = 0; i < entries.length; i++) {
      out.add(
        _check(
          bytes: bytes,
          doc: doc,
          index: i,
          field: entries[i].$1,
          sig: entries[i].$2,
          range: entries[i].$3,
          sigEnds: sigEnds,
          revisionEnds: revisionEnds,
          roots: rootCerts,
          trusted: trusted,
        ),
      );
    }
    return PdfSignatureReport(signatures: out);
  }

  static List<int> _revisionEnds(Uint8List b) {
    final out = <int>[];
    final marker = ascii.encode('%%EOF');
    var i = 0;
    while (true) {
      final at = pdfIndexOf(b, marker, i);
      if (at < 0) break;
      var end = at + marker.length;
      if (end < b.length && b[end] == 0x0D) end++;
      if (end < b.length && b[end] == 0x0A) end++;
      out.add(end);
      i = at + marker.length;
    }
    return out;
  }

  static PdfSignatureStatus _check({
    required Uint8List bytes,
    required PdfCosDocument doc,
    required int index,
    required PdfSignatureFieldInfo field,
    required PdfDict sig,
    required List<int> range,
    required List<int> sigEnds,
    required List<int> revisionEnds,
    required List<X509Certificate> roots,
    required Set<String> trusted,
  }) {
    String? text(String key) {
      final v = doc.resolve(sig[key]);
      return v is PdfString ? v.text : null;
    }

    final subFilter = sig.nameOf('SubFilter');
    final end = range[2] + range[3];
    final covers = (bytes.length - end).abs() <= 2;
    var signedAgainOnly = false;
    if (!covers) {
      final later = revisionEnds.where((r) => r > end + 2).toList();
      signedAgainOnly =
          later.isNotEmpty &&
          later.every((r) => sigEnds.any((s) => (s - r).abs() <= 2)) &&
          sigEnds.any((s) => (s - bytes.length).abs() <= 2);
    }
    DateTime? when = _parsePdfDate(text('M'));
    final base = (
      fieldName: field.name,
      page: field.pageIndex1Based,
      rect: [field.normLeft, field.normTop, field.normRight, field.normBottom],
    );

    PdfSignatureStatus result({
      required PdfSignatureVerdict verdict,
      required bool intact,
      required PdfSignatureTrust trust,
      required String summary,
      String? signer,
      CertificateInfo? cert,
      List<CertificateInfo> chain = const [],
      bool timestamped = false,
    }) => PdfSignatureStatus(
      index: index,
      fieldName: base.fieldName,
      verdict: verdict,
      intact: intact,
      trust: trust,
      summary: summary,
      signerName: signer ?? text('Name'),
      signingTime: when,
      reason: text('Reason'),
      location: text('Location'),
      subFilter: subFilter,
      coversWholeDocument: covers,
      signedAgainOnly: signedAgainOnly,
      timestamped: timestamped,
      certificate: cert,
      chain: chain,
      page1Based: base.page,
      normRect: base.rect,
      visible: field.visible,
    );

    final contents = doc.resolve(sig['Contents']);
    if (contents is! PdfString ||
        range[0] != 0 ||
        range[1] < 0 ||
        range[2] < range[1] ||
        end > bytes.length) {
      return result(
        verdict: PdfSignatureVerdict.invalid,
        intact: false,
        trust: PdfSignatureTrust.unknown,
        summary: 'The signature data is malformed.',
      );
    }
    final data = Uint8List(range[1] + range[3])
      ..setRange(0, range[1], bytes)
      ..setRange(range[1], range[1] + range[3], bytes, range[2]);

    try {
      final ci = Ber.parse(contents.bytes);
      final sd = ci[1][0];
      final certs = <X509Certificate>[];
      Ber? signerInfos;
      Uint8List? eContent;
      final encap = sd[2];
      if (encap.length > 1) eContent = encap[1][0].octets;
      for (final k in sd.kids.skip(3)) {
        if (k.tag == 0xa0) {
          for (final c in k.kids) {
            if (c.tag != 0x30) continue;
            try {
              certs.add(X509Certificate.parse(Uint8List.fromList(c.raw)));
            } catch (_) {}
          }
        } else if (k.tag == 0x31) {
          signerInfos = k;
        }
      }
      if (signerInfos == null || signerInfos.kids.isEmpty) {
        throw const FormatException('No signer');
      }
      final si = signerInfos[0];
      final sid = si[1];
      X509Certificate? signerCert;
      if (sid.tag == 0x30) {
        final serial = sid[1].content;
        for (final c in certs) {
          if (_sameInt(c.serialBytes, serial)) signerCert = c;
        }
      }
      signerCert ??= certs.isEmpty ? null : certs.first;
      final digestOid = si[2][0].oid;
      var idx = 3;
      Ber? signedAttrs;
      if (si[idx].tag == 0xa0) {
        signedAttrs = si[idx];
        idx++;
      }
      final sigAlgOid = si[idx][0].oid ?? '';
      final signatureValue = si[idx + 1].octets;
      var timestamped = false;
      if (si.length > idx + 2 && si[idx + 2].tag == 0xa1) {
        for (final a in si[idx + 2].kids) {
          if (a[0].oid == '1.2.840.113549.1.9.16.2.14') timestamped = true;
        }
      }
      final hash = hashForOid(digestOid);
      if (hash == null || signerCert == null) {
        return result(
          verdict: PdfSignatureVerdict.unknown,
          intact: false,
          trust: PdfSignatureTrust.unknown,
          summary: 'Unsupported signature algorithm.',
        );
      }
      // adbe.pkcs7.sha1 embeds the SHA-1 of the byte range as content.
      final content = eContent ?? data;
      var digestOk = true;
      if (eContent != null) {
        final inner = hashForOid(oidSha1)!.convert(data).bytes;
        digestOk = _sameBytes(inner, eContent);
      }
      Uint8List signedBytes;
      if (signedAttrs != null) {
        final md = _attr(signedAttrs, '1.2.840.113549.1.9.4');
        final expected = hash.convert(content).bytes;
        if (md == null || !_sameBytes(md.octets, expected)) digestOk = false;
        final st = _attr(signedAttrs, '1.2.840.113549.1.9.5');
        if (when == null && st != null) {
          when = _parseAsn1Time(String.fromCharCodes(st.content));
        }
        signedBytes = Uint8List.fromList(signedAttrs.raw)..[0] = 0x31;
      } else {
        signedBytes = content;
      }
      final isPss = sigAlgOid == '1.2.840.113549.1.1.10';
      if (isPss) {
        return result(
          verdict: PdfSignatureVerdict.unknown,
          intact: false,
          trust: PdfSignatureTrust.unknown,
          summary: 'RSA-PSS signatures cannot be verified yet.',
          signer: signerCert.commonName,
          cert: signerCert.toCertificateInfo(),
        );
      }
      final hashOid =
          (sigAlgOid == '1.2.840.113549.1.1.1' ||
              sigAlgOid == '1.2.840.10045.2.1')
          ? digestOid
          : (hashOidForSignatureOid(sigAlgOid) ?? digestOid);
      final sigOk = DartPublicKey.fromSpki(
        signerCert.spkiDer,
      ).verify(data: signedBytes, signature: signatureValue, hashOid: hashOid);
      final chain = _buildChain(signerCert, certs, roots);
      final top = chain.last;
      final topTrusted =
          trusted.contains(top.fingerprintSha256) ||
          trusted.contains(signerCert.fingerprintSha256) ||
          roots.any((r) => r.fingerprintSha256 == top.fingerprintSha256);
      final trust = topTrusted
          ? PdfSignatureTrust.trusted
          : (top.isSelfIssued && chain.length == 1
                ? PdfSignatureTrust.selfSigned
                : PdfSignatureTrust.unknown);
      final intact = digestOk && sigOk;
      final signer = signerCert.commonName;
      final chainInfo = [for (final c in chain) c.toCertificateInfo()];
      if (!intact) {
        return result(
          verdict: PdfSignatureVerdict.invalid,
          intact: false,
          trust: trust,
          summary: digestOk
              ? 'The signature value does not match the signer’s certificate.'
              : 'The signed part of the document was altered or corrupted.',
          signer: signer,
          cert: signerCert.toCertificateInfo(),
          chain: chainInfo,
          timestamped: timestamped,
        );
      }
      if (!covers && !signedAgainOnly) {
        return result(
          verdict: PdfSignatureVerdict.modified,
          intact: true,
          trust: trust,
          summary:
              'The document has been modified after this signature '
              'was applied.',
          signer: signer,
          cert: signerCert.toCertificateInfo(),
          chain: chainInfo,
          timestamped: timestamped,
        );
      }
      final trustedNow = trust == PdfSignatureTrust.trusted;
      return result(
        verdict: trustedNow
            ? PdfSignatureVerdict.valid
            : PdfSignatureVerdict.identityUnknown,
        intact: true,
        trust: trust,
        summary: [
          'The document has not been modified since this signature was applied.',
          if (signedAgainOnly) 'Later revisions only add signatures.',
          if (!trustedNow)
            trust == PdfSignatureTrust.selfSigned
                ? 'The signer’s identity is unknown: the certificate is '
                      'self-signed and not in your trusted list.'
                : 'The signer’s identity is unknown: the certificate chain '
                      'does not lead to a trusted root.',
        ].join(' '),
        signer: signer,
        cert: signerCert.toCertificateInfo(),
        chain: chainInfo,
        timestamped: timestamped,
      );
    } catch (e) {
      return result(
        verdict: PdfSignatureVerdict.unknown,
        intact: false,
        trust: PdfSignatureTrust.unknown,
        summary: 'The signature could not be read ($e).',
      );
    }
  }

  static List<X509Certificate> _buildChain(
    X509Certificate leaf,
    List<X509Certificate> pool,
    List<X509Certificate> roots,
  ) {
    final chain = [leaf];
    var cur = leaf;
    for (var depth = 0; depth < 8 && !cur.isSelfIssued; depth++) {
      X509Certificate? issuer;
      for (final c in [...pool, ...roots]) {
        if (c.subjectDn != cur.issuerDn || identical(c, cur)) continue;
        if (_certSignedBy(cur, c)) {
          issuer = c;
          break;
        }
      }
      if (issuer == null) break;
      chain.add(issuer);
      cur = issuer;
    }
    return chain;
  }

  static bool _certSignedBy(X509Certificate cert, X509Certificate issuer) {
    try {
      final root = Ber.parse(cert.der);
      final sig = root[2].content.sublist(1);
      final hashOid = hashOidForSignatureOid(cert.signatureAlgorithmOid);
      if (hashOid == null) return false;
      return DartPublicKey.fromSpki(issuer.spkiDer).verify(
        data: Uint8List.fromList(root[0].raw),
        signature: Uint8List.fromList(sig),
        hashOid: hashOid,
      );
    } catch (_) {
      return false;
    }
  }

  static Ber? _attr(Ber attrs, String oid) {
    for (final a in attrs.kids) {
      if (a.length >= 2 && a[0].oid == oid && a[1].kids.isNotEmpty) {
        return a[1][0];
      }
    }
    return null;
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _sameInt(List<int> a, List<int> b) {
    var i = 0, j = 0;
    while (i < a.length - 1 && a[i] == 0) {
      i++;
    }
    while (j < b.length - 1 && b[j] == 0) {
      j++;
    }
    return _sameBytes(a.sublist(i), b.sublist(j));
  }

  static DateTime? _parseAsn1Time(String s) {
    final m = RegExp(r'^(\d{2,4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?')
        .firstMatch(s);
    if (m == null) return null;
    var year = int.parse(m.group(1)!);
    if (m.group(1)!.length == 2) year += year >= 50 ? 1900 : 2000;
    return DateTime.utc(
      year,
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.tryParse(m.group(6) ?? '0') ?? 0,
    ).toLocal();
  }
}

DateTime? _parsePdfDate(String? s) {
  if (s == null) return null;
  final m = RegExp(
    r"D:(\d{4})(\d{2})?(\d{2})?(\d{2})?(\d{2})?(\d{2})?([Z+\-])?(\d{2})?'?(\d{2})?",
  ).firstMatch(s);
  if (m == null) return null;
  int g(int i, int d) => int.tryParse(m.group(i) ?? '') ?? d;
  var dt = DateTime.utc(
    g(1, 2000),
    g(2, 1),
    g(3, 1),
    g(4, 0),
    g(5, 0),
    g(6, 0),
  );
  final tz = m.group(7);
  if (tz == '+' || tz == '-') {
    final off = Duration(hours: g(8, 0), minutes: g(9, 0));
    dt = tz == '+' ? dt.subtract(off) : dt.add(off);
  }
  return dt.toLocal();
}
