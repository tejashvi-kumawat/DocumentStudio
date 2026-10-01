import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:document_studio/infrastructure/pdf/signing/der.dart';

enum X509KeyAlgorithm { rsa, ec, unknown }

class CertificateInfo {
  const CertificateInfo({
    required this.commonName,
    required this.subjectDn,
    required this.issuerDn,
    required this.issuerCommonName,
    required this.serial,
    required this.notBefore,
    required this.notAfter,
    this.email,
    this.organization,
  });

  final String commonName;
  final String subjectDn;
  final String issuerDn;
  final String issuerCommonName;
  final String serial;
  final DateTime notBefore;
  final DateTime notAfter;
  final String? email;
  final String? organization;
}

class X509Certificate {
  X509Certificate._({
    required this.der,
    required this.tbsCertificate,
    required this.serialBytes,
    required this.subjectDer,
    required this.issuerDer,
    required this.subjectDn,
    required this.issuerDn,
    required this.notBefore,
    required this.notAfter,
    required this.spkiDer,
    required this.signatureAlgorithmOid,
    required this.keyAlgorithm,
    required this.keyDescription,
    required this.keyUsage,
    required this.isCa,
    required this.isSelfIssued,
    required this.fingerprintSha256,
  });

  final Uint8List der;
  final Uint8List tbsCertificate;
  final Uint8List serialBytes;
  final Uint8List subjectDer;
  final Uint8List issuerDer;
  final String subjectDn;
  final String issuerDn;
  final DateTime notBefore;
  final DateTime notAfter;
  final Uint8List spkiDer;
  final String signatureAlgorithmOid;
  final X509KeyAlgorithm keyAlgorithm;
  final String keyDescription;
  final List<String> keyUsage;
  final bool isCa;
  final bool isSelfIssued;
  final String fingerprintSha256;

  String get commonName => _rdnValue(subjectDn, 'CN') ?? subjectDn;
  String get issuerCommonName => _rdnValue(issuerDn, 'CN') ?? issuerDn;
  String? get email =>
      _rdnValue(subjectDn, 'E') ?? _rdnValue(subjectDn, 'emailAddress');
  String? get organization => _rdnValue(subjectDn, 'O');
  String get serial => serialBytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();

  bool get isExpired => DateTime.now().isAfter(notAfter);
  bool get isNotYetValid => DateTime.now().isBefore(notBefore);
  bool get isExpiringSoon {
    final days = notAfter.difference(DateTime.now()).inDays;
    return !isExpired && days <= 30;
  }

  bool get canSignDocuments {
    if (keyUsage.isEmpty) return true;
    return keyUsage.contains('digitalSignature') ||
        keyUsage.contains('nonRepudiation');
  }

  CertificateInfo toCertificateInfo() => CertificateInfo(
    commonName: commonName,
    subjectDn: subjectDn,
    issuerDn: issuerDn,
    issuerCommonName: issuerCommonName,
    serial: serial,
    notBefore: notBefore,
    notAfter: notAfter,
    email: email,
    organization: organization,
  );

  static X509Certificate parse(Uint8List der) {
    final root = DerNode.decode(der);
    if (root.tag != 0x30 ||
        root.children == null ||
        root.children!.length < 3) {
      throw FormatException('Not an X.509 certificate');
    }
    final tbsNode = root.children![0];
    final tbs = tbsNode.encode();
    final algNode = root.children![1];
    final algOid = algNode.children?.isNotEmpty == true
        ? (algNode.children!.first.asOid() ?? '')
        : '';

    final kids = tbsNode.children ?? const <DerNode>[];
    var idx = 0;
    if (kids.isNotEmpty && kids[0].tag == 0xa0) idx = 1;
    if (kids.length < idx + 6)
      throw FormatException('TBSCertificate truncated');

    final serialNode = kids[idx];
    final serialBytes = _stripIntPadding(serialNode.value);
    // signature alg at idx+1
    final issuerNode = kids[idx + 2];
    final validity = kids[idx + 3];
    final subjectNode = kids[idx + 4];
    final spkiNode = kids[idx + 5];

    final notBefore = _parseTime(validity.children![0]);
    final notAfter = _parseTime(validity.children![1]);
    final subjectDn = _formatName(subjectNode);
    final issuerDn = _formatName(issuerNode);

    final spkiDer = spkiNode.encode();
    final spkiAlg = spkiNode.children?.isNotEmpty == true
        ? (spkiNode.children!.first.children?.first.asOid() ?? '')
        : '';

    var keyAlg = X509KeyAlgorithm.unknown;
    var keyDesc = 'Unknown key';
    if (spkiAlg == '1.2.840.113549.1.1.1') {
      keyAlg = X509KeyAlgorithm.rsa;
      final bit = spkiNode.children!.length > 1 ? spkiNode.children![1] : null;
      if (bit != null && bit.value.length > 1) {
        try {
          final rsa = DerNode.decode(bit.value.sublist(1));
          final n = rsa.children?.first.value ?? Uint8List(0);
          final bits = (n.length - (n.isNotEmpty && n[0] == 0 ? 1 : 0)) * 8;
          keyDesc = 'RSA $bits';
        } catch (_) {
          keyDesc = 'RSA';
        }
      } else {
        keyDesc = 'RSA';
      }
    } else if (spkiAlg == '1.2.840.10045.2.1') {
      keyAlg = X509KeyAlgorithm.ec;
      final params = spkiNode.children!.first.children;
      final curve = (params != null && params.length > 1)
          ? params[1].asOid()
          : null;
      keyDesc = switch (curve) {
        '1.2.840.10045.3.1.7' => 'EC P-256',
        '1.3.132.0.34' => 'EC P-384',
        '1.3.132.0.35' => 'EC P-521',
        _ => 'EC',
      };
    }

    final usages = <String>[];
    var isCa = false;
    for (final extContainer in kids.skip(idx + 6)) {
      if (extContainer.tag != 0xa3) continue;
      final seq = extContainer.children?.first;
      for (final ext in seq?.children ?? const <DerNode>[]) {
        final oid = ext.children?.first.asOid();
        final octet = ext.children?.lastWhere(
          (c) => c.tag == 0x04,
          orElse: () => DerNode(0, Uint8List(0)),
        );
        if (oid == '2.5.29.15' && octet != null && octet.value.isNotEmpty) {
          // KeyUsage BIT STRING inside OCTET STRING
          try {
            final ku = DerNode.decode(octet.value);
            if (ku.tag == 0x03 && ku.value.length >= 2) {
              final bits = ku.value[1];
              if (bits & 0x80 != 0) usages.add('digitalSignature');
              if (bits & 0x40 != 0) usages.add('nonRepudiation');
              if (bits & 0x20 != 0) usages.add('keyEncipherment');
              if (bits & 0x10 != 0) usages.add('dataEncipherment');
              if (bits & 0x08 != 0) usages.add('keyAgreement');
              if (bits & 0x04 != 0) usages.add('keyCertSign');
              if (bits & 0x02 != 0) usages.add('cRLSign');
            }
          } catch (_) {}
        }
        if (oid == '2.5.29.19' && octet != null) {
          try {
            final bc = DerNode.decode(octet.value);
            for (final c in bc.children ?? const <DerNode>[]) {
              if (c.tag == 0x01 && c.value.isNotEmpty && c.value[0] != 0)
                isCa = true;
            }
          } catch (_) {}
        }
      }
    }

    final fp = sha256
        .convert(der)
        .bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':')
        .toUpperCase();
    final selfIssued = _namesEqual(subjectDn, issuerDn);

