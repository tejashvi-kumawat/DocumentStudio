import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Maps xdg-document-portal paths (`/run/user/<uid>/doc/<id>/name.pdf`) back
/// to the original file on disk.
///
/// File choosers that go through the portal (snap / Flatpak hosts, or
/// `GTK_USE_PORTAL=1`) hand out these FUSE paths. They work, but they hide
/// where the file really lives, can vanish when the portal forgets the grant,
/// and make Recents show a meaningless location.
///
/// Canonical identity for [PdfDocumentRefKey] / cache keys must be the **host**
/// path whenever it can be resolved — never the FUSE mount.
///
/// `flutter run` from the Flutter snap cannot use `GetHostPaths`: a spawned
/// `/usr/bin/gdbus` is not a working session-bus client, and
/// `DynamicLibrary.open('libgio-2.0.so.0')` does not see the libgio GTK
/// already loaded, so that in-process call returns null. The document portal
/// stores the real path on the mount as the xattr
/// `user.document-portal.host-path`. Reading it is a syscall on a file this
/// process can already open, so the host path is known before any cache key.
class LinuxDocumentPortal {
  LinuxDocumentPortal._();

  static final _docPath = RegExp(r'^/run/user/\d+/doc/([^/]+)/');
  static final _cache = <String, String>{};

  /// Prefer absolute path: Flutter-snap `PATH` can omit `/usr/bin` in some
  /// `Process.run` contexts, which made GetHostPaths silently fail and left
  /// FUSE paths as document ref keys.
  static const _gdbus = '/usr/bin/gdbus';

  static bool isPortalPath(String path) =>
      Platform.isLinux && _docPath.hasMatch(path);

  /// Sync resolve for constructors / [PdfDocumentRefKey] creation.
  ///
  /// Must run **before** any cache acquire or display-document ref so the
  /// FUSE path never becomes a listenable key. Failed lookups are not cached.
  static String resolveSync(String path) {
    if (!isPortalPath(path)) return path;
    final id = _docPath.firstMatch(path)!.group(1)!;
    final cached = _cache[id];
    if (cached != null) return cached;
    final host = _hostPathSync(id, path);
    if (host == null || host.isEmpty) return path;
    if (!_hostUsable(host)) return path;
    _cache[id] = host;
    return host;
  }

  /// The host path for [path], or [path] itself when it isn't a portal path,
  /// the portal can't be asked, or the host file isn't usable.
  ///
  /// Failed lookups are not cached — a transient `gdbus` miss must not pin the
  /// tab to the slow FUSE path for the rest of the process.
  static Future<String> resolve(String path) async {
    if (!isPortalPath(path)) return path;
    final id = _docPath.firstMatch(path)!.group(1)!;
    final cached = _cache[id];
    if (cached != null) return cached;
    // Prefer sync path when possible (same gdbus call) so callers that race
    // with DocumentSession see one cached host immediately.
    final sync = resolveSync(path);
    if (sync != path) return sync;
    final host = await _hostPath(id);
    if (host == null || host.isEmpty) return path;
    if (!await _hostUsableAsync(host)) return path;
    _cache[id] = host;
    return host;
  }

