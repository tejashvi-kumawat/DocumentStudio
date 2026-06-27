import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/infrastructure/pdf/signing/cms_builder.dart';
import 'package:document_studio/infrastructure/pdf/signing/pkcs11/pkcs11_ffi.dart';
import 'package:document_studio/infrastructure/pdf/signing/pkcs11/pkcs11_modules.dart';
import 'package:document_studio/infrastructure/pdf/signing/signing_credential.dart';
import 'package:document_studio/infrastructure/pdf/signing/x509.dart';

bool _sameId(Set<String> ids, String id) {
  if (id.isEmpty) return false;
  final want = id.toLowerCase();
  for (final k in ids) {
    if (k.toLowerCase() == want) return true;
  }
  return false;
}

bool _isTrustOrSoftoken(String modulePath) {
  final l = modulePath.toLowerCase();
  return l.contains('libsoftokn3') ||
      l.contains('p11-kit-trust') ||
      l.contains('nssckbi') ||
      l.contains('libnssckbi');
}

/// Slots exposed via p11-kit-proxy for system trust / NSS softoken — not USB.
bool _isSoftwareTrustOrNssSlot(Pkcs11TokenInfo t) {
  final blob = '${t.label} ${t.manufacturer} ${t.model}'.toLowerCase();
  return blob.contains('p11-kit-trust') ||
      blob.contains('trust module') ||
      blob.contains('trust anchors') ||
      blob.contains('nssckbi') ||
      blob.contains('libnssckbi') ||
      blob.contains('builtin object') ||
      blob.contains('certificate db') ||
      blob.contains('softoken') ||
      blob.contains('nss generic') ||
      blob.contains('config lib') ||
      _isNamedPublicRoot(blob);
}

/// Public CA certificates (Amazon, ANF, Atos, and other roots) are not USB tokens.
bool _isTrustAnchor(X509Certificate x) {
  if (x.isCa) return true;
  final blob = '${x.commonName} ${x.subjectDn}'.toLowerCase();
  if (blob.contains('root ca') ||
      blob.contains('rootca') ||
      blob.contains('trusted root') ||
      blob.contains('trust anchor') ||
      x.commonName.toLowerCase().endsWith(' root')) {
    return true;
  }
  if (_isNamedPublicRoot(blob)) return true;
  return x.keyUsage.contains('keyCertSign') && !x.canSignDocuments;
}

/// Trust-store roots that p11-kit-proxy exposes as if they were tokens.
bool _isNamedPublicRoot(String blob) {
  final rootish = blob.contains('root') || blob.contains('trust anchor');
  if (!rootish) return false;
  if (blob.contains('amazon') || blob.contains('atos')) return true;
  return RegExp(r'(^|[^a-z])anf([^a-z]|$)').hasMatch(blob);
}

/// Lists signing credentials from PKCS#11 tokens and NSS DBs.
class Pkcs11Backend {
  const Pkcs11Backend();

