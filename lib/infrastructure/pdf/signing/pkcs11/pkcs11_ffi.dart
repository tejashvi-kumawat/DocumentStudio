import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// PKCS#11 CK_ULONG is unsigned long (8 bytes on Linux/macOS LP64, 4 on Windows).
typedef CkUlong = Uint64;
typedef CkUlongDart = int;

// --- PKCS#11 constants (subset) ---
const int CKR_OK = 0x00000000;
const int CKR_PIN_INCORRECT = 0x000000A0;
const int CKR_PIN_LOCKED = 0x000000A4;
const int CKR_PIN_EXPIRED = 0x000000A3;
const int CKR_USER_NOT_LOGGED_IN = 0x00000101;
const int CKR_DEVICE_REMOVED = 0x00000032;
const int CKR_TOKEN_NOT_PRESENT = 0x000000E0;
const int CKR_SLOT_ID_INVALID = 0x00000003;
const int CKR_ARGUMENTS_BAD = 0x00000007;
const int CKR_GENERAL_ERROR = 0x00000005;

const int CKF_TOKEN_PRESENT = 0x00000001;
const int CKF_HW_SLOT = 0x00000004;
const int CKF_WRITE_PROTECTED = 0x00000002;
const int CKF_LOGIN_REQUIRED = 0x00000004;
const int CKF_USER_PIN_LOCKED = 0x00040000;
const int CKF_PROTECTED_AUTHENTICATION_PATH = 0x00000100;
const int CKF_SO_PIN_LOCKED = 0x00020000;

const int CKU_USER = 1;
const int CKF_SERIAL_SESSION = 0x00000004;
const int CKF_RW_SESSION = 0x00000002;

const int CKO_CERTIFICATE = 0x00000001;
const int CKO_PUBLIC_KEY = 0x00000002;
const int CKO_PRIVATE_KEY = 0x00000003;

const int CKC_X_509 = 0x00000000;

const int CKA_CLASS = 0x00000000;
const int CKA_TOKEN = 0x00000001;
const int CKA_PRIVATE = 0x00000002;
const int CKA_LABEL = 0x00000003;
const int CKA_VALUE = 0x00000011;
const int CKA_CERTIFICATE_TYPE = 0x00000080;
const int CKA_ID = 0x00000102;
const int CKA_KEY_TYPE = 0x00000105;
const int CKA_SIGN = 0x00000108;
const int CKA_ALWAYS_AUTHENTICATE = 0x00000202;

const int CKK_RSA = 0x00000000;
const int CKK_EC = 0x00000003;

const int CKM_RSA_PKCS = 0x00000001;
const int CKM_SHA256_RSA_PKCS = 0x00000040;
const int CKM_ECDSA = 0x00001041;
const int CKM_ECDSA_SHA256 = 0x00001042;

final class _CkVersion extends Struct {
  @Uint8()
  external int major;
  @Uint8()
  external int minor;
}

final class _CkInfo extends Struct {
  external _CkVersion cryptokiVersion;
  @Array(32)
  external Array<Uint8> manufacturerID;
  @Uint64()
  external int flags;
  @Array(32)
  external Array<Uint8> libraryDescription;
  external _CkVersion libraryVersion;
}

final class _CkSlotInfo extends Struct {
  @Array(64)
  external Array<Uint8> slotDescription;
  @Array(32)
  external Array<Uint8> manufacturerID;
  @Uint64()
  external int flags;
  external _CkVersion hardwareVersion;
  external _CkVersion firmwareVersion;
}

final class _CkTokenInfo extends Struct {
  @Array(32)
  external Array<Uint8> label;
  @Array(32)
  external Array<Uint8> manufacturerID;
  @Array(16)
  external Array<Uint8> model;
  @Array(16)
  external Array<Uint8> serialNumber;
  @Uint64()
  external int flags;
  @Uint64()
  external int ulMaxSessionCount;
  @Uint64()
  external int ulSessionCount;
  @Uint64()
  external int ulMaxRwSessionCount;
  @Uint64()
  external int ulRwSessionCount;
  @Uint64()
  external int ulMaxPinLen;
  @Uint64()
  external int ulMinPinLen;
  @Uint64()
  external int ulTotalPublicMemory;
  @Uint64()
  external int ulFreePublicMemory;
  @Uint64()
  external int ulTotalPrivateMemory;
  @Uint64()
  external int ulFreePrivateMemory;
  external _CkVersion hardwareVersion;
  external _CkVersion firmwareVersion;
  @Array(16)
  external Array<Uint8> utcTime;
}

final class _CkAttribute extends Struct {
  @Uint64()
  external int type;
  external Pointer<Void> pValue;
  @Uint64()
  external int ulValueLen;
}

final class _CkMechanism extends Struct {
  @Uint64()
  external int mechanism;
  external Pointer<Void> pParameter;
  @Uint64()
  external int ulParameterLen;
}

