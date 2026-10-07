import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/core/isolate/run_isolated.dart';
import 'package:document_studio/infrastructure/pdf/signing/apple_keychain_backend.dart';
import 'package:document_studio/infrastructure/pdf/signing/cms_builder.dart';
import 'package:document_studio/infrastructure/pdf/signing/dart_pki.dart';
import 'package:document_studio/infrastructure/pdf/signing/digital_id_store.dart';
import 'package:document_studio/infrastructure/pdf/signing/openssl_pki.dart';
import 'package:document_studio/infrastructure/pdf/signing/pdf_incremental_signer.dart';
import 'package:document_studio/infrastructure/pdf/signing/pkcs11/pkcs11_backend.dart';
import 'package:document_studio/infrastructure/pdf/signing/signing_credential.dart';
import 'package:document_studio/infrastructure/pdf/signing/windows_cert_store_backend.dart';
import 'package:document_studio/infrastructure/pdf/signing/x509.dart';

/// Aggregates credentials from PKCS#11 / NSS / Keychain / Windows / imported store.
class SigningCredentialService {
  SigningCredentialService({
    DigitalIdStore? store,
    OpenSslPki? pki,
    Pkcs11Backend? pkcs11,
    AppleKeychainBackend? apple,
    WindowsCertStoreBackend? windows,
  }) : _store = store ?? DigitalIdStore(),
       _pki = pki ?? OpenSslPki(),
       _pkcs11 = pkcs11 ?? const Pkcs11Backend(),
       _apple = apple ?? const AppleKeychainBackend(),
       _windows = windows ?? const WindowsCertStoreBackend();

  final DigitalIdStore _store;
  final OpenSslPki _pki;
  final Pkcs11Backend _pkcs11;
  final AppleKeychainBackend _apple;
  final WindowsCertStoreBackend _windows;

  static final Map<String, String> _sessionPins = {};

  DigitalIdStore get store => _store;

  /// Hardware tokens, OS keychains and browser stores need desktop drivers.
  static bool get supportsSystemStores =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  void rememberPin(String credentialId, String pin) {
    _sessionPins[credentialId] = pin;
  }

  String? sessionPin(String credentialId) {
    final pin = _sessionPins[credentialId];
    if (pin != null) return pin;
    if (credentialId.startsWith('store:')) {
      return _store.sessionPassword(credentialId.substring(6));
    }
    return null;
  }

  void forgetPin(String credentialId) => _sessionPins.remove(credentialId);