  Future<List<SigningCredential>> listCredentials() async {
    if (!(Platform.isLinux || Platform.isMacOS)) return const [];
    final out = <SigningCredential>[];
    final modules = await Pkcs11Modules.discoverModulePaths();

    for (final mod in modules) {
      if (_isTrustOrSoftoken(mod)) continue;
      final scan = pkcs11ScanModule(mod);
      if (!scan.ok) continue;
      for (final t in scan.tokens) {
        if (_isSoftwareTrustOrNssSlot(t)) continue;
        for (final c in t.certs) {
          try {
            final x = X509Certificate.parse(c.der);
            if (_isTrustAnchor(x)) continue;
            final hasKey = _sameId(t.privateKeyIds, c.idHex);
            // Real token: private key present, or login needed to reveal it.
            if (!hasKey && !t.loginRequired) continue;
            if (!x.canSignDocuments && x.keyUsage.isNotEmpty) continue;
            out.add(
              SigningCredential(
                id: 'p11:${t.key}:${c.idHex}:${x.fingerprintSha256}',
                displayName: x.commonName.isEmpty
                    ? (c.label.isEmpty ? 'Token cert' : c.label)
                    : x.commonName,
                source: SigningCredentialSource.smartCard,
                subjectDn: x.subjectDn,
                issuerDn: x.issuerDn,
                notBefore: x.notBefore,
                notAfter: x.notAfter,
                fingerprint: x.fingerprintSha256,
                keyDescription: x.keyDescription,
                keyUsage: x.keyUsage,
                isSelfSigned: x.isSelfIssued,
                hardwareBacked: true,
                requiresPin: t.loginRequired && !t.protectedAuthPath,
                protectedAuthPath: t.protectedAuthPath,
                certificateDer: c.der,
                pkcs11ModulePath: mod,
                pkcs11TokenKey: t.key,
                pkcs11SlotId: t.slotId,
                pkcs11KeyIdHex: c.idHex,
                pkcs11CertLabel: c.label,
                tokenLabel: t.label,
                hasPrivateKey: hasKey,
                statusNote: hasKey
                    ? null
                    : (t.objectsError ??
                          'Certificate visible; private key not listed (login may be required).'),
              ),
            );
          } catch (_) {}
        }
        if (t.certs.isEmpty && t.loginRequired) {
          out.add(
            SigningCredential(
              id: 'p11-empty:${t.key}',
              displayName: t.label.isEmpty ? 'Smart card / token' : t.label,
              source: SigningCredentialSource.smartCard,
              subjectDn: '',
              issuerDn: '',
              notBefore: DateTime.fromMillisecondsSinceEpoch(0),
              notAfter: DateTime.fromMillisecondsSinceEpoch(0),
              fingerprint: t.key,
              keyDescription: '',
              keyUsage: const [],
              isSelfSigned: false,
              hardwareBacked: true,
              requiresPin: true,
              protectedAuthPath: t.protectedAuthPath,
              tokenLabel: t.label,
              hasPrivateKey: false,
              statusNote: t.pinLocked ? 'PIN locked' : 'Token present — enter PIN / refresh after login to list certificates.',
              pkcs11ModulePath: mod,
              pkcs11TokenKey: t.key,
              pkcs11SlotId: t.slotId,
            ),
          );
        }
      }
    }

    final soft = Pkcs11Modules.softoknPath();
    if (soft != null) {
      for (final db in discoverNssDbDirs()) {
        final params = nssReadOnlyParams(db);
        final scan = pkcs11ScanModule(soft, nssParams: params);
        if (!scan.ok) continue;
        for (final t in scan.tokens) {
          for (final c in t.certs) {
            try {
              final x = X509Certificate.parse(c.der);
              if (_isTrustAnchor(x)) continue;
              final hasKey = _sameId(t.privateKeyIds, c.idHex);
              final userDb = t.label.toLowerCase().contains('certificate db');
              if (!hasKey && !t.loginRequired && !userDb) continue;
              if (!x.canSignDocuments && x.keyUsage.isNotEmpty) continue;
              out.add(
                SigningCredential(
                  id: 'nss:$db:${c.idHex}:${x.fingerprintSha256}',
                  displayName: x.commonName.isEmpty ? c.label : x.commonName,
                  source: SigningCredentialSource.nss,
                  subjectDn: x.subjectDn,
                  issuerDn: x.issuerDn,
                  notBefore: x.notBefore,
                  notAfter: x.notAfter,
                  fingerprint: x.fingerprintSha256,
                  keyDescription: x.keyDescription,
                  keyUsage: x.keyUsage,
                  isSelfSigned: x.isSelfIssued,
                  hardwareBacked: false,
                  requiresPin: t.loginRequired,
                  certificateDer: c.der,
                  pkcs11ModulePath: soft,
                  pkcs11NssParams: params,
                  pkcs11TokenKey: t.key,
                  pkcs11SlotId: t.slotId,
                  pkcs11KeyIdHex: c.idHex,
                  pkcs11CertLabel: c.label,
                  tokenLabel: db,
                  hasPrivateKey: hasKey || userDb,
                ),
              );
            } catch (_) {}
          }
        }
      }
    }
    return out;
  }

  Future<List<int>> signHash(
    SigningCredential credential,
    List<int> signedAttributes,
    List<int> contentDigest, {
    String? pin,
  }) async {
    final der = credential.certificateDer;
    if (der == null) {
      throw StateError('Certificate data missing for token credential.');
    }
    final x = X509Certificate.parse(der);
    final digest = Uint8List.fromList(contentDigest);
    final attrs = Uint8List.fromList(signedAttributes);
    return pkcs11Sign(
      Pkcs11SignRequest(
        modulePath: credential.pkcs11ModulePath!,
        nssParams: credential.pkcs11NssParams,
        tokenKey: credential.pkcs11TokenKey ?? '',
        slotIdHint: credential.pkcs11SlotId,
        tokenLabel: credential.tokenLabel,
        keyIdHex: credential.pkcs11KeyIdHex ?? '',
        certLabel: credential.pkcs11CertLabel,
        isEc: x.keyAlgorithm == X509KeyAlgorithm.ec,
        signedAttributes: attrs,
        digestInfoOrHash: sha256DigestInfo(digest),
        sha256Digest: digest,
        pin: pin,
      ),
    );
  }
}
