import 'dart:io';

import 'package:document_studio/core/storage/linux_document_portal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GetHostPaths stdout is a host path, not the portal mount', () {
    const portal = '/run/user/1000/doc/262a484a/final_lab_4_tejashvi.pdf';
    final host = LinuxDocumentPortal.parseGetHostPathsStdout(
      "({'262a484a': b'/home/me/Downloads/final_lab_4_tejashvi.pdf'},)\n",
    );
    expect(host, '/home/me/Downloads/final_lab_4_tejashvi.pdf');
    expect(host, isNot(portal));
    expect(LinuxDocumentPortal.isPortalPath(portal), isTrue);
    expect(LinuxDocumentPortal.isPortalPath(host!), isFalse);
  });

  test('portal path is not the cache key when GetHostPaths resolves', () {
    if (!Platform.isLinux) return;
    const portal =
        '/run/user/1000/doc/e00d2737/SWAMI VIVEKANANDA COMPLETE WORKS (Vol 1).pdf';
    if (!File(portal).existsSync()) return;
    final host = LinuxDocumentPortal.resolveSync(portal);
    expect(LinuxDocumentPortal.isPortalPath(host), isFalse,
        reason: 'PdfDocumentRefKey must use the host path');
    expect(host, isNot(startsWith('/run/user/')));
    expect(File(host).existsSync(), isTrue);
    // Portal path and host path are one file (same cache identity).
    expect(LinuxDocumentPortal.sameFileSync(portal, host), isTrue);
    expect(LinuxDocumentPortal.fileIdSync(portal),
        LinuxDocumentPortal.fileIdSync(host));
    // A second call shares the cached host; a miss must not stick.
    expect(LinuxDocumentPortal.resolveSync(portal), host);
  });

  test('a hardlink shares file id with its target', () {
    if (!Platform.isLinux) return;
    final dir = Directory.systemTemp.createTempSync('ds_file_id_');
    try {
      final src = File('${dir.path}/book (Vol 1).pdf')
        ..writeAsStringSync('%PDF-1.4\n');
      final link = '${dir.path}/book _Vol 1_.pdf';
      final ln = Process.runSync('ln', [src.path, link]);
      expect(ln.exitCode, 0, reason: '${ln.stderr}');
      expect(LinuxDocumentPortal.sameFileSync(src.path, link), isTrue);
      expect(LinuxDocumentPortal.fileIdSync(src.path),
          LinuxDocumentPortal.fileIdSync(link));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('a failed portal lookup is not cached', () {
    if (!Platform.isLinux) return;
    const portal = '/run/user/1000/doc/00000000/missing.pdf';
    expect(LinuxDocumentPortal.resolveSync(portal), portal);
    expect(LinuxDocumentPortal.resolveSync(portal), portal);
  });
}