typedef _CkRv = Uint64;
typedef _CInitializeNative = _CkRv Function(Pointer<Void>);
typedef _CInitializeDart = int Function(Pointer<Void>);
typedef _CFinalizeNative = _CkRv Function(Pointer<Void>);
typedef _CFinalizeDart = int Function(Pointer<Void>);
typedef _CGetInfoNative = _CkRv Function(Pointer<_CkInfo>);
typedef _CGetInfoDart = int Function(Pointer<_CkInfo>);
typedef _CGetSlotListNative = _CkRv Function(
  Uint8,
  Pointer<Uint64>,
  Pointer<Uint64>,
);
typedef _CGetSlotListDart = int Function(int, Pointer<Uint64>, Pointer<Uint64>);
typedef _CGetSlotInfoNative = _CkRv Function(Uint64, Pointer<_CkSlotInfo>);
typedef _CGetSlotInfoDart = int Function(int, Pointer<_CkSlotInfo>);
typedef _CGetTokenInfoNative = _CkRv Function(Uint64, Pointer<_CkTokenInfo>);
typedef _CGetTokenInfoDart = int Function(int, Pointer<_CkTokenInfo>);
typedef _COpenSessionNative = _CkRv Function(
  Uint64,
  Uint64,
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Uint64>,
);
typedef _COpenSessionDart = int Function(
  int,
  int,
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Uint64>,
);
typedef _CCloseSessionNative = _CkRv Function(Uint64);
typedef _CCloseSessionDart = int Function(int);
typedef _CLoginNative = _CkRv Function(Uint64, Uint64, Pointer<Uint8>, Uint64);
typedef _CLoginDart = int Function(int, int, Pointer<Uint8>, int);
typedef _CLogoutNative = _CkRv Function(Uint64);
typedef _CLogoutDart = int Function(int);
typedef _CFindObjectsInitNative = _CkRv Function(
  Uint64,
  Pointer<_CkAttribute>,
  Uint64,
);
typedef _CFindObjectsInitDart = int Function(int, Pointer<_CkAttribute>, int);
typedef _CFindObjectsNative = _CkRv Function(
  Uint64,
  Pointer<Uint64>,
  Uint64,
  Pointer<Uint64>,
);
typedef _CFindObjectsDart = int Function(
  int,
  Pointer<Uint64>,
  int,
  Pointer<Uint64>,
);
typedef _CFindObjectsFinalNative = _CkRv Function(Uint64);
typedef _CFindObjectsFinalDart = int Function(int);
typedef _CGetAttributeValueNative = _CkRv Function(
  Uint64,
  Uint64,
  Pointer<_CkAttribute>,
  Uint64,
);
typedef _CGetAttributeValueDart = int Function(
  int,
  int,
  Pointer<_CkAttribute>,
  int,
);
typedef _CSignInitNative = _CkRv Function(
  Uint64,
  Pointer<_CkMechanism>,
  Uint64,
);
typedef _CSignInitDart = int Function(int, Pointer<_CkMechanism>, int);
typedef _CSignNative = _CkRv Function(
  Uint64,
  Pointer<Uint8>,
  Uint64,
  Pointer<Uint8>,
  Pointer<Uint64>,
);
typedef _CSignDart = int Function(
  int,
  Pointer<Uint8>,
  int,
  Pointer<Uint8>,
  Pointer<Uint64>,
);

class Pkcs11CertInfo {
  const Pkcs11CertInfo({
    required this.label,
    required this.idHex,
    required this.der,
  });
  final String label;
  final String idHex;
  final Uint8List der;
}

class Pkcs11TokenInfo {
  const Pkcs11TokenInfo({
    required this.key,
    required this.slotId,
    required this.label,
    required this.model,
    required this.serial,
    required this.manufacturer,
    required this.loginRequired,
    required this.protectedAuthPath,
    required this.certs,
    required this.privateKeyIds,
    required this.publicKeyIds,
    this.objectsError,
    this.pinLocked = false,
  });

  final String key;
  final int slotId;
  final String label;
  final String model;
  final String serial;
  final String manufacturer;
  final bool loginRequired;
  final bool protectedAuthPath;
  final List<Pkcs11CertInfo> certs;
  final Set<String> privateKeyIds;
  final Set<String> publicKeyIds;
  final String? objectsError;
  final bool pinLocked;
}

class Pkcs11ScanResult {
  const Pkcs11ScanResult({
    required this.ok,
    this.error,
    this.manufacturer = '',
    this.description = '',
    this.tokens = const [],
    this.emptySlots = 0,
  });

  final bool ok;
  final String? error;
  final String manufacturer;
  final String description;
  final List<Pkcs11TokenInfo> tokens;
  final int emptySlots;
}

class Pkcs11SignRequest {
  const Pkcs11SignRequest({
    required this.modulePath,
    required this.tokenKey,
    required this.keyIdHex,
    required this.signedAttributes,
    required this.digestInfoOrHash,
    required this.sha256Digest,
    required this.isEc,
    this.nssParams,
    this.slotIdHint,
    this.tokenLabel,
    this.certLabel,
    this.pin,
  });