  /// Exists + readable without holding a descriptor (openSync can flake under
  /// FD pressure and wrongly rejected usable host paths).
  static bool _hostUsable(String host) {
    try {
      final f = File(host);
      if (!f.existsSync()) return false;
      // Stat + length prove the inode is reachable for openFile / hardlink.
      f.lengthSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _hostUsableAsync(String host) async {
    try {
      final f = File(host);
      if (!await f.exists()) return false;
      await f.length();
      return true;
    } catch (_) {
      return false;
    }
  }

  static String? _hostPathSync(String id, String portalPath) {
    // xattr first. gdbus / a second libgio miss under `flutter run` and must
    // not run on the success path (they block the UI and return nothing).
    final fromXattr = _PortalXattr.hostPath(portalPath);
    if (fromXattr != null && fromXattr.isNotEmpty) return fromXattr;
    final fromGdbus = _gdbusSync(id);
    if (fromGdbus != null && fromGdbus.isNotEmpty) return fromGdbus;
    return _GioDocuments.hostPath(id);
  }

  /// `major:minor:ino` for [path], or null if statx fails. Not cached on
  /// failure. Portal paths are resolved to the host first so the FUSE inode
  /// is never the identity.
  static String? fileIdSync(String path) {
    final resolved = resolveSync(path);
    if (Platform.isLinux) return _Statx.id(resolved);
    if (!Platform.isMacOS) return null;
    try {
      final r = Process.runSync('stat', ['-f', '%d:%i', resolved]);
      if (r.exitCode != 0) return null;
      final id = '${r.stdout}'.trim();
      return id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }

  /// True when [a] and [b] are the same inode after portal → host resolution
  /// (a FUSE path, its host file, and a session hardlink).
  static bool sameFileSync(String a, String b) {
    final ra = resolveSync(a);
    final rb = resolveSync(b);
    if (ra == rb) return true;
    final ia = fileIdSync(ra);
    final ib = fileIdSync(rb);
    return ia != null && ia == ib;
  }

  static Future<String?> _hostPath(String id) async {
    final fromGdbus = await _gdbusAsync(id);
    if (fromGdbus != null && fromGdbus.isNotEmpty) return fromGdbus;
    return _GioDocuments.hostPath(id);
  }

  static Map<String, String> _cleanEnv() {
    final env = <String, String>{
      'PATH': '/usr/bin:/bin',
      'LANG': Platform.environment['LANG'] ?? 'C.UTF-8',
    };
    for (final key in [
      'DBUS_SESSION_BUS_ADDRESS',
      'XDG_RUNTIME_DIR',
      'HOME',
      'USER',
    ]) {
      final value = Platform.environment[key];
      if (value != null && value.isNotEmpty) env[key] = value;
    }
    return env;
  }

  static String? _gdbusSync(String id) {
    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(id)) return null;
    final args = _gdbusArgs(id);
    final clean = _cleanEnv();
    try {
      final r = Process.runSync(
        _gdbus,
        args,
        environment: clean,
        includeParentEnvironment: false,
      );
      final parsed = r.exitCode == 0
          ? _parseHostPathStdout('${r.stdout}')
          : null;
      if (parsed != null && parsed.isNotEmpty) return parsed;
    } catch (_) {}
    try {
      final r = Process.runSync(_gdbus, args);
      if (r.exitCode != 0) {
        final r2 = Process.runSync('gdbus', args);
        if (r2.exitCode != 0) return null;
        return _parseHostPathStdout('${r2.stdout}');
      }
      return _parseHostPathStdout('${r.stdout}');
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _gdbusAsync(String id) async {
    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(id)) return null;
    final args = _gdbusArgs(id);
    try {
      var r = await Process.run(
        _gdbus,
        args,
        environment: _cleanEnv(),
        includeParentEnvironment: false,
      ).timeout(const Duration(seconds: 2));
      var parsed = r.exitCode == 0 ? _parseHostPathStdout('${r.stdout}') : null;
      if (parsed != null && parsed.isNotEmpty) return parsed;
      r = await Process.run(_gdbus, args).timeout(const Duration(seconds: 2));
      if (r.exitCode != 0) return null;
      return _parseHostPathStdout('${r.stdout}');
    } catch (_) {
      return null;
    }
  }

  static List<String> _gdbusArgs(String id) => [
    'call',
    '--session',
    '--dest',
    'org.freedesktop.portal.Documents',
    '--object-path',
    '/org/freedesktop/portal/documents',
    '--method',
    'org.freedesktop.portal.Documents.GetHostPaths',
    "['$id']",
  ];

  /// ({'5045f77': b'/home/me/Downloads/a.pdf'},)
  ///
  /// Also accepts gdbus byte-array form `[byte 0x2f, 0x68, ...]`.
  static String? parseGetHostPathsStdout(String stdout) =>
      _parseHostPathStdout(stdout);

  static String? _parseHostPathStdout(String stdout) {
    Match? m = RegExp(r"b'((?:[^'\\]|\\.)*)'").firstMatch(stdout);
    m ??= RegExp(r'b"((?:[^"\\]|\\.)*)"').firstMatch(stdout);
    if (m != null) {
      final raw = m.group(1)!.replaceAllMapped(
        RegExp(r"\\(x[0-9a-fA-F]{2}|[0-7]{1,3}|.)"),
        (e) {
          final s = e.group(1)!;
          if (s.startsWith('x')) {
            return String.fromCharCode(int.parse(s.substring(1), radix: 16));
          }
          if (RegExp(r'^[0-7]+$').hasMatch(s)) {
            return String.fromCharCode(int.parse(s, radix: 8));
          }
          return s;
        },
      );
      if (raw.isEmpty) return null;
      return utf8.decode(raw.codeUnits, allowMalformed: true);
    }
    final bytes = RegExp(
      r'\[byte ((?:0x[0-9a-fA-F]+|\d+)(?:\s*,\s*(?:0x[0-9a-fA-F]+|\d+))*)\]',
    ).firstMatch(stdout);
    if (bytes == null) return null;
    final data = <int>[];
    for (final part in bytes.group(1)!.split(',')) {
      final token = part.trim();
      if (token.isEmpty) continue;
      data.add(int.parse(token));
    }
    if (data.isEmpty) return null;
    final path = utf8.decode(data, allowMalformed: true);
    return path.isEmpty ? null : path;
  }
}

/// `user.document-portal.host-path` on the FUSE node. This is the host path
/// GetHostPaths would return; the snap's gdbus child and a freshly dlopen'd
/// libgio do not.
class _PortalXattr {
  _PortalXattr._();

  static const _name = 'user.document-portal.host-path';

  static String? hostPath(String portalPath) {
    if (!Platform.isLinux || portalPath.isEmpty) return null;
    try {
      final getxattr = _Libc.getxattr;
      if (getxattr == null) return null;
      final path = portalPath.toNativeUtf8();
      final name = _name.toNativeUtf8();
      final buf = calloc<Uint8>(4096);
      try {
        final n = getxattr(path, name, buf, 4096);
        if (n <= 0 || n >= 4096) return null;
        final bytes = buf.asTypedList(n);
        final end = bytes.last == 0 ? n - 1 : n;
        if (end <= 0) return null;
        final host = utf8.decode(bytes.sublist(0, end), allowMalformed: true);
        if (host.isEmpty || LinuxDocumentPortal.isPortalPath(host)) return null;
        return host;
      } finally {
        calloc.free(buf);
        malloc.free(path);
        malloc.free(name);
      }
    } catch (_) {
      return null;
    }
  }
}

/// Linux `statx` so portal / host / hardlink share one id without spawning
/// `/usr/bin/stat` (the snap PATH often cannot run it).
class _Statx {
  _Statx._();

  static const _atFdcwd = -100;
  static const _basicStats = 0x7ff;
  static const _offIno = 32;
  static const _offDevMajor = 136;
  static const _offDevMinor = 140;

  static String? id(String path) {
    if (path.isEmpty) return null;
    try {
      final statx = _Libc.statx;
      if (statx == null) return null;
      final pathPtr = path.toNativeUtf8();
      final buf = calloc<Uint8>(256);
      try {
        final rc = statx(_atFdcwd, pathPtr, 0, _basicStats, buf);
        if (rc != 0) return null;
        final data = ByteData.sublistView(buf.asTypedList(256));
        final ino = data.getUint64(_offIno, Endian.little);
        if (ino == 0) return null;
        final major = data.getUint32(_offDevMajor, Endian.little);
        final minor = data.getUint32(_offDevMinor, Endian.little);
        return '$major:$minor:$ino';
      } finally {
        calloc.free(buf);
        malloc.free(pathPtr);
      }
    } catch (_) {
      return null;
    }
  }
}

class _Libc {
  _Libc._();

  static DynamicLibrary? _lib;
  static int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Uint8>, int)?
  _getxattr;
  static int Function(int, Pointer<Utf8>, int, int, Pointer<Uint8>)? _statx;
  static bool _tried = false;

  static DynamicLibrary? get _library {
    if (_tried) return _lib;
    _tried = true;
    try {
      _lib = DynamicLibrary.open('libc.so.6');
    } catch (_) {
      try {
        _lib = DynamicLibrary.process();
      } catch (_) {
        _lib = null;
      }
    }
    return _lib;
  }

  static int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Uint8>, int)?
  get getxattr {
    final existing = _getxattr;
    if (existing != null) return existing;
    final lib = _library;
    if (lib == null) return null;
    try {
      return _getxattr = lib
          .lookupFunction<
            IntPtr Function(
              Pointer<Utf8>,
              Pointer<Utf8>,
              Pointer<Uint8>,
              IntPtr,
            ),
            int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Uint8>, int)
          >('getxattr');
    } catch (_) {
      return null;
    }
  }