  Future<List<SigningCredential>> listAll() async {
    final byFp = <String, SigningCredential>{};
    void add(SigningCredential c) {
      final key = c.fingerprint.isEmpty ? c.id : c.fingerprint;
      final existing = byFp[key];
      if (existing == null || (!existing.hasPrivateKey && c.hasPrivateKey)) {
        byFp[key] = c;
      }
    }

    try {
      for (final c in await _pkcs11.listCredentials()) {
        add(c);
      }
    } catch (_) {}
    try {
      for (final c in await _apple.listCredentials()) {
        add(c);
      }
    } catch (_) {}
    try {
      for (final c in await _windows.listCredentials()) {
        add(c);
      }
    } catch (_) {}

    for (final id in await _store.loadAll()) {
      try {
        Uint8List? der = id.certificateDer;
        X509Certificate? cert;
        final pw = _store.sessionPassword(id.id);
        if (der == null && pw != null && await File(id.p12Path).exists()) {
          try {
            final bytes = await File(id.p12Path).readAsBytes();
            der = (await runIsolated(_parseP12, (bytes, pw))).certificateDer;
          } catch (_) {
            try {
              final unpacked = await _pki.unpack(id.p12Path, pw);
              der = unpacked.certDer;
              await unpacked.dispose();
            } catch (_) {}
          }
        }
        if (der != null) cert = X509Certificate.parse(der);
        add(
          SigningCredential(
            id: 'store:${id.id}',
            displayName: id.displayName,
            source: id.source == DigitalIdSource.selfSigned
                ? SigningCredentialSource.selfSigned
                : SigningCredentialSource.imported,
            subjectDn: cert?.subjectDn ?? id.subject,
            issuerDn: cert?.issuerDn ?? '',
            notBefore:
                cert?.notBefore ?? DateTime.fromMillisecondsSinceEpoch(0),
            notAfter: cert?.notAfter ?? DateTime.fromMillisecondsSinceEpoch(0),
            fingerprint: cert?.fingerprintSha256 ?? id.id,
            keyDescription: cert?.keyDescription ?? '',
            keyUsage: cert?.keyUsage ?? const [],
            isSelfSigned:
                cert?.isSelfIssued ?? (id.source == DigitalIdSource.selfSigned),
            hardwareBacked: false,
            requiresPin: true,
            hasPrivateKey: true,
            certificateDer: der,
            p12Path: id.p12Path,
          ),
        );
      } catch (_) {
        add(
          SigningCredential(
            id: 'store:${id.id}',
            displayName: id.displayName,
            source: id.source == DigitalIdSource.selfSigned
                ? SigningCredentialSource.selfSigned
                : SigningCredentialSource.imported,
            subjectDn: id.subject,
            issuerDn: '',
            notBefore: DateTime.fromMillisecondsSinceEpoch(0),
            notAfter: DateTime.fromMillisecondsSinceEpoch(0),
            fingerprint: id.id,
            keyDescription: '',
            keyUsage: const [],
            isSelfSigned: id.source == DigitalIdSource.selfSigned,
            requiresPin: true,
            hasPrivateKey: true,
            p12Path: id.p12Path,
          ),
        );
      }
    }

    final list = byFp.values.where(_canOfferForSigning).toList()
      ..sort((a, b) {
        final s = a.source.sortOrder.compareTo(b.source.sortOrder);
        if (s != 0) return s;
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
    return list;
  }

  /// A certificate is offered only when it can actually sign. Trust-store
  /// roots are dropped. A token cert whose key is hidden until PIN login is
  /// kept; a cert with no key and no PIN is not. A plugged-in token that has
  /// not listed certs yet (`p11-empty:`) is kept so the USB section can show it.
  static bool _canOfferForSigning(SigningCredential c) {
    if (c.isTrustAnchorListing) return false;
    if (c.source == SigningCredentialSource.smartCard &&
        c.id.startsWith('p11-empty:')) {
      return true;
    }
    if (c.isExpired || c.isNotYetValid) return false;
    final cn = c.displayName.toLowerCase();
    if (cn.contains('root ca') || cn.contains('trusted root')) return false;
    if (c.keyUsage.isNotEmpty && !c.canSignDocuments) return false;
    if (c.keyUsage.contains('keyCertSign') && !c.canSignDocuments) return false;
    if (c.hasPrivateKey) return true;
    return c.requiresPin &&
        c.certificateDer != null &&
        (c.source == SigningCredentialSource.nss ||
            c.source == SigningCredentialSource.smartCard);
  }

  /// Signs [input] into [target] as an incremental update.
  Future<Uint8List> signPdf({
    required Uint8List input,
    required SigningCredential credential,
    required PdfSignatureTarget target,
    required PdfSignDetails details,
    String? pin,
  }) {
    return PdfIncrementalSigner().sign(
      input: input,
      target: target,
      details: details,
      cms: (data) => signDetachedCms(
        credential: credential,
        data: data,
        pin: pin,
        signingTime: details.signingTime,
      ),
    );
  }

  /// Build detached CMS for [data] using [credential].
  Future<Uint8List> signDetachedCms({
    required SigningCredential credential,
    required Uint8List data,
    String? pin,
    DateTime? signingTime,
  }) async {
    final effectivePin = pin ?? sessionPin(credential.id);

    if (credential.p12Path != null) {
      final password = effectivePin ?? '';
      final p12 = await File(credential.p12Path!).readAsBytes();
      Pkcs12Identity? identity;
      try {
        identity = await runIsolated(_parseP12, (p12, password));
      } on Pkcs12WrongPassword {
        rethrow;
      } catch (_) {
        identity = null;
      }
      if (identity != null) {
        final key = identity.key;
        final chain = <X509Certificate>[];
        for (final c in identity.chainDer) {
          try {
            chain.add(X509Certificate.parse(c));
          } catch (_) {}
        }
        return CmsBuilder.buildDetached(
          content: data,
          signer: X509Certificate.parse(identity.certificateDer),
          extraCerts: chain,
          signingTime: signingTime?.toUtc(),
          sign: (attrs, _) => runIsolated(_signSha256, (key, attrs)),
        );
      }
      final id = await _pki.unpack(credential.p12Path!, password);
      try {
        return await _pki.signDetached(identity: id, data: data, cades: true);
      } finally {
        await id.dispose();
      }
    }

    final der = credential.certificateDer;
    if (der == null) {
      throw StateError('No certificate available for this digital ID.');
    }
    final cert = X509Certificate.parse(der);

    return CmsBuilder.buildDetached(
      content: data,
      signer: cert,
      sign: (attrs, digest) async {
        switch (credential.source) {
          case SigningCredentialSource.smartCard:
          case SigningCredentialSource.nss:
            final sig = await _pkcs11.signHash(
              credential,
              attrs,
              digest,
              pin: effectivePin,
            );
            return Uint8List.fromList(sig);
          case SigningCredentialSource.keychain:
            return _apple.signHash(credential, attrs);
          case SigningCredentialSource.windowsStore:
            return _windows.signHash(credential, attrs, digest);
          case SigningCredentialSource.imported:
          case SigningCredentialSource.selfSigned:
            throw StateError('Imported ID is missing its .p12 path.');
        }
      },
    );
  }
}

Pkcs12Identity _parseP12((Uint8List, String) a) => parsePkcs12(a.$1, a.$2);

Uint8List _signSha256((DartPrivateKey, Uint8List) a) => a.$1.signSha256(a.$2);