  final String modulePath;
  final String? nssParams;
  final String tokenKey;
  final int? slotIdHint;
  final String? tokenLabel;
  final String keyIdHex;
  final String? certLabel;
  final bool isEc;
  final Uint8List signedAttributes;
  final Uint8List digestInfoOrHash;
  final Uint8List sha256Digest;
  final String? pin;
}

class Pkcs11Exception implements Exception {
  Pkcs11Exception(this.message, {this.code});
  final String message;
  final int? code;
  @override
  String toString() => message;
}

String _ckrMessage(int rv) => switch (rv) {
  CKR_PIN_INCORRECT => 'Wrong PIN.',
  CKR_PIN_LOCKED => 'PIN is locked. Unlock the token with the vendor tool.',
  CKR_PIN_EXPIRED => 'PIN has expired.',
  CKR_TOKEN_NOT_PRESENT => 'Smart card / token is not present.',
  CKR_DEVICE_REMOVED => 'Token was removed.',
  CKR_USER_NOT_LOGGED_IN => 'Login required.',
  CKR_SLOT_ID_INVALID =>
    'Token slot is no longer valid. Refresh and try again.',
  _ => 'PKCS#11 error 0x${rv.toRadixString(16)}',
};

String _fixedString(Array<Uint8> arr, int len) {
  final bytes = <int>[];
  for (var i = 0; i < len; i++) {
    final b = arr[i];
    if (b == 0) break;
    bytes.add(b);
  }
  // trim trailing spaces typical of PKCS#11 padded fields
  return String.fromCharCodes(bytes).trimRight();
}

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

class _Pkcs11Lib {
  _Pkcs11Lib(
    this.path,
    this.dl, {
    required this.initialize,
    required this.finalize,
    required this.getInfo,
    required this.getSlotList,
    required this.getSlotInfo,
    required this.getTokenInfo,
    required this.openSession,
    required this.closeSession,
    required this.login,
    required this.logout,
    required this.findObjectsInit,
    required this.findObjects,
    required this.findObjectsFinal,
    required this.getAttributeValue,
    required this.signInit,
    required this.sign,
  });

  final String path;
  final DynamicLibrary dl;
  final _CInitializeDart initialize;
  final _CFinalizeDart finalize;
  final _CGetInfoDart getInfo;
  final _CGetSlotListDart getSlotList;
  final _CGetSlotInfoDart getSlotInfo;
  final _CGetTokenInfoDart getTokenInfo;
  final _COpenSessionDart openSession;
  final _CCloseSessionDart closeSession;
  final _CLoginDart login;
  final _CLogoutDart logout;
  final _CFindObjectsInitDart findObjectsInit;
  final _CFindObjectsDart findObjects;
  final _CFindObjectsFinalDart findObjectsFinal;
  final _CGetAttributeValueDart getAttributeValue;
  final _CSignInitDart signInit;
  final _CSignDart sign;

  static final Map<String, _Pkcs11Lib> _cache = {};

  static void evictSoftokn() {
    final keys = _cache.keys.where((k) => k.contains('libsoftokn')).toList();
    for (final k in keys) {
      final lib = _cache.remove(k);
      try {
        lib?.finalize(nullptr);
      } catch (_) {}
    }
  }

  static bool _nssDepsLoaded = false;

  static void _preloadNssDeps() {
    if (_nssDepsLoaded) return;
    _nssDepsLoaded = true;
    if (!(Platform.isLinux || Platform.isMacOS)) return;
    const candidates = <String>[
      'libnspr4.so',
      'libplc4.so',
      'libplds4.so',
      'libnssutil3.so',
      'libnss3.so',
      '/usr/lib/x86_64-linux-gnu/libnspr4.so',
      '/usr/lib/x86_64-linux-gnu/libnssutil3.so',
      '/usr/lib/x86_64-linux-gnu/libnss3.so',
      '/usr/lib64/libnspr4.so',
      '/usr/lib64/libnss3.so',
    ];
    for (final name in candidates) {
      try {
        DynamicLibrary.open(name);
      } catch (_) {}
    }
  }

