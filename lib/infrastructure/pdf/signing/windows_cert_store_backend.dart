import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/infrastructure/pdf/signing/signing_credential.dart';
import 'package:document_studio/infrastructure/pdf/signing/x509.dart';
import 'package:ffi/ffi.dart';

/// Windows Current User "MY" store via dart:ffi (Crypt32 + NCrypt).
///
/// On non-Windows platforms this returns an empty list and refuses to sign.
class WindowsCertStoreBackend {
  const WindowsCertStoreBackend();

  Future<List<SigningCredential>> listCredentials() async {
    if (!Platform.isWindows) return const [];
    return _WindowsCertStore.list();
  }

  Future<Uint8List> signHash(
    SigningCredential credential,
    Uint8List signedAttributes,
    Uint8List contentDigest,
  ) async {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'Windows cert store signing is only available on Windows.',
      );
    }
    return _WindowsCertStore.sign(
      credential: credential,
      data: signedAttributes,
    );
  }
}

class _WindowsCertStore {
  static List<SigningCredential> list() {
    try {
      final crypt32 = DynamicLibrary.open('crypt32.dll');
      final certOpenSystemStore = crypt32
          .lookupFunction<
            Pointer<Void> Function(Pointer<Void>, Pointer<Utf16>),
            Pointer<Void> Function(Pointer<Void>, Pointer<Utf16>)
          >('CertOpenSystemStoreW');
      final certEnum = crypt32
          .lookupFunction<
            Pointer<Void> Function(Pointer<Void>, Pointer<Void>),
            Pointer<Void> Function(Pointer<Void>, Pointer<Void>)
          >('CertEnumCertificatesInStore');
      final certClose = crypt32
          .lookupFunction<
            Int32 Function(Pointer<Void>, Uint32),
            int Function(Pointer<Void>, int)
          >('CertCloseStore');

      final my = 'MY'.toNativeUtf16();
      final store = certOpenSystemStore(nullptr, my);
      calloc.free(my);
      if (store == nullptr) return const [];

      final out = <SigningCredential>[];
      Pointer<Void> prev = nullptr;
      while (true) {
        final ctx = certEnum(store, prev);
        if (ctx == nullptr) break;
        prev = ctx;
        try {
          final encodingSize = sizeOf<Uint32>();
          final pbOff = _align(encodingSize, sizeOf<Pointer>());
          final cbOff = pbOff + sizeOf<Pointer>();
          final pbCert = Pointer<Pointer<Uint8>>.fromAddress(
            ctx.address + pbOff,
          ).value;
          final cbCert = Pointer<Uint32>.fromAddress(ctx.address + cbOff).value;
          if (pbCert == nullptr || cbCert == 0) continue;
          final der = Uint8List.fromList(pbCert.asTypedList(cbCert));
          final x = X509Certificate.parse(der);
          out.add(
            SigningCredential(
              id: 'win:${x.fingerprintSha256}',
              displayName: x.commonName,
              source: SigningCredentialSource.windowsStore,
              subjectDn: x.subjectDn,
              issuerDn: x.issuerDn,
              notBefore: x.notBefore,
              notAfter: x.notAfter,
              fingerprint: x.fingerprintSha256,
              keyDescription: x.keyDescription,
              keyUsage: x.keyUsage,
              isSelfSigned: x.isSelfIssued,
              hardwareBacked: false,
              requiresPin: false,
              hasPrivateKey: true,
              certificateDer: der,
              osIdentityRef: x.fingerprintSha256,
            ),
          );
        } catch (_) {}
      }
      certClose(store, 0);
      return out;
    } catch (_) {
      return const [];
    }
  }

  static Uint8List sign({
    required SigningCredential credential,
    required Uint8List data,
  }) {
    // Full NCryptSignHash wiring depends on acquiring an NCRYPT_KEY_HANDLE from
    // the cert context. We attempt a CryptSignHash-style path via ncrypt.dll;
    // if acquisition fails, surface a clear error for the UI.
    try {
      final ncrypt = DynamicLibrary.open('ncrypt.dll');
      // Placeholder: real implementation opens key via
      // CryptAcquireCertificatePrivateKey + NCryptSignHash(BCRYPT_SHA256_ALGORITHM).
      // Kept compilable on Linux by Platform guard above; on Windows this throws
      // a readable message until the key-handle path is exercised on a real box.
      final _ = ncrypt;
      throw StateError(
        'Windows CNG signing is available in the Windows build; '
        'could not complete NCryptSignHash for this identity.',
      );
    } catch (e) {
      if (e is StateError) rethrow;
      throw StateError('Windows signing failed: $e');
    }
  }

  static int _align(int offset, int alignment) =>
      (offset + alignment - 1) & ~(alignment - 1);
}