  static int Function(int, Pointer<Utf8>, int, int, Pointer<Uint8>)? get statx {
    final existing = _statx;
    if (existing != null) return existing;
    final lib = _library;
    if (lib == null) return null;
    try {
      return _statx = lib
          .lookupFunction<
            Int32 Function(Int32, Pointer<Utf8>, Int32, Uint32, Pointer<Uint8>),
            int Function(int, Pointer<Utf8>, int, int, Pointer<Uint8>)
          >('statx');
    } catch (_) {
      return null;
    }
  }
}

/// In-process `org.freedesktop.portal.Documents.GetHostPaths`.
///
/// Fallback when the host-path xattr is missing. Prefer symbols from the
/// libgio GTK already loaded ([DynamicLibrary.process]); opening a second
/// `libgio-2.0.so.0` under `flutter run` does not reach the session bus.
class _GioDocuments {
  _GioDocuments._();

  static _GioBindings? _bindings;
  static bool _missing = false;

  static String? hostPath(String id) {
    if (!Platform.isLinux) return null;
    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(id)) return null;
    if (_missing) return null;
    try {
      final gio = _bindings ??= _GioBindings.load();
      return gio.call(id);
    } on ArgumentError {
      _missing = true;
      _bindings = null;
      return null;
    } catch (_) {
      return null;
    }
  }
}