  static _Pkcs11Lib open(String modulePath, {String? nssParams}) {
    final key = '$modulePath|${nssParams ?? ''}';
    final cached = _cache[key];
    if (cached != null) return cached;

    if (!File(modulePath).existsSync()) {
      throw Pkcs11Exception('PKCS#11 module not found: $modulePath');
    }
    if (modulePath.contains('libsoftokn') || nssParams != null) {
      _preloadNssDeps();
    }
    final dl = DynamicLibrary.open(modulePath);

    try {
      late final _CInitializeDart initialize;
      late final _CFinalizeDart finalize;
      late final _CGetInfoDart getInfo;
      late final _CGetSlotListDart getSlotList;
      late final _CGetSlotInfoDart getSlotInfo;
      late final _CGetTokenInfoDart getTokenInfo;
      late final _COpenSessionDart openSession;
      late final _CCloseSessionDart closeSession;
      late final _CLoginDart login;
      late final _CLogoutDart logout;
      late final _CFindObjectsInitDart findObjectsInit;
      late final _CFindObjectsDart findObjects;
      late final _CFindObjectsFinalDart findObjectsFinal;
      late final _CGetAttributeValueDart getAttributeValue;
      late final _CSignInitDart signInit;
      late final _CSignDart sign;

      var loadedViaSymbols = false;
      try {
        initialize = dl
            .lookup<NativeFunction<_CInitializeNative>>('C_Initialize')
            .asFunction<_CInitializeDart>();
        finalize = dl
            .lookup<NativeFunction<_CFinalizeNative>>('C_Finalize')
            .asFunction<_CFinalizeDart>();
        getInfo = dl
            .lookup<NativeFunction<_CGetInfoNative>>('C_GetInfo')
            .asFunction<_CGetInfoDart>();
        getSlotList = dl
            .lookup<NativeFunction<_CGetSlotListNative>>('C_GetSlotList')
            .asFunction<_CGetSlotListDart>();
        getSlotInfo = dl
            .lookup<NativeFunction<_CGetSlotInfoNative>>('C_GetSlotInfo')
            .asFunction<_CGetSlotInfoDart>();
        getTokenInfo = dl
            .lookup<NativeFunction<_CGetTokenInfoNative>>('C_GetTokenInfo')
            .asFunction<_CGetTokenInfoDart>();
        openSession = dl
            .lookup<NativeFunction<_COpenSessionNative>>('C_OpenSession')
            .asFunction<_COpenSessionDart>();
        closeSession = dl
            .lookup<NativeFunction<_CCloseSessionNative>>('C_CloseSession')
            .asFunction<_CCloseSessionDart>();
        login = dl
            .lookup<NativeFunction<_CLoginNative>>('C_Login')
            .asFunction<_CLoginDart>();
        logout = dl
            .lookup<NativeFunction<_CLogoutNative>>('C_Logout')
            .asFunction<_CLogoutDart>();
        findObjectsInit = dl
            .lookup<NativeFunction<_CFindObjectsInitNative>>(
              'C_FindObjectsInit',
            )
            .asFunction<_CFindObjectsInitDart>();
        findObjects = dl
            .lookup<NativeFunction<_CFindObjectsNative>>('C_FindObjects')
            .asFunction<_CFindObjectsDart>();
        findObjectsFinal = dl
            .lookup<NativeFunction<_CFindObjectsFinalNative>>(
              'C_FindObjectsFinal',
            )
            .asFunction<_CFindObjectsFinalDart>();
        getAttributeValue = dl
            .lookup<NativeFunction<_CGetAttributeValueNative>>(
              'C_GetAttributeValue',
            )
            .asFunction<_CGetAttributeValueDart>();
        signInit = dl
            .lookup<NativeFunction<_CSignInitNative>>('C_SignInit')
            .asFunction<_CSignInitDart>();
        sign = dl
            .lookup<NativeFunction<_CSignNative>>('C_Sign')
            .asFunction<_CSignDart>();
        loadedViaSymbols = true;
      } catch (_) {
        loadedViaSymbols = false;
      }

      if (!loadedViaSymbols) {
        // NSS softokn / some vendor modules only export C_GetFunctionList.
        final getList = dl
            .lookup<NativeFunction<Uint32 Function(Pointer<Pointer<Void>>)>>(
              'C_GetFunctionList',
            )
            .asFunction<int Function(Pointer<Pointer<Void>>)>();
        final out = calloc<Pointer<Void>>();
        final rv = getList(out);
        if (rv != CKR_OK) {
          calloc.free(out);
          throw Pkcs11Exception(_ckrMessage(rv), code: rv);
        }
        final fl = out.value;
        calloc.free(out);
        // CK_FUNCTION_LIST: CK_VERSION (2 bytes) + pad to 8, then pointers.
        final table = Pointer<Pointer<Void>>.fromAddress(fl.address + 8);
        Pointer<NativeFunction<T>> fn<T extends Function>(int index) =>
            table[index].cast<NativeFunction<T>>();

        // Indices from PKCS#11 2.40 CK_FUNCTION_LIST.
        initialize = fn<_CInitializeNative>(0).asFunction<_CInitializeDart>();
        finalize = fn<_CFinalizeNative>(1).asFunction<_CFinalizeDart>();
        getInfo = fn<_CGetInfoNative>(2).asFunction<_CGetInfoDart>();
        getSlotList = fn<_CGetSlotListNative>(4)
            .asFunction<_CGetSlotListDart>();
        getSlotInfo = fn<_CGetSlotInfoNative>(5)
            .asFunction<_CGetSlotInfoDart>();
        getTokenInfo = fn<_CGetTokenInfoNative>(6)
            .asFunction<_CGetTokenInfoDart>();
        openSession = fn<_COpenSessionNative>(12)
            .asFunction<_COpenSessionDart>();
        closeSession = fn<_CCloseSessionNative>(13)
            .asFunction<_CCloseSessionDart>();
        login = fn<_CLoginNative>(18).asFunction<_CLoginDart>();
        logout = fn<_CLogoutNative>(19).asFunction<_CLogoutDart>();
        getAttributeValue = fn<_CGetAttributeValueNative>(24)
            .asFunction<_CGetAttributeValueDart>();
        findObjectsInit = fn<_CFindObjectsInitNative>(26)
            .asFunction<_CFindObjectsInitDart>();
        findObjects = fn<_CFindObjectsNative>(27)
            .asFunction<_CFindObjectsDart>();
        findObjectsFinal = fn<_CFindObjectsFinalNative>(28)
            .asFunction<_CFindObjectsFinalDart>();
        signInit = fn<_CSignInitNative>(42).asFunction<_CSignInitDart>();
        sign = fn<_CSignNative>(43).asFunction<_CSignDart>();
      }

      final lib = _Pkcs11Lib(
        modulePath,
        dl,
        initialize: initialize,
        finalize: finalize,
        getInfo: getInfo,
        getSlotList: getSlotList,
        getSlotInfo: getSlotInfo,
        getTokenInfo: getTokenInfo,
        openSession: openSession,
        closeSession: closeSession,
        login: login,
        logout: logout,
        findObjectsInit: findObjectsInit,
        findObjects: findObjects,
        findObjectsFinal: findObjectsFinal,
        getAttributeValue: getAttributeValue,
        signInit: signInit,
        sign: sign,
      );

      final rv = _initialize(lib, nssParams);
      if (rv != CKR_OK &&
          rv != 0x00000191 /* CKR_CRYPTOKI_ALREADY_INITIALIZED */ ) {
        throw Pkcs11Exception(
          'Could not initialize PKCS#11 module: ${_ckrMessage(rv)}',
          code: rv,
        );
      }
      _cache[key] = lib;
      return lib;
    } catch (e) {
      if (e is Pkcs11Exception) rethrow;
      throw Pkcs11Exception('Failed to load PKCS#11 module $modulePath: $e');
    }
  }

