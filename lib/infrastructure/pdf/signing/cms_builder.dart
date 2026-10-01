import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:document_studio/infrastructure/pdf/signing/der.dart';
import 'package:document_studio/infrastructure/pdf/signing/x509.dart';

typedef CmsSignCallback = Future<Uint8List> Function(
  Uint8List signedAttributesDer,
  Uint8List contentDigest,
);

/// Builds an ETSI.CAdES.detached / PKCS#7 detached SignedData structure.
class CmsBuilder {
  /// [sign] receives DER of signed attributes encoded as SET (tag 0x31) and
  /// the SHA-256 digest of [content]. It must return the raw signature value
  /// (RSA PKCS#1 v1.5 or ECDSA). Private keys need not live in Dart.
  static Future<Uint8List> buildDetached({
    required Uint8List content,
    required X509Certificate signer,
    required CmsSignCallback sign,
    DateTime? signingTime,
    List<X509Certificate> extraCerts = const [],
  }) async {
    final digest = Uint8List.fromList(sha256.convert(content).bytes);
    final attrs = _buildSignedAttributes(
      contentDigest: digest,
      signer: signer,
      signingTime: signingTime ?? DateTime.now().toUtc(),
    );
    // For signing, signedAttrs are encoded as SET OF; CMS wraps them as
    // IMPLICIT [0]. OpenSSL signs the SET encoding (0x31 ...).
    final attrsForSign = Uint8List.fromList(attrs);
    attrsForSign[0] = 0x31;
    final signature = await sign(attrsForSign, digest);

    final digestAlg = Der.sequence([
      Der.objectIdentifier('2.16.840.1.101.3.4.2.1'), // sha256
    ]);

    final sigAlg = signer.keyAlgorithm == X509KeyAlgorithm.ec
        ? Der.sequence([
            Der.objectIdentifier('1.2.840.10045.4.3.2'), // ecdsa-with-SHA256
          ])
        : Der.sequence([
            Der.objectIdentifier('1.2.840.113549.1.1.1'), // rsaEncryption
            Der.null_(),
          ]);

    final issuerAndSerial = Der.sequence([
      signer.issuerDer,
      Der.integerBytes(signer.serialBytes),
    ]);

    final signerInfo = Der.sequence([
      Der.integer(BigInt.one), // version
      issuerAndSerial,
      digestAlg,
      // signedAttrs as [0] IMPLICIT
      _retag(attrs, 0xa0),
      sigAlg,
      Der.octetString(signature),
    ]);

    final certs = Der.context(0, [
      signer.der,
      for (final c in extraCerts) c.der,
    ]);

    final signedData = Der.sequence([
      Der.integer(BigInt.one),
      Der.set([digestAlg]),
      Der.sequence([
        Der.objectIdentifier(
          '1.2.840.113549.1.7.1',
        ), // data (detached: no content)
      ]),
      certs,
      Der.set([signerInfo]),
    ]);

    return Der.sequence([
      Der.objectIdentifier('1.2.840.113549.1.7.2'), // signedData
      Der.context(0, [signedData]),
    ]);
  }

  static Uint8List _buildSignedAttributes({
    required Uint8List contentDigest,
    required X509Certificate signer,
    required DateTime signingTime,
  }) {
    final contentType = Der.sequence([
      Der.objectIdentifier('1.2.840.113549.1.9.3'),
      Der.set([Der.objectIdentifier('1.2.840.113549.1.7.1')]),
    ]);
    final messageDigest = Der.sequence([
      Der.objectIdentifier('1.2.840.113549.1.9.4'),
      Der.set([Der.octetString(contentDigest)]),
    ]);
    final timeAttr = Der.sequence([
      Der.objectIdentifier('1.2.840.113549.1.9.5'),
      Der.set([Der.utcTime(signingTime)]),
    ]);
    // ESS signing-certificate-v2 (CAdES)
    final essCertId = Der.sequence([
      Der.sequence([
        Der.sequence([
          Der.objectIdentifier('2.16.840.1.101.3.4.2.1'), // sha256
        ]),
        Der.octetString(Uint8List.fromList(sha256.convert(signer.der).bytes)),
        Der.sequence([signer.issuerDer, Der.integerBytes(signer.serialBytes)]),
      ]),
    ]);
    final signingCertV2 = Der.sequence([
      Der.objectIdentifier('1.2.840.113549.1.9.16.2.47'),
      Der.set([
        Der.sequence([
          Der.sequence([essCertId]), // certs
        ]),
      ]),
    ]);

    // Encode as SET OF Attribute; caller may retag for CMS [0].
    return Der.set([contentType, signingCertV2, messageDigest, timeAttr]);
  }

  static Uint8List _retag(Uint8List der, int newTag) {
    final out = Uint8List.fromList(der);
    out[0] = newTag;
    return out;
  }
}

/// DigestInfo for SHA-256 (used with CKM_RSA_PKCS / raw RSA).
Uint8List sha256DigestInfo(Uint8List digest) {
  return Der.sequence([
    Der.sequence([Der.objectIdentifier('2.16.840.1.101.3.4.2.1'), Der.null_()]),
    Der.octetString(digest),
  ]);
}

/// Alias for DER helpers used above.
typedef Der = DerNode;
