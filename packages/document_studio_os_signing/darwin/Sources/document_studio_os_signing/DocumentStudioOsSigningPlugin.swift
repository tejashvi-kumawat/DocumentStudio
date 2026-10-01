import Foundation
import Security
#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif

public class DocumentStudioOsSigningPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "document_studio_os_signing",
      binaryMessenger: registrar.messenger
    )
    let instance = DocumentStudioOsSigningPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "listIdentities":
      result(listIdentities())
    case "signHash":
      guard let args = call.arguments as? [String: Any],
            let ref = args["identityRef"] as? String,
            let data = args["data"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "bad_args", message: "identityRef and data required", details: nil))
        return
      }
      do {
        let sig = try signHash(identityRef: ref, data: data.data)
        result(FlutterStandardTypedData(bytes: sig))
      } catch {
        result(FlutterError(code: "sign_failed", message: error.localizedDescription, details: nil))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func listIdentities() -> [[String: Any]] {
    let query: [String: Any] = [
      kSecClass as String: kSecClassIdentity,
      kSecMatchLimit as String: kSecMatchLimitAll,
      kSecReturnRef as String: true,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess else { return [] }

    let identities: [SecIdentity]
    if let arr = item as? [SecIdentity] {
      identities = arr
    } else if let single = item as! SecIdentity? {
      identities = [single]
    } else {
      return []
    }

    var out: [[String: Any]] = []
    for identity in identities {
      var cert: SecCertificate?
      SecIdentityCopyCertificate(identity, &cert)
      guard let certificate = cert else { continue }
      let der = SecCertificateCopyData(certificate) as Data
      let summary = SecCertificateCopySubjectSummary(certificate) as String? ?? "Keychain identity"
      let fp = der.map { String(format: "%02X", $0) }.joined(separator: ":")
      out.append([
        "identityRef": fp,
        "commonName": summary,
        "subjectDn": summary,
        "issuerDn": "",
        "fingerprint": fp,
        "certificateDer": FlutterStandardTypedData(bytes: der),
        "keyDescription": "Keychain",
        "keyUsage": ["digitalSignature"],
        "isSelfSigned": false,
        "hardwareBacked": false,
        "requiresPin": false,
        "notBeforeMs": 0,
        "notAfterMs": Int(Date().addingTimeInterval(365 * 24 * 3600).timeIntervalSince1970 * 1000),
      ])
    }
    return out
  }

  private func signHash(identityRef: String, data: Data) throws -> Data {
    let query: [String: Any] = [
      kSecClass as String: kSecClassIdentity,
      kSecMatchLimit as String: kSecMatchLimitAll,
      kSecReturnRef as String: true,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let identities = item as? [SecIdentity] else {
      throw NSError(domain: "document_studio_os_signing", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "No Keychain identities"])
    }
    var privateKey: SecKey?
    for identity in identities {
      var cert: SecCertificate?
      SecIdentityCopyCertificate(identity, &cert)
      guard let certificate = cert else { continue }
      let der = SecCertificateCopyData(certificate) as Data
      let fp = der.map { String(format: "%02X", $0) }.joined(separator: ":")
      if fp == identityRef {
        SecIdentityCopyPrivateKey(identity, &privateKey)
        break
      }
    }
    guard let key = privateKey else {
      throw NSError(domain: "document_studio_os_signing", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Private key unavailable"])
    }
    var error: Unmanaged<CFError>?
    // Prefer RSA SHA-256 message; SecKey will fail clearly for EC keys.
    let algorithms: [SecKeyAlgorithm] = [
      .rsaSignatureMessagePKCS1v15SHA256,
      .ecdsaSignatureMessageX962SHA256,
    ]
    for algorithm in algorithms {
      if let signature = SecKeyCreateSignature(key, algorithm, data as CFData, &error) as Data? {
        return signature
      }
    }
    let err = error?.takeRetainedValue()
    throw err ?? NSError(domain: "document_studio_os_signing", code: 4,
                         userInfo: [NSLocalizedDescriptionKey: "SecKeyCreateSignature failed"])
  }
}