  static final List<Pointer<Utf8>> _retainedNssParams = [];

  static int _initialize(_Pkcs11Lib lib, String? nssParams) {
    if (nssParams == null || nssParams.isEmpty) {
      // CKF_OS_LOCKING_OK = 0x2
      final args = calloc<Uint8>(48);
      try {
        final flags = Pointer<Uint64>.fromAddress(args.address + 32);
        flags.value = 0x2;
        return lib.initialize(args.cast());
      } finally {
        calloc.free(args);
      }
    }
    // Softoken reads LibraryParameters (NSS extension at the pReserved slot).
    // The config string must outlive C_Initialize — retain it for process life.
    final args = calloc<Uint8>(48);
    final params = nssParams.toNativeUtf8();
    _retainedNssParams.add(params);
    final flags = Pointer<Uint64>.fromAddress(args.address + 32);
    flags.value = 0x2; // CKF_OS_LOCKING_OK
    final libraryParameters = Pointer<Pointer<Void>>.fromAddress(
      args.address + 40,
    );
    libraryParameters.value = params.cast<Void>();
    final rv = lib.initialize(args.cast());
    // Softoken copies or retains; keep args too (small leak per unique DB).
    return rv;
  }
}

/// Scan a PKCS#11 module for certificates and key IDs.
Pkcs11ScanResult pkcs11ScanModule(String modulePath, {String? nssParams}) {
  try {
    // Softoken keeps a process-wide configdir; re-init when nssParams change.
    if (nssParams != null && modulePath.contains('libsoftokn')) {
      _Pkcs11Lib.evictSoftokn();
    }
    final lib = _Pkcs11Lib.open(modulePath, nssParams: nssParams);
    final info = calloc<_CkInfo>();
    try {
      lib.getInfo(info);
      final manufacturer = _fixedString(info.ref.manufacturerID, 32);
      final description = _fixedString(info.ref.libraryDescription, 32);

      final countPtr = calloc<Uint64>();
      // Always enumerate all slots first (tokenPresent=false) so we size the
      // buffer correctly — softokn exposes 2 slots but only one may look "present".
      var rv = lib.getSlotList(0, nullptr, countPtr);
      var count = countPtr.value;
      var emptySlots = 0;
      if (rv != CKR_OK || count == 0) {
        lib.getSlotList(1, nullptr, countPtr);
        count = countPtr.value;
      }
      if (count == 0) {
        calloc.free(countPtr);
        return Pkcs11ScanResult(
          ok: true,
          manufacturer: manufacturer,
          description: description,
          emptySlots: 0,
        );
      }
      final slots = calloc<Uint64>(count);
      rv = lib.getSlotList(0, slots, countPtr);
      if (rv != CKR_OK) {
        // Retry with tokenPresent=true into the same-sized buffer.
        rv = lib.getSlotList(1, slots, countPtr);
      }
      if (rv != CKR_OK) {
        calloc.free(slots);
        calloc.free(countPtr);
        return Pkcs11ScanResult(ok: false, error: _ckrMessage(rv));
      }
      count = countPtr.value;
      final tokens = <Pkcs11TokenInfo>[];
      for (var i = 0; i < count; i++) {
        final slotId = slots[i];
        final slotInfo = calloc<_CkSlotInfo>();
        lib.getSlotInfo(slotId, slotInfo);
        final tokenPresent = (slotInfo.ref.flags & CKF_TOKEN_PRESENT) != 0;
        calloc.free(slotInfo);
        if (!tokenPresent) {
          emptySlots++;
          continue;
        }
        final tokenInfo = calloc<_CkTokenInfo>();
        rv = lib.getTokenInfo(slotId, tokenInfo);
        if (rv != CKR_OK) {
          calloc.free(tokenInfo);
          emptySlots++;
          continue;
        }
        final label = _fixedString(tokenInfo.ref.label, 32);
        final model = _fixedString(tokenInfo.ref.model, 16);
        final serial = _fixedString(tokenInfo.ref.serialNumber, 16);
        final manuf = _fixedString(tokenInfo.ref.manufacturerID, 32);
        final flags = tokenInfo.ref.flags;
        final loginRequired = (flags & CKF_LOGIN_REQUIRED) != 0;
        final protectedPath = (flags & CKF_PROTECTED_AUTHENTICATION_PATH) != 0;
        final pinLocked = (flags & CKF_USER_PIN_LOCKED) != 0;
        calloc.free(tokenInfo);

        final key = '$modulePath#$slotId#$serial#$label';
        String? objectsError;
        final certs = <Pkcs11CertInfo>[];
        final privIds = <String>{};
        final pubIds = <String>{};
        final sessionPtr = calloc<Uint64>();
        rv = lib.openSession(
          slotId,
          CKF_SERIAL_SESSION,
          nullptr,
          nullptr,
          sessionPtr,
        );
        if (rv != CKR_OK) {
          objectsError = _ckrMessage(rv);
          calloc.free(sessionPtr);
        } else {
          final session = sessionPtr.value;
          calloc.free(sessionPtr);
          try {
            certs.addAll(_findCerts(lib, session));
            privIds.addAll(_findKeyIds(lib, session, CKO_PRIVATE_KEY));
            pubIds.addAll(_findKeyIds(lib, session, CKO_PUBLIC_KEY));
          } catch (e) {
            objectsError = e.toString();
          } finally {
            lib.closeSession(session);
          }
        }
        tokens.add(
          Pkcs11TokenInfo(
            key: key,
            slotId: slotId,
            label: label,
            model: model,
            serial: serial,
            manufacturer: manuf,
            loginRequired: loginRequired,
            protectedAuthPath: protectedPath,
            certs: certs,
            privateKeyIds: privIds,
            publicKeyIds: pubIds,
            objectsError: objectsError,
            pinLocked: pinLocked,
          ),
        );
      }
      calloc.free(slots);
      calloc.free(countPtr);
      return Pkcs11ScanResult(
        ok: true,
        manufacturer: manufacturer,
        description: description,
        tokens: tokens,
        emptySlots: emptySlots,
      );
    } finally {
      calloc.free(info);
    }
  } catch (e) {
    return Pkcs11ScanResult(ok: false, error: e.toString());
  }
}