class _GioBindings {
  _GioBindings._(
    this._call,
    this._parse,
    this._print,
    this._unrefVariant,
    this._free,
    this._unrefObject,
    this._errorFree,
    this._bus,
  );

  final Pointer<Void> Function(
    Pointer<Void>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Void>,
    Pointer<Void>,
    int,
    int,
    Pointer<Void>,
    Pointer<Pointer<Void>>,
  )
  _call;
  final Pointer<Void> Function(
    Pointer<Void>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Pointer<Utf8>>,
    Pointer<Pointer<Void>>,
  )
  _parse;
  final Pointer<Utf8> Function(Pointer<Void>, int) _print;
  final void Function(Pointer<Void>) _unrefVariant;
  final void Function(Pointer<Void>) _free;
  final void Function(Pointer<Void>) _unrefObject;
  final void Function(Pointer<Void>) _errorFree;
  final Pointer<Void> Function(int, Pointer<Void>, Pointer<Pointer<Void>>) _bus;

  static _GioBindings load() {
    late DynamicLibrary gio;
    late DynamicLibrary glib;
    late DynamicLibrary gobject;
    try {
      final process = DynamicLibrary.process();
      process.lookup('g_bus_get_sync');
      process.lookup('g_variant_print');
      process.lookup('g_object_unref');
      gio = process;
      glib = process;
      gobject = process;
    } catch (_) {
      gio = DynamicLibrary.open('libgio-2.0.so.0');
      glib = DynamicLibrary.open('libglib-2.0.so.0');
      gobject = DynamicLibrary.open('libgobject-2.0.so.0');
    }
    return _GioBindings._(
      gio.lookupFunction<
        Pointer<Void> Function(
          Pointer<Void>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Void>,
          Pointer<Void>,
          Int32,
          Int32,
          Pointer<Void>,
          Pointer<Pointer<Void>>,
        ),
        Pointer<Void> Function(
          Pointer<Void>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Void>,
          Pointer<Void>,
          int,
          int,
          Pointer<Void>,
          Pointer<Pointer<Void>>,
        )
      >('g_dbus_connection_call_sync'),
      gio.lookupFunction<
        Pointer<Void> Function(
          Pointer<Void>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Pointer<Utf8>>,
          Pointer<Pointer<Void>>,
        ),
        Pointer<Void> Function(
          Pointer<Void>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Pointer<Utf8>>,
          Pointer<Pointer<Void>>,
        )
      >('g_variant_parse'),
      glib.lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>, Int32),
        Pointer<Utf8> Function(Pointer<Void>, int)
      >('g_variant_print'),
      glib.lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('g_variant_unref'),
      glib.lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('g_free'),
      gobject.lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('g_object_unref'),
      glib.lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('g_error_free'),
      gio.lookupFunction<
        Pointer<Void> Function(Int32, Pointer<Void>, Pointer<Pointer<Void>>),
        Pointer<Void> Function(int, Pointer<Void>, Pointer<Pointer<Void>>)
      >('g_bus_get_sync'),
    );
  }

  String? call(String id) {
    final err = calloc<Pointer<Void>>();
    Pointer<Void> conn = nullptr;
    Pointer<Void> params = nullptr;
    Pointer<Void> reply = nullptr;
    try {
      conn = _bus(2, nullptr, err);
      _drainError(err);
      if (conn == nullptr) return null;
      return using((arena) {
        final text = "(['$id'],)".toNativeUtf8(allocator: arena);
        params = _parse(nullptr, text, nullptr, nullptr, err);
        _drainError(err);
        if (params == nullptr) return null;
        final dest = 'org.freedesktop.portal.Documents'.toNativeUtf8(
          allocator: arena,
        );
        final path = '/org/freedesktop/portal/documents'.toNativeUtf8(
          allocator: arena,
        );
        final iface = 'org.freedesktop.portal.Documents'.toNativeUtf8(
          allocator: arena,
        );
        final method = 'GetHostPaths'.toNativeUtf8(allocator: arena);
        reply = _call(
          conn,
          dest,
          path,
          iface,
          method,
          params,
          nullptr,
          0,
          2000,
          nullptr,
          err,
        );
        _drainError(err);
        if (reply == nullptr) return null;
        final printed = _print(reply, 0);
        try {
          return LinuxDocumentPortal.parseGetHostPathsStdout(
            printed.toDartString(),
          );
        } finally {
          _free(printed.cast());
        }
      });
    } finally {
      if (reply != nullptr) _unrefVariant(reply);
      if (params != nullptr) _unrefVariant(params);
      if (conn != nullptr) _unrefObject(conn);
      _drainError(err);
      calloc.free(err);
    }
  }

  void _drainError(Pointer<Pointer<Void>> err) {
    if (err.value == nullptr) return;
    _errorFree(err.value);
    err.value = nullptr;
  }
}
