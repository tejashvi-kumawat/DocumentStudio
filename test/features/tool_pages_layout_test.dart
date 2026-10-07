import 'package:document_studio/design_system/ds_theme.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/features/security/protect_screen.dart';
import 'package:document_studio/features/security/unlock_screen.dart';
import 'package:document_studio/infrastructure/pdf/qpdf_encrypt_adapter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Storage implements FileStoragePort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Encrypt implements PdfEncryptPort {
  @override
  Future<bool> isAvailable() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final screens = <String, Widget Function()>{
    'Encrypt': () => ProtectScreen(deps: ProtectDeps(fileStorage: _Storage(), encryptPort: _Encrypt())),
    'Decrypt': () => UnlockScreen(deps: UnlockDeps(fileStorage: _Storage(), encryptPort: _Encrypt())),
  };

  for (final entry in screens.entries) {
    for (final size in const [Size(390, 800), Size(1280, 800)]) {
      testWidgets('${entry.key} empty state at ${size.width.toInt()}px', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          await tester.pumpWidget(ProviderScope(
            child: MaterialApp(theme: DsTheme.light(), home: entry.value()),
          ));
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.textContaining('Drop a'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
          tester.view.reset();
        }
      });
    }
  }
}