List<Pkcs11CertInfo> _findCerts(_Pkcs11Lib lib, int session) {
  final out = <Pkcs11CertInfo>[];
  final template = calloc<_CkAttribute>(2);
  final classVal = calloc<Uint64>()..value = CKO_CERTIFICATE;
  final typeVal = calloc<Uint64>()..value = CKC_X_509;
  template[0].type = CKA_CLASS;
  template[0].pValue = classVal.cast();
  template[0].ulValueLen = 8;
  template[1].type = CKA_CERTIFICATE_TYPE;
  template[1].pValue = typeVal.cast();
  template[1].ulValueLen = 8;
  var rv = lib.findObjectsInit(session, template, 2);
  calloc.free(classVal);
  calloc.free(typeVal);
  calloc.free(template);
  if (rv != CKR_OK) return out;
  final handles = calloc<Uint64>(32);
  final count = calloc<Uint64>();
  rv = lib.findObjects(session, handles, 32, count);
  lib.findObjectsFinal(session);
  if (rv == CKR_OK) {
    for (var i = 0; i < count.value; i++) {
      final h = handles[i];
      final label = _getBytesAttr(lib, session, h, CKA_LABEL);
      final id = _getBytesAttr(lib, session, h, CKA_ID);
      final value = _getBytesAttr(lib, session, h, CKA_VALUE);
      if (value == null || value.isEmpty) continue;
      out.add(
        Pkcs11CertInfo(
          label: label == null ? '' : utf8.decode(label, allowMalformed: true),
          idHex: id == null ? '' : _hex(id),
          der: value,
        ),
      );
    }
  }
  calloc.free(handles);
  calloc.free(count);
  return out;
}

