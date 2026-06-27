import 'dart:typed_data';

enum SigningCredentialSource {
  smartCard,
  keychain,
  windowsStore,
  nss,
  imported,
  selfSigned,
}

extension SigningCredentialSourceLabel on SigningCredentialSource {
  String get groupTitle => switch (this) {
    SigningCredentialSource.smartCard => 'USB token & smart card',
    SigningCredentialSource.keychain => 'Keychain',
    SigningCredentialSource.windowsStore => 'Windows certificate store',
    SigningCredentialSource.nss => 'Browser & system stores (NSS)',
    SigningCredentialSource.imported => 'Imported',
    SigningCredentialSource.selfSigned => 'Self-signed',
  };

  int get sortOrder => switch (this) {
    SigningCredentialSource.smartCard => 0,
    SigningCredentialSource.keychain => 1,
    SigningCredentialSource.windowsStore => 2,
    SigningCredentialSource.nss => 3,
    SigningCredentialSource.imported => 4,
    SigningCredentialSource.selfSigned => 5,
  };
}

/// A discoverable digital ID that can sign a CMS hash (key may be non-exportable).
class SigningCredential {
  const SigningCredential({
    required this.id,
    required this.displayName,
    required this.source,
    required this.subjectDn,
    required this.issuerDn,
    required this.notBefore,
    required this.notAfter,
    required this.fingerprint,
    required this.keyDescription,
    required this.keyUsage,
    required this.isSelfSigned,
    this.hardwareBacked = false,
    this.requiresPin = false,
    this.protectedAuthPath = false,
    this.hasPrivateKey = true,
    this.certificateDer,
    this.p12Path,
    this.pkcs11ModulePath,
    this.pkcs11NssParams,
    this.pkcs11TokenKey,
    this.pkcs11SlotId,
    this.pkcs11KeyIdHex,
    this.pkcs11CertLabel,
    this.tokenLabel,
    this.osIdentityRef,
    this.statusNote,
  });

  final String id;
  final String displayName;
  final SigningCredentialSource source;
  final String subjectDn;
  final String issuerDn;
  final DateTime notBefore;
  final DateTime notAfter;
  final String fingerprint;
  final String keyDescription;
  final List<String> keyUsage;
  final bool isSelfSigned;
  final bool hardwareBacked;
  final bool requiresPin;
  final bool protectedAuthPath;
  final bool hasPrivateKey;
  final Uint8List? certificateDer;
  final String? p12Path;
  final String? pkcs11ModulePath;
  final String? pkcs11NssParams;
  final String? pkcs11TokenKey;
  final int? pkcs11SlotId;
  final String? pkcs11KeyIdHex;
  final String? pkcs11CertLabel;
  final String? tokenLabel;
  final String? osIdentityRef;
  final String? statusNote;

  String get issuerCommonName {
    for (final part in issuerDn.split(',')) {
      final eq = part.indexOf('=');
      if (eq > 0 && part.substring(0, eq).trim().toUpperCase() == 'CN') {
        return part.substring(eq + 1).trim();
      }
    }
    return issuerDn;
  }

  bool get isExpired => DateTime.now().isAfter(notAfter);
  bool get isNotYetValid => DateTime.now().isBefore(notBefore);
  bool get isExpiringSoon {
    final days = notAfter.difference(DateTime.now()).inDays;
    return !isExpired && !isNotYetValid && days <= 30;
  }

  bool get canSignDocuments {
    if (keyUsage.isEmpty) return true;
    return keyUsage.contains('digitalSignature') ||
        keyUsage.contains('nonRepudiation');
  }

  bool get isUsable =>
      hasPrivateKey &&
      certificateDer != null &&
      !isExpired &&
      !isNotYetValid &&
      (p12Path != null ||
          pkcs11ModulePath != null ||
          osIdentityRef != null ||
          source == SigningCredentialSource.imported ||
          source == SigningCredentialSource.selfSigned);

  /// p11-kit trust anchors (Amazon / ANF / Atos roots, nssckbi) are not tokens.
  bool get isTrustAnchorListing {
    if (source != SigningCredentialSource.smartCard &&
        source != SigningCredentialSource.nss) {
      return false;
    }
    final module = (pkcs11ModulePath ?? '').toLowerCase();
    final label =
        '$displayName ${tokenLabel ?? ''} $subjectDn ${pkcs11CertLabel ?? ''}'
            .toLowerCase();
    final trustModule = module.contains('p11-kit-trust') ||
        module.contains('nssckbi') ||
        module.contains('libnssckbi') ||
        label.contains('p11-kit-trust') ||
        label.contains('nssckbi') ||
        label.contains('libnssckbi') ||
        label.contains('trust anchors') ||
        label.contains('trust module');
    if (trustModule) return source == SigningCredentialSource.smartCard;
    if (source != SigningCredentialSource.smartCard) return false;
    if (label.contains('root ca') ||
        label.contains('rootca') ||
        label.contains('trusted root') ||
        label.contains('trust anchor')) {
      return true;
    }
    final rootish = label.contains('root') || label.contains('trust anchor');
    if (!rootish) return false;
    if (label.contains('amazon') || label.contains('atos')) return true;
    return RegExp(r'(^|[^a-z])anf([^a-z]|$)').hasMatch(label);
  }
}