    return X509Certificate._(
      der: Uint8List.fromList(der),
      tbsCertificate: tbs,
      serialBytes: serialBytes,
      subjectDer: subjectNode.encode(),
      issuerDer: issuerNode.encode(),
      subjectDn: subjectDn,
      issuerDn: issuerDn,
      notBefore: notBefore,
      notAfter: notAfter,
      spkiDer: spkiDer,
      signatureAlgorithmOid: algOid,
      keyAlgorithm: keyAlg,
      keyDescription: keyDesc,
      keyUsage: usages,
      isCa: isCa,
      isSelfIssued: selfIssued,
      fingerprintSha256: fp,
    );
  }

  static Uint8List _stripIntPadding(Uint8List v) {
    var i = 0;
    while (i < v.length - 1 && v[i] == 0) {
      i++;
    }
    return Uint8List.fromList(v.sublist(i));
  }

  static DateTime _parseTime(DerNode n) {
    final s = n.asString() ?? '';
    if (n.tag == 0x17 && s.length >= 13) {
      // YYMMDDHHMMSSZ
      final yy = int.parse(s.substring(0, 2));
      final year = yy >= 50 ? 1900 + yy : 2000 + yy;
      return DateTime.utc(
        year,
        int.parse(s.substring(2, 4)),
        int.parse(s.substring(4, 6)),
        int.parse(s.substring(6, 8)),
        int.parse(s.substring(8, 10)),
        int.parse(s.substring(10, 12)),
      ).toLocal();
    }
    if (n.tag == 0x18 && s.length >= 15) {
      // YYYYMMDDHHMMSSZ
      return DateTime.utc(
        int.parse(s.substring(0, 4)),
        int.parse(s.substring(4, 6)),
        int.parse(s.substring(6, 8)),
        int.parse(s.substring(8, 10)),
        int.parse(s.substring(10, 12)),
        int.parse(s.substring(12, 14)),
      ).toLocal();
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static String _formatName(DerNode name) {
    final parts = <String>[];
    for (final rdn in name.children ?? const <DerNode>[]) {
      for (final atv in rdn.children ?? const <DerNode>[]) {
        final kids = atv.children;
        if (kids == null || kids.length < 2) continue;
        final oid = kids[0].asOid() ?? '';
        final val = kids[1].asString() ?? base64.encode(kids[1].value);
        parts.add('${_oidToKey(oid)}=$val');
      }
    }
    return parts.join(', ');
  }

  static String _oidToKey(String oid) => switch (oid) {
    '2.5.4.3' => 'CN',
    '2.5.4.6' => 'C',
    '2.5.4.7' => 'L',
    '2.5.4.8' => 'ST',
    '2.5.4.10' => 'O',
    '2.5.4.11' => 'OU',
    '1.2.840.113549.1.9.1' => 'emailAddress',
    _ => oid,
  };

  static String? _rdnValue(String dn, String key) {
    for (final part in dn.split(',')) {
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      if (part.substring(0, eq).trim().toLowerCase() == key.toLowerCase()) {
        final v = part.substring(eq + 1).trim();
        return v.isEmpty ? null : v;
      }
    }
    return null;
  }

  static bool _namesEqual(String a, String b) =>
      a.toLowerCase().replaceAll(' ', '') ==
      b.toLowerCase().replaceAll(' ', '');
}