Set<String> _findKeyIds(_Pkcs11Lib lib, int session, int objClass) {
  final out = <String>{};
  final template = calloc<_CkAttribute>();
  final classVal = calloc<Uint64>()..value = objClass;
  template[0].type = CKA_CLASS;
  template[0].pValue = classVal.cast();
  template[0].ulValueLen = 8;
  var rv = lib.findObjectsInit(session, template, 1);
  calloc.free(classVal);
  calloc.free(template);
  if (rv != CKR_OK) return out;
  final handles = calloc<Uint64>(64);
  final count = calloc<Uint64>();
  rv = lib.findObjects(session, handles, 64, count);
  lib.findObjectsFinal(session);
  if (rv == CKR_OK) {
    for (var i = 0; i < count.value; i++) {
      final id = _getBytesAttr(lib, session, handles[i], CKA_ID);
      if (id != null && id.isNotEmpty) out.add(_hex(id));
    }
  }
  calloc.free(handles);
  calloc.free(count);
  return out;
}

Uint8List? _getBytesAttr(
  _Pkcs11Lib lib,
  int session,
  int handle,
  int attrType,
) {
  final attr = calloc<_CkAttribute>();
  attr.ref.type = attrType;
  attr.ref.pValue = nullptr;
  attr.ref.ulValueLen = 0;
  var rv = lib.getAttributeValue(session, handle, attr, 1);
  if (rv != CKR_OK ||
      attr.ref.ulValueLen == 0 ||
      attr.ref.ulValueLen == 0xffffffff ||
      attr.ref.ulValueLen == 0xffffffffffffffff) {
    calloc.free(attr);
    return null;
  }
  final buf = calloc<Uint8>(attr.ref.ulValueLen);
  attr.ref.pValue = buf.cast();
  rv = lib.getAttributeValue(session, handle, attr, 1);
  Uint8List? out;
  if (rv == CKR_OK) {
    out = Uint8List.fromList(buf.asTypedList(attr.ref.ulValueLen));
  }
  calloc.free(buf);
  calloc.free(attr);
  return out;
}

/// Sign [Pkcs11SignRequest.signedAttributes] on the token.
Uint8List pkcs11Sign(Pkcs11SignRequest request) {
  final lib = _Pkcs11Lib.open(request.modulePath, nssParams: request.nssParams);
  final scan = pkcs11ScanModule(
    request.modulePath,
    nssParams: request.nssParams,
  );
  if (!scan.ok) throw Pkcs11Exception(scan.error ?? 'Scan failed');
  final token = scan.tokens.cast<Pkcs11TokenInfo?>().firstWhere(
    (t) =>
        t!.key == request.tokenKey ||
        (request.slotIdHint != null && t.slotId == request.slotIdHint) ||
        (request.tokenLabel != null && t.label == request.tokenLabel),
    orElse: () => scan.tokens.isEmpty ? null : scan.tokens.first,
  );
  if (token == null) {
    throw Pkcs11Exception('Token not found. Is the smart card plugged in?');
  }
  if (token.pinLocked) {
    throw Pkcs11Exception(
      'PIN is locked. Unlock the token with the vendor tool.',
    );
  }

  final sessionPtr = calloc<Uint64>();
  var rv = lib.openSession(
    token.slotId,
    CKF_SERIAL_SESSION | CKF_RW_SESSION,
    nullptr,
    nullptr,
    sessionPtr,
  );
  if (rv != CKR_OK) {
    calloc.free(sessionPtr);
    throw Pkcs11Exception(_ckrMessage(rv), code: rv);
  }
  final session = sessionPtr.value;
  calloc.free(sessionPtr);

  try {
    if (token.loginRequired || request.pin != null) {
      if (token.protectedAuthPath &&
          (request.pin == null || request.pin!.isEmpty)) {
        rv = lib.login(session, CKU_USER, nullptr, 0);
      } else {
        final pin = request.pin ?? '';
        if (pin.isEmpty && token.loginRequired && !token.protectedAuthPath) {
          throw Pkcs11Exception('PIN required for this token.');
        }
        final pinPtr = pin.isEmpty ? nullptr : pin.toNativeUtf8().cast<Uint8>();
        try {
          rv = lib.login(session, CKU_USER, pinPtr, pin.length);
        } finally {
          if (pinPtr != nullptr) calloc.free(pinPtr.cast<Utf8>());
        }
      }
      if (rv != CKR_OK && rv != 0x00000100 /* CKR_USER_ALREADY_LOGGED_IN */ ) {
        throw Pkcs11Exception(_ckrMessage(rv), code: rv);
      }
    }

    final keyHandle = _findPrivateKey(
      lib,
      session,
      request.keyIdHex,
      request.certLabel,
    );
    if (keyHandle == null) {
      throw Pkcs11Exception(
        'Private key not found on token for this certificate.',
      );
    }

    final mech = calloc<_CkMechanism>();
    Uint8List dataToSign = request.signedAttributes;
    if (request.isEc) {
      mech.ref.mechanism = CKM_ECDSA_SHA256;
      // Some tokens only support CKM_ECDSA with pre-hashed data.
      // Try SHA256 first; fall back to ECDSA on raw digest.
    } else {
      mech.ref.mechanism = CKM_SHA256_RSA_PKCS;
    }
    mech.ref.pParameter = nullptr;
    mech.ref.ulParameterLen = 0;

    rv = lib.signInit(session, mech, keyHandle);
    if (rv != CKR_OK && request.isEc) {
      mech.ref.mechanism = CKM_ECDSA;
      dataToSign = request.sha256Digest;
      rv = lib.signInit(session, mech, keyHandle);
    }
    if (rv != CKR_OK && !request.isEc) {
      mech.ref.mechanism = CKM_RSA_PKCS;
      dataToSign = request.digestInfoOrHash;
      rv = lib.signInit(session, mech, keyHandle);
    }
    calloc.free(mech);
    if (rv != CKR_OK) {
      throw Pkcs11Exception('SignInit failed: ${_ckrMessage(rv)}', code: rv);
    }

    final dataPtr = calloc<Uint8>(dataToSign.length);
    dataPtr.asTypedList(dataToSign.length).setAll(0, dataToSign);
    final sigLen = calloc<Uint64>()..value = 4096;
    final sigBuf = calloc<Uint8>(4096);
    rv = lib.sign(session, dataPtr, dataToSign.length, sigBuf, sigLen);
    if (rv != CKR_OK) {
      calloc.free(dataPtr);
      calloc.free(sigBuf);
      calloc.free(sigLen);
      throw Pkcs11Exception('Sign failed: ${_ckrMessage(rv)}', code: rv);
    }
    final sig = Uint8List.fromList(sigBuf.asTypedList(sigLen.value));
    calloc.free(dataPtr);
    calloc.free(sigBuf);
    calloc.free(sigLen);

    // ECDSA PKCS#11 returns r||s; CMS wants DER SEQUENCE.
    if (request.isEc && sig.length >= 64 && sig[0] != 0x30) {
      return _ecdsaP1363ToDer(sig);
    }
    return sig;
  } finally {
    try {
      lib.logout(session);
    } catch (_) {}
    lib.closeSession(session);
  }
}

int? _findPrivateKey(_Pkcs11Lib lib, int session, String idHex, String? label) {
  final template = calloc<_CkAttribute>();
  final classVal = calloc<Uint64>()..value = CKO_PRIVATE_KEY;
  template[0].type = CKA_CLASS;
  template[0].pValue = classVal.cast();
  template[0].ulValueLen = 8;
  var rv = lib.findObjectsInit(session, template, 1);
  calloc.free(classVal);
  calloc.free(template);
  if (rv != CKR_OK) return null;
  final handles = calloc<Uint64>(64);
  final count = calloc<Uint64>();
  rv = lib.findObjects(session, handles, 64, count);
  lib.findObjectsFinal(session);
  int? found;
  if (rv == CKR_OK) {
    for (var i = 0; i < count.value; i++) {
      final h = handles[i];
      final id = _getBytesAttr(lib, session, h, CKA_ID);
      final idH = id == null ? '' : _hex(id);
      if (idHex.isNotEmpty && idH.toLowerCase() == idHex.toLowerCase()) {
        found = h;
        break;
      }
      if (found == null && label != null && label.isNotEmpty) {
        final lb = _getBytesAttr(lib, session, h, CKA_LABEL);
        final ls = lb == null ? '' : utf8.decode(lb, allowMalformed: true);
        if (ls == label) found = h;
      }
    }
    if (found == null && count.value == 1) found = handles[0];
  }
  calloc.free(handles);
  calloc.free(count);
  return found;
}

Uint8List _ecdsaP1363ToDer(Uint8List rs) {
  final half = rs.length ~/ 2;
  final r = rs.sublist(0, half);
  final s = rs.sublist(half);
  Uint8List encInt(Uint8List raw) {
    var v = raw;
    while (v.length > 1 && v[0] == 0) {
      v = v.sublist(1);
    }
    if (v.isNotEmpty && v[0] & 0x80 != 0) {
      v = Uint8List.fromList([0, ...v]);
    }
    return Uint8List.fromList([0x02, v.length, ...v]);
  }

  final er = encInt(r);
  final es = encInt(s);
  final body = Uint8List.fromList([...er, ...es]);
  if (body.length < 128) {
    return Uint8List.fromList([0x30, body.length, ...body]);
  }
  return Uint8List.fromList([0x30, 0x81, body.length, ...body]);
}
